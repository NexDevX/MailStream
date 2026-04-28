import SwiftUI

/// Full-screen overlay that animates a circular reveal of the new
/// theme, like sunlight spreading from the spot the user tapped.
///
/// Sequencing (see also `ThemeController`):
///
///   1. **Expand** (~520 ms) — radius animates 0 → `finalRadius`,
///      disc fully opaque, target-theme background gradient. The
///      user sees a colored wave wash from the toggle outward.
///   2. **Commit** — at the moment the disc fully covers the
///      window, `controller.commitPendingTheme()` flips the actual
///      `colorScheme` published value. The view tree underneath
///      re-renders in the new theme but is invisible because the
///      disc still covers everything.
///   3. **Fade** (~200 ms) — disc opacity 1 → 0. Underneath now
///      matches the disc's color, so the fade is imperceptible —
///      the perceived effect is just "the wave settled".
///   4. **Clear** — `controller.clearTransition()` removes the
///      overlay entirely so `task(id:)` is ready for the next
///      toggle.
///
/// The overlay is `allowsHitTesting(false)` throughout so the
/// underlying UI stays interactive. We can't gate the toggle
/// button against re-fires during the animation easily without
/// complicating the controller, so the user *can* re-toggle mid-
/// animation — that just kicks off a fresh transition with a new
/// `id`, which preempts the in-flight one cleanly.
struct ThemeRevealOverlay: View {
    let transition: ThemeTransition
    let onCommit: () -> Void
    let onComplete: () -> Void

    @State private var radius: CGFloat = 0
    @State private var opacity: Double = 1

    var body: some View {
        // The disc lives in the same coordinate space as the
        // `origin` the controller stored. We position by the disc's
        // center so SwiftUI doesn't have to do any extra translation.
        Circle()
            .fill(discFill)
            .frame(width: max(radius, 0) * 2, height: max(radius, 0) * 2)
            .position(transition.origin)
            .opacity(opacity)
            .blur(radius: 0.5) // sub-pixel blur masks any aliasing on the leading edge
            .compositingGroup()
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .task(id: transition.id) {
                radius = 0
                opacity = 1

                // Phase 1 — expand. easeOut so the wave decelerates
                // as it reaches the corners; matches a real light-
                // spreading-on-a-surface feel better than easeInOut.
                withAnimation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.52)) {
                    radius = transition.finalRadius
                }

                // Wait for expand to finish, then flip theme behind
                // the now-opaque cover.
                try? await Task.sleep(nanoseconds: 540_000_000)
                onCommit()

                // Phase 2 — fade. Underneath now matches the disc
                // color so this is invisible to the user; we still
                // animate it to avoid an instant pop in case the
                // gradient and the new theme background don't line
                // up exactly (they nearly do, but warm-white vs
                // pure-white is a perceptible mismatch).
                withAnimation(.easeOut(duration: 0.22)) {
                    opacity = 0
                }

                try? await Task.sleep(nanoseconds: 240_000_000)
                onComplete()
            }
    }

    /// Sun-like radial gradient resolved in the **target** theme's
    /// palette. Going-light uses warm white core + cream edge;
    /// going-dark uses deep slate core + cool blue edge. The center
    /// matches the new theme's `surface` token, so the fade-out at
    /// the end has nothing to fade *to* visually.
    private var discFill: RadialGradient {
        switch transition.target {
        case .light:
            return RadialGradient(
                colors: [
                    Color(red: 1.00, green: 0.99, blue: 0.96),  // warm white core
                    Color(red: 1.00, green: 0.96, blue: 0.88),  // cream halo
                    Color(red: 0.97, green: 0.95, blue: 0.92)   // settles to surface
                ],
                center: .center,
                startRadius: 0,
                endRadius: max(radius, 1)
            )
        case .dark:
            return RadialGradient(
                colors: [
                    Color(red: 0.06, green: 0.07, blue: 0.10),  // deep slate core
                    Color(red: 0.04, green: 0.05, blue: 0.08),  // midnight halo
                    Color(red: 0.02, green: 0.03, blue: 0.05)   // settles to surface
                ],
                center: .center,
                startRadius: 0,
                endRadius: max(radius, 1)
            )
        }
    }
}
