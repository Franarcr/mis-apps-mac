// Lee y crea recordatorios sin abrir la app Recordatorios (EventKit).
//   recordatorios listar "Recordatorios" "Pagar Naret"
//       -> una línea por recordatorio: hecho(0/1) \t fecha-hecho(aaaa-mm-dd o vacío) \t FT \t título
//   recordatorios crear "Recordatorios" "título" "notas" aaaa-mm-dd
//       -> crea (si no existe uno pendiente igual) con fecha ese día 9:00 y aviso en 1 minuto
import EventKit
import Foundation

let store = EKEventStore()
let sem = DispatchSemaphore(value: 0)
var ok = false
if #available(macOS 14.0, *) {
    store.requestFullAccessToReminders { g, _ in ok = g; sem.signal() }
} else {
    store.requestAccess(to: .reminder) { g, _ in ok = g; sem.signal() }
}
sem.wait()
guard ok else { FileHandle.standardError.write("sin permiso para Recordatorios\n".data(using: .utf8)!); exit(2) }

let a = CommandLine.arguments
guard a.count >= 3, let lista = store.calendars(for: .reminder).first(where: { $0.title == a[2] }) else {
    FileHandle.standardError.write("lista no encontrada\n".data(using: .utf8)!); exit(3)
}

func todos() -> [EKReminder] {
    var res: [EKReminder] = []
    let s = DispatchSemaphore(value: 0)
    store.fetchReminders(matching: store.predicateForReminders(in: [lista])) { r in res = r ?? []; s.signal() }
    s.wait()
    return res
}

let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
switch a[1] {
case "listar":
    let prefijo = a.count > 3 ? a[3] : ""
    for r in todos() where (r.title ?? "").hasPrefix(prefijo) {
        let notas = r.notes ?? ""
        var ft = ""
        if let rg = notas.range(of: "FT[0-9]+", options: .regularExpression) { ft = String(notas[rg]) }
        let cd = r.completionDate.map { fmt.string(from: $0) } ?? ""
        print("\(r.isCompleted ? 1 : 0)\t\(cd)\t\(ft)\t\(r.title ?? "")")
    }
case "crear":
    guard a.count >= 6, let dia = fmt.date(from: a[5]) else { exit(4) }
    if todos().contains(where: { $0.title == a[3] && !$0.isCompleted }) { print("ya"); exit(0) }
    let r = EKReminder(eventStore: store)
    r.calendar = lista
    r.title = a[3]
    r.notes = a[4]
    var c = Calendar.current.dateComponents([.year, .month, .day], from: dia)
    c.hour = 9; c.minute = 0
    r.dueDateComponents = c
    r.addAlarm(EKAlarm(absoluteDate: Date().addingTimeInterval(60)))
    try store.save(r, commit: true)
    print("nuevo")
default:
    exit(1)
}
