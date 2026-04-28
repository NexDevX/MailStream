import SwiftUI

/// Full-screen overlay that performs a *true* circular reveal of
/// the new theme.
///
/// **Visual model.** When the user taps the toggle, three things
/// happen in the same render pass (see `ThemeController.toggle`):
///   1. The window is captured as `transition.snapshot` (frozen
///      frame of the OLD theme).
///   2. `mode` flips, so the live RootView immediately starts
///      repainting in the NEW theme.
///   3. This overlay mounts on top, rendering the snapshot at full
///      window size with a circular hole at `transition.origin`,
///      radius 0.
///
/// As the hole grows, the OLD-theme pixels are erased from inside
/// out and the NEW-theme live view shows through the cut. When the
/// hole covers the window, the snapshot is fully erased and we call
/// `onComplete` to drop the overlay.
///
/// The overlay is `allowsHitTesting(false)` so the underlying UI is
/// interactive throughout. Re-toggling mid-animation kicks off a
/// fresh transition with a new `id`; `task(id:)` preempts cleanly.
struct ThemeRevealOverlay: View {
    let transition: ThemeTransition
    let onComplete: () -> Void

    @State private var radius: CGFloat = 0

    var body: some View {
        Image(nsImage: transition.snapshot)
            .resizable()
            // The snapshot's point size matches the window content
            // view at capture time, which IS the full named root
            // coordinate space. `.scaledToFill` + `.ignoresSafeArea`
            // pin it edge-to-edge regardless of the user resizing
            // the window mid-animation (the resize would warp the
            // snapshot, but resizing during a 600 ms animation is
            // an extreme edge case).
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .mask(holeMask)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .task(id: transition.id) {
                // Pin to 0 first in case the previous transition
                // left animatable state behind. SwiftUI snaps any
                // outside-of-withAnimation assignment instantly.
                radius = 0
                withAnimation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.62)) {
                    radius = transition.finalRadius
                }
                try? await Task.sleep(nanoseconds: 660_000_000)
                onComplete()
            }
    }

    /// Mask: opaque rectangle with a punched-out circle at `origin`.
    /// `.mask(_:)` keeps content where the mask is opaque, so this
    /// keeps the snapshot visible everywhere EXCEPT the circle —
    /// inside the circle the snapshot is transparent and the live
    /// new-theme view underneath shows through.
    ///
    /// `.compositingGroup` is mandatory: without it the
    /// `destinationOut` blend mode bleeds across the wider render
    /// tree and the hole never appears. The group flattens the
    /// rectangle + circle into a self-contained layer first.
    private var holeMask: some View {
        Rectangle()
            .fill(Color.white)
            .overlay(
                Circle()
                    .frame(width: max(radius, 0) * 2,
                           height: max(radius, 0) * 2)
                    .position(transition.origin)
                    .blendMode(.destinationOut)
            )
            .compositingGroup()
            .ignoresSafeArea()
    }
}
