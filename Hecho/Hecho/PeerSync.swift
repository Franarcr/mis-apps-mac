import Foundation
import Network
import Observation
import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Sincronización por Wi-Fi entre el Mac y el iPhone, sin iCloud.
///
/// Cada equipo con Hecho abierto se anuncia en la red local (Bonjour, `_hecho._tcp`) y busca a los demás.
/// Al conectarse se mandan todo su contenido, y luego cada cambio. Cada registro lleva su fecha de último
/// cambio y gana el más reciente. Lo borrado deja una «lápida» para que no vuelva desde el otro equipo.
@MainActor @Observable final class PeerSync {
    static let shared = PeerSync()
    static let serviceType = "_hecho._tcp"

    /// Equipos conectados ahora (por nombre).
    private(set) var peerNames: [String] = []
    private(set) var lastSync: Date?
    private(set) var problem: String?

    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var peers: [ObjectIdentifier: Peer] = [:]
    @ObservationIgnored private var sendTask: Task<Void, Never>?
    /// Mientras se aplican cambios del otro equipo no se marcan fechas ni se reenvía nada.
    @ObservationIgnored private(set) var applyingRemote = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    static let deviceID: String = {
        let key = "hecho.sync.equipo"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()

    static var deviceName: String {
        #if os(macOS)
        Host.current().localizedName ?? "Mac"
        #else
        UIDevice.current.name
        #endif
    }

    // MARK: Arranque

    func start(_ context: ModelContext) {
        if self.context == nil {
            self.context = context
            fillMissingIDs()
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: ModelContext.willSave, object: context, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.stampChanges() }
            })
            observers.append(center.addObserver(forName: ModelContext.didSave, object: context, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.localDidSave() }
            })
        }
        restartNetwork()
    }

    @ObservationIgnored private var wasInBackground = false

    /// Al volver a la app (el iPhone corta la red en segundo plano) se vuelve a anunciar y buscar.
    func scenePhaseChanged(to phase: ScenePhase) {
        if phase == .background { wasInBackground = true }
        if phase == .active && wasInBackground {
            wasInBackground = false
            restartNetwork()
        }
    }

    func restartNetwork() {
        guard context != nil else { return }
        stopNetwork()
        do {
            let params = NWParameters.tcp
            params.includePeerToPeer = true
            let listener = try NWListener(using: params)
            listener.service = NWListener.Service(name: Self.deviceID, type: Self.serviceType)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.adopt(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    if case .failed(let error) = state { self?.problem = "No pude anunciar Hecho en la red: \(error.localizedDescription)" }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            problem = "No pude anunciar Hecho en la red: \(error.localizedDescription)"
        }

        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.found(results) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                if case .failed(let error) = state { self?.problem = "No pude buscar equipos en la red: \(error.localizedDescription)" }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    private func stopNetwork() {
        listener?.cancel()
        browser?.cancel()
        listener = nil
        browser = nil
        for peer in peers.values { peer.connection.cancel() }
        peers.removeAll()
        updateNames()
    }

    // MARK: Conexiones

    private func found(_ results: Set<NWBrowser.Result>) {
        for result in results {
            guard case .service(let name, _, _, _) = result.endpoint, name != Self.deviceID else { continue }
            // Solo conecta el de identificador menor, para no abrir dos conexiones entre los mismos equipos.
            guard Self.deviceID < name, !peers.values.contains(where: { $0.deviceID == name }) else { continue }
            let params = NWParameters.tcp
            params.includePeerToPeer = true
            let connection = NWConnection(to: result.endpoint, using: params)
            adopt(connection, deviceID: name)
        }
    }

    private func adopt(_ connection: NWConnection, deviceID: String? = nil) {
        let peer = Peer(connection: connection)
        peer.deviceID = deviceID
        let key = ObjectIdentifier(peer)
        peers[key] = peer
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.send(to: peer)
                    self.receive(from: peer)
                case .failed, .cancelled:
                    self.peers[key] = nil
                    self.updateNames()
                case .waiting:
                    connection.cancel()
                default: break
                }
            }
        }
        connection.start(queue: .main)
    }

    private func receive(from peer: Peer) {
        peer.connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] header, _, done, error in
            Task { @MainActor in
                guard let self else { return }
                guard error == nil, let header, header.count == 4 else {
                    if done || error != nil { peer.connection.cancel() }
                    return
                }
                let length = Int(header.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
                peer.connection.receive(minimumIncompleteLength: length, maximumLength: length) { body, _, _, error in
                    Task { @MainActor in
                        guard error == nil, let body, body.count == length else { peer.connection.cancel(); return }
                        self.handle(body, from: peer)
                        self.receive(from: peer)
                    }
                }
            }
        }
    }

    private func handle(_ data: Data, from peer: Peer) {
        guard let message = try? Self.decoder.decode(SyncMessage.self, from: data) else { return }
        peer.deviceID = message.device
        peer.name = message.name
        // Si quedaron dos conexiones con el mismo equipo, se cierra la repetida.
        if peers.values.contains(where: { $0 !== peer && $0.deviceID == message.device }) {
            peer.connection.cancel()
            return
        }
        updateNames()
        merge(message.snapshot)
        lastSync = .now
    }

    private func updateNames() {
        peerNames = peers.values.compactMap(\.name).sorted()
    }

    // MARK: Envío

    private func send(to peer: Peer) {
        guard let data = try? Self.encoder.encode(SyncMessage(device: Self.deviceID, name: Self.deviceName, snapshot: snapshot()))
        else { return }
        var frame = withUnsafeBytes(of: UInt32(data.count).bigEndian) { Data($0) }
        frame.append(data)
        peer.connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func localDidSave() {
        guard !applyingRemote, !peers.isEmpty else { return }
        sendTask?.cancel()
        sendTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            for peer in self.peers.values where peer.connection.state == .ready { self.send(to: peer) }
            self.lastSync = .now
        }
    }

    // MARK: Marcas de cambio

    private func fillMissingIDs() {
        guard let context else { return }
        func fill<T: PersistentModel & Syncable>(_ type: T.Type) {
            for item in (try? context.fetch(FetchDescriptor<T>())) ?? [] where item.uid.isEmpty { item.uid = UUID().uuidString }
        }
        fill(Area.self); fill(Project.self); fill(Heading.self); fill(TodoItem.self); fill(ChecklistItem.self); fill(TagItem.self)

        // Una vez: lo que nunca se cambió desde que hay sincronización recibe una fecha antigua, más reciente cuanto
        // antes se creó. Así el original le gana a una copia incompleta que haya llegado al otro equipo.
        let key = "hecho.sync.fechasIniciales"
        if !UserDefaults.standard.bool(forKey: key) {
            UserDefaults.standard.set(true, forKey: key)
            func stamp<T: PersistentModel & Syncable>(_ type: T.Type) {
                for item in (try? context.fetch(FetchDescriptor<T>())) ?? [] where item.modifiedAt <= .distantPast {
                    item.modifiedAt = Date(timeIntervalSinceReferenceDate: -3e10 - item.creationRank)
                }
            }
            stamp(Area.self); stamp(Project.self); stamp(Heading.self); stamp(TodoItem.self); stamp(ChecklistItem.self); stamp(TagItem.self)
        }
        applyingRemote = true
        try? context.save()
        applyingRemote = false
    }

    /// Antes de guardar: pone la fecha de cambio a lo nuevo o cambiado y anota lo borrado.
    private func stampChanges() {
        guard !applyingRemote, let context else { return }
        let now = Date()
        for model in context.insertedModelsArray + context.changedModelsArray {
            guard let item = model as? any Syncable else { continue }
            if item.uid.isEmpty { item.uid = UUID().uuidString }
            item.modifiedAt = now
        }
        let gone = context.deletedModelsArray.compactMap { ($0 as? any Syncable)?.uid }.filter { !$0.isEmpty }
        if !gone.isEmpty { Tombstones.add(gone, at: now) }
    }

    // MARK: Contenido

    private func snapshot() -> Snapshot {
        guard let context else { return Snapshot() }
        func all<T: PersistentModel>(_ type: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }
        var s = Snapshot()
        s.areas = all(Area.self).map { AreaDTO(uid: $0.uid, modified: $0.modifiedAt, title: $0.title, order: $0.order, createdAt: $0.createdAt) }
        s.tags = all(TagItem.self).map { TagDTO(uid: $0.uid, modified: $0.modifiedAt, title: $0.title, order: $0.order) }
        s.projects = all(Project.self).map {
            ProjectDTO(uid: $0.uid, modified: $0.modifiedAt, title: $0.title, notes: $0.notes, order: $0.order, createdAt: $0.createdAt,
                       statusRaw: $0.statusRaw, completedAt: $0.completedAt, startRaw: $0.startRaw, startDate: $0.startDate,
                       deadline: $0.deadline, trashed: $0.trashed, area: $0.area?.uid)
        }
        s.headings = all(Heading.self).map { HeadingDTO(uid: $0.uid, modified: $0.modifiedAt, title: $0.title, order: $0.order, project: $0.project?.uid) }
        // Las tareas recién creadas y todavía vacías no se mandan.
        s.todos = all(TodoItem.self).filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty || !$0.notes.isEmpty || !$0.checklist.isEmpty }.map {
            TodoDTO(uid: $0.uid, modified: $0.modifiedAt, title: $0.title, notes: $0.notes, createdAt: $0.createdAt, order: $0.order,
                    todayOrder: $0.todayOrder, startRaw: $0.startRaw, startDate: $0.startDate, evening: $0.evening, deadline: $0.deadline,
                    statusRaw: $0.statusRaw, completedAt: $0.completedAt, trashed: $0.trashed, reminderAt: $0.reminderAt,
                    repeatRaw: $0.repeatRaw, nextUID: $0.nextUID, project: $0.project?.uid, area: $0.area?.uid,
                    heading: $0.heading?.uid, tags: $0.tags.map(\.uid))
        }
        s.steps = all(ChecklistItem.self).map { StepDTO(uid: $0.uid, modified: $0.modifiedAt, title: $0.title, done: $0.done, order: $0.order, todo: $0.todo?.uid) }
        s.tombstones = Tombstones.all
        return s
    }

    /// Junta lo que llega con lo de aquí: por cada registro gana el cambio más reciente.
    private func merge(_ remote: Snapshot) {
        guard let context else { return }
        applyingRemote = true
        defer { applyingRemote = false }

        func index<T: PersistentModel & Syncable>(_ type: T.Type) -> [String: T] {
            Dictionary(((try? context.fetch(FetchDescriptor<T>())) ?? []).map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
        }

        // Lo borrado allá se borra aquí, salvo que aquí haya cambiado después.
        Tombstones.merge(remote.tombstones)
        let tombs = Tombstones.dates
        func buried(_ uid: String, _ modified: Date) -> Bool { tombs[uid].map { $0 >= modified } ?? false }
        func bury<T: PersistentModel & Syncable>(_ items: [String: T]) {
            for (uid, item) in items where buried(uid, item.modifiedAt) { context.delete(item) }
        }
        bury(index(Area.self)); bury(index(TagItem.self)); bury(index(Project.self))
        bury(index(Heading.self)); bury(index(TodoItem.self)); bury(index(ChecklistItem.self))

        // Áreas y etiquetas con el mismo nombre en los dos equipos se juntan en una (se queda el identificador menor).
        var areas = index(Area.self)
        var alias: [String: String] = [:]
        for dto in remote.areas where !buried(dto.uid, dto.modified) {
            var item = areas[dto.uid]
            if item == nil, let twin = areas.values.first(where: { local in local.title.lowercased() == dto.title.lowercased() && !remote.areas.contains { $0.uid == local.uid } }) {
                if dto.uid < twin.uid { areas[twin.uid] = nil; twin.uid = dto.uid; areas[dto.uid] = twin } else { alias[dto.uid] = twin.uid; continue }
                item = twin
            }
            if item == nil { let a = Area(title: dto.title); a.uid = dto.uid; context.insert(a); areas[dto.uid] = a; item = a; item?.modifiedAt = Self.notYet }
            guard let a = item, dto.modified > a.modifiedAt else { continue }
            a.title = dto.title; a.order = dto.order; a.createdAt = dto.createdAt; a.modifiedAt = dto.modified
        }

        var tags = index(TagItem.self)
        for dto in remote.tags where !buried(dto.uid, dto.modified) {
            var item = tags[dto.uid]
            if item == nil, let twin = tags.values.first(where: { local in local.title.lowercased() == dto.title.lowercased() && !remote.tags.contains { $0.uid == local.uid } }) {
                if dto.uid < twin.uid { tags[twin.uid] = nil; twin.uid = dto.uid; tags[dto.uid] = twin } else { alias[dto.uid] = twin.uid; continue }
                item = twin
            }
            if item == nil { let t = TagItem(title: dto.title); t.uid = dto.uid; t.modifiedAt = Self.notYet; context.insert(t); tags[dto.uid] = t; item = t }
            guard let t = item, dto.modified > t.modifiedAt else { continue }
            t.title = dto.title; t.order = dto.order; t.modifiedAt = dto.modified
        }
        func resolve(_ uid: String?) -> String? { uid.map { alias[$0] ?? $0 } }

        var projects = index(Project.self)
        var projectLinks: [(Project, ProjectDTO)] = []
        for dto in remote.projects where !buried(dto.uid, dto.modified) {
            let p: Project
            if let existing = projects[dto.uid] { p = existing } else {
                p = Project(title: dto.title); p.uid = dto.uid; p.modifiedAt = Self.notYet; context.insert(p); projects[dto.uid] = p
            }
            guard dto.modified > p.modifiedAt else { continue }
            p.title = dto.title; p.notes = dto.notes; p.order = dto.order; p.createdAt = dto.createdAt; p.statusRaw = dto.statusRaw
            p.completedAt = dto.completedAt; p.startRaw = dto.startRaw; p.startDate = dto.startDate; p.deadline = dto.deadline
            p.trashed = dto.trashed; p.modifiedAt = dto.modified
            projectLinks.append((p, dto))
        }
        for (p, dto) in projectLinks { p.area = resolve(dto.area).flatMap { areas[$0] } }

        var headings = index(Heading.self)
        for dto in remote.headings where !buried(dto.uid, dto.modified) {
            let h: Heading
            if let existing = headings[dto.uid] { h = existing } else {
                guard let project = dto.project.flatMap({ projects[$0] }) else { continue }
                h = Heading(title: dto.title, project: project); h.uid = dto.uid; h.modifiedAt = Self.notYet; context.insert(h); headings[dto.uid] = h
            }
            guard dto.modified > h.modifiedAt else { continue }
            h.title = dto.title; h.order = dto.order; h.modifiedAt = dto.modified
            h.project = dto.project.flatMap { projects[$0] }
        }

        var todos = index(TodoItem.self)
        for dto in remote.todos where !buried(dto.uid, dto.modified) {
            let t: TodoItem
            if let existing = todos[dto.uid] { t = existing } else {
                t = TodoItem(title: dto.title); t.uid = dto.uid; t.modifiedAt = Self.notYet; context.insert(t); todos[dto.uid] = t
            }
            guard dto.modified > t.modifiedAt else { continue }
            t.title = dto.title; t.notes = dto.notes; t.createdAt = dto.createdAt; t.order = dto.order; t.todayOrder = dto.todayOrder
            t.startRaw = dto.startRaw; t.startDate = dto.startDate; t.evening = dto.evening; t.deadline = dto.deadline
            t.statusRaw = dto.statusRaw; t.completedAt = dto.completedAt; t.trashed = dto.trashed; t.reminderAt = dto.reminderAt
            t.repeatRaw = dto.repeatRaw; t.nextUID = dto.nextUID
            t.project = dto.project.flatMap { projects[$0] }
            t.area = resolve(dto.area).flatMap { areas[$0] }
            t.heading = dto.heading.flatMap { headings[$0] }
            t.tags = dto.tags.compactMap { resolve($0).flatMap { tags[$0] } }
            t.modifiedAt = dto.modified
        }

        let steps = index(ChecklistItem.self)
        for dto in remote.steps where !buried(dto.uid, dto.modified) {
            let c: ChecklistItem
            if let existing = steps[dto.uid] { c = existing } else {
                guard dto.todo.flatMap({ todos[$0] }) != nil else { continue }
                c = ChecklistItem(title: dto.title); c.uid = dto.uid; c.modifiedAt = Self.notYet; context.insert(c)
            }
            guard dto.modified > c.modifiedAt else { continue }
            c.title = dto.title; c.done = dto.done; c.order = dto.order; c.modifiedAt = dto.modified
            c.todo = dto.todo.flatMap { todos[$0] }
        }

        try? context.save()
        applyingRemote = false
        removeTwins()
        Sync.run(context, state: nil)
    }

    /// Lo que existía igual en los dos equipos antes de sincronizar (la guía de inicio, por ejemplo) queda repetido.
    /// Se deja una sola copia de lo que nunca se cambió desde entonces. Los dos equipos borran la misma copia
    /// (la de identificador mayor), y el borrado viaja al otro como cualquier otro.
    private func removeTwins() {
        guard let context else { return }
        let untouched = Date(timeIntervalSinceReferenceDate: -1e10)
        var removed = false

        let projects = ((try? context.fetch(FetchDescriptor<Project>())) ?? []).filter { $0.modifiedAt < untouched }
        for group in Dictionary(grouping: projects, by: { [$0.title, $0.area?.title ?? "", $0.statusRaw, String($0.trashed)] }).values where group.count > 1 {
            let keep = group.min { $0.uid < $1.uid }!
            for p in group where p !== keep
                && p.todos.map(\.title).sorted() == keep.todos.map(\.title).sorted()
                && p.todos.allSatisfy({ $0.modifiedAt < untouched }) {
                context.delete(p)
                removed = true
            }
        }

        let todos = ((try? context.fetch(FetchDescriptor<TodoItem>())) ?? []).filter { $0.modifiedAt < untouched && !$0.isDeleted }
        func place(_ t: TodoItem) -> [String] {
            [t.title, t.notes, t.statusRaw, String(t.trashed), t.startRaw, t.project?.title ?? "", t.area?.title ?? "", t.heading?.title ?? ""]
        }
        for group in Dictionary(grouping: todos, by: place).values where group.count > 1 {
            let keep = group.min { $0.uid < $1.uid }!
            for t in group where t !== keep { context.delete(t); removed = true }
        }
        if removed { try? context.save() }
    }

    /// Fecha de lo que acaba de llegar y aún no tiene datos: cualquier versión que llegue es más nueva.
    private static let notYet = Date.distantPast.addingTimeInterval(-1)

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
}

