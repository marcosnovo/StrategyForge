//
//  Theme.swift
//  StrategyForge
//
//  Visual identity: "Forge / Circuit" — a dark-first developer-tool look on a
//  cool graphite base with a single electric spring-green signature accent
//  ("Voltage"). Monospaced labels give it a technical fingerprint. All tokens
//  ship both light and dark.
//

import SwiftUI
import AppKit

// MARK: - Dynamic color helper

extension Color {
    /// A color that resolves differently in light vs dark appearance.
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        }))
    }
}

enum Theme {

    // MARK: Brand — "Wisteria haze" palette
    /// The four gradient stops (from the user's palette).
    static let moonWhite = Color(red: 0.918, green: 0.957, blue: 0.988)   // #EAF4FC
    static let wisteria   = Color(red: 0.698, green: 0.561, blue: 0.808)  // #B28FCE
    static let ibisPink   = Color(red: 0.957, green: 0.702, blue: 0.761)  // #F4B3C2
    static let sky        = Color(red: 0.627, green: 0.847, blue: 0.937)  // #A0D8EF

    /// Accent = Wisteria; slightly deeper in light for legible small text/icons,
    /// lighter in dark so it glows on the near-black surfaces.
    static let accent = Color(
        light: Color(red: 0.588, green: 0.427, blue: 0.729),   // #966DBA (deepened wisteria)
        dark:  Color(red: 0.741, green: 0.612, blue: 0.855))   // #BD9CDA
    static let accentHover = Color(
        light: Color(red: 0.647, green: 0.486, blue: 0.784),
        dark:  Color(red: 0.800, green: 0.678, blue: 0.898))
    static let accentSoft = wisteria.opacity(0.20)
    static let accentGlow = Color(
        light: wisteria.opacity(0.35),
        dark:  Color(red: 0.741, green: 0.612, blue: 0.855).opacity(0.55))
    /// Readable text/foreground to place ON a solid accent fill.
    static let onAccent = Color.white

