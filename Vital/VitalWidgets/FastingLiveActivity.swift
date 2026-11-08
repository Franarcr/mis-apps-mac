import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// El ayuno en la pantalla bloqueada y en la Dynamic Island. El tiempo corre solo (temporizadores del sistema);
/// al pasar la meta la actividad queda «stale» y se muestra como cumplida.
struct FastingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FastingActivityAttributes.self) { context in
            LockScreenView(state: context.state, reached: context.isStale)
                .activityBackgroundTint(.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            let reached = context.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Ayuno", systemImage: "timer").font(.headline).foregroundStyle(.indigo)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(reached ? "Meta cumplida" : "Meta \(state.goalDate.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(reached ? .green : .secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(timerInterval: state.start...Date.distantFuture, countsDown: false)
                                .font(.title2.bold()).monospacedDigit()
                            Text("de \(Int(state.goalHours)) h").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(intent: EndFastIntent()) {
                                Label("Terminar", systemImage: "fork.knife")
                            }
                            .tint(reached ? .green : .indigo)
                        }
                        ProgressView(timerInterval: state.start...state.goalDate, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                            .tint(reached ? .green : .indigo)
                    }
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(reached ? .green : .indigo)
            } compactTrailing: {
                Text(timerInterval: state.start...Date.distantFuture, countsDown: false)
                    .monospacedDigit().frame(maxWidth: 56)
                    .foregroundStyle(reached ? .green : .white)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(reached ? .green : .indigo)
            }
        }
    }
}

private struct LockScreenView: View {
    let state: FastingActivityAttributes.ContentState
    let reached: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Image(systemName: "timer").font(.title2).foregroundStyle(reached ? .green : .indigo)
                VStack(alignment: .leading, spacing: 0) {
                    Text(reached ? "¡Meta cumplida!" : "Ayuno · meta \(state.goalDate.formatted(date: .omitted, time: .shortened))")
                        .font(.caption.weight(.semibold)).foregroundStyle(reached ? .green : .secondary)
                    Text(timerInterval: state.start...Date.distantFuture, countsDown: false)
                        .font(.title.bold()).monospacedDigit()
                }
                Spacer()
                Button(intent: EndFastIntent()) {
                    Label("Terminar", systemImage: "fork.knife").font(.callout.bold())
                }
                .tint(reached ? .green : .indigo)
            }
            ProgressView(timerInterval: state.start...state.goalDate, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .tint(reached ? .green : .indigo)
        }
        .padding(16)
    }
}
