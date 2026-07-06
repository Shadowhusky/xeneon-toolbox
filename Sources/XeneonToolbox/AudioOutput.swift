import CoreAudio
import Foundation

/// Lists the Mac's audio output devices and switches the system default — the
/// "Sound" module in macOS Control Centre. Pure CoreAudio, no extra permissions.
@MainActor
final class AudioOutput: ObservableObject {
    struct Device: Identifiable, Equatable {
        let id: AudioDeviceID
        let name: String
        let current: Bool
        let symbol: String
    }

    @Published private(set) var devices: [Device] = []
    @Published private(set) var currentName: String?
    @Published private(set) var inputDevices: [Device] = []
    @Published private(set) var currentInputName: String?

    private var listenerInstalled = false

    func refresh() {
        let curOut = Self.defaultDevice(input: false)
        devices = Self.list(input: false, current: curOut)
        currentName = devices.first(where: { $0.current })?.name

        let curIn = Self.defaultDevice(input: true)
        inputDevices = Self.list(input: true, current: curIn)
        currentInputName = inputDevices.first(where: { $0.current })?.name

        installListener()
    }

    func setDefault(_ device: Device) { setDefault(device, input: false) }
    func setDefaultInput(_ device: Device) { setDefault(device, input: true) }

    private func setDefault(_ device: Device, input: Bool) {
        AppLog.info("audio", "\(input ? "input" : "output") → \(device.name)")
        var id = device.id
        var addr = AudioObjectPropertyAddress(
            mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                   UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        refresh()
    }

    private static func list(input: Bool, current: AudioDeviceID) -> [Device] {
        var out: [Device] = []
        for id in allDevices() where hasStreams(id, input: input) {
            guard let name = name(id) else { continue }
            out.append(Device(id: id, name: name, current: id == current,
                              symbol: input ? micSymbol(for: name) : symbol(for: name)))
        }
        return out.sorted { ($0.current ? 0 : 1, $0.name) < ($1.current ? 0 : 1, $1.name) }
    }

    private static func micSymbol(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpod") { return "airpodspro" }
        if n.contains("built-in") || n.contains("macbook") || n.contains("internal") { return "mic.fill" }
        return "mic.fill"
    }

    // MARK: - CoreAudio helpers

    private static func defaultDevice(input: Bool) -> AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    private static func allDevices() -> [AudioDeviceID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func hasStreams(_ id: AudioDeviceID, input: Bool) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        let buf = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buf.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, buf) == noErr else { return false }
        let list = buf.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        return buffers.contains { $0.mNumberChannels > 0 }
    }

    private static func name(_ id: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name) == noErr,
              let cf = name?.takeRetainedValue() else { return nil }
        let s = cf as String
        return s.isEmpty ? nil : s
    }

    private static func symbol(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpod") { return "airpodspro" }
        if n.contains("headphone") || n.contains("beats") { return "headphones" }
        if n.contains("display") || n.contains("monitor") || n.contains("hdmi") { return "display" }
        if n.contains("macbook") || n.contains("built-in") || n.contains("internal") { return "laptopcomputer" }
        if n.contains("mac") { return "desktopcomputer" }
        return "hifispeaker.fill"
    }

    private func installListener() {
        guard !listenerInstalled else { return }
        listenerInstalled = true
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice] {
            var addr = AudioObjectPropertyAddress(mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main) { [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }
}