    /// The "Wisteria haze" gradient, used as a soft ambient app background.
    static let haze = LinearGradient(
        stops: [
            .init(color: moonWhite, location: 0.10),
            .init(color: wisteria,  location: 0.40),
            .init(color: ibisPink,  location: 0.66),
            .init(color: sky,       location: 0.92),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    // MARK: Surfaces — soft lavender in light, cool graphite in dark
    static let appBg = Color(
        light: Color(red: 0.929, green: 0.918, blue: 0.965),   // #EDEAF6 wisteria-white
        dark:  Color(red: 0.051, green: 0.059, blue: 0.071))   // #0D0F12
    static let cardBg = Color(
        light: .white,
        dark:  Color(red: 0.086, green: 0.098, blue: 0.118))   // #16191E
    static let insetBg = Color(
        light: Color(red: 0.890, green: 0.867, blue: 0.941),   // #E3DDF0 wisteria inset
        dark:  Color(red: 0.039, green: 0.047, blue: 0.059))   // #0A0C0F
    /// Near-black surface for the left navigation rail (dark in both appearances).
    static let railBg = Color(
        light: Color(red: 0.129, green: 0.125, blue: 0.157),   // #211F28
        dark:  Color(red: 0.078, green: 0.075, blue: 0.098))   // #141319

    // MARK: Lines
    static let hairline = Color(
        light: Color.black.opacity(0.10),
        dark:  Color.white.opacity(0.09))

    // MARK: Text on translucent materials
    // System .secondary/.tertiary lose contrast over thin/ultraThin materials in
    // dark mode; these hold a readable level there while staying native in light.
    static let secondaryOnMaterial = Color(
        light: Color.secondary,
        dark:  Color.white.opacity(0.72))
    static let tertiaryOnMaterial = Color(
        light: Color.secondary.opacity(0.75),
        dark:  Color.white.opacity(0.55))

    // MARK: Status (cool, saturated — matched to the tech palette)
    static let success = Color(
        light: Color(red: 0.055, green: 0.612, blue: 0.471),   // #0E9C78 (teal-green)
        dark:  Color(red: 0.184, green: 0.812, blue: 0.651))   // #2FCFA6
    static let warning = Color(
        light: Color(red: 0.722, green: 0.525, blue: 0.043),   // #B8860B
        dark:  Color(red: 1.000, green: 0.773, blue: 0.239))   // #FFC53D
    static let danger = Color(
        light: Color(red: 0.831, green: 0.173, blue: 0.227),   // #D42C3A
        dark:  Color(red: 1.000, green: 0.361, blue: 0.424))   // #FF5C6C

    // MARK: Metrics — softer, more rounded (reference-style)
    static let corner: CGFloat = 18
    static let innerCorner: CGFloat = 14
    /// Chat message bubble radius.
    static let bubbleCorner: CGFloat = 18
    static let sectionSpacing: CGFloat = 20
    /// Vertical gap between chat messages (Claude/Superhuman-like breathing room).
    static let messageSpacing: CGFloat = 18
    /// Extra gap added above a user message to separate conversation turns.
    static let turnGap: CGFloat = 10
    /// Extra line spacing for body copy so long replies read comfortably.
    static let bodyLineSpacing: CGFloat = 3
}

/// 4-based spacing scale.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

// MARK: - Type scale

extension Font {
    // Relative to the system text styles so everything scales with the user's
    // Dynamic Type setting. The mapped styles sit within ~0.5pt of the previous
    // fixed sizes at the default setting, so the tuned look is preserved.
    /// Tight bold display for the hero title / brand (no serif).
    static let sfDisplay = Font.system(.title, design: .default).weight(.bold)          // ~22
    static let sfCardTitle = Font.system(.title3).weight(.semibold)                     // ~15
    static let sfBodyM = Font.system(.body)                                             // ~13
    static let sfCallout = Font.system(.callout)                                        // ~12
    static let sfCaption2 = Font.system(.subheadline)                                   // ~11
    /// Monospaced, all-caps field labels — the technical fingerprint.
    static let sfFieldLabel = Font.system(.caption, design: .monospaced).weight(.semibold) // ~10
    static let sfCode = Font.system(.callout, design: .monospaced)                      // ~12
    /// Monospaced wordmark / model tags.
    static let sfMono = Font.system(.body, design: .monospaced).weight(.semibold)       // ~13
}

// MARK: - Card surface

private struct CardModifier: ViewModifier {
    var padding: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.cardBg)
                    .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

extension View {
    /// Wrap content in a solid, hairline-bordered card with subtle depth.
    func card(padding: CGFloat = 20) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

// MARK: - Numbered step badge (mono numeral)

struct StepBadge: View {
    let number: Int
    var body: some View {
        Text("\(number)")
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(Theme.accent)
            .frame(width: 26, height: 26)
            .background(Circle().fill(Theme.accentSoft))
            .overlay(Circle().strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Info / glossary popover button

struct InfoPopoverButton: View {
    let text: String
    var systemName: String = "questionmark.circle"
    @State private var show = false
    var body: some View {
        Button { show = true } label: {
            Image(systemName: systemName)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .popover(isPresented: $show, arrowEdge: .bottom) {
            Text(text)
                .font(.sfCallout)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Space.l)
                .frame(width: 300)
        }
    }
}

// MARK: - Icon badge (soft Voltage)

struct IconBadge: View {
    let systemName: String
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Theme.accentSoft))
    }
}

// MARK: - Section header (icon)

struct SectionHeader<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    init(_ icon: String, _ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                IconBadge(systemName: icon)
                Text(title)
                    .font(.sfCardTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer(minLength: Space.s)
                trailing
            }
            if let subtitle {
                Text(subtitle)
                    .font(.sfCallout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 28 + Space.m)
            }
        }
    }
}

// MARK: - Small labeled control caption (mono caps)

struct FieldLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.sfFieldLabel)
            .foregroundStyle(.tertiary)
            .tracking(0.8)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .allowsTightening(true)
    }
}
