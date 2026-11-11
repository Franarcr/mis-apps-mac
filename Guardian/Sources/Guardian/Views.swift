import AppKit
import SwiftUI

/// Recuadro de ayuda al principio de cada ventana: qué muestra y qué hacer con ello.
struct Guide: View {
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(.blue).font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
}

// MARK: Programas

struct ProgramsView: View {
    @ObservedObject var state: GuardState
    @State private var filter = Filter.attention
    @State private var search = ""

    enum Filter: String, CaseIterable, Identifiable {
        case attention = "Para revisar"
        case remote = "Acceso remoto"
        case autostart = "Arrancan solos"
        case all = "Todos"
        var id: String { rawValue }
    }

    private var shown: [Program] {
        state.programs.filter { program in
            let matches: Bool
            switch filter {
            case .attention: matches = program.needsAttention
            case .remote: matches = program.capabilities.contains(.remote)
            case .autostart: matches = program.capabilities.contains(.autostart)
            case .all: matches = true
            }
            return matches && (search.isEmpty || program.name.localizedCaseInsensitiveContains(search)
                || program.developer.localizedCaseInsensitiveContains(search))
        }
        .sorted { ($0.needsAttention ? 0 : 1, $0.verdict, $0.name) < ($1.needsAttention ? 0 : 1, $1.verdict, $1.name) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Guide(title: "Qué programas tienes y si son de fiar",
                  text: "Guardián mira la firma de cada programa de Aplicaciones: quién lo hizo y si Apple lo revisó. Los marcados en ámbar o rojo, y los que dejan entrar a otra persona a tu Mac, salen en «Para revisar». Si no reconoces alguno, no lo abras y pregunta a quien te lo instaló. Guardián solo mira: no cambia ni borra nada.")

            if !state.systemAccess.filter(\.enabled).isEmpty || filter == .remote {
                SystemAccessBox(access: state.systemAccess)
            }

            HStack {
                Picker("Mostrar", selection: $filter) {
                    ForEach(Filter.allCases) { Text(label(for: $0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .hint("Elegir qué programas se ven en la lista")
                TextField("Buscar", text: $search).textFieldStyle(.roundedBorder).frame(width: 160)
                Button {
                    state.scanPrograms()
                } label: {
                    Label("Revisar otra vez", systemImage: "arrow.clockwise")
                }
                .disabled(state.scanning)
                .hint("Volver a revisar todos los programas instalados")
            }

            if state.scanning && state.programs.isEmpty {
                ProgressView("Revisando los programas…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shown.isEmpty {
                Text(filter == .attention ? "Nada para revisar: todos tus programas tienen una firma de confianza." : "No hay programas en esta lista.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(shown) { ProgramRow(program: $0) }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            if filter == .autostart && !state.orphanLaunchItems.isEmpty {
                OrphanItemsBox(items: state.orphanLaunchItems)
            }

            HStack {
                if let last = state.lastScan {
                    Text("\(state.programs.count) programas revisados · \(last.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if state.scanning { ProgressView().controlSize(.small) }
            }
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 560)
    }

    private func label(for filter: Filter) -> String {
        let count: Int
        switch filter {
        case .attention: count = state.programs.filter(\.needsAttention).count
        case .remote: count = state.programs.filter { $0.capabilities.contains(.remote) }.count
        case .autostart: count = state.programs.filter { $0.capabilities.contains(.autostart) }.count
        case .all: count = state.programs.count
        }
        return "\(filter.rawValue) (\(count))"
    }
}

struct ProgramRow: View {
    let program: Program

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: program.url.path))
                .resizable().frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(program.name).font(.body.weight(.semibold))
                    if !program.version.isEmpty { Text(program.version).font(.caption).foregroundStyle(.secondary) }
                    if program.running {
                        Badge(text: "Abierto", color: .secondary)
                            .hint("Este programa está funcionando ahora mismo")
                    }
                }
                HStack(spacing: 6) {
                    Badge(text: program.verdict.title, color: Color(nsColor: program.verdict.color))
                        .hint(program.verdict.explanation)
                    if !program.developer.isEmpty && program.verdict != .apple {
                        Text(program.developer).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if program.verdict.needsReview {
                    Text(program.verdict.explanation).font(.caption).foregroundStyle(.secondary)
                }
                if program.capabilities.contains(.remote) {
                    Text("Deja que otra persona vea y maneje este Mac. Si no lo usas, desinstálalo; si lo usas, revisa quién entra en «Conexiones».")
                        .font(.caption).foregroundStyle(.orange)
                }
                ForEach(program.launchItems) { item in
                    Text("Arranca solo · \(item.kind) · \(item.label)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                ForEach(Capability.allCases.filter { program.capabilities.contains($0) }, id: \.self) { cap in
                    Image(systemName: cap.symbol)
                        .foregroundStyle(cap == .remote ? .orange : .secondary)
                        .hint("\(cap.rawValue): \(cap.explanation)")
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([program.url])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .hint("Mostrar este programa en el Finder")
            }
        }
        .padding(.vertical, 4)
    }
}

struct SystemAccessBox: View {
    let access: [SystemAccess]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Accesos remotos de macOS").font(.subheadline.weight(.semibold))
            ForEach(access) { item in
                HStack(alignment: .top) {
                    Image(systemName: item.enabled ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(item.enabled ? .orange : .green)
                        .hint(item.enabled ? "Encendido" : "Apagado")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(item.name): \(item.enabled ? "encendido" : "apagado")").font(.callout.weight(.medium))
                        if item.enabled { Text(item.explanation + " Si no lo usas, apágalo en Ajustes › General › Compartir.").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if item.enabled, let url = URL(string: item.settingsURL) {
                        Button("Abrir Ajustes") { NSWorkspace.shared.open(url) }
                            .hint("Abrir Ajustes › General › Compartir para apagarlo")
                    }
                }
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct OrphanItemsBox: View {
    let items: [LaunchItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Otros que arrancan solos (sin app en Aplicaciones)").font(.subheadline.weight(.semibold))
            Text("Suelen ser restos de programas que ya desinstalaste, o ayudantes de impresoras y actualizadores. Si no reconoces alguno, pide ayuda antes de borrarlo.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(items) { item in
                HStack {
                    Text(item.label).font(.callout)
                    Text(item.kind).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([item.file])
                    } label: { Image(systemName: "folder") }
                        .buttonStyle(.borderless)
                        .hint("Mostrar su archivo en el Finder")
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: Conexiones de AnyDesk

struct ConnectionsView: View {
    @ObservedObject var state: GuardState
    var cut: () -> Void
    @State private var naming: String?
    @State private var newName = ""

    private static let dateStyle = Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "es"))

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Guide(title: "Quién entra a tu Mac por AnyDesk",
                  text: "Aquí ves cada equipo que se conectó a este Mac con AnyDesk, cuándo y cómo. Marca como «de confianza» los que son tuyos o de personas que conoces: Guardián te avisará siempre que alguien entre, y con más fuerza si es un equipo desconocido. Si ves una conexión que no esperabas, pulsa «Cortar ahora».")

            statusBox

            if state.unattended {
                HStack(alignment: .top) {
                    Image(systemName: "lock.open.fill").foregroundStyle(.orange)
                        .hint("Acceso desatendido encendido")
                    Text("El **acceso desatendido** está encendido: quien tenga la contraseña o un acceso guardado puede entrar sin que nadie acepte en pantalla. Si no lo necesitas, apágalo en AnyDesk › Ajustes › Seguridad.")
                        .font(.callout)
                }
                .padding(10)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            Text("Equipos que se han conectado").font(.headline)
            if state.devices.isEmpty {
                Text("Nadie se ha conectado a este Mac por AnyDesk.").foregroundStyle(.secondary)
            } else {
                List(state.devices, id: \.id) { device in
                    deviceRow(device)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .frame(minHeight: 140)
            }

            Text("Últimas conexiones").font(.headline)
            List(state.incoming.reversed().prefix(200)) { connection in
                HStack {
                    Text(connection.date.formatted(Self.dateStyle)).monospacedDigit().frame(width: 170, alignment: .leading)
                    Text(TrustedDevices.label(connection.remoteID))
                        .foregroundStyle(state.trusted[connection.remoteID] == nil ? .orange : .primary)
                    Spacer()
                    Text(connection.methodText).foregroundStyle(.secondary)
                        .hint(connection.methodExplanation)
                }
                .font(.callout)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
        .padding(16)
        .frame(minWidth: 680, minHeight: 620)
        .sheet(item: Binding(get: { naming.map(NamingID.init) }, set: { naming = $0?.id })) { item in
            VStack(alignment: .leading, spacing: 12) {
                Text("¿De quién es el equipo \(item.id)?").font(.headline)
                Text("Ponle un nombre para reconocerlo, por ejemplo «Mi MacBook» o «Fran, oficina».").font(.callout).foregroundStyle(.secondary)
                TextField("Nombre", text: $newName).textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancelar") { naming = nil }
                    Button("Marcar como de confianza") {
                        state.trust(item.id, name: newName)
                        naming = nil
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 400)
        }
    }

    private struct NamingID: Identifiable { let id: String }

    @ViewBuilder private var statusBox: some View {
        if let session = state.sessions.first {
            let id = session.remoteID ?? "?"
            let known = state.trusted[id] != nil
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: known ? "eye.fill" : "exclamationmark.triangle.fill")
                    .font(.title).foregroundStyle(known ? .blue : .red)
                    .hint(known ? "Hay alguien conectado desde un equipo de confianza" : "Hay alguien conectado desde un equipo que no marcaste como de confianza")
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.sessions.count > 1 ? "Hay \(state.sessions.count) conexiones abiertas ahora" : "Hay alguien conectado ahora").font(.headline)
                    Text("\(TrustedDevices.label(id)) · desde las \(session.since.formatted(date: .omitted, time: .shortened))")
                        .font(.callout).foregroundStyle(.secondary)
                    if state.isSameNetwork(id) {
                        Text("Está en tu misma red (casa u oficina).").font(.caption).foregroundStyle(.secondary)
                    } else if let address = state.addresses[id] {
                        Text("Entra desde otra red, dirección \(address).").font(.caption).foregroundStyle(.orange)
                    }
                }
                Spacer()
                Button(role: .destructive) { cut() } label: {
                    Label("Cortar ahora", systemImage: "xmark.octagon.fill")
                }
                .controlSize(.large)
                .hint("Cortar la conexión y cerrar AnyDesk: nadie podrá entrar hasta que lo vuelvas a abrir")
            }
            .padding(12)
            .background((known ? Color.blue : Color.red).opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
        } else {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill").font(.title2).foregroundStyle(.green)
                    .hint("No hay ninguna conexión abierta")
                Text("Ahora mismo no hay nadie conectado a este Mac por AnyDesk.").font(.callout)
                Spacer()
                if let own = state.ownID {
                    Text("El número de este Mac en AnyDesk es \(own)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func deviceRow(_ device: (id: String, last: Date, count: Int, methods: Set<String>)) -> some View {
        let name = state.trusted[device.id]
        return HStack(alignment: .top) {
            Image(systemName: name == nil ? "questionmark.circle.fill" : "checkmark.seal.fill")
                .foregroundStyle(name == nil ? .orange : .green)
                .hint(name == nil ? "Equipo sin revisar: márcalo si lo reconoces" : "Equipo de confianza")
            VStack(alignment: .leading, spacing: 2) {
                Text(name.map { "\($0) · \(device.id)" } ?? "Equipo \(device.id)").font(.callout.weight(.semibold))
                Text("\(device.count) \(device.count == 1 ? "vez" : "veces") · la última \(device.last.formatted(Self.dateStyle))")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if state.isSameNetwork(device.id) {
                        Badge(text: "Tu misma red", color: .green)
                            .hint("Entró desde la misma conexión a internet que este Mac: está en tu casa u oficina")
                    } else if let address = state.addresses[device.id] {
                        Badge(text: "Otra red · \(address)", color: .orange)
                            .hint("Entró desde fuera de tu casa u oficina")
                    }
                    if device.methods.contains("Token") {
                        Badge(text: "Tiene acceso guardado", color: .orange)
                            .hint("Puede volver a entrar sin contraseña y sin que nadie acepte. Para quitárselo: AnyDesk › Ajustes › Seguridad › Borrar todos los accesos guardados")
                    }
                }
            }
            Spacer()
            if name == nil {
                Button("Es de confianza…") {
                    newName = ""
                    naming = device.id
                }
                .hint("Ponerle nombre a este equipo y dejar de avisar como desconocido")
            } else {
                Button("Quitar confianza") { state.forget(device.id) }
                    .hint("Volver a avisar como desconocido cuando este equipo entre")
            }
        }
        .padding(.vertical, 3)
    }
}
