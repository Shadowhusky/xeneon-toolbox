import Foundation
import IOKit

/// Live power telemetry for the energy-flow modal: watts flowing from the wall
/// into the machine and where they go inside the SoC.
///
/// Sources (no root, no helpers):
/// - `AppleSmartBattery`'s `PowerTelemetryData` — instantaneous SystemPowerIn /
///   adapter efficiency loss / battery charge-discharge, in mW. Present on
///   Apple-Silicon Macs (desktops too, battery or not).
/// - IOReport's private "Energy Model" group — per-block energy counters
///   (CPU/GPU/ANE/DRAM/display/media), sampled twice and differenced into watts.
///   Same mechanism third-party SoC power monitors use; unavailable → nil.
@MainActor
final class PowerTelemetry: ObservableObject {
    struct Snapshot: Equatable {
        var systemIn: Double?        // W into the machine (nil = telemetry absent)
        var adapterLoss: Double?     // W lost in the adapter (wall = systemIn + loss)
        var batteryInstalled = false
        var batteryPercent: Int?
        var batteryW = 0.0           // >0 charging, <0 discharging
        var charging = false
        var external = true          // on wall power

        var cpu = 0.0, gpu = 0.0, memory = 0.0, neural = 0.0, media = 0.0, displays = 0.0
        var blocksAvailable = false  // IOReport worked

        var blocksTotal: Double { cpu + gpu + memory + neural + media + displays }
        /// Everything the SoC counters don't attribute (SSD, fans, USB, board).
        var other: Double? { systemIn.map { max(0, $0 - blocksTotal) } }
        var wall: Double? { systemIn.map { $0 + (adapterLoss ?? 0) } }
    }

    @Published private(set) var snap = Snapshot()
    private var timer: Timer?
    private let reporter = EnergyModelReporter()

    /// Begin 2s sampling while the modal is open.
    func start() {
        guard timer == nil else { return }
        tick()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate(); timer = nil
    }

    private func tick() {
        var s = Snapshot()
        Self.readBattery(into: &s)
        if let blocks = reporter.sampleWatts() {
            s.blocksAvailable = true
            s.cpu = blocks.cpu; s.gpu = blocks.gpu; s.memory = blocks.memory
            s.neural = blocks.neural; s.media = blocks.media; s.displays = blocks.displays
        }
        snap = s
    }

    private static func readBattery(into s: inout Snapshot) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return }

        s.batteryInstalled = dict["BatteryInstalled"] as? Bool ?? false
        s.external = dict["ExternalConnected"] as? Bool ?? true
        s.charging = dict["IsCharging"] as? Bool ?? false
        if s.batteryInstalled,
           let cur = dict["CurrentCapacity"] as? Int, let max = dict["MaxCapacity"] as? Int, max > 0 {
            s.batteryPercent = Int((Double(cur) / Double(max) * 100).rounded())
        }
        if let ptd = dict["PowerTelemetryData"] as? [String: Any] {
            if let mw = ptd["SystemPowerIn"] as? Int, mw > 0 { s.systemIn = Double(mw) / 1000 }
            if let mw = ptd["AdapterEfficiencyLoss"] as? Int, mw > 0 { s.adapterLoss = Double(mw) / 1000 }
            if let mw = ptd["BatteryPower"] as? Int, mw != 0 { s.batteryW = Double(mw) / 1000 }
        }
        // Battery Macs without telemetry: derive battery watts from V×I.
        if s.batteryW == 0, s.batteryInstalled,
           let mA = dict["Amperage"] as? Int, let mV = dict["Voltage"] as? Int, mA != 0 {
            // Amperage is signed 64-bit two's-complement in some firmwares.
            let amps = mA > Int(Int32.max) ? Double(Int64(truncatingIfNeeded: Int64(mA))) : Double(mA)
            s.batteryW = amps / 1000 * (Double(mV) / 1000)
        }
    }
}

/// IOReport "Energy Model" reader. All symbols resolved at runtime via dlsym so
/// a macOS build without the library (or a schema change) degrades to nil
/// instead of failing to launch. Not main-actor: sampling is called from the
/// main actor but does plain C work.
private final class EnergyModelReporter {
    struct Blocks { var cpu = 0.0, gpu = 0.0, memory = 0.0, neural = 0.0, media = 0.0, displays = 0.0 }