// MARK: - Apoyo

private final class Peer {
    let connection: NWConnection
    var deviceID: String?
    var name: String?
    init(connection: NWConnection) { self.connection = connection }
}

/// Todo modelo que se sincroniza tiene identificador estable y fecha de cambio.
protocol Syncable: AnyObject {
    var uid: String { get set }
    var modifiedAt: Date { get set }
    /// Cuándo se creó, aproximado (para ordenar lo que es anterior a la sincronización).
    var creationRank: Double { get }
}
extension Area: Syncable { var creationRank: Double { createdAt.timeIntervalSinceReferenceDate } }
extension Project: Syncable { var creationRank: Double { createdAt.timeIntervalSinceReferenceDate } }
extension TodoItem: Syncable { var creationRank: Double { createdAt.timeIntervalSinceReferenceDate } }
extension Heading: Syncable { var creationRank: Double { order } }
extension ChecklistItem: Syncable { var creationRank: Double { order } }
extension TagItem: Syncable { var creationRank: Double { order } }

/// Identificadores de lo borrado, con su fecha. Se guardan 60 días.
enum Tombstones {
    private static let key = "hecho.sync.borrados"

    static var dates: [String: Date] {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: Date]) ?? [:]
    }
    static var all: [Tombstone] { dates.map { Tombstone(uid: $0.key, at: $0.value) } }

    static func add(_ uids: [String], at date: Date) {
        var d = dates
        for uid in uids { d[uid] = date }
        save(d)
    }

    static func merge(_ remote: [Tombstone]) {
        var d = dates
        for t in remote where (d[t.uid] ?? .distantPast) < t.at { d[t.uid] = t.at }
        save(d)
    }

    private static func save(_ d: [String: Date]) {
        let limit = Date().addingTimeInterval(-60 * 86_400)
        UserDefaults.standard.set(d.filter { $0.value > limit }, forKey: key)
    }
}

