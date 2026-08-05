//
//  DesignSystem.swift
//  StrategyForge
//
//  Swappable visual "design systems" — the colour foundation `Theme` reads from, so the
//  whole app can be re-skinned live from a rail selector. Four directions from the art-
//  director exploration:
//   • Classic     — the original warm coral (kept for comparison).
//   • Reef Light  — a purer, brighter coral on COOL porcelain (kills the "brick" cast).
//   • Midnight    — dark-first cinematic; coral glows through near-black.
//   • Ember       — a coral→magenta duotone; the bold switch.
//
//  Theme tokens read the active palette through the nonisolated `ThemeState.active`
//  snapshot (so the many static tokens stay cheap and actor-free); the @Observable
//  `ThemeStore` drives the picker + persistence and re-renders the root on change.
//

import SwiftUI

/// A design LANGUAGE is more than a palette — it sets the background atmosphere, whether
/// surfaces are glass or matte paper, and the hero's typographic voice.
enum Backdrop: Sendable { case auroraCoral, caustic, paper, duotone }
enum HeroVoice: Sendable {
    case standard, rounded, serif
    var design: Font.Design {
        switch self { case .standard: return .default; case .rounded: return .rounded; case .serif: return .serif }
    }
}

/// The root colours a design system provides; every `Theme` colour derives from these.
struct Palette {
    var appBg, columnBg, cardBg, insetBg, railBg: Color
    var ink, secondary, tertiary, hairline: Color
    /// Brand coral (bright), the deep end of the CTA gradient (magenta in Ember), and the
    /// text/icon accent (light+dark, AA-safe where it carries text).
    var coral, coralDeep, accent: Color
    /// Accent-glow opacity (Bioluminescence leans on this).
    var glow: Double
    /// Background atmosphere, whether cards are glass vs matte paper, and the hero voice —
    /// the things that make each system a distinct LANGUAGE, not a recolour.
    var backdrop: Backdrop = .auroraCoral
    var usesGlass: Bool = true
    var hero: HeroVoice = .standard
}

enum DesignSystem: String, CaseIterable, Identifiable, Sendable {
    case classic, reefPaper, bioluminescence, ember
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic:         return "Classic"
        case .reefPaper:       return "Reef Paper"
        case .bioluminescence: return "Bioluminescence"
        case .ember:           return "Ember"
        }
    }

    /// Bioluminescence is dark-first — force dark regardless of the system setting.
    var forcedScheme: ColorScheme? { self == .bioluminescence ? .dark : nil }

    var palette: Palette {
        switch self {
        case .classic:
            // A COOL near-white light ground (was warm greige #F1EFEA) with a real elevation
            // staircase appBg < columnBg < cardBg(#FFF) so cards read as lit sheets, and a
            // recessed (not near-black) rail. Foregrounds retuned to clear WCAG AA on the new,
            // non-white ground. (Design pass 2, 2026-08-05 — verified ratios in the tokens.)
            return Palette(
                // Warm PAPER ramp (R>=G>=B — no green/slate cast) lifted brighter so appBg reads
                // as bright paper and columns/wells sit a whisper below it, not a gray gutter.
                // (Design pass 3, 2026-08-05 — the "demasiado gris" fix.)
                appBg: hex("FBFAF8", "0C1315"), columnBg: hex("F6F5F2", "121E21"),
                cardBg: hex("FFFFFF", "16262A"), insetBg: hex("F2F0EC", "1B2E33"),
                railBg: hex("EFEDE8", "081014"),
                ink: hex("1A2426", "EAF3F1"), secondary: hex("6B6660", "86A0A0"),
                tertiary: hex("928C84", "7E9A9A"), hairline: hex("E6E5E1", "1D2D32"),
                coral: hex("FF6B54", "FF6B54"), coralDeep: hex("E24029", "E24029"),
                accent: hex("BE3A22", "FF6B54"), glow: 0.22,
                backdrop: .auroraCoral, usesGlass: true, hero: .standard)

        case .reefPaper:
            // Editorial: warm PORCELAIN ground (not pure white), matte paper (no glass),
            // serif hero. The base sits ~12 L* below the white cards so cards read as sheets
            // resting on a warm desk, giving the flat paper language real figure/ground.
            return Palette(
                appBg: hex("EFEDE8", "0E1114"), columnBg: hex("E7E5DF", "141A1E"),
                cardBg: hex("FFFFFF", "1A2227"), insetBg: hex("E0DED7", "10161A"),
                railBg: hex("E1DFD9", "080B0E"),
                ink: hex("1C1D1F", "ECEFF1"), secondary: hex("63656A", "98A0A6"),
                tertiary: hex("8A8C92", "6E767C"), hairline: hex("D6D4CC", "242E33"),
                coral: hex("F5573C", "FF6E56"), coralDeep: hex("E0432B", "E8482E"),
                accent: hex("C4402A", "FF7C64"), glow: 0.06,
                backdrop: .paper, usesGlass: false, hero: .serif)

        case .bioluminescence:
            // Luminous reef: near-black void + caustic glow, glowing rounded hero, glass.
            return Palette(
                appBg: hex("E8ECED", "070C10"), columnBg: hex("DFE5E6", "0B1318"),
                cardBg: hex("FFFFFF", "101A20"), insetBg: hex("D6DEDF", "0A1015"),
                railBg: hex("05090C", "05090C"),
                ink: hex("0E1618", "EAF4F2"), secondary: hex("4E5E60", "7FA0A0"),
                tertiary: hex("6E7C7E", "6E8888"), hairline: hex("CBD3D4", "17242A"),
                coral: hex("F04A30", "FF6E56"), coralDeep: hex("D8341C", "FF3D6B"),
                accent: hex("C6381F", "FF7A63"), glow: 0.42,
                backdrop: .caustic, usesGlass: true, hero: .rounded)

        case .ember:
            return Palette(
                appBg: hex("EFEDF2", "0D0B12"), columnBg: hex("E8E5EE", "141221"),
                cardBg: hex("FFFFFF", "181521"), insetBg: hex("E2DEEA", "1E1A2A"),
                railBg: hex("E4E1EA", "0A0810"),
                ink: hex("141118", "F0ECF4"), secondary: hex("615A6C", "A79FB4"),
                tertiary: hex("7C7488", "8A8398"), hairline: hex("D6D2DE", "241F2E"),
                coral: hex("FF6B54", "FF6B54"), coralDeep: hex("E5397E", "FF3D8A"),
                accent: hex("D62D6E", "FF7A9C"), glow: 0.24,
                backdrop: .duotone, usesGlass: true, hero: .standard)
        }
    }
}

