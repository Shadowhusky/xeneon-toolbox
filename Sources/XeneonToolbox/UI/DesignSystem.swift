import SwiftUI

/// Telemetry-deck design language: near-black layered surfaces, hue-coded
/// metrics, soft glows, monospaced readouts.
enum Theme {
    static let background = Color(red: 0.035, green: 0.04, blue: 0.05)
    static let backgroundEdge = Color(red: 0.02, green: 0.022, blue: 0.03)
    static let tileTop = Color(red: 0.10, green: 0.11, blue: 0.135)
    static let tileBottom = Color(red: 0.065, green: 0.07, blue: 0.09)
    static let stroke = Color.white.opacity(0.07)
    static let strokeStrong = Color.white.opacity(0.14)

    static let textPrimary = Color(red: 0.93, green: 0.95, blue: 0.98)
    static let textSecondary = Color(red: 0.58, green: 0.62, blue: 0.70)
    static let textFaint = Color(red: 0.40, green: 0.44, blue: 0.52)

    // Hue-coded per metric — the colour encodes which signal you're reading.
    static let cpu = Color(red: 0.33, green: 0.84, blue: 0.92)      // cyan
    static let memory = Color(red: 0.56, green: 0.49, blue: 1.0)    // violet
    static let netDown = Color(red: 0.36, green: 0.90, blue: 0.65)  // mint
    static let netUp = Color(red: 0.98, green: 0.74, blue: 0.38)    // amber
    static let disk = Color(red: 0.40, green: 0.62, blue: 1.0)      // blue
    static let battery = Color(red: 0.46, green: 0.89, blue: 0.58)  // green
    static let batteryLow = Color(red: 0.98, green: 0.45, blue: 0.42)
    static let accent = Color(red: 0.33, green: 0.84, blue: 0.92)

    static let tileCorner: CGFloat = 26
    static let tileGap: CGFloat = 16
}

/// Press feedback for touch — scales and dims slightly while held.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

extension Font {
    static func deck(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func readout(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

enum Fmt {
    static func percent(_ f: Double) -> String { "\(Int((f * 100).rounded()))%" }

    static func gb(_ bytes: UInt64) -> String { gb(Int64(bytes)) }
    static func gb(_ bytes: Int64) -> String {
        let g = Double(bytes) / 1_073_741_824
        return g >= 100 ? String(format: "%.0f", g) : String(format: "%.1f", g)
    }

    static func uptime(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        let d = s / 86_400, h = (s % 86_400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    static func rate(_ bytesPerSec: Double) -> (value: String, unit: String) {
        let units = ["B", "KB", "MB", "GB"]
        var v = bytesPerSec, i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        let s = v >= 100 || i == 0 ? String(format: "%.0f", v) : String(format: "%.1f", v)
        return (s, units[i] + "/s")
    }
}
