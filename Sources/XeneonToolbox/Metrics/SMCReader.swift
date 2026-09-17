import Foundation
import IOKit

/// Temperatures and fan speeds for the Thermals tile.
struct ThermalSnapshot: Equatable {
    var socC: Double?
    var gpuC: Double?
    var fanRPM: [Double] = []
}

/// Reads the SMC through the AppleSMC user client — no root, no helper. Key
/// names differ per chip, so the reader picks its sensor set once: every
/// temperature key (`T…`, type `flt`) that reads as a plausible temperature,
/// grouped by the prefixes Apple uses for CPU clusters (`Tp`, `Tc`, `Te`) and
/// GPU (`Tg`). On machines that expose nothing usable, `thermals()` returns
/// empty values and the tile says so.
final class SMCReader: @unchecked Sendable {
    private var conn: io_connect_t = 0
    private var cpuKeys: [String] = []
    private var gpuKeys: [String] = []
    private var fanKeys: [String] = []

    init?() {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        guard IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS, conn != 0 else { return nil }
        discover()
    }

    deinit { if conn != 0 { IOServiceClose(conn) } }

    func thermals() -> ThermalSnapshot {
        var t = ThermalSnapshot()
        t.socC = maxReading(cpuKeys)
        t.gpuC = maxReading(gpuKeys)
        t.fanRPM = fanKeys.compactMap { readFloat($0) }
        return t
    }

    // MARK: - Discovery

    private func discover() {
        guard let count = readFloat("#KEY").map(Int.init), count > 0 else { return }
        var cpu: [(String, Double)] = [], gpu: [(String, Double)] = []
        for i in 0..<UInt32(min(count, 8000)) {
            guard let key = keyAt(i), key.hasPrefix("T") else { continue }
            let prefix = String(key.prefix(2))
            guard prefix == "Tp" || prefix == "Tc" || prefix == "Te" || prefix == "Tg" else { continue }
            guard let v = readFloat(key), v > 5, v < 130 else { continue }
            if prefix == "Tg" { gpu.append((key, v)) } else { cpu.append((key, v)) }
        }
        // Keep the hottest sensors of each group — enough for a faithful maximum,
        // few enough to read every few seconds.
        cpuKeys = cpu.sorted { $0.1 > $1.1 }.prefix(24).map(\.0)
        gpuKeys = gpu.sorted { $0.1 > $1.1 }.prefix(16).map(\.0)
        let fans = Int(readFloat("FNum") ?? 0)
        fanKeys = (0..<max(0, min(fans, 8))).map { "F\($0)Ac" }
    }

    private func maxReading(_ keys: [String]) -> Double? {
        let values = keys.compactMap { readFloat($0) }.filter { $0 > 5 && $0 < 130 }
        return values.max()
    }

    // MARK: - SMC protocol
    //
    // Selector 2 (kSMCHandleYPCEvent) with an 80-byte SMCKeyData_t:
    // key @0 (fourcc, host order), keyInfo.dataSize @28, keyInfo.dataType @32,
    // result @40, data8 @42 (9 = key info, 5 = read, 8 = key by index),
    // data32 @44 (index), bytes @48.

    private func call(_ input: [UInt8]) -> [UInt8]? {
        var inp = input
        var out = [UInt8](repeating: 0, count: 80)
        var outSize = 80
        let kr = IOConnectCallStructMethod(conn, 2, &inp, 80, &out, &outSize)
        return kr == KERN_SUCCESS ? out : nil
    }

    private static func fourcc(_ s: String) -> UInt32 { s.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }
    private static func fromFourcc(_ v: UInt32) -> String {
        String(bytes: [UInt8(v >> 24), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)], encoding: .ascii) ?? "????"
    }
    private static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }
    private static func put32(_ b: inout [UInt8], _ o: Int, _ v: UInt32) {
        b[o] = UInt8(v & 0xff); b[o + 1] = UInt8((v >> 8) & 0xff); b[o + 2] = UInt8((v >> 16) & 0xff); b[o + 3] = UInt8(v >> 24)
    }

    private struct KeyInfo { let size: Int; let type: String }

    private func keyInfo(_ key: UInt32) -> KeyInfo? {
        var inp = [UInt8](repeating: 0, count: 80)
        Self.put32(&inp, 0, key)
        inp[42] = 9
        guard let out = call(inp), out[40] == 0 else { return nil }
        return KeyInfo(size: Int(Self.u32(out, 28)), type: Self.fromFourcc(Self.u32(out, 32)))
    }

    private func keyAt(_ index: UInt32) -> String? {
        var inp = [UInt8](repeating: 0, count: 80)
        Self.put32(&inp, 44, index)
        inp[42] = 8
        guard let out = call(inp), out[40] == 0 else { return nil }
        return Self.fromFourcc(Self.u32(out, 0))
    }

    /// A numeric key as Double: `flt`, `ui8`/`ui16`/`ui32`, or the Intel `sp78`.
    func readFloat(_ name: String) -> Double? {
        let key = Self.fourcc(name)
        guard let info = keyInfo(key), info.size > 0, info.size <= 32 else { return nil }
        var inp = [UInt8](repeating: 0, count: 80)
        Self.put32(&inp, 0, key)
        inp[42] = 5
        Self.put32(&inp, 28, UInt32(info.size))
        guard let out = call(inp), out[40] == 0 else { return nil }
        let b = Array(out[48..<48 + info.size])
        switch info.type {
        case "flt ": return Double(Float(bitPattern: Self.u32(b, 0)))
        case "ui8 ": return Double(b[0])
        case "ui16": return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
        case "ui32": return Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
        case "sp78": return Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256
        default: return nil
        }
    }
}
