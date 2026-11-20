import AVFoundation
import Accelerate
import QuartzCore
import SwiftUI

/// Una nota que el iPad oyó: cuándo empezó (reloj de CACurrentMediaTime) y su altura MIDI.
struct HeardNote {
    let time: Double
    let midi: Int
}

/// Escucha el micrófono: nivel, frecuencia actual (para el afinador) y notas nuevas (para el juego).
@MainActor
final class Listener: ObservableObject {
    @Published private(set) var level: Float = 0
    @Published private(set) var frequency: Double?
    @Published private(set) var running = false
    @Published private(set) var denied = false

    /// Lo llama el juego cada vez que empieza una nota nueva.
    var onNote: ((HeardNote) -> Void)?

    private let engine = AVAudioEngine()
    private var processor: PitchProcessor?

    /// Cuántas pantallas lo están usando; se apaga cuando no queda ninguna.
    private var users = 0

    func start() {
        users += 1
        guard !running else { return }
        AVAudioApplication.requestRecordPermission { ok in
            Task { @MainActor in
                if ok { self.begin() } else { self.denied = true }
            }
        }
    }

    private func begin() {
        guard !running, users > 0 else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            // «measurement» quita el control automático de volumen y los filtros de voz.
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
            let latency = session.inputLatency + session.ioBufferDuration

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else { return }
            let proc = PitchProcessor(sampleRate: format.sampleRate, latency: latency) { [weak self] update in
                DispatchQueue.main.async { self?.receive(update) }
            }
            processor = proc
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                proc.process(buffer)
            }
            try engine.start()
            running = true
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            running = false
        }
    }

    func stop() {
        users = max(0, users - 1)
        guard users == 0, running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        running = false
        level = 0
        frequency = nil
    }

    private func receive(_ u: PitchProcessor.Update) {
        level = u.level
        frequency = u.frequency
        for n in u.notes { onNote?(n) }
    }
}

/// Hace el trabajo pesado fuera del hilo principal: busca la frecuencia con el método YIN
/// y decide cuándo empieza una nota (golpe de púa o cambio de nota).
final class PitchProcessor: @unchecked Sendable {
    struct Update {
        var level: Float
        var frequency: Double?
        var notes: [HeardNote]
    }

    private let sampleRate: Double
    private let latency: Double
    private let send: (Update) -> Void

    private let window = 2048
    private let hop = 512
    private let minTau: Int
    private let maxTau: Int
    private var samples: [Float] = []
    private var diff: [Float]

    /// Por debajo de este nivel se considera silencio.
    private let gate: Float = 0.006
    private var lastLevel: Float = 0
    private var onsetTime: Double?
    private var onsetSent = false
    private var lastOnset: Double = -.infinity
    private var candidate: Int?
    private var candidateCount = 0
    private var stableMidi: Int?

    init(sampleRate: Double, latency: Double, send: @escaping (Update) -> Void) {
        self.sampleRate = sampleRate
        self.latency = latency
        self.send = send
        // De 65 Hz (bajo el Mi♭ grave) a 1200 Hz (traste 15 de la primera cuerda, con margen).
        minTau = max(2, Int(sampleRate / 1200))
        maxTau = min(Int(sampleRate / 65), 2048 / 2 + 300)
        diff = [Float](repeating: 0, count: maxTau + 2)
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        let arrival = CACurrentMediaTime()
        samples.append(contentsOf: UnsafeBufferPointer(start: ch, count: count))

        var update = Update(level: 0, frequency: nil, notes: [])
        var analyzed = false
        while samples.count >= window {
            // Momento (aproximado) en que sonó el centro de esta ventana.
            let samplesAfter = samples.count - window
            let time = arrival - latency - Double(samplesAfter + window / 2) / sampleRate
            let frame = samples.withUnsafeBufferPointer { analyze($0.baseAddress!, time: time) }
            update.level = frame.level
            update.frequency = frame.frequency
            if let n = frame.note { update.notes.append(n) }
            samples.removeFirst(hop)
            analyzed = true
        }
        if analyzed { send(update) }
    }

    private struct Frame {
        var level: Float
        var frequency: Double?
        var note: HeardNote?
    }

    private func analyze(_ x: UnsafePointer<Float>, time: Double) -> Frame {
        var rms: Float = 0
        vDSP_rmsqv(x, 1, &rms, vDSP_Length(window))
        var frame = Frame(level: rms)

        // Golpe: el volumen sube de golpe después de una caída o desde el silencio.
        if rms > gate, rms > lastLevel * 1.5, time - lastOnset > 0.07 {
            startNote(at: time)
        }
        lastLevel = rms
        if rms < gate {
            stableMidi = nil
            candidate = nil
            candidateCount = 0
            return frame
        }

        guard let f = yin(x) else { return frame }
        frame.frequency = f
        let midi = Int((69 + 12 * log2(f / 440)).rounded())

        if midi == candidate { candidateCount += 1 } else { candidate = midi; candidateCount = 1 }
        guard candidateCount >= 2 else { return frame }

        // Cambio de nota sin golpe fuerte (ligado, slide): también cuenta como nota nueva.
        if let stable = stableMidi, stable != midi, onsetSent {
            startNote(at: time - Double(hop) / sampleRate)
        }
        stableMidi = midi

        // Solo se usa una ventana que empieza después del golpe; si no, todavía suena la nota anterior.
        let windowStart = time - Double(window / 2) / sampleRate
        if let start = onsetTime, !onsetSent, windowStart >= start - 0.01, time - start < 0.35 {
            onsetSent = true
            frame.note = HeardNote(time: start, midi: midi)
        }
        return frame
    }

    private func startNote(at time: Double) {
        onsetTime = time
        onsetSent = false
        lastOnset = time
    }

    /// Método YIN (de Cheveigné y Kawahara, 2002) para hallar la frecuencia fundamental.
    private func yin(_ x: UnsafePointer<Float>) -> Double? {
        let w = window - maxTau
        guard w > 0 else { return nil }
        diff.withUnsafeMutableBufferPointer { d in
            for tau in 1...maxTau {
                vDSP_distancesq(x, 1, x + tau, 1, &d[tau], vDSP_Length(w))
            }
        }
        // Diferencia normalizada acumulada.
        var running: Float = 0
        var cmnd = [Float](repeating: 1, count: maxTau + 1)
        for tau in 1...maxTau {
            running += diff[tau]
            cmnd[tau] = running > 0 ? diff[tau] * Float(tau) / running : 1
        }
        let threshold: Float = 0.15
        var tau = minTau
        var found = false
        while tau < maxTau {
            if cmnd[tau] < threshold {
                while tau + 1 < maxTau, cmnd[tau + 1] < cmnd[tau] { tau += 1 }
                found = true
                break
            }
            tau += 1
        }
        guard found else { return nil }

        // Interpolación parabólica para afinar el periodo.
        var better = Double(tau)
        if tau > 1, tau < maxTau {
            let a = Double(cmnd[tau - 1]), b = Double(cmnd[tau]), c = Double(cmnd[tau + 1])
            let den = a + c - 2 * b
            if abs(den) > 1e-9 { better += (a - c) / (2 * den) }
        }
        return sampleRate / better
    }
}
