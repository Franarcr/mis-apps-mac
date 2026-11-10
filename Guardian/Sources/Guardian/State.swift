import AppKit
import Foundation

/// Estado compartido entre el menú y las ventanas.
@MainActor
final class GuardState: ObservableObject {
    // Programas
    @Published var programs: [Program] = []
    @Published var orphanLaunchItems: [LaunchItem] = []
    @Published var systemAccess: [SystemAccess] = []
    @Published var scanning = false
    @Published var lastScan: Date?

    // AnyDesk
    @Published var connections: [Connection] = []
    @Published var sessions: [ActiveSession] = []
    @Published var addresses: [String: String] = [:]
    @Published var ownAddress: String?
    @Published var ownID: String?
    @Published var unattended = false
    @Published var trusted = TrustedDevices.all

    var incoming: [Connection] { connections.filter(\.incoming) }

    /// Equipos que entraron, del más reciente al más antiguo, con cuántas veces y cómo.
    var devices: [(id: String, last: Date, count: Int, methods: Set<String>)] {
        let groups = Dictionary(grouping: incoming, by: \.remoteID)
        return groups.map { id, list in
            (id, list.map(\.date).max() ?? .distantPast, list.count, Set(list.map(\.method)))
        }.sorted { $0.last > $1.last }
    }

    /// Entró desde la misma dirección de internet que este Mac: está en tu misma red (casa u oficina).
    func isSameNetwork(_ id: String) -> Bool {
        guard let own = ownAddress, let address = addresses[id] else { return false }
        return own == address
    }

    func trust(_ id: String, name: String) {
        TrustedDevices.trust(id, name: name)
        trusted = TrustedDevices.all
    }

    func forget(_ id: String) {
        TrustedDevices.forget(id)
        trusted = TrustedDevices.all
    }

    /// Relee el registro de AnyDesk y mira si hay sesiones abiertas.
    func refreshAnyDesk() {
        connections = AnyDeskWatch.connections()
        sessions = AnyDeskWatch.activeSessions(lastIncoming: incoming.last?.remoteID)
        unattended = AnyDeskWatch.unattendedEnabled()
        ownID = AnyDeskWatch.ownID()
        let found = AnyDeskWatch.addresses()
        addresses = found.byID
        ownAddress = found.own
    }

    func scanPrograms() {
        guard !scanning else { return }
        scanning = true
        Task.detached(priority: .userInitiated) {
            let programs = ProgramScanner.scan()
            let items = ProgramScanner.scanLaunchItems()
            let used = Set(programs.flatMap { $0.launchItems.map(\.id) })
            let access = ProgramScanner.systemAccess()
            await MainActor.run {
                self.programs = programs
                self.orphanLaunchItems = items.filter { !used.contains($0.id) && !$0.label.hasPrefix("com.apple.") }
                self.systemAccess = access
                self.lastScan = Date()
                self.scanning = false
            }
        }
    }
}
