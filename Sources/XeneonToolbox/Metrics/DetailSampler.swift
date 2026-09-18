import Foundation
import Darwin
import IOKit
import CoreWLAN
import Metal
import SystemConfiguration

struct CoreLoad: Equatable, Identifiable {
    let id: Int
    let efficiency: Bool
    var load: Double
}

struct NetInterface: Equatable, Identifiable {
    var id: String { name }
    let name: String
    let label: String
    let address: String
}

/// The extra numbers a detail panel shows. Sampled only while one is open.
struct SystemDetail: Equatable {
    var chip = ""
    var cores: [CoreLoad] = []
    var loadAverage: [Double] = []
    var processCount = 0

    var gpuName = ""
    var gpuCores = 0
    var gpuRenderer: Double?
    var gpuTiler: Double?
    var gpuMemoryInUse: UInt64?
    var gpuMemoryAllocated: UInt64?
    var gpuWorkingSet: UInt64 = 0
    var gpuFamily = ""

    var memApp: UInt64 = 0
    var memWired: UInt64 = 0
    var memCompressed: UInt64 = 0
    var memCached: UInt64 = 0
    var memFree: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    /// 1 normal, 2 warning, 4 critical (kern.memorystatus_vm_pressure_level).
    var pressureLevel = 1

    var interface = ""
    var rssi: Int?
    var txRateMbps: Double?
    var router: String?
    var dns: [String] = []
    var interfaces: [NetInterface] = []
    var bytesIn: UInt64 = 0
    var bytesOut: UInt64 = 0

    var performanceCores: Int { cores.filter { !$0.efficiency }.count }
    var efficiencyCores: Int { cores.filter(\.efficiency).count }
}

/// Reads the detail numbers. Holds the previous CPU ticks, so use one instance
/// from one task at a time.
final class DetailSampler: @unchecked Sendable {
    private var previousTicks: [[UInt32]] = []
    private var route: (gateway: String?, interface: String?)?
    private var totals: (UInt64, UInt64) = (0, 0)
    private var linkSamples = 0
    private lazy var chip = Self.sysctlString("machdep.cpu.brand_string")
    private lazy var efficiencyCount = Self.sysctlInt("hw.perflevel1.logicalcpu") ?? 0
    private lazy var gpuIdentity = Self.gpuIdentity()
    private lazy var metal = Self.metalFacts()
    private lazy var interfaceLabels = Self.interfaceLabels()

    func sample(network: Bool) -> SystemDetail {
        var d = SystemDetail()
        d.chip = chip
        d.cores = coreLoads()
        var avg = [Double](repeating: 0, count: 3)
        if getloadavg(&avg, 3) == 3 { d.loadAverage = avg }
        d.processCount = Int(proc_listallpids(nil, 0))

        d.gpuName = gpuIdentity.name; d.gpuCores = gpuIdentity.cores
        if let stats = Self.gpuStatistics() {
            d.gpuRenderer = Self.percent(stats["Renderer Utilization %"])
            d.gpuTiler = Self.percent(stats["Tiler Utilization %"])
            d.gpuMemoryInUse = (stats["In use system memory"] as? NSNumber)?.uint64Value
            d.gpuMemoryAllocated = (stats["Alloc system memory"] as? NSNumber)?.uint64Value
        }
        d.gpuWorkingSet = metal.workingSet; d.gpuFamily = metal.family

        memory(into: &d)
        if network { link(into: &d) }
        return d
    }

    // MARK: Processor

