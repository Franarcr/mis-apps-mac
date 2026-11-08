import SwiftUI
import WatchKit

/// El entreno en el reloj: un ejercicio y una serie a la vez. La corona cambia el peso (o las repeticiones),
/// ✓ marca la serie y empieza el descanso, que vibra al terminar.
struct WorkoutView: View {
    let routine: WatchRoutine
    let unit: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var workout = WorkoutManager()
    @State private var itemIndex = 0
    @State private var setIndex = 0
    @State private var weight: Double = 0
    @State private var reps: Double = 0
    @State private var editingReps = false
    @State private var done: [WatchDoneSet] = []
    @State private var restUntil: Date?
    @State private var confirmingEnd = false
    @State private var finished = false
    private let session = UUID()
    @State private var started = Date.now

    private var item: WatchItem? { routine.items.indices.contains(itemIndex) ? routine.items[itemIndex] : nil }
    private var planned: WatchSet? { item.flatMap { $0.plan.indices.contains(setIndex) ? $0.plan[setIndex] : $0.plan.last } }
    private var setCount: Int { max(item?.plan.count ?? 0, 1) }

    var body: some View {
        Group {
            if finished {
                summary
            } else if let restUntil {
                rest(until: restUntil)
            } else if let item {
                setScreen(item)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if !finished { Button { confirmingEnd = true } label: { Image(systemName: "xmark") } }
            }
        }
        .confirmationDialog("¿Terminar el entreno?", isPresented: $confirmingEnd) {
            Button("Guardar y terminar") { Task { await end() } }
            Button("Salir sin guardar", role: .destructive) { workout.discard(); dismiss() }
        }
        .task {
            started = .now
            loadPlanned()
            await workout.start()
        }
    }

    // MARK: Serie

    private func setScreen(_ item: WatchItem) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(item.name).font(.headline).lineLimit(2).minimumScaleFactor(0.7)
                Spacer()
                if let hr = workout.heartRate {
                    Label("\(Int(hr))", systemImage: "heart.fill").font(.caption2).foregroundStyle(.red)
                }
            }
            Text("Serie \(setIndex + 1) de \(setCount) · ejercicio \(itemIndex + 1)/\(routine.items.count)")
                .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                if item.weighted {
                    value(format(weight), unit, selected: !editingReps) { editingReps = false }
                }
                value("\(Int(reps))", "reps", selected: editingReps || !item.weighted) { editingReps = true }
            }
            .focusable()
            .digitalCrownRotation(crownBinding(item), from: 0, through: (editingReps || !item.weighted) ? 50 : 500,
                                  by: (editingReps || !item.weighted) ? 1 : (unit == "lb" ? 5 : 2.5),
                                  sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
            HStack {
                Button { skipExercise() } label: { Image(systemName: "forward.fill") }
                    .tint(.gray)
                Button { complete(item) } label: { Image(systemName: "checkmark").font(.title3.bold()) }
                    .tint(.green)
            }
        }
    }

    private func value(_ text: String, _ label: String, selected: Bool, onTap: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Text(text).font(.system(size: 30, weight: .bold, design: .rounded)).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 4)
        .background(selected ? Color.green.opacity(0.25) : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .onTapGesture(perform: onTap)
    }

    private func crownBinding(_ item: WatchItem) -> Binding<Double> {
        (editingReps || !item.weighted) ? $reps : $weight
    }

    // MARK: Descanso

    private func rest(until: Date) -> some View {
        VStack(spacing: 6) {
            Text("Descanso").font(.headline)
            Text(timerInterval: Date.now...max(until, .now), countsDown: true)
                .font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.cyan)
            if let item, let next = planned {
                Text("Sigue: \(item.name)\n\(item.weighted ? "\(format(next.weight ?? weight)) \(unit) × " : "")\(next.reps)")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Button("Seguir ya") { restUntil = nil }.tint(.cyan)
        }
        .task(id: until) {
            try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow)))
            if restUntil == until {
                WKInterfaceDevice.current().play(.notification)
                restUntil = nil
            }
        }
    }

    // MARK: Resumen

    private var summary: some View {
        ScrollView {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                Text("\(done.count) series").font(.title3.bold())
                Text("\(Int(workout.calories)) kcal · \(Int(Date.now.timeIntervalSince(started) / 60)) min").foregroundStyle(.secondary)
                Text("Guardado en Salud. Las series pasan al iPhone.").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Listo") { dismiss() }.tint(.green)
            }
        }
    }

    // MARK: Lógica

    private func loadPlanned() {
        guard let planned else { return }
        if let w = planned.weight { weight = w }
        reps = Double(planned.reps)
        editingReps = false
    }

    private func complete(_ item: WatchItem) {
        done.append(WatchDoneSet(exerciseID: item.exerciseID, index: setIndex,
                                 weight: item.weighted ? weight : nil, reps: Int(reps)))
        WKInterfaceDevice.current().play(.success)
        if setIndex + 1 < setCount {
            setIndex += 1
        } else if itemIndex + 1 < routine.items.count {
            itemIndex += 1
            setIndex = 0
        } else {
            Task { await end() }
            return
        }
        // El peso de la serie anterior se mantiene si la siguiente no trae uno propio.
        let keep = weight
        loadPlanned()
        if planned?.weight == nil { weight = keep }
        restUntil = .now.addingTimeInterval(TimeInterval(item.rest))
    }

    private func skipExercise() {
        if itemIndex + 1 < routine.items.count {
            itemIndex += 1
            setIndex = 0
            loadPlanned()
        } else {
            confirmingEnd = true
        }
    }

    private func end() async {
        guard !finished else { return }
        finished = true
        restUntil = nil
        if done.isEmpty {
            workout.discard()
            dismiss()
            return
        }
        await workout.finish(name: routine.name, sets: done.count)
        WatchStore.shared.send(WatchResult(session: session, routineName: routine.name, start: started, end: .now,
                                           unit: unit, sets: done))
    }

    private func format(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(w))" : String(format: "%.1f", w)
    }
}
