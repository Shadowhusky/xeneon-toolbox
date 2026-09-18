import SwiftUI

/// A full-strip control surface, opened from the Surfaces page.
enum Surface: String, CaseIterable, Identifiable {
    case mixer, scrub, keys, windows, shelf, captions, prompter, agents, telemetry

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mixer: return "Mixer"
        case .scrub: return "Scrub strip"
        case .keys: return "Keys and pads"
        case .windows: return "Window map"
        case .shelf: return "Shelf"
        case .captions: return "Live captions"
        case .prompter: return "Teleprompter"
        case .agents: return "Agents"
        case .telemetry: return "Telemetry"
        }
    }

    var blurb: String {
        switch self {
        case .mixer: return "A fader for every app that's making sound, plus output and mic."
        case .scrub: return "Jog, scrub and drop markers in whichever editor is in front."
        case .keys: return "A keyboard, pads and an XY pad that play into any MIDI app."
        case .windows: return "Every display in miniature. Drag a window where you want it."
        case .shelf: return "Park files, text and images here. Tap to paste them back."
        case .captions: return "Whatever is playing or being said, written out as it happens."
        case .prompter: return "Your script, scrolling just under the camera."
        case .agents: return "Coding agents, dev servers and containers, with a tap to approve or stop."
        case .telemetry: return "Revs, gear and speed from the race sim on your network."
        }
    }

    var icon: String {
        switch self {
        case .mixer: return "slider.vertical.3"
        case .scrub: return "timeline.selection"
        case .keys: return "pianokeys"
        case .windows: return "macwindow.on.rectangle"
        case .shelf: return "tray.full.fill"
        case .captions: return "captions.bubble.fill"
        case .prompter: return "text.line.first.and.arrowtriangle.forward"
        case .agents: return "terminal.fill"
        case .telemetry: return "gauge.open.with.lines.needle.84percent.exclamation"
        }
    }

    var tint: Color {
        switch self {
        case .mixer: return Theme.battery
        case .scrub: return Theme.accent
        case .keys: return Theme.gpu
        case .windows: return Theme.ice
        case .shelf: return Theme.netUp
        case .captions: return Theme.netDown
        case .prompter: return Theme.time
        case .agents: return Theme.memory
        case .telemetry: return Theme.heat
        }
    }
}

/// The frame every surface shares: a way back, its name, its actions, and the
/// rest of the strip for the surface itself.
struct SurfaceShell<Content: View>: View {
    let surface: Surface
    var subtitle: String? = nil
    var actions: [DetailAction] = []
    let onBack: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                CircleIconButton(icon: "chevron.left", size: 52, action: onBack)
                Image(systemName: surface.icon).font(.system(size: 18, weight: .bold)).foregroundStyle(surface.tint)
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: Theme.wellCorner, style: .continuous).fill(surface.tint.opacity(0.14)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(surface.title).font(.deck(24, .semibold)).foregroundStyle(Theme.textPrimary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.deck(14, .medium)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 16)
                ForEach(actions) { a in
                    GhostButton(title: a.title, icon: a.icon, tint: a.tint, height: 50, action: a.run)
                }
            }
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// What a surface shows when it can't run yet (a permission, a missing app).
struct SurfaceNotice: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: () -> Void = {}

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 38, weight: .light)).foregroundStyle(Theme.textFaint)
            Text(title).font(.deck(20, .semibold)).foregroundStyle(Theme.textPrimary)
            Text(message).font(.deck(15)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 620).fixedSize(horizontal: false, vertical: true)
            if let actionTitle { PrimaryButton(title: actionTitle, height: 52, action: action).frame(width: 260).padding(.top, 6) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
