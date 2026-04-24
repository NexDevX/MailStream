import SwiftUI
import AppKit

/// MailStream design system — tokens from `docs/Design/mailstream/styles.css`.
/// All colors resolve dynamically for light & dark appearances.
enum DS {}

// MARK: - Colors

extension DS {
    enum Color {
        // Neutrals
        static let bg          = dyn(light: .hex(0xfafbfc), dark: .hex(0x0e1118))
        static let surface     = dyn(light: .hex(0xffffff), dark: .hex(0x161b24))
        static let surface2    = dyn(light: .hex(0xf6f7f9), dark: .hex(0x1b2028))
        static let surface3    = dyn(light: .hex(0xeef1f4), dark: .hex(0x232834))
        static let hover       = dyn(light: .hex(0xf2f4f7), dark: .hex(0x20252f))
        static let selected    = dyn(light: .hex(0xe6ecf5), dark: .hex(0x23304a))
        static let selectedStr = dyn(light: .hex(0xdce4f1), dark: .hex(0x2a3a58))

        // Ink (5 steps)
        static let ink   = dyn(light: .hex(0x0e1522), dark: .hex(0xe7ecf4))
        static let ink2  = dyn(light: .hex(0x3a4557), dark: .hex(0xb8c1d0))
        static let ink3  = dyn(light: .hex(0x6e7989), dark: .hex(0x8792a3))
        static let ink4  = dyn(light: .hex(0xa2abb7), dark: .hex(0x5d6777))
        static let ink5  = dyn(light: .hex(0xc4cad3), dark: .hex(0x424a58))

        // Lines
        static let line        = dyn(light: .hex(0xe6e9ee), dark: .hex(0x252b36))
        static let lineStrong  = dyn(light: .hex(0xd6dae0), dark: .hex(0x30384a))

        // Accent
        static let accent      = dyn(light: .hex(0x2457d6), dark: .hex(0x5b85e8))
        static let accentInk   = dyn(light: .hex(0x1c3f9f), dark: .hex(0x8ba9f0))
        static let accentSoft  = dyn(light: .hex(0xecf1fd), dark: .hex(0x1d2a48))
        static let accentGlow  = dyn(light: SwiftUI.Color(red: 0.14, green: 0.34, blue: 0.84, opacity: 0.14),
                                     dark:  SwiftUI.Color(red: 0.36, green: 0.52, blue: 0.91, opacity: 0.22))

        // Semantic
        static let red         = dyn(light: .hex(0xd4344b), dark: .hex(0xe86078))
        static let redSoft     = dyn(light: .hex(0xfdecef), dark: .hex(0x3a1d23))
        static let amber       = dyn(light: .hex(0xb87318), dark: .hex(0xe1a552))
        static let amberSoft   = dyn(light: .hex(0xfcf2e4), dark: .hex(0x3b2a17))
        static let green       = dyn(light: .hex(0x0f7a52), dark: .hex(0x3cc08a))
        static let greenSoft   = dyn(light: .hex(0xe6f3ed), dark: .hex(0x17332a))

        // Providers
        static let pGmail   = dyn(light: .hex(0xd64a40), dark: .hex(0xe56a5f))
        static let pOutlook = dyn(light: .hex(0x2a6cc9), dark: .hex(0x4d8dd8))
        static let pICloud  = dyn(light: .hex(0x4a5568), dark: .hex(0x8792a3))
        static let pQQ      = dyn(light: .hex(0x1e63c4), dark: .hex(0x4e8cdc))
        static let pCustom  = dyn(light: .hex(0x7a4aaa), dark: .hex(0xa37bcf))

        // Labels (from data.jsx)
        static let labelWork    = dyn(light: .hex(0x2457d6), dark: .hex(0x5b85e8))
        static let labelReceipt = dyn(light: .hex(0x148a5e), dark: .hex(0x3cc08a))
        static let labelTravel  = dyn(light: .hex(0xc77a19), dark: .hex(0xe5a958))
        static let labelTeam    = dyn(light: .hex(0x7a4aaa), dark: .hex(0xa37bcf))
        static let labelClient  = dyn(light: .hex(0xd4344b), dark: .hex(0xe86078))

        // Window chrome
        static let chromeTop    = dyn(light: .hex(0xf1f3f6), dark: .hex(0x1a1e27))
        static let chromeBottom = dyn(light: .hex(0xf7f8fa), dark: .hex(0x1e232d))
    }
}

// MARK: - Radii, spacing, shadows

extension DS {
    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 6
        static let lg: CGFloat = 8
    }

    enum Stroke {
        static let hairline: CGFloat = 1
    }

    enum Shadow {
        static func pop(_ colorScheme: ColorScheme = .light) -> SwiftUI.Color {
            colorScheme == .dark
                ? SwiftUI.Color.black.opacity(0.5)
                : SwiftUI.Color.black.opacity(0.16)
        }
    }
}

// MARK: - Typography

extension DS {
    enum Font {
        /// UI sans — falls back to SF Pro, matches Inter at small sizes.
        static func sans(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .default)
        }

        /// Monospace — SF Mono stand-in for JetBrains Mono.
        static func mono(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .monospaced)
        }

        /// Serif display — for large subject headings in the reading pane.
        static func serif(_ size: CGFloat, weight: SwiftUI.Font.Weight = .semibold) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .serif)
        }
    }
}

// MARK: - Dynamic color helpers

private extension SwiftUI.Color {
    static func hex(_ rgb: UInt32, _ alpha: Double = 1.0) -> SwiftUI.Color {
        SwiftUI.Color(
            red:   Double((rgb >> 16) & 0xff) / 255,
            green: Double((rgb >>  8) & 0xff) / 255,
            blue:  Double( rgb        & 0xff) / 255,
            opacity: alpha
        )
    }
}

private func dyn(light: SwiftUI.Color, dark: SwiftUI.Color) -> SwiftUI.Color {
    SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark])
            .map { $0 == .darkAqua || $0 == .vibrantDark } ?? false
        return NSColor(isDark ? dark : light)
    })
}
