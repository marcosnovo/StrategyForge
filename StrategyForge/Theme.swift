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

    // MARK: Brand — messenger-screenshot violet, with Wisteria-haze nuances
    /// Nuance colors (from the Wisteria palette) for the soft background wash.
    static let moonWhite = Color(red: 0.918, green: 0.957, blue: 0.988)   // #EAF4FC
    static let wisteria   = Color(red: 0.698, green: 0.561, blue: 0.808)  // #B28FCE
    static let ibisPink   = Color(red: 0.957, green: 0.702, blue: 0.761)  // #F4B3C2
    static let sky        = Color(red: 0.627, green: 0.847, blue: 0.937)  // #A0D8EF

    /// Accent = neutral graphite (sober, Linear-like). Color is reserved for small
    /// details (status greens, provider tints, the diagram).
    static let accent = Color(
        light: Color(red: 0.227, green: 0.247, blue: 0.290),   // #3A3F4A graphite
        dark:  Color(red: 0.729, green: 0.749, blue: 0.796))   // #BABFCB (light on dark)
    static let accentHover = Color(
        light: Color(red: 0.290, green: 0.314, blue: 0.361),   // #4A505C
        dark:  Color(red: 0.808, green: 0.827, blue: 0.867))
    static let accentSoft = Color(
        light: Color(red: 0.227, green: 0.247, blue: 0.290).opacity(0.10),
        dark:  Color.white.opacity(0.10))
    static let accentGlow = Color(
        light: Color(red: 0.227, green: 0.247, blue: 0.290).opacity(0.18),
        dark:  Color.white.opacity(0.30))
    /// Readable text/foreground to place ON a solid accent fill.
    static let onAccent = Color.white

    /// Primary button fill — a subtle graphite gradient (deeper at the bottom).
    static let primaryFill = LinearGradient(
        colors: [Color(red: 0.271, green: 0.294, blue: 0.341),   // #454B57
                 Color(red: 0.196, green: 0.216, blue: 0.259)],  // #323742
        startPoint: .top, endPoint: .bottom)

    /// A soft lavender ambient wash (subtle Wisteria nuances) behind the app.
    static let haze = LinearGradient(
        stops: [
            .init(color: moonWhite, location: 0.05),
            .init(color: wisteria,  location: 0.45),
            .init(color: ibisPink,  location: 0.70),
            .init(color: sky,       location: 0.95),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    // MARK: Surfaces — soft lavender in light, cool graphite in dark
    static let appBg = Color(
        light: Color(red: 0.929, green: 0.922, blue: 0.965),   // #EDEBF7 soft lavender
        dark:  Color(red: 0.051, green: 0.055, blue: 0.078))   // #0D0E14
    static let cardBg = Color(
        light: .white,
        dark:  Color(red: 0.086, green: 0.090, blue: 0.118))   // #16171E
    static let insetBg = Color(
        light: Color(red: 0.902, green: 0.890, blue: 0.953),   // #E6E3F3 lavender inset
        dark:  Color(red: 0.039, green: 0.043, blue: 0.063))   // #0A0B10
    /// Near-black surface for the left navigation rail (like the screenshot).
    static let railBg = Color(
        light: Color(red: 0.125, green: 0.122, blue: 0.153),   // #201F27
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
        light: Color(red: 0.180, green: 0.620, blue: 0.420),   // #2E9E6B green
        dark:  Color(red: 0.306, green: 0.796, blue: 0.557))   // #4ECB8E
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
            .shadow(color: Theme.accent.opacity(0.32), radius: 6, x: 0, y: 2)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed)
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
