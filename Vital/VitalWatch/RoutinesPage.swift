import SwiftUI

/// Rutinas: la lista que mandó el iPhone. Al tocar una empieza el entreno.
struct RoutinesPage: View {
    @ObservedObject var store: WatchStore

    var body: some View {
        List {
            let routines = store.payload?.routines ?? []
            if routines.isEmpty {
                Text("Abre Vital en el iPhone para traer tus rutinas.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(routines) { routine in
                NavigationLink(value: routine) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(routine.name).font(.headline)
                        Text("\(routine.items.count) ejercicios").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Rutinas")
        .navigationDestination(for: WatchRoutine.self) { WorkoutView(routine: $0, unit: store.unit) }
    }
}
