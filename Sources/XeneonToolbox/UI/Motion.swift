import SwiftUI

/// One motion vocabulary for the whole app, so every overlay, dropdown and page
/// swap shares the same feel. Prefer these over ad-hoc `.spring(response:…)` /
/// `.easeInOut(duration:…)` literals — a single tuned set keeps transitions
/// coherent (and easy to retune in one place).
enum Motion {
    /// Most state and layout changes — a settled spring with a hint of life but
    /// no visible overshoot.
    static let standard = Animation.spring(response: 0.34, dampingFraction: 0.85)

    /// A menu, modal or picker appearing. The Apple-style soft bounce: it
    /// overshoots a touch and settles (~6%). Use with `.popCard` transitions.
    static let pop = Animation.spring(response: 0.42, dampingFraction: 0.70)

    /// Quick control feedback — toggles, small dropdowns, header buttons. Fast,
    /// barely any overshoot.
    static let snappy = Animation.spring(response: 0.26, dampingFraction: 0.82)

    /// A directional page turn (deck/app swipe, route change) — carries weight.
    static let page = Animation.spring(response: 0.45, dampingFraction: 0.86)

    /// Non-overshooting cross-fade for pure content swaps (no scale/move).
    static let smooth = Animation.easeInOut(duration: 0.24)

    /// The tactile press feedback under `PressableStyle` — fast, with a little
    /// give so a tap on the glass feels physical.
    static let press = Animation.spring(response: 0.25, dampingFraction: 0.6)
}

extension AnyTransition {
    /// The signature "pop" for centred menus and modals: grows from slightly
    /// small while fading in, and shrinks a touch while fading out. Paired with
    /// `Motion.pop` this reads as a soft bounce in and a quick, quiet dismiss.
    static var popCard: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.90).combined(with: .opacity),
            removal: .scale(scale: 0.96).combined(with: .opacity))
    }

    /// A sheet/bar that rises from the bottom edge (now-playing, banners).
    static var riseUp: AnyTransition {
        .move(edge: .bottom).combined(with: .opacity)
    }

    /// A dropdown that expands down from the top edge (control-centre pickers).
    static var dropDown: AnyTransition {
        .move(edge: .top).combined(with: .opacity)
    }
}

/// A centred modal card floating over a dimming scrim, with the app's standard
/// pop-in motion: the scrim fades, the card springs. Tapping the scrim (outside
/// the card) dismisses. The card itself catches taps so a press inside it never
/// falls through to the scrim.
struct ModalScaffold<Content: View>: View {
    var dim: Double = 0.55
    let onDismiss: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(dim).ignoresSafeArea()
                .transition(.opacity)
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
            content()
                .transition(.popCard)
        }
    }
}