struct Tombstone: Codable { var uid: String; var at: Date }
struct AreaDTO: Codable { var uid: String; var modified: Date; var title: String; var order: Double; var createdAt: Date }
struct TagDTO: Codable { var uid: String; var modified: Date; var title: String; var order: Double }
struct ProjectDTO: Codable {
    var uid: String; var modified: Date; var title: String; var notes: String; var order: Double; var createdAt: Date
    var statusRaw: String; var completedAt: Date?; var startRaw: String; var startDate: Date?; var deadline: Date?
    var trashed: Bool; var area: String?
}
struct HeadingDTO: Codable { var uid: String; var modified: Date; var title: String; var order: Double; var project: String? }
struct TodoDTO: Codable {
    var uid: String; var modified: Date; var title: String; var notes: String; var createdAt: Date; var order: Double
    var todayOrder: Double; var startRaw: String; var startDate: Date?; var evening: Bool; var deadline: Date?
    var statusRaw: String; var completedAt: Date?; var trashed: Bool; var reminderAt: Date?; var repeatRaw: String?
    var nextUID: String?; var project: String?; var area: String?; var heading: String?; var tags: [String]
}
struct StepDTO: Codable { var uid: String; var modified: Date; var title: String; var done: Bool; var order: Double; var todo: String? }

struct Snapshot: Codable {
    var areas: [AreaDTO] = []
    var tags: [TagDTO] = []
    var projects: [ProjectDTO] = []
    var headings: [HeadingDTO] = []
    var todos: [TodoDTO] = []
    var steps: [StepDTO] = []
    var tombstones: [Tombstone] = []
}

struct SyncMessage: Codable {
    var device: String
    var name: String
    var snapshot: Snapshot
}
