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

    // MARK: Brand — "Deep sea" palette
    /// The four gradient stops (from the user's palette).
    static let indigoWhite   = Color(red: 0.922, green: 0.965, blue: 0.969)  // #EBF6F7
    static let storeroomBlue = Color(red: 0.000, green: 0.533, blue: 0.600)  // #008899 teal
    static let indigo        = Color(red: 0.153, green: 0.290, blue: 0.471)  // #274A78
    static let youngBamboo   = Color(red: 0.408, green: 0.745, blue: 0.553)  // #68BE8D

    /// Accent = the deep-sea teal; slightly deepened in light for legible small
    /// text/icons, brighter in dark so it glows on the near-black surfaces.
    static let accent = Color(
        light: Color(red: 0.000, green: 0.478, blue: 0.541),   // #007A8A (deep teal)
        dark:  Color(red: 0.275, green: 0.718, blue: 0.788))   // #46B7C9
    static let accentHover = Color(
        light: Color(red: 0.000, green: 0.533, blue: 0.600),
        dark:  Color(red: 0.361, green: 0.780, blue: 0.851))
    static let accentSoft = accent.opacity(0.16)
    static let accentGlow = Color(
        light: storeroomBlue.opacity(0.32),
        dark:  Color(red: 0.275, green: 0.718, blue: 0.788).opacity(0.55))
    /// Readable text/foreground to place ON a solid accent fill.
    static let onAccent = Color.white

    /// Fill for the primary "deep sea" buttons: teal → indigo.
    static let primaryFill = LinearGradient(
        colors: [storeroomBlue, indigo], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// The "Deep sea" gradient, used as a soft ambient app background.
    static let haze = LinearGradient(
        stops: [
            .init(color: indigoWhite,   location: 0.10),
            .init(color: storeroomBlue, location: 0.40),
            .init(color: indigo,        location: 0.66),
            .init(color: youngBamboo,   location: 0.92),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    // MARK: Surfaces — soft lavender in light, cool graphite in dark
    static let appBg = Color(
        light: Color(red: 0.922, green: 0.965, blue: 0.969),   // #EBF6F7 indigo-white
        dark:  Color(red: 0.043, green: 0.055, blue: 0.071))   // #0B0E12
    static let cardBg = Color(
        light: .white,
        dark:  Color(red: 0.075, green: 0.094, blue: 0.118))   // #13181E
    static let insetBg = Color(
        light: Color(red: 0.859, green: 0.918, blue: 0.925),   // #DBEAEC teal inset
        dark:  Color(red: 0.035, green: 0.047, blue: 0.059))   // #090C0F
    /// Deep-navy surface for the left navigation rail (dark in both appearances).
    static let railBg = Color(
        light: Color(red: 0.098, green: 0.184, blue: 0.298),   // #192F4C deep indigo
        dark:  Color(red: 0.063, green: 0.106, blue: 0.169))   // #101B2B

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
        light: Color(red: 0.239, green: 0.588, blue: 0.408),   // #3D9668 (deep bamboo)
        dark:  Color(red: 0.408, green: 0.745, blue: 0.553))   // #68BE8D young bamboo
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

// MARK: - Primary "Deep sea" button style

/// The primary action button: a teal→indigo gradient fill with white text.
struct MoonButtonStyle: ButtonStyle {
    // Explicit type: bare `Configuration` collides with the app's Configuration model.
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        MoonButtonBody(configuration: configuration)
    }
}

private struct MoonButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.primaryFill))
            .shadow(color: Theme.storeroomBlue.opacity(0.30), radius: 6, x: 0, y: 2)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}
extension ButtonStyle where Self == MoonButtonStyle {
    /// Primary deep-sea (teal→indigo) button.
    static var moon: MoonButtonStyle { MoonButtonStyle() }
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
