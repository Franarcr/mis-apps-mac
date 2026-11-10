import SwiftUI

/// Ajustes: calendario y avisos.
struct SettingsView: View {
    @Environment(CalendarFeed.self) private var calendar
    @Environment(\.dismiss) private var dismiss
    @State private var notificationsOK = false

    var body: some View {
        @Bindable var calendar = calendar
        NavigationStack {
            Form {
                Section {
                    Toggle("Mostrar mis eventos en Hoy y Próximo", isOn: Binding(
                        get: { calendar.enabled && calendar.authorized },
                        set: { on in
                            if on {
                                Task {
                                    let ok = calendar.authorized ? true : await calendar.requestAccess()
                                    calendar.enabled = ok
                                }
                            } else {
                                calendar.enabled = false
                            }
                        }))
                    if calendar.enabled && calendar.authorized {
                        ForEach(calendar.calendars, id: \.calendarIdentifier) { cal in
                            Toggle(isOn: Binding(
                                get: { !calendar.hidden.contains(cal.calendarIdentifier) },
                                set: { show in
                                    if show { calendar.hidden.remove(cal.calendarIdentifier) } else { calendar.hidden.insert(cal.calendarIdentifier) }
                                })) {
                                Label {
                                    Text(cal.title)
                                } icon: {
                                    Circle().fill(Color(cgColor: cal.cgColor)).frame(width: 10, height: 10)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Calendario")
                } footer: {
                    if calendar.enabled && !calendar.authorized {
                        Text("Hecho no tiene permiso para leer tu calendario. Actívalo en Ajustes del sistema › Privacidad › Calendarios.")
                    } else {
                        Text("Hecho solo lee tus eventos para mostrarlos; no los cambia.")
                    }
                }

                Section {
                    Toggle("Pasar las tareas con fecha a mi calendario", isOn: Binding(
                        get: { calendar.exportEnabled && calendar.authorized },
                        set: { on in
                            if on {
                                Task {
                                    let ok = calendar.authorized ? true : await calendar.requestAccess()
                                    calendar.exportEnabled = ok
                                }
                            } else {
                                calendar.exportEnabled = false
                            }
                        }))
                    if calendar.exportEnabled && calendar.authorized {
                        Picker("Calendario", selection: Binding(
                            get: { calendar.exportCalendar?.calendarIdentifier ?? "" },
                            set: { calendar.exportCalendarID = $0 })) {
                            ForEach(calendar.writableCalendars, id: \.calendarIdentifier) { cal in
                                Text(cal.title + " (" + cal.source.title + ")").tag(cal.calendarIdentifier)
                            }
                        }
                    }
                } header: {
                    Text("Tareas en el calendario")
                } footer: {
                    Text("Cada tarea con fecha aparece como evento: a la hora del aviso, o de todo el día si no tiene aviso. Si cambias la fecha, el evento se mueve; si la completas o la borras, se quita. Nunca se duplica aunque uses Hecho en el Mac y en el iPhone. En cada tarea puedes elegir otro calendario.")
                }

                Section {
                    HStack {
                        Label("Avisos", systemImage: "bell")
                        Spacer()
                        if notificationsOK {
                            Text("Permitidos").foregroundStyle(.secondary)
                        } else {
                            Button("Permitir") {
                                Task { notificationsOK = await Reminders.requestPermission() }
                            }
                        }
                    }
                } footer: {
                    Text("Para recibir un aviso, abre una tarea, toca el calendario y activa «Avisarme». Si antes dijiste que no, actívalos en Ajustes del sistema › Notificaciones › Hecho.")
                }

                Section {
                    let sync = PeerSync.shared
                    if sync.peerNames.isEmpty {
                        Label("Buscando otro equipo con Hecho abierto…", systemImage: "wifi")
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Conectado con " + sync.peerNames.joined(separator: ", "), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    if let last = sync.lastSync {
                        Text("Última sincronización: " + last.formatted(date: .omitted, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                    if let problem = sync.problem {
                        Text(problem).foregroundStyle(.orange)
                    }
                } header: {
                    Text("Sincronización por Wi-Fi")
                } footer: {
                    Text("Con Hecho abierto en el Mac y en el iPhone, en la misma red, se pasan las tareas solas. Si cambias lo mismo en los dos, queda el cambio más reciente.")
                }

                #if os(iOS)
                Section {
                    Text("Mantén presionada la pantalla de inicio, toca «Editar» › «Añadir widget» y busca Hecho para ver tus tareas de Hoy y marcarlas sin abrir la app.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Widget")
                }
                #endif
            }
            .formStyle(.grouped)
            .navigationTitle("Ajustes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
            .task { notificationsOK = await Reminders.authorized() }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 340, idealHeight: 480)
        #endif
    }
}
