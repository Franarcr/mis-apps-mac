import SwiftUI

/// Salud: la recuperación (fija al despertar, con la del momento en el anillo interno) y lo principal de la noche.
struct HealthPage: View {
    @ObservedObject var store: WatchStore

    private var snap: WatchSnapshot? {
        guard let s = store.payload?.snapshot, Calendar.current.isDateInToday(s.date) else { return nil }
        return s
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ring
                if let snap {
                    row("Sueño", snap.sleepHours.map { hours($0) }, icon: "bed.double.fill", color: .indigo,
                        good: snap.sleepHours.map { $0 >= 7 })
                    row("VFC", snap.hrv.map { "\(Int($0.rounded())) ms" }, icon: "waveform.path.ecg", color: .cyan,
                        detail: snap.hrvBase.map { "normal \(Int($0.rounded()))" }, good: pair(snap.hrv, snap.hrvBase).map { $0 >= $1 })
                    row("Reposo", snap.restingHR.map { "\(Int($0.rounded())) lpm" }, icon: "heart.fill", color: .red,
                        detail: snap.restingBase.map { "normal \(Int($0.rounded()))" }, good: pair(snap.restingHR, snap.restingBase).map { $0 <= $1 })
                    row("Estrés", snap.stress.map { "\($0)" }, icon: "brain.head.profile", color: .orange,
                        detail: snap.energy.map { "energía \($0)" }, good: snap.stress.map { $0 < 30 })
                    Text("Del iPhone \(snap.date.formatted(.relative(presentation: .named)))")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let expiry = snap.expiry, expiry.timeIntervalSinceNow < 2 * 86400 {
                        Label("Vital caduca \(expiry.formatted(.relative(presentation: .named)))", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                } else {
                    Text("Abre Vital en el iPhone para traer los datos de hoy.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
        }
        .navigationTitle("Salud")
    }

    private var ring: some View {
        let fixed = snap?.recovery
        let live = snap?.live.flatMap { $0 != fixed ? $0 : nil }
        return ZStack {
            Circle().stroke(.white.opacity(0.12), lineWidth: 10)
            if let fixed {
                Circle().trim(from: 0, to: Double(fixed) / 100)
                    .stroke(color(fixed).gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            if let live {
                Circle().stroke(.white.opacity(0.08), lineWidth: 4).padding(13)
                Circle().trim(from: 0, to: Double(live) / 100)
                    .stroke(color(live).opacity(0.75), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90)).padding(13)
            }
            VStack(spacing: 0) {
                Text(fixed.map(String.init) ?? "–")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(fixed.map(color) ?? .secondary)
                Text("RECUPERACIÓN").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                if let live { Text("ahora \(live)").font(.caption2.weight(.semibold)).foregroundStyle(color(live)) }
            }
        }
        .frame(width: 120, height: 120)
    }

    private func row(_ title: String, _ value: String?, icon: String, color: Color, detail: String? = nil, good: Bool? = nil) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(color).frame(width: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value ?? "–").font(.headline)
            }
            Spacer()
            if let detail { Text(detail).font(.caption2).foregroundStyle(good == false ? .orange : .secondary) }
        }
        .padding(.horizontal, 4)
    }

    private func hours(_ h: Double) -> String { "\(Int(h)) h \(Int((h - Double(Int(h))) * 60)) min" }
    private func color(_ score: Int) -> Color { score >= 67 ? .green : score >= 34 ? .orange : .red }
}

private func pair(_ a: Double?, _ b: Double?) -> (Double, Double)? {
    guard let a, let b else { return nil }
    return (a, b)
}
