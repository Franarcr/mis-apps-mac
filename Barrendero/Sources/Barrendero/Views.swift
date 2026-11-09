import AppKit
import SwiftUI

/// Lista para confirmar: correos agrupados por la regla que los atrapó.
struct ReviewView: View {
    @ObservedObject var state: SweepState
    let sweep: () -> Void
    let close: () -> Void

    private var groups: [(String, [Candidate])] {
        Dictionary(grouping: state.candidates, by: \.reason).sorted { $0.value.count > $1.value.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(state.selected.count) correos para la papelera").font(.title2.bold())
                Spacer()
                Text("de \(state.candidates.count) encontrados").foregroundStyle(.secondary)
            }
            Text("Mail apartó esto en «Barridos» según tus reglas, más el correo no deseado de cada cuenta. Lo marcado va a la papelera (se puede recuperar); lo desmarcado vuelve a la bandeja de entrada.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            List {
                ForEach(groups, id: \.0) { reason, items in
                    DisclosureGroup {
                        ForEach(items.prefix(30)) { item in
                            HStack {
                                Text(item.subject.isEmpty ? "(sin asunto)" : item.subject).lineLimit(1)
                                Spacer()
                                Text(item.received.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                        if items.count > 30 {
                            Text("…y \(items.count - 30) más").font(.caption).foregroundStyle(.secondary)
                        }
                    } label: {
                        Toggle(isOn: Binding(
                            get: { !state.excluded.contains(reason) },
                            set: { on in if on { state.excluded.remove(reason) } else { state.excluded.insert(reason) } }
                        )) {
                            HStack {
                                Text(reason).fontWeight(.medium)
                                Text(Set(items.map(\.account)).sorted().joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text("\(items.count)").monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            if let busy = state.busy {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(busy).font(.callout)
                }
            }
            Toggle("Dejar de barrer a los remitentes que desmarque", isOn: $state.forgetUnchecked)
                .toggleStyle(.checkbox)
            HStack {
                Button("Marcar todo") { state.excluded = [] }
                Button("Desmarcar todo") { state.excluded = Set(state.candidates.map(\.reason)) }
                Spacer()
                Button("Ahora no") { close() }.keyboardShortcut(.cancelAction)
                Button(state.unselected.isEmpty ? "Mover \(state.selected.count) a la papelera"
                       : "Mover \(state.selected.count) a la papelera y devolver \(state.unselected.count)") { sweep() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(state.candidates.isEmpty || state.busy != nil)
            }
        }
        .padding(20)
        .frame(minWidth: 600, minHeight: 420)
    }
}

/// Reglas: remitentes, avisos por asunto, excepciones y correo no deseado.
struct RulesView: View {
    @ObservedObject var state: SweepState
    @State private var newSender = ""
    @State private var newRuleSender = ""
    @State private var newRuleSubject = ""
    @State private var newException = ""
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Vaciar también el correo no deseado de cada cuenta", isOn: $state.rules.emptyJunk)

            GroupBox("Remitentes que se barren (\(state.rules.senders.count))") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("Dirección o dominio, p. ej. ofertas@tienda.com o tienda.com", text: $newSender)
                            .onSubmit(addSender)
                        Button("Agregar", action: addSender).disabled(newSender.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    TextField("Buscar en la lista", text: $search)
                    List {
                        ForEach(state.rules.senders.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }, id: \.self) { sender in
                            HStack {
                                Text(sender)
                                Spacer()
                                Button { state.rules.senders.removeAll { $0 == sender } } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless)
                                    .help("Dejar de barrer este remitente")
                            }
                        }
                    }
                    .frame(minHeight: 180)
                }
                .padding(4)
            }

            GroupBox("Avisos por asunto (solo se barren si el asunto coincide)") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(state.rules.subjectRules) { rule in
                        HStack {
                            Text(rule.sender).fontWeight(.medium)
                            Text("con asunto «\(rule.subject)»").foregroundStyle(.secondary)
                            Spacer()
                            Button { state.rules.subjectRules.removeAll { $0.id == rule.id } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                    HStack {
                        TextField("Remitente", text: $newRuleSender).frame(width: 180)
                        TextField("Texto del asunto", text: $newRuleSubject)
                        Button("Agregar") {
                            state.rules.subjectRules.append(SubjectRule(sender: newRuleSender.trimmingCharacters(in: .whitespaces),
                                                                        subject: newRuleSubject.trimmingCharacters(in: .whitespaces)))
                            newRuleSender = ""
                            newRuleSubject = ""
                        }
                        .disabled(newRuleSender.isEmpty || newRuleSubject.isEmpty)
                    }
                }
                .padding(4)
            }

            GroupBox("Nunca barrer (aunque coincida con una regla)") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.rules.neverSweep.joined(separator: " · ")).font(.callout).textSelection(.enabled)
                    HStack {
                        TextField("p. ej. poder-judicial.go.cr", text: $newException)
                        Button("Agregar") {
                            state.rules.neverSweep.append(newException.trimmingCharacters(in: .whitespaces).lowercased())
                            newException = ""
                        }
                        .disabled(newException.trimmingCharacters(in: .whitespaces).isEmpty)
                        Menu("Quitar") {
                            ForEach(state.rules.neverSweep, id: \.self) { item in
                                Button(item) { state.rules.neverSweep.removeAll { $0 == item } }
                            }
                        }
                        .fixedSize()
                    }
                }
                .padding(4)
            }
            HStack {
                Button("Volver a las reglas originales") { state.rules = .defaults }
                Spacer()
                Button("Mostrar el archivo de reglas") { NSWorkspace.shared.activateFileViewerSelecting([SweepRules.url]) }
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(20)
        .frame(minWidth: 560, minHeight: 520)
    }

    private func addSender() {
        let value = newSender.trimmingCharacters(in: .whitespaces).lowercased()
        guard !value.isEmpty, !state.rules.senders.contains(value) else { return }
        state.rules.senders.append(value)
        newSender = ""
    }
}
