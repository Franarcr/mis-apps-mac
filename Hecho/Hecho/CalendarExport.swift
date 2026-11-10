import EventKit
import Foundation

/// Pasa las tareas con fecha a tu calendario, como eventos.
///
/// Cada evento lleva la marca de su tarea (`hecho://tarea/<id>` y `[hecho:<id>]` en las notas).
/// Antes de crear uno se busca esa marca en el calendario, así que aunque el Mac y el iPhone
/// lo intenten a la vez, solo queda un evento por tarea: el segundo encuentra el del primero y lo actualiza.
@MainActor enum CalendarExport {
    /// Tareas a las que este aparato les creó evento (para quitarlo si la tarea se borra para siempre).
    private static let mineKey = "hecho.calendario.mios"

    static func url(_ uid: String) -> URL? { URL(string: "hecho://tarea/\(uid)") }
    static func marker(_ uid: String) -> String { "[hecho:\(uid)]" }

    /// La tarea a la que pertenece un evento creado por Hecho (nil si no es de Hecho).
    nonisolated static func uid(of e: EKEvent) -> String? {
        if let u = e.url, u.scheme == "hecho", u.host() == "tarea", !u.lastPathComponent.isEmpty, u.lastPathComponent != "/" {
            return u.lastPathComponent
        }
        if let n = e.notes, let r = n.range(of: "[hecho:") {
            let rest = n[r.upperBound...]
            if let end = rest.firstIndex(of: "]") { return String(rest[..<end]) }
        }
        return nil
    }

    static func sync(_ all: [TodoItem]) {
        let feed = CalendarFeed.shared
        guard feed.authorized else { return }
        let store = feed.store
        let writable = store.calendars(for: .event).filter(\.allowsContentModifications)
        guard !writable.isEmpty else { return }

        var mine = Set(UserDefaults.standard.stringArray(forKey: mineKey) ?? [])
        let today = Date().startOfDay
        let predicate = store.predicateForEvents(withStart: today.adding(days: -60), end: today.adding(days: 800),
                                                 calendars: writable)
        var existing: [String: [EKEvent]] = [:]
        for e in store.events(matching: predicate) {
            if let u = uid(of: e) { existing[u, default: []].append(e) }
        }

        var changed = false
        var known = Set<String>()
        for t in all where !t.uid.isEmpty {
            known.insert(t.uid)
            let events = existing[t.uid] ?? []
            let wants = feed.exportEnabled && t.status == .open && !t.trashed && t.parentActive && t.startDate != nil
            if wants, let cal = feed.calendar(id: t.calendarID) ?? feed.exportCalendar {
                let event = events.first ?? EKEvent(eventStore: store)
                // Si por algo quedaron dos eventos de la misma tarea, se deja uno.
                for extra in events.dropFirst() {
                    try? store.remove(extra, span: .thisEvent, commit: false)
                    changed = true
                }
                if fill(event, with: t, calendar: cal) {
                    try? store.save(event, span: .thisEvent, commit: false)
                    changed = true
                }
                mine.insert(t.uid)
            } else if !events.isEmpty {
                // Completada, sin fecha, en la papelera o ya no se pasan tareas al calendario: se quita el evento.
                for e in events { try? store.remove(e, span: .thisEvent, commit: false) }
                changed = true
                mine.remove(t.uid)
            } else {
                mine.remove(t.uid)
            }
        }
        // Tareas borradas para siempre en este aparato.
        for u in mine where !known.contains(u) {
            for e in existing[u] ?? [] { try? store.remove(e, span: .thisEvent, commit: false) }
            changed = true
            mine.remove(u)
        }
        if changed { try? store.commit() }
        UserDefaults.standard.set(Array(mine), forKey: mineKey)
    }

    /// Copia los datos de la tarea al evento. Devuelve si cambió algo.
    private static func fill(_ e: EKEvent, with t: TodoItem, calendar: EKCalendar) -> Bool {
        var changed = false
        let isNew = e.calendar == nil
        if isNew || e.calendar.calendarIdentifier != calendar.calendarIdentifier {
            e.calendar = calendar
            changed = true
        }
        if e.title != t.displayTitle {
            e.title = t.displayTitle
            changed = true
        }
        guard let day = t.startDate else { return changed }
        if let r = t.reminderAt {
            // Con aviso: a esa hora, media hora.
            let end = r.addingTimeInterval(30 * 60)
            if e.isAllDay || e.startDate != r || e.endDate != end {
                e.isAllDay = false
                e.startDate = r
                e.endDate = end
                changed = true
            }
        } else if !e.isAllDay || e.startDate.map({ $0.startOfDay }) != day.startOfDay {
            e.isAllDay = true
            e.startDate = day.startOfDay
            e.endDate = day.startOfDay
            changed = true
        }
        let notes = (t.notes.isEmpty ? "" : t.notes + "\n\n") + "Tarea de Hecho " + marker(t.uid)
        if e.notes != notes {
            e.notes = notes
            changed = true
        }
        if e.url != url(t.uid) {
            e.url = url(t.uid)
            changed = true
        }
        // Hecho ya avisa con su propia notificación: el evento no lleva alertas, para no avisar dos veces.
        if isNew || !(e.alarms ?? []).isEmpty {
            e.alarms = []
            changed = true
        }
        return changed
    }
}
