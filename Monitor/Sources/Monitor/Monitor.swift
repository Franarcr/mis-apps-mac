import Foundation

/// Últimos `capacity` valores de una métrica, para las gráficas.
struct Series: Equatable {
    static let capacity = 60
    private(set) var values: [Double] = []

    var last: Double { values.last ?? 0 }

    mutating func push(_ value: Double) {
        values.append(value)
        if values.count > Self.capacity { values.removeFirst(values.count - Self.capacity) }
    }
}

/// Toma una muestra de todos los recursos cada segundo.
@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var cpu = Series()
    @Published private(set) var memory = Series()
    @Published private(set) var memoryUsed: UInt64 = 0
    @Published private(set) var gpu = Series()
    @Published private(set) var gpuAvailable = false
    @Published private(set) var temperature = Series()
    @Published private(set) var thermalState = ThermalStats.state
    @Published private(set) var throttling = false
    @Published private(set) var power = Series()
    @Published private(set) var connection: ConnectionInfo?
    @Published private(set) var download = Series()
    @Published private(set) var upload = Series()
    @Published private(set) var diskRead = Series()
    @Published private(set) var diskWrite = Series()
    @Published private(set) var diskSpace: (free: Int64, total: Int64)?
    @Published private(set) var battery: BatteryInfo?
    @Published private(set) var topProcesses: [ProcessUsage] = []

    let machineName = Host.current().localizedName ?? "Mac"

    /// Se llama tras cada muestra (para actualizar la barra de menú).
    var onTick: (() -> Void)?

    let connectionReader = ConnectionReader()
    private let cpuSampler = CPUSampler()
    private var network = RateCounter()
    private var disk = RateCounter()
    private var ticks = 0
    private var timer: Timer?
    private var loadingProcesses = false

    func start() {
        guard timer == nil else { return }
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func tick() {
        if let value = cpuSampler.sample() { cpu.push(value) }

        if let used = MemoryStats.used() {
            memoryUsed = used
            memory.push(Double(used) / Double(MemoryStats.total))
        }

        if let value = GPUStats.utilization() {
            gpuAvailable = true
            gpu.push(value)
        }

        if let value = ThermalStats.chipTemperature() { temperature.push(value) }
        thermalState = ThermalStats.state
        throttling = ThermalStats.isThrottling
        if let watts = PowerStats.systemWatts() { power.push(watts) }

        if let totals = NetworkStats.totals(), let (down, up) = network.rates(a: totals.received, b: totals.sent) {
            download.push(down)
            upload.push(up)
        }

        let io = DiskStats.totals()
        if let (read, write) = disk.rates(a: io.read, b: io.written) {
            diskRead.push(read)
            diskWrite.push(write)
        }

        // Lo que cambia despacio se lee con menos frecuencia.
        if ticks % 30 == 0 { diskSpace = DiskStats.space() }
        if ticks % 10 == 0 { battery = BatteryStats.read() }
        if ticks % 5 == 0 { refreshConnection() }
        if ticks % 3 == 0 { refreshProcesses() }
        ticks += 1
        onTick?()
    }

    func refreshConnection() {
        connection = connectionReader.read()
    }

    private func refreshProcesses() {
        guard !loadingProcesses else { return }
        loadingProcesses = true
        DispatchQueue.global(qos: .utility).async {
            let top = ProcessStats.top(3)
            DispatchQueue.main.async {
                self.topProcesses = top
                self.loadingProcesses = false
            }
        }
    }
}
