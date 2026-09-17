import Foundation
import Darwin
import IOKit
import IOKit.ps

struct BatteryInfo: Equatable {
    var level: Double          // 0...1
    var charging: Bool
    var minutesRemaining: Int? // nil if estimating / on AC
}

struct MetricsSnapshot: Equatable {
    var cpu: Double = 0                 // 0...1
    var gpu: Double = 0                 // 0...1
    var gpuAvailable = true             // false when this Mac exposes no GPU counter
    var systemWatts: Double? = nil      // instantaneous machine draw (Apple power telemetry)
    var memUsed: UInt64 = 0
    var memTotal: UInt64 = 0
    var netRx: Double = 0               // bytes/sec
    var netTx: Double = 0
    var diskFree: Int64 = 0
    var diskTotal: Int64 = 0
    var battery: BatteryInfo? = nil
    var uptime: TimeInterval = 0
    var thermals: ThermalSnapshot? = nil
    var localIPv4: String? = nil        // address of the busiest interface

    var memFraction: Double { memTotal == 0 ? 0 : Double(memUsed) / Double(memTotal) }
    var diskUsedFraction: Double { diskTotal == 0 ? 0 : 1 - Double(diskFree) / Double(diskTotal) }
}

/// One published value per tick: the snapshot plus the short histories the
/// sparklines draw. Publishing them separately used to invalidate the dashboard
/// six times per tick.
struct MetricsFrame: Equatable {
    var snap = MetricsSnapshot()
    var cpu: [Double] = []
    var gpu: [Double] = []
    var mem: [Double] = []
    var netRx: [Double] = []
    var netTx: [Double] = []
}

/// Polls system telemetry off the main thread and publishes one frame per tick.
/// Fast while the dashboard is on screen, slow everywhere else, stopped in sleep.
@MainActor
final class SystemMetrics: ObservableObject {
    @Published private(set) var frame = MetricsFrame()

    var snap: MetricsSnapshot { frame.snap }
    var cpuHistory: [Double] { frame.cpu }
    var gpuHistory: [Double] { frame.gpu }
    var memHistory: [Double] { frame.mem }
    var netRxHistory: [Double] { frame.netRx }
    var netTxHistory: [Double] { frame.netTx }

    enum Cadence: TimeInterval { case fast = 2, slow = 6 }

    private let historyLength = 48
    private var timer: Timer?
    private var cadence: Cadence = .fast
    private let sampler = MetricsSampler()
    private var inFlight = false
    private var ticks = 0

