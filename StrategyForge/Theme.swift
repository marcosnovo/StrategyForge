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

    // MARK: Brand — "Pulse" (vibrant electric violet — AI / premium)
    static let accent = Color(
        light: Color(red: 0.427, green: 0.365, blue: 0.910),   // #6D5DE8 (holds on white)
        dark:  Color(red: 0.545, green: 0.490, blue: 1.000))   // #8B7DFF (glows on near-black)
    static let accentHover = Color(
        light: Color(red: 0.490, green: 0.431, blue: 0.941),
        dark:  Color(red: 0.620, green: 0.573, blue: 1.000))
    static let accentSoft = accent.opacity(0.16)
    static let accentGlow = Color(
        light: Color(red: 0.427, green: 0.365, blue: 0.910).opacity(0.30),
        dark:  Color(red: 0.545, green: 0.490, blue: 1.000).opacity(0.55))
    /// Readable text/foreground to place ON a solid accent fill.
    static let onAccent = Color.white

    // MARK: Surfaces — cool graphite, never warm
    static let appBg = Color(
        light: Color(red: 0.957, green: 0.965, blue: 0.973),   // #F4F6F8
        dark:  Color(red: 0.051, green: 0.059, blue: 0.071))   // #0D0F12
    static let cardBg = Color(
        light: .white,
        dark:  Color(red: 0.086, green: 0.098, blue: 0.118))   // #16191E
    static let insetBg = Color(
        light: Color(red: 0.918, green: 0.933, blue: 0.949),   // #EAEEF2
        dark:  Color(red: 0.039, green: 0.047, blue: 0.059))   // #0A0C0F

    // MARK: Lines
    static let hairline = Color(
        light: Color.black.opacity(0.10),
        dark:  Color.white.opacity(0.09))

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

    // MARK: Metrics
    static let corner: CGFloat = 14
    static let innerCorner: CGFloat = 10
    static let sectionSpacing: CGFloat = 20
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
    /// Tight bold display for the hero title / brand (no serif).
    static let sfDisplay = Font.system(size: 22, weight: .bold)
    static let sfCardTitle = Font.system(size: 15, weight: .semibold)
    static let sfBodyM = Font.system(size: 13)
    static let sfCallout = Font.system(size: 12.5)
    static let sfCaption2 = Font.system(size: 11.5)
    /// Monospaced, all-caps field labels — the technical fingerprint.
    static let sfFieldLabel = Font.system(size: 10, weight: .semibold, design: .monospaced)
    static let sfCode = Font.system(size: 12, design: .monospaced)
    /// Monospaced wordmark / model tags.
    static let sfMono = Font.system(size: 13, weight: .semibold, design: .monospaced)
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