    private func coreLoads() -> [CoreLoad] {
        var cpuCount: natural_t = 0, infoCount: mach_msg_type_number_t = 0
        var info: processor_info_array_t?
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return [] }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)) }

        let states = Int(CPU_STATE_MAX)
        var ticks: [[UInt32]] = []
        for i in 0..<Int(cpuCount) {
            ticks.append((0..<states).map { UInt32(bitPattern: info[i * states + $0]) })
        }
        defer { previousTicks = ticks }
        guard previousTicks.count == ticks.count else {
            return ticks.indices.map { CoreLoad(id: $0, efficiency: $0 < efficiencyCount, load: 0) }
        }
        return ticks.indices.map { i in
            let delta = (0..<states).map { Double(ticks[i][$0] &- previousTicks[i][$0]) }
            let total = delta.reduce(0, +), idle = delta[Int(CPU_STATE_IDLE)]
            // Apple silicon lists the efficiency cores first.
            return CoreLoad(id: i, efficiency: i < efficiencyCount, load: total > 0 ? max(0, min(1, (total - idle) / total)) : 0)
        }
    }

    // MARK: Memory

    private func memory(into d: inout SystemDetail) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let ok = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        } == KERN_SUCCESS
        if ok {
            let page = UInt64(vm_kernel_page_size)
            let purgeable = UInt64(stats.purgeable_count), internalPages = UInt64(stats.internal_page_count)
            d.memApp = (internalPages > purgeable ? internalPages - purgeable : 0) * page
            d.memWired = UInt64(stats.wire_count) * page
            d.memCompressed = UInt64(stats.compressor_page_count) * page
            d.memCached = (UInt64(stats.external_page_count) + purgeable) * page
            d.memFree = UInt64(stats.free_count) * page
        }
        var swap = xsw_usage(); var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 { d.swapUsed = swap.xsu_used; d.swapTotal = swap.xsu_total }
        d.pressureLevel = Self.sysctlInt("kern.memorystatus_vm_pressure_level") ?? 1
    }

    // MARK: Graphics

    private static func gpuService<T>(_ body: (io_service_t) -> T?) -> T? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            if let value = body(service) { return value }
        }
        return nil
    }

    private static func gpuStatistics() -> [String: Any]? {
        gpuService { IORegistryEntryCreateCFProperty($0, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] }
    }

    private static func gpuIdentity() -> (name: String, cores: Int) {
        gpuService { service -> (String, Int)? in
            let prop = { (key: String) in IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() }
            var name = ""
            if let s = prop("model") as? String { name = s }
            else if let data = prop("model") as? Data { name = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .controlCharacters) }
            let cores = (prop("gpu-core-count") as? NSNumber)?.intValue ?? 0
            return name.isEmpty && cores == 0 ? nil : (name, cores)
        } ?? ("", 0)
    }

    private static func metalFacts() -> (workingSet: UInt64, family: String) {
        guard let device = MTLCreateSystemDefaultDevice() else { return (0, "") }
        let family = device.supportsFamily(.metal3) ? "Metal 3" : device.supportsFamily(.apple7) ? "Metal 2, Apple 7" : "Metal 2"
        return (device.recommendedMaxWorkingSetSize, family)
    }

    private static func percent(_ value: Any?) -> Double? {
        (value as? NSNumber).map { max(0, min(1, $0.doubleValue / 100)) }
    }

    // MARK: Network

    private func link(into d: inout SystemDetail) {
        let wifi = CWWiFiClient.shared().interface()
        if let wifi, wifi.powerOn(), wifi.rssiValue() != 0 { d.rssi = wifi.rssiValue(); d.txRateMbps = wifi.transmitRate() }
        if route == nil { route = Self.defaultRoute() }
        d.router = route?.gateway
        d.interface = route?.interface ?? wifi?.interfaceName ?? ""
        if linkSamples % 5 == 0, let fresh = Self.byteTotals(interface: d.interface) { totals = fresh }
        linkSamples += 1
        d.bytesIn = totals.0; d.bytesOut = totals.1
        d.interfaces = activeInterfaces()
        if let dns = SCDynamicStoreCopyValue(nil, "State:/Network/Global/DNS" as CFString) as? [String: Any] {
            d.dns = dns["ServerAddresses"] as? [String] ?? []
        }
    }

    private func activeInterfaces() -> [NetInterface] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }
        var found: [NetInterface] = []
        var cursor = head
        while let entry = cursor?.pointee {
            defer { cursor = entry.ifa_next }
            let flags = Int32(entry.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0,
                  let addr = entry.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let name = String(cString: entry.ifa_name)
            guard !found.contains(where: { $0.name == name }) else { continue }
            let label = interfaceLabels[name] ?? (name.hasPrefix("utun") || name.hasPrefix("ipsec") ? "VPN tunnel" : name.hasPrefix("bridge") ? "Bridge" : "Network")
            found.append(NetInterface(name: name, label: label, address: String(cString: host)))
        }
        return found
    }

    private static func interfaceLabels() -> [String: String] {
        var labels: [String: String] = [:]
        for interface in SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? [] {
            guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String?,
                  let name = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? else { continue }
            labels[bsd] = name
        }
        return labels
    }

    private static func defaultRoute() -> (gateway: String?, interface: String?)? {
        let out = run("/sbin/route", ["-n", "get", "default"])
        func field(_ name: String) -> String? {
            out.split(separator: "\n").first { $0.trimmingCharacters(in: .whitespaces).hasPrefix(name + ":") }
                .map { $0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces) }
        }
        return (field("gateway"), field("interface"))
    }

    /// 64-bit counters from netstat: the ones getifaddrs and sysctl hand out wrap at 4 GB.
    private static func byteTotals(interface: String) -> (UInt64, UInt64)? {
        guard !interface.isEmpty else { return nil }
        for line in run("/usr/sbin/netstat", ["-ibn", "-I", interface]).split(separator: "\n").dropFirst() {
            let f = line.split(separator: " ", omittingEmptySubsequences: true)
            // Name Mtu Network Address Ipkts Ierrs Ibytes Opkts Oerrs Obytes Coll — the <Link#> row carries the totals
            guard f.count >= 10, f[2].hasPrefix("<Link") else { continue }
            let n = f.count
            if let i = UInt64(f[n - 5]), let o = UInt64(f[n - 2]) { return (i, o) }
        }
        return nil
    }

    // MARK: Helpers

    private static func run(_ path: String, _ args: [String]) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0; var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? Int(value) : nil
    }
}