    func start() {
        guard timer == nil else { return }
        tick()
        schedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func setCadence(_ c: Cadence) {
        guard c != cadence else { return }
        cadence = c
        if timer != nil { stop(); schedule() }
    }

    private func schedule() {
        let t = Timer(timeInterval: cadence.rawValue, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard !inFlight else { return }
        inFlight = true
        ticks += 1
        let sampler = self.sampler
        let withThermals = ticks % 3 == 1
        Task.detached(priority: .utility) {
            let s = sampler.sample(thermals: withThermals)
            await MainActor.run { [weak self] in self?.apply(s) }
        }
    }

    private func apply(_ s: MetricsSnapshot) {
        inFlight = false
        var f = frame
        f.snap = s
        f.cpu = trimmed(f.cpu + [s.cpu])
        f.gpu = trimmed(f.gpu + [s.gpu])
        f.mem = trimmed(f.mem + [s.memFraction])
        f.netRx = trimmed(f.netRx + [s.netRx])
        f.netTx = trimmed(f.netTx + [s.netTx])
        frame = f
    }

    private func trimmed(_ a: [Double]) -> [Double] {
        a.count > historyLength ? Array(a.suffix(historyLength)) : a
    }
}

/// The samplers and their delta state. Runs on a utility task; `sample()` is
/// never called concurrently (the owner serializes ticks), so plain vars are
/// fine. IOKit services are matched once and reused.
final class MetricsSampler: @unchecked Sendable {
    private var last = MetricsSnapshot()
    private var prevCPU: (busy: Double, total: Double)?
    private var prevNet: (rx: UInt64, tx: UInt64)?
    private var prevNetTime: Date?
    private var lastGPU = 0.0
    private var gpuEverRead = false
    private var lastWatts: Double?
    private var gpuService: io_service_t = 0
    private var smartBattery: io_service_t = 0
    private lazy var smc = SMCReader()

    deinit {
        if gpuService != 0 { IOObjectRelease(gpuService) }
        if smartBattery != 0 { IOObjectRelease(smartBattery) }
    }

    func sample(thermals: Bool) -> MetricsSnapshot {
        var s = MetricsSnapshot()
        s.cpu = sampleCPU()
        if let g = sampleGPU() { s.gpu = g; lastGPU = g; gpuEverRead = true }
        else { s.gpu = lastGPU }
        s.gpuAvailable = gpuEverRead
        let mem = sampleMemory()
        s.memUsed = mem.used
        s.memTotal = mem.total
        let net = sampleNetwork()
        s.netRx = net.rx
        s.netTx = net.tx
        s.localIPv4 = net.address
        let disk = sampleDisk()
        s.diskFree = disk.free
        s.diskTotal = disk.total
        s.battery = sampleBattery()
        s.uptime = sampleUptime()
        // The telemetry read is occasionally empty (firmware-side hiccups) —
        // keep the last good value so the tile doesn't flap back to "AC POWER".
        if let w = quickSystemWatts() { lastWatts = w }
        s.systemWatts = lastWatts
        s.thermals = thermals ? smc?.thermals() : last.thermals
        last = s
        return s
    }

    // MARK: - Samplers

    private func sampleCPU() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return last.cpu }
        let user = Double(info.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3)
        let busy = user + system + nice
        let total = busy + idle
        defer { prevCPU = (busy, total) }
        guard let prev = prevCPU else { return 0 }
        let dBusy = busy - prev.busy
        let dTotal = total - prev.total
        return dTotal > 0 ? max(0, min(1, dBusy / dTotal)) : 0
    }

    /// Current GPU utilisation (0…1), or nil when this Mac exposes no readable
    /// utilisation counter — so the UI can show "unavailable" instead of a
    /// misleading flat 0% that looks like a genuinely idle GPU. The accelerator
    /// service is matched once; a failed read re-matches.
    private func sampleGPU() -> Double? {
        if gpuService != 0, let u = gpuUtilization(gpuService) { return u }
        if gpuService != 0 { IOObjectRelease(gpuService); gpuService = 0 }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let u = gpuUtilization(service) {
                gpuService = service   // keep the reference
                return u
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return nil
    }

    private func gpuUtilization(_ service: io_service_t) -> Double? {
        guard let props = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any] else { return nil }
        var util = -1.0
        if let u = props["Device Utilization %"] as? Int { util = Double(u) }
        else if let u = props["Device Utilization %"] as? Double { util = u }
        else if let u = props["GPU Activity(%)"] as? Int { util = Double(u) }
        return util >= 0 ? max(0, min(1, util / 100)) : nil
    }