/// Nonisolated snapshot the (static, actor-free) `Theme` tokens read.
enum ThemeState {
    // v2: bumped when the DEFAULT design system changed (→ classic, the spectacular light).
    // A new key means every install starts fresh on the new default instead of being pinned
    // to a stale persisted choice (and it sidesteps cfprefsd caching the old value).
    static let key = "coral.designSystem.v2"
    nonisolated(unsafe) static var active: DesignSystem =
        DesignSystem(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .classic
}

/// Appearance override so the light palettes are actually visible even when macOS is in
/// dark mode (the "they're all dark" trap: without this, every non-Midnight system just
/// shows its dark variant on a dark system).
enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case auto, light, dark
    var id: String { rawValue }
    var scheme: ColorScheme? { self == .light ? .light : (self == .dark ? .dark : nil) }
    var labelKey: String { "appearance.\(rawValue)" }
}

/// Observable holder for the rail picker: mutating `active` persists it, updates the
/// nonisolated snapshot, and (because the root reads it) re-renders the whole app.
@Observable
@MainActor
final class ThemeStore {
    static let shared = ThemeStore()
    var active: DesignSystem {
        didSet {
            UserDefaults.standard.set(active.rawValue, forKey: ThemeState.key)
            ThemeState.active = active
        }
    }
    /// User-chosen appearance override (auto follows the system, unless the design system
    /// forces one — Midnight is always dark).
    var appearance: AppAppearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }
    /// The color scheme to force on the shell: the design system's own (Midnight → dark),
    /// else the user's appearance override.
    var resolvedScheme: ColorScheme? { active.forcedScheme ?? appearance.scheme }

    static let appearanceKey = "coral.appearance.v2"
    private init() {
        active = ThemeState.active
        appearance = AppAppearance(rawValue: UserDefaults.standard.string(forKey: Self.appearanceKey) ?? "") ?? .auto
    }
}

// MARK: - Hex helper

/// Build a `Color(light:dark:)` from two hex strings ("RRGGBB").
private func hex(_ light: String, _ dark: String) -> Color {
    Color(light: color(fromHex: light), dark: color(fromHex: dark))
}

private func color(fromHex s: String) -> Color {
    var v: UInt64 = 0
    Scanner(string: s).scanHexInt64(&v)
    return Color(red: Double((v >> 16) & 0xFF) / 255,
                 green: Double((v >> 8) & 0xFF) / 255,
                 blue: Double(v & 0xFF) / 255)
}
