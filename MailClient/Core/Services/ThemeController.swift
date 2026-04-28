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
/// the toggle button until the reveal animation completes.
///
/// The visual model is a *true* circular reveal — the new theme is
/// already live underneath, and we paint a frozen frame of the OLD
/// theme on top of it, then progressively erase the snapshot from
/// inside out at the click point. So inside the growing hole the
/// user sees the new theme's actual content; outside the hole, a
/// pixel-perfect freeze of where they were a moment ago.
struct ThemeTransition: Identifiable {
    /// Stable id so `View.task(id:)` re-runs the animation pipeline
    /// for every fresh toggle, even if the user clicks twice in a row
    /// while a previous transition is still finishing.
    let id: UUID
    let target: ThemeMode
    /// Where the toggle button is, in the root coordinate space the
    /// overlay also reads from. The expanding hole is centered here.
    let origin: CGPoint
    /// Radius at full expansion. Caller computes
    /// `distance-to-farthest-corner + small padding` so the hole
    /// always covers the entire window when expansion finishes.
    let finalRadius: CGFloat
    /// Frozen pixels of the window contents at the moment the user
    /// tapped, captured in the OLD theme. Rendered above the live
    /// view and masked with a growing hole; once the hole covers
    /// everything the snapshot is fully erased and we drop the
    /// transition. Equatable identity falls back to `id` only.
    let snapshot: NSImage
}

extension ThemeTransition: Equatable {
    static func == (lhs: ThemeTransition, rhs: ThemeTransition) -> Bool {
        // Two transitions are "the same" iff they were created by
        // the same toggle. NSImage's bitwise equality is both
        // expensive and meaningless here.
        lhs.id == rhs.id
    }
}

extension NSView {
    /// Capture a deterministic, retina-correct snapshot of the
    /// view's current rendering. Uses `cacheDisplay` so we don't
    /// trip the screen-recording permission gate that
    /// `CGWindowListCreateImage` would. Returns nil only when AppKit
    /// fails to allocate the bitmap (effectively never on a healthy
    /// system). Called on the main thread immediately before the
    /// theme flip so the captured pixels are guaranteed to be the
    /// OLD theme's render.
    func mailStream_snapshotImage() -> NSImage? {
        guard bounds.width > 0, bounds.height > 0,
              let rep = bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }
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
    /// (the named root coordinate space `RootView` establishes);
    /// `snapshot` is a freeze frame of the window in the OLD theme,
    /// captured by the caller right before this method is invoked.
    ///
    /// The mode is flipped *immediately* — the live view tree under
    /// the snapshot starts repainting in the new theme right away.
    /// The user doesn't see the flip because the snapshot covers
    /// everything; as the overlay's hole grows, more of the new live
    /// view is revealed.
    func toggle(origin: CGPoint, windowSize: CGSize, snapshot: NSImage) {
        // Cover the farthest corner — that's how far the hole must
        // grow to fully erase the snapshot. Padding handles
        // floating-point rounding at the corners.
        let dx = max(origin.x, windowSize.width  - origin.x)
        let dy = max(origin.y, windowSize.height - origin.y)
        let radius = sqrt(dx * dx + dy * dy) + 40

        let next: ThemeMode = mode == .dark ? .light : .dark
        transition = ThemeTransition(
            id: UUID(),
            target: next,
            origin: origin,
            finalRadius: radius,
            snapshot: snapshot
        )
        // Flip live theme NOW. Tied to the same publish cycle as
        // the transition assignment so SwiftUI sees both in one
        // render pass — the snapshot appears at the same instant
        // the underlying tree starts repainting in the new theme.
        mode = next
        defaults.set(next.rawValue, forKey: Self.storageKey)
    }

    /// Tear down the transition once the hole has consumed the
    /// entire snapshot. The overlay calls this from its `task`
    /// modifier when the radius animation completes.
    func clearTransition() {
        transition = nil
    }
}