    private func sampleMemory() -> (used: UInt64, total: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (0, total) }
        let pageSize = UInt64(vm_kernel_page_size)
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * pageSize
        return (used, total)
    }

    /// The IPv4 address the user thinks of as "my IP": the busiest physical
    /// interface (en*) — a VPN tunnel can move more bytes but isn't the LAN
    /// address anyone connects to. Standalone so the Network detail can read it.
    static func localIPv4() -> String? {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0 else { return nil }
        defer { freeifaddrs(ifap) }
        var traffic: [String: UInt64] = [:]
        var ipv4: [String: String] = [:]
        var ptr = ifap
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            guard let addr = p.pointee.ifa_addr, (Int32(p.pointee.ifa_flags) & IFF_UP) != 0 else { continue }
            let name = String(cString: p.pointee.ifa_name)
            guard !name.hasPrefix("lo") else { continue }
            if addr.pointee.sa_family == UInt8(AF_LINK), let data = p.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                traffic[name] = UInt64(data.pointee.ifi_ibytes) + UInt64(data.pointee.ifi_obytes)
            } else if addr.pointee.sa_family == UInt8(AF_INET), ipv4[name] == nil {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let s = String(cString: host)
                    if !s.hasPrefix("169.254") { ipv4[name] = s }
                }
            }
        }
        let ranked = ipv4.keys.sorted { (traffic[$0] ?? 0) > (traffic[$1] ?? 0) }
        let name = ranked.first { $0.hasPrefix("en") } ?? ranked.first
        return name.flatMap { ipv4[$0] }
    }

    private func sampleNetwork() -> (rx: Double, tx: Double, address: String?) {
        var rx: UInt64 = 0, tx: UInt64 = 0
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0 else { return (last.netRx, last.netTx, last.localIPv4) }
        defer { freeifaddrs(ifap) }
        var busiest: (name: String, bytes: UInt64)?
        var ipv4: [String: String] = [:]
        var ptr = ifap
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            let flags = Int32(p.pointee.ifa_flags)
            guard let addr = p.pointee.ifa_addr, (flags & IFF_UP) != 0 else { continue }
            let name = String(cString: p.pointee.ifa_name)
            guard !name.hasPrefix("lo") else { continue }
            if addr.pointee.sa_family == UInt8(AF_LINK) {
                if let data = p.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                    let bytes = UInt64(data.pointee.ifi_ibytes) + UInt64(data.pointee.ifi_obytes)
                    rx += UInt64(data.pointee.ifi_ibytes)
                    tx += UInt64(data.pointee.ifi_obytes)
                    if bytes > (busiest?.bytes ?? 0) { busiest = (name, bytes) }
                }
            } else if addr.pointee.sa_family == UInt8(AF_INET), ipv4[name] == nil {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let s = String(cString: host)
                    if !s.hasPrefix("169.254") { ipv4[name] = s }
                }
            }
        }
        let address = busiest.flatMap { ipv4[$0.name] } ?? ipv4.values.sorted().first
        let now = Date()
        defer { prevNet = (rx, tx); prevNetTime = now }
        guard let prev = prevNet, let prevTime = prevNetTime else { return (0, 0, address) }
        let dt = now.timeIntervalSince(prevTime)
        guard dt > 0 else { return (0, 0, address) }
        let drx = rx >= prev.rx ? Double(rx - prev.rx) : 0
        let dtx = tx >= prev.tx ? Double(tx - prev.tx) : 0
        return (drx / dt, dtx / dt, address)
    }

    private func sampleDisk() -> (free: Int64, total: Int64) {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return (last.diskFree, last.diskTotal) }
        return (v.volumeAvailableCapacityForImportantUsage ?? 0, Int64(v.volumeTotalCapacity ?? 0))
    }

    private func sampleUptime() -> TimeInterval {
        var bt = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &bt, &size, nil, 0) == 0, bt.tv_sec != 0 else { return last.uptime }
        return Date().timeIntervalSince1970 - Double(bt.tv_sec)
    }

    private func sampleBattery() -> BatteryInfo? {
        guard let snapRef = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapRef)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(snapRef, source)?.takeUnretainedValue() as? [String: Any],
                  let cur = desc[kIOPSCurrentCapacityKey as String] as? Int,
                  let maxCap = desc[kIOPSMaxCapacityKey as String] as? Int, maxCap > 0 else { continue }
            let charging = (desc[kIOPSPowerSourceStateKey as String] as? String) == (kIOPSACPowerValue as String)
            let mins = desc[kIOPSTimeToEmptyKey as String] as? Int
            return BatteryInfo(level: Double(cur) / Double(maxCap), charging: charging,
                               minutesRemaining: (mins ?? -1) > 0 ? mins : nil)
        }
        return nil
    }

    /// Just the instantaneous system draw (W) — one IORegistry read on a cached
    /// AppleSmartBattery service, no IOReport.
    private func quickSystemWatts() -> Double? {
        if smartBattery == 0 {
            smartBattery = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
            guard smartBattery != 0 else { return nil }
        }
        guard let ptd = IORegistryEntryCreateCFProperty(smartBattery, "PowerTelemetryData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any],
              let mw = ptd["SystemPowerIn"] as? Int, mw > 0 else { return nil }
        return Double(mw) / 1000
    }
}
