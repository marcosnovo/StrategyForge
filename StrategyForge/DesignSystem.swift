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

/// The root colours a design system provides; every `Theme` colour derives from these.
struct Palette {
    var appBg, columnBg, cardBg, insetBg, railBg: Color
    var ink, secondary, tertiary, hairline: Color
    /// Brand coral (bright), the deep end of the CTA gradient (magenta in Ember), and the
    /// text/icon accent (light+dark, AA-safe where it carries text).
    var coral, coralDeep, accent: Color
    /// Accent-glow opacity (Midnight leans on this).
    var glow: Double
}

enum DesignSystem: String, CaseIterable, Identifiable, Sendable {
    case classic, reefLight, midnight, ember
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic:   return "Classic"
        case .reefLight: return "Reef Light"
        case .midnight:  return "Midnight Reef"
        case .ember:     return "Ember"
        }
    }

    /// Midnight is dark-first — force dark regardless of the system setting.
    var forcedScheme: ColorScheme? { self == .midnight ? .dark : nil }

    var palette: Palette {
        switch self {
        case .classic:
            return Palette(
                appBg: hex("FAF9F6", "0C1315"), columnBg: hex("FBFBFA", "121E21"),
                cardBg: hex("FFFFFF", "16262A"), insetBg: hex("F4F3F2", "1B2E33"),
                railBg: hex("081014", "081014"),
                ink: hex("1A2426", "EAF3F1"), secondary: hex("5D6A67", "86A0A0"),
                tertiary: hex("736A5F", "7E9A9A"), hairline: hex("EAE3D9", "1D2D32"),
                coral: hex("FF6B54", "FF6B54"), coralDeep: hex("E24029", "E24029"),
                accent: hex("C33A22", "FF6B54"), glow: 0.22)
        case .reefLight:
            return Palette(
                appBg: hex("FBFBFD", "0E1116"), columnBg: hex("F5F6F9", "141922"),
                cardBg: hex("FFFFFF", "1A2029"), insetBg: hex("EEF0F5", "212936"),
                railBg: hex("0A0D13", "0A0D13"),
                ink: hex("111318", "EEF1F6"), secondary: hex("5A6070", "9AA3B4"),
                tertiary: hex("7A8090", "7E8698"), hairline: hex("E6E8EE", "232B37"),
                coral: hex("FF5A42", "FF6B54"), coralDeep: hex("F0442C", "FF6B54"),
                accent: hex("D93A26", "FF6B54"), glow: 0.20)
        case .midnight:
            return Palette(
                appBg: hex("F8F9FB", "080A0F"), columnBg: hex("F1F3F7", "0C0F16"),
                cardBg: hex("FFFFFF", "12161F"), insetBg: hex("EBEEF3", "0A0D13"),
                railBg: hex("050609", "050609"),
                ink: hex("12151C", "F2F5FA"), secondary: hex("5C6270", "8B94A6"),
                tertiary: hex("7A8290", "6E7688"), hairline: hex("E4E7EE", "1B2130"),
                coral: hex("FF6B54", "FF6B54"), coralDeep: hex("FF4D6D", "FF4D6D"),
                accent: hex("D93A26", "FF7A63"), glow: 0.35)
        case .ember:
            return Palette(
                appBg: hex("FCFBFD", "0D0B12"), columnBg: hex("F6F5F9", "141221"),
                cardBg: hex("FFFFFF", "181521"), insetBg: hex("EFEDF3", "1E1A2A"),
                railBg: hex("0A0810", "0A0810"),
                ink: hex("141118", "F0ECF4"), secondary: hex("615A6C", "A79FB4"),
                tertiary: hex("7C7488", "8A8398"), hairline: hex("ECE8F0", "241F2E"),
                coral: hex("FF6B54", "FF6B54"), coralDeep: hex("E5397E", "FF3D8A"),
                accent: hex("D62D6E", "FF7A9C"), glow: 0.24)
        }
    }
}

/// Nonisolated snapshot the (static, actor-free) `Theme` tokens read.
enum ThemeState {
    static let key = "coral.designSystem"
    nonisolated(unsafe) static var active: DesignSystem =
        DesignSystem(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .reefLight
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
    private init() { active = ThemeState.active }
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
