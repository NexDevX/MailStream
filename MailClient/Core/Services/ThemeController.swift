import SwiftUI
import AppKit

/// User-controlled light / dark theme override.
///
/// Sticks at "system" only on the very first launch — once the user
/// flips the toggle once, we explicitly remember `.light` or `.dark`
/// because the radial-reveal animation has no sensible meaning when
/// the destination is "whatever the system happens to be". `.system`
/// would also force us to react to OS-level appearance changes mid-
/// session, which is more state than the toggle promises.
enum ThemeMode: String, Codable, Sendable {
    case light, dark

    var colorScheme: ColorScheme {
        self == .dark ? .dark : .light
    }
}

/// In-flight theme switch. Lifetime: from the moment the user taps
/// the toggle button until the reveal animation completes (~750 ms).
/// Held by `ThemeController.transition`; consumed by
/// `ThemeRevealOverlay` which drives the actual radius animation.
struct ThemeTransition: Equatable, Identifiable {
    /// Stable id so `View.task(id:)` re-runs the animation pipeline
    /// for every fresh toggle, even if the user clicks twice in a row
    /// while a previous transition is still finishing.
    let id: UUID
    let target: ThemeMode
    /// Where the toggle button is, in the root coordinate space the
    /// overlay also reads from. The expanding circle is centered
    /// here — that's the "sun rising at this point" semantic.
    let origin: CGPoint
    /// Radius at full expansion. Caller computes
    /// `distance-to-farthest-corner + small padding` so the disc
    /// always covers the entire window when expansion finishes.
    let finalRadius: CGFloat
}

@MainActor
final class ThemeController: ObservableObject {
    @Published private(set) var mode: ThemeMode
    @Published var transition: ThemeTransition?

    private let defaults: UserDefaults
    private static let storageKey = "mailclient.theme.mode"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.storageKey),
           let saved = ThemeMode(rawValue: raw) {
            self.mode = saved
        } else {
            // Match the system's effective appearance on first launch
            // so the user doesn't see a jarring flash to the opposite
            // theme before they've expressed a preference. After this
            // we never read the system again — explicit toggles only.
            let appearance: NSAppearance =
                NSApp?.effectiveAppearance
                ?? NSAppearance(named: .aqua)
                ?? NSAppearance.current
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            self.mode = isDark ? .dark : .light
        }
    }

    /// Begin a circular-reveal toggle to the opposite mode.
    /// `origin` and `windowSize` are in the same coordinate space
    /// (the named root coordinate space `RootView` establishes).
    /// The animation actor (`ThemeRevealOverlay`) calls `commit()`
    /// at the moment the disc fully covers the screen; the swap of
    /// `mode` happens behind the disc so there's no visible jump.
    func toggle(origin: CGPoint, windowSize: CGSize) {
        // Cover the farthest corner — that's how far the disc must
        // grow to fully eclipse the window. Padding handles the case
        // where the user clicks near the dead-center and we'd
        // otherwise stop a fraction short due to floating-point
        // rounding.
        let dx = max(origin.x, windowSize.width  - origin.x)
        let dy = max(origin.y, windowSize.height - origin.y)
        let radius = sqrt(dx * dx + dy * dy) + 40

        let next: ThemeMode = mode == .dark ? .light : .dark
        transition = ThemeTransition(
            id: UUID(),
            target: next,
            origin: origin,
            finalRadius: radius
        )
    }

    /// Atomic swap: flip the published `mode`, persist, leave the
    /// transition in place so the overlay can fade out the disc on
    /// its own schedule. The fade is purely cosmetic — by this
    /// point the underlying scene has already re-rendered in the
    /// new theme behind the (still opaque) disc.
    func commitPendingTheme() {
        guard let t = transition else { return }
        mode = t.target
        defaults.set(mode.rawValue, forKey: Self.storageKey)
    }

    /// Tear down the transition once the fade-out is complete.
    /// Separate from `commitPendingTheme` because the disc has to
    /// keep rendering between commit and removal — a `transition =
    /// nil` here would yank the disc off-screen mid-fade.
    func clearTransition() {
        transition = nil
    }
}