    private typealias CopyChannelsT = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
    private typealias CreateSubT = @convention(c) (UnsafeRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64, CFTypeRef?) -> UnsafeMutableRawPointer?
    private typealias CreateSamplesT = @convention(c) (UnsafeMutableRawPointer, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias SamplesDeltaT = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias IterateT = @convention(c) (CFDictionary, @convention(block) (CFDictionary) -> Int32) -> Void
    private typealias GetNameT = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias GetIntT = @convention(c) (CFDictionary, Int32) -> Int64
    private typealias GetUnitT = @convention(c) (CFDictionary) -> Unmanaged<CFString>?

    private var subscription: UnsafeMutableRawPointer?
    private var subscribed: CFMutableDictionary?
    private var lastSample: CFDictionary?
    private var lastTime: CFAbsoluteTime = 0

    private var samplesDelta: SamplesDeltaT?
    private var createSamples: CreateSamplesT?
    private var iterate: IterateT?
    private var getName: GetNameT?
    private var getInt: GetIntT?
    private var getUnit: GetUnitT?

    init() {
        guard let h = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW) else { return }
        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            guard let p = dlsym(h, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        guard let copyChannels = sym("IOReportCopyChannelsInGroup", CopyChannelsT.self),
              let createSub = sym("IOReportCreateSubscription", CreateSubT.self),
              let mkSamples = sym("IOReportCreateSamples", CreateSamplesT.self),
              let delta = sym("IOReportCreateSamplesDelta", SamplesDeltaT.self),
              let iter = sym("IOReportIterate", IterateT.self),
              let name = sym("IOReportChannelGetChannelName", GetNameT.self),
              let intv = sym("IOReportSimpleGetIntegerValue", GetIntT.self),
              let unit = sym("IOReportChannelGetUnitLabel", GetUnitT.self),
              let chans = copyChannels("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue() else { return }
        var subbed: Unmanaged<CFMutableDictionary>?
        guard let sub = createSub(nil, chans, &subbed, 0, nil), let sd = subbed?.takeRetainedValue() else { return }
        subscription = sub
        subscribed = sd
        createSamples = mkSamples
        samplesDelta = delta
        iterate = iter
        getName = name
        getInt = intv
        getUnit = unit
    }

    /// Watts per block since the previous call (nil on the first call or when
    /// IOReport is unavailable). Call on an interval; the delta spans the gap.
    func sampleWatts() -> Blocks? {
        guard let subscription, let subscribed, let createSamples, let samplesDelta,
              let iterate, let getName, let getInt, let getUnit,
              let now = createSamples(subscription, subscribed, nil)?.takeRetainedValue() else { return nil }
        let t = CFAbsoluteTimeGetCurrent()
        defer { lastSample = now; lastTime = t }
        guard let prev = lastSample, t - lastTime > 0.2,
              let delta = samplesDelta(prev, now, nil)?.takeRetainedValue() else { return nil }
        let dt = t - lastTime

        var b = Blocks()
        iterate(delta) { item in
            guard let cfName = getName(item)?.takeUnretainedValue() as String? else { return 0 }
            let unit = getUnit(item)?.takeUnretainedValue() as String? ?? "mJ"
            let scale: Double = unit.hasPrefix("n") ? 1e-9 : unit.hasPrefix("u") ? 1e-6 : unit.hasPrefix("m") ? 1e-3 : 1
            let joules = Double(getInt(item, 0)) * scale
            let w = joules / dt
            // Only whole-block aggregates — per-core/cluster/controller channels
            // would double-count what the aggregates already include.
            if cfName.hasSuffix("CPU Energy") { b.cpu += w }              // DIE_n_CPU Energy
            else if cfName == "GPU Energy" { b.gpu += w }                 // whole-SoC aggregate
            else if cfName.hasPrefix("DRAM") { b.memory += w }
            else if cfName.hasPrefix("ANE") { b.neural += w }
            else if cfName.hasPrefix("ISP") || cfName.hasPrefix("AVE") || cfName.hasPrefix("MSR") { b.media += w }
            else if cfName.hasPrefix("DISP") { b.displays += w }
            return 0
        }
        return b
    }
}
