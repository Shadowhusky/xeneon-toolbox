import Foundation
import Darwin
import IOKit.ps

struct BatteryInfo: Equatable {
    var level: Double          // 0...1
    var charging: Bool
    var minutesRemaining: Int? // nil if estimating / on AC
}

struct MetricsSnapshot: Equatable {
    var cpu: Double = 0                 // 0...1
    var memUsed: UInt64 = 0
    var memTotal: UInt64 = 0
    var netRx: Double = 0               // bytes/sec
    var netTx: Double = 0
    var diskFree: Int64 = 0
    var diskTotal: Int64 = 0
    var battery: BatteryInfo? = nil
    var uptime: TimeInterval = 0

    var memFraction: Double { memTotal == 0 ? 0 : Double(memUsed) / Double(memTotal) }
    var diskUsedFraction: Double { diskTotal == 0 ? 0 : 1 - Double(diskFree) / Double(diskTotal) }
}

/// Polls system telemetry on a light cadence and publishes a snapshot plus
/// short histories for sparklines. All Mach/IOKit calls are cheap and run on
/// the main run loop, so the panel stays effectively free when idle.
@MainActor
final class SystemMetrics: ObservableObject {
    @Published private(set) var snap = MetricsSnapshot()
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var netRxHistory: [Double] = []
    @Published private(set) var netTxHistory: [Double] = []

    private let historyLength = 48
    private let interval: TimeInterval = 1.5
    private var timer: Timer?

    private var prevCPU: (busy: Double, total: Double)?
    private var prevNet: (rx: UInt64, tx: UInt64)?
    private var prevNetTime: Date?

    func start() {
        guard timer == nil else { return }
        sample()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        var s = MetricsSnapshot()
        s.cpu = sampleCPU()
        let mem = sampleMemory()
        s.memUsed = mem.used
        s.memTotal = mem.total
        let net = sampleNetwork()
        s.netRx = net.rx
        s.netTx = net.tx
        let disk = sampleDisk()
        s.diskFree = disk.free
        s.diskTotal = disk.total
        s.battery = sampleBattery()
        s.uptime = sampleUptime()
        snap = s

        cpuHistory = trimmed(cpuHistory + [s.cpu])
        netRxHistory = trimmed(netRxHistory + [s.netRx])
        netTxHistory = trimmed(netTxHistory + [s.netTx])
    }

    private func trimmed(_ a: [Double]) -> [Double] {
        a.count > historyLength ? Array(a.suffix(historyLength)) : a
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
        guard kr == KERN_SUCCESS else { return snap.cpu }
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

    private func sampleNetwork() -> (rx: Double, tx: Double) {
        var rx: UInt64 = 0, tx: UInt64 = 0
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0 else { return (snap.netRx, snap.netTx) }
        defer { freeifaddrs(ifap) }
        var ptr = ifap
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            let flags = Int32(p.pointee.ifa_flags)
            guard let addr = p.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  (flags & IFF_UP) != 0 else { continue }
            let name = String(cString: p.pointee.ifa_name)
            guard !name.hasPrefix("lo") else { continue }
            if let data = p.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                rx += UInt64(data.pointee.ifi_ibytes)
                tx += UInt64(data.pointee.ifi_obytes)
            }
        }
        let now = Date()
        defer { prevNet = (rx, tx); prevNetTime = now }
        guard let prev = prevNet, let prevTime = prevNetTime else { return (0, 0) }
        let dt = now.timeIntervalSince(prevTime)
        guard dt > 0 else { return (0, 0) }
        let drx = rx >= prev.rx ? Double(rx - prev.rx) : 0
        let dtx = tx >= prev.tx ? Double(tx - prev.tx) : 0
        return (drx / dt, dtx / dt)
    }

    private func sampleDisk() -> (free: Int64, total: Int64) {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return (snap.diskFree, snap.diskTotal) }
        return (v.volumeAvailableCapacityForImportantUsage ?? 0, Int64(v.volumeTotalCapacity ?? 0))
    }

    private func sampleUptime() -> TimeInterval {
        var bt = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &bt, &size, nil, 0) == 0, bt.tv_sec != 0 else { return snap.uptime }
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
}
