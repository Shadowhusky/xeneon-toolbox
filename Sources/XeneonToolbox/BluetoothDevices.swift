import Foundation
import ToolboxKit

/// Bluetooth peripherals and their charge, for the dashboard's Devices tile.
/// `system_profiler` costs ~100 ms, so it runs off-main once a minute and only
/// while the tile is on screen (the tile starts and stops it).
@MainActor
final class BluetoothDevices: ObservableObject {
    @Published private(set) var devices: [BluetoothPeripheral] = []
    @Published private(set) var loaded = false
    private var task: Task<Void, Never>?

    var connected: [BluetoothPeripheral] { devices.filter(\.connected) }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                let list = await Self.sample()
                guard let self, !Task.isCancelled else { return }
                if list != devices { devices = list }
                loaded = true
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private nonisolated static func sample() async -> [BluetoothPeripheral] {
        await Task.detached(priority: .utility) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            p.arguments = ["SPBluetoothDataType", "-json"]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { return [] }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return BluetoothReport.parse(data)
        }.value
    }
}
