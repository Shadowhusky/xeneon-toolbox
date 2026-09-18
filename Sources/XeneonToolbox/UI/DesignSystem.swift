import SwiftUI

/// Obsidian Instrument: black glass surfaces with a physical bezel, warm bone
/// text, one amber signature, and hue-coded instruments. Everything in the app
/// draws from here.
enum Theme {
    // Surfaces
    static let background = Color(hex: 0x0A0B0D)        // carbon
    static let backgroundEdge = Color(hex: 0x060708)
    static let tileTop = Color(hex: 0x171A20)            // graphite
    static let tileBottom = Color(hex: 0x0E1014)         // slate
    static let stroke = Color.white.opacity(0.06)
    static let strokeStrong = Color.white.opacity(0.12)
    static let bezelLight = Color.white.opacity(0.11)    // the lit top edge of glass
    static let bezelDark = Color.black.opacity(0.6)      // the shaded bottom edge
    static let trackFill = Color.white.opacity(0.06)     // empty part of any gauge/bar
    static let wellFill = Color.black.opacity(0.3)       // recessed graph/gauge area
    static let innerHighlight = Color.white.opacity(0.05)

    // Text — warm bone on cool glass
    static let textPrimary = Color(hex: 0xECE9E1)
    static let textSecondary = Color(hex: 0x9C9B95)
    static let textFaint = Color(hex: 0x5F615F)

    // The signature and its second
    static let accent = Color(hex: 0xF5B544)             // amber
    static let time = accent                             // the clock is the primary instrument
    static let ice = Color(hex: 0x8FD3F4)

    // Hue-coded instruments
    static let cpu = ice
    static let gpu = Color(hex: 0xC79BFF)                // orchid
    static let memory = Color(hex: 0xFF8FA3)             // rose
    static let netDown = Color(hex: 0x8BE3B0)            // mint
    static let netUp = Color(hex: 0xE3C97A)              // sand
    static let disk = Color(hex: 0xA9B4C2)               // steel
    static let battery = Color(hex: 0x9BD97A)            // moss
    static let batteryLow = Color(hex: 0xFF5E5E)
    static let heat = Color(hex: 0xFF7A59)               // ember

    // Semantic state hues — one place to escalate any metric.
    static let warning = accent
    static let critical = batteryLow

    /// A metric's colour under load: its own hue until 75 %, amber to 90 %, red above.
    static func pressure(_ fraction: Double, base: Color) -> Color {
        fraction >= 0.9 ? critical : fraction >= 0.75 ? warning : base
    }

    static let labelTracking: CGFloat = 0.2

    // Radius encodes hierarchy: tiles, then wells/rows, then badges.
    static let tileCorner: CGFloat = 22
    static let wellCorner: CGFloat = 12
    static let badgeCorner: CGFloat = 8
    static let tileGap: CGFloat = 16

    // Modular spacing scale so interiors share one rhythm.
    static let s1: CGFloat = 8
    static let s2: CGFloat = 12
    static let s3: CGFloat = 16
    static let s4: CGFloat = 22

    // The lamp bloom — used on indicators, never on large shapes.
    static let glowOpacity: Double = 0.6
    static let glowRadius: CGFloat = 6
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension View {
    /// The indicator bloom, applied consistently to small lit elements.
    func deckGlow(_ color: Color, strength: CGFloat = 1) -> some View {
        shadow(color: color.opacity(Theme.glowOpacity), radius: Theme.glowRadius * strength)
    }

    /// A physical bezel: lit top edge, shaded bottom edge, hairline stroke.
    func bezel(corner: CGFloat, tint: Color = .clear) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [Theme.bezelLight.opacity(1), tint.opacity(0.18), Theme.bezelDark],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
        )
    }
}

/// Press feedback for touch — scales and dims slightly while held.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

extension Font {
    /// Words: SF Pro, sentence case.
    static func deck(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    /// Numbers: monospaced so readouts never jitter and read as instruments.
    static func readout(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    /// The hero clock: light monospaced, like an aircraft clock.
    static func hero(_ size: CGFloat) -> Font {
        .system(size: size, weight: .light, design: .monospaced)
    }
    // Named roles so hierarchy stays consistent across pages.
    static var deckLabel: Font { deck(14, .semibold) }   // tile/section header
    static var deckCaption: Font { deck(12) }
    static var readoutHero: Font { readout(56, .semibold) }
    static var readoutXL: Font { readout(44, .semibold) }
}

/// A recessed area inside a tile — graphs and gauges sit in one so the surface
/// reads as layered rather than flat.
struct Well<Content: View>: View {
    var corner: CGFloat = Theme.wellCorner
    var inset: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(inset)
            .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Theme.wellFill))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.black.opacity(0.5), Color.white.opacity(0.05)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }
}

/// An indicator lamp: a small dot that is either lit (with bloom) or dark.
struct Lamp: View {
    var color: Color
    var on = true
    var size: CGFloat = 7
    var body: some View {
        Circle()
            .fill(on ? color : Color.white.opacity(0.12))
            .frame(width: size, height: size)
            .deckGlow(on ? color : .clear, strength: 0.9)
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
