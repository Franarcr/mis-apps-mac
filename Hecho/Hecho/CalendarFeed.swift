import EventKit
import SwiftUI

/// Un evento del calendario, listo para mostrar.
struct CalEvent: Identifiable, Hashable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var allDay: Bool
    var color: Color
}

/// Lee los eventos de tus calendarios para mostrarlos en Hoy y Próximo.
@Observable final class CalendarFeed {
    static let shared = CalendarFeed()
    @ObservationIgnored let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?

    var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "hecho.calendario.activo") } }
    var hidden: Set<String> { didSet { UserDefaults.standard.set(Array(hidden), forKey: "hecho.calendario.ocultos") } }
    /// Pasar las tareas con fecha a un calendario.
    var exportEnabled: Bool { didSet { UserDefaults.standard.set(exportEnabled, forKey: "hecho.calendario.exportar") } }
    /// Calendario de siempre para las tareas.
    var exportCalendarID: String? { didSet { UserDefaults.standard.set(exportCalendarID, forKey: "hecho.calendario.destino") } }
    var authorized = false
    /// Cambia cuando cambian los calendarios, para que las listas se vuelvan a dibujar.
    var version = 0

    init() {
        enabled = UserDefaults.standard.bool(forKey: "hecho.calendario.activo")
        hidden = Set(UserDefaults.standard.stringArray(forKey: "hecho.calendario.ocultos") ?? [])
        exportEnabled = UserDefaults.standard.bool(forKey: "hecho.calendario.exportar")
        exportCalendarID = UserDefaults.standard.string(forKey: "hecho.calendario.destino")
        authorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.version += 1
        }
    }

    /// Pide permiso para leer el calendario. Devuelve si se concedió.
    @MainActor func requestAccess() async -> Bool {
        let ok = (try? await store.requestFullAccessToEvents()) ?? false
        authorized = ok
        version += 1
        return ok
    }

    var calendars: [EKCalendar] {
        guard authorized else { return [] }
        return store.calendars(for: .event).sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    /// Calendarios donde se puede escribir.
    var writableCalendars: [EKCalendar] { calendars.filter(\.allowsContentModifications) }

    /// Calendario de siempre para las tareas (el elegido, o el predeterminado del sistema).
    var exportCalendar: EKCalendar? {
        let writable = writableCalendars
        if let id = exportCalendarID, let c = writable.first(where: { $0.calendarIdentifier == id }) { return c }
        if let d = store.defaultCalendarForNewEvents, d.allowsContentModifications { return d }
        return writable.first
    }

    func calendar(id: String?) -> EKCalendar? {
        guard let id else { return nil }
        return writableCalendars.first { $0.calendarIdentifier == id }
    }

    /// Eventos de un día, primero los de todo el día (sin los que creó Hecho: esas tareas ya se ven en la lista).
    func events(on day: Date) -> [CalEvent] {
        _ = version
        guard enabled, authorized else { return [] }
        let cals = store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
        guard !cals.isEmpty else { return [] }
        let start = day.startOfDay
        let predicate = store.predicateForEvents(withStart: start, end: start.adding(days: 1), calendars: cals)
        return store.events(matching: predicate)
            .filter { CalendarExport.uid(of: $0) == nil }
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .map { e in
                CalEvent(id: (e.eventIdentifier ?? UUID().uuidString) + "\(e.startDate.timeIntervalSince1970)",
                         title: e.title ?? "Evento", start: e.startDate, end: e.endDate, allDay: e.isAllDay,
                         color: Color(cgColor: e.calendar.cgColor))
            }
    }
}

/// Fila de un evento del calendario.
struct EventRow: View {
    let event: CalEvent
    var now = Date()

    var body: some View {
        let past = !event.allDay && event.end < now
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.color)
                .frame(width: 4, height: 18)
            Text(event.allDay ? "Todo el día" : Fmt.time(event.start))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 70, alignment: .leading)
            Text(event.title)
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .opacity(past ? 0.45 : 1)
        .padding(.vertical, 1)
    }
}
