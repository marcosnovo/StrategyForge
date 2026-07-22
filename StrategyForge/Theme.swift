//
//  Theme.swift
//  StrategyForge
//
//  Visual identity: "Coral" — a dark-first developer-tool look with a living
//  coral accent (the brand, actions, the orchestrator) over a teal "reef water"
//  secondary and neutrals biased warm/cool to harmonize. Monospaced labels give
//  it a technical fingerprint. All tokens ship both light and dark.
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

    // MARK: Coral brand accent + teal secondary
    /// The brand coral. Bright on dark; a touch deeper on light so small text/icons
    /// keep contrast. This is the app's action color and the orchestrator's hue.
    static let coral      = Color(red: 1.000, green: 0.420, blue: 0.330)   // #FF6B54
    static let coralDeep  = Color(red: 0.886, green: 0.251, blue: 0.165)   // #E24029 (fills/pressed)
    /// The reef-water secondary: team agents, active/live state, secondary actions.
    static let teal       = Color(red: 0.078, green: 0.761, blue: 0.671)   // #14C2AB
    static let tealDeep   = Color(red: 0.047, green: 0.549, blue: 0.486)   // #0C8C7C
    // Coral = user/brand/action. Teal = system/agents/secondary.
    static let tealSoft   = Color(red: 0.078, green: 0.761, blue: 0.671).opacity(0.12)  // chip/worker washes
    static let tealEdge   = Color(red: 0.078, green: 0.761, blue: 0.671).opacity(0.30)  // faint worker borders
    /// Teal #14C2AB is only ~2.1:1 on white — unreadable as text. Use this for teal
    /// TEXT/icon labels (live-state) on light surfaces; `teal` stays for fills/dots/bars.
    static let tealText   = Color(
        light: Color(red: 0.039, green: 0.490, blue: 0.431),   // #0A7D6E (AA 5.0:1 on white)
        dark:  Color(red: 0.078, green: 0.761, blue: 0.671))   // #14C2AB

    /// Accent = coral. Small text/icon tints resolve a hair deeper on light ground.
    static let accent = Color(
        light: Color(red: 0.765, green: 0.227, blue: 0.133),   // #C33A22 readable coral (AA 5.3:1 on white)
        dark:  Color(red: 1.000, green: 0.420, blue: 0.330))   // #FF6B54
    static let accentHover = Color(
        light: Color(red: 0.784, green: 0.243, blue: 0.145),   // #C83E25
        dark:  Color(red: 1.000, green: 0.541, blue: 0.451))   // #FF8A73
    static let accentSoft = Color(
        light: Color(red: 1.000, green: 0.420, blue: 0.330).opacity(0.18),   // raised: a 12% wash on white was nearly invisible (color review)
        dark:  Color(red: 1.000, green: 0.420, blue: 0.330).opacity(0.16))
    static let accentGlow = Color(
        light: Color(red: 1.000, green: 0.420, blue: 0.330).opacity(0.22),
        dark:  Color(red: 1.000, green: 0.420, blue: 0.330).opacity(0.30))

    // MARK: Selection & Focus
    /// Soft coral wash for a selected list row / card. Pale enough to read as a
    /// background state, not a solid block. Pair with `selectionBorder` + the bar.
    static let selectionFill = Color(
        light: Color(red: 1.000, green: 0.420, blue: 0.330).opacity(0.22),   // raised so a selected row reads coral on white, not a peach ghost
        dark:  Color(red: 1.000, green: 0.420, blue: 0.330).opacity(0.20))
    /// Hairline border for a selected row/card (1 pt).
    static let selectionBorder = Color(
        light: Color(red: 0.862, green: 0.290, blue: 0.180).opacity(0.40),
        dark:  Color(red: 1.000, green: 0.420, blue: 0.330).opacity(0.44))
    /// Focus ring stroke for text fields / focusable controls (visible only when focused).
    static let focusRing = Theme.accent.opacity(0.55)
    /// Focus glow shadow color for focused inputs.
    static let focusGlow = Theme.accent.opacity(0.18)

    /// Readable text/foreground to place ON a solid accent (coral) fill.
    /// Contrast rule (WCAG AA): any fill that carries `onAccent` (white) text — the coral
    /// gradients below, `success`/`danger` when filled — must keep white ≥ 4.5:1 across the
    /// WHOLE fill, including a gradient's lightest stop. The coral gradients were darkened
    /// from #FF8A6E (only ~2.3:1 with white) to meet this.
    static let onAccent = Color.white

    /// Primary/body text — warm "ink" (identity), instead of cool system black/gray.
    static let ink = Color(
        light: Color(red: 0.102, green: 0.141, blue: 0.149),   // #1A2426
        dark:  Color(red: 0.918, green: 0.953, blue: 0.945))   // #EAF3F1
    static let inkDim = Color(
        light: Color(red: 0.431, green: 0.482, blue: 0.471),   // #6E7B78
        dark:  Color(red: 0.525, green: 0.627, blue: 0.627))   // #86A0A0

    /// Primary button fill — the identity CTA gradient, now the TRUE brand coral: bright
    /// #FF6B54 into a controlled deep. White text legibility is guaranteed at the glyph via
    /// `coralTextShadow` (a scrim on the text), NOT by browning the whole fill — so the CTA
    /// finally reads as Coral, not rust (color review, hero-coral decision).
    static let primaryFill = LinearGradient(
        colors: [Color(red: 1.000, green: 0.420, blue: 0.330),   // #FF6B54 bright coral
                 Color(red: 0.886, green: 0.251, blue: 0.165)],  // #E24029 coralDeep
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Vivid coral gradient for the user's chat bubble — the founder's bright coral (#FF6B54)
    /// into coralDeep. White text rides on `coralTextShadow` so the top bright stop stays
    /// legible without darkening the fill to brick.
    static let userBubbleFill = LinearGradient(
        colors: [Color(red: 1.000, green: 0.420, blue: 0.330),   // #FF6B54 bright coral
                 Color(red: 0.886, green: 0.251, blue: 0.165)],  // #E24029 coralDeep
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// A soft dark scrim applied to white text/glyphs sitting on a bright coral fill (user
    /// bubble, `.moon` CTA, send button). Lets the fill stay vivid #FF6B54 while keeping the
    /// white legible — the "contrast at the glyph" approach.
    static let coralTextShadow = Color.black.opacity(0.28)

    // MARK: Surfaces — near-white (a whisper of warmth) in light, "reef ink" in dark
    // Warm greige neutrals with a REAL elevation staircase (bg < column < card < inset), so
    // depth reads from tone first and shadow is a whisper on top (premium review, wave 1).
    static let appBg = Color(
        light: Color(red: 0.969, green: 0.957, blue: 0.933),   // #F7F4EE warm sand ground
        dark:  Color(red: 0.043, green: 0.071, blue: 0.078))   // #0B1214 warm reef ink
    static let cardBg = Color(
        light: Color(red: 1.000, green: 0.992, blue: 0.980),   // #FFFDFA warm off-white (lifts by tone)
        dark:  Color(red: 0.082, green: 0.145, blue: 0.157))   // #152528 warm reef surface (≠ column)
    static let insetBg = Color(
        light: Color(red: 0.937, green: 0.922, blue: 0.890),   // #EFEBE3 warm stone well
        dark:  Color(red: 0.102, green: 0.180, blue: 0.196))   // #1A2E32 deeper well
    /// Warm near-black surface for the left navigation rail (the darkest anchor).
    static let railBg = Color(
        light: Color(red: 0.031, green: 0.059, blue: 0.071),   // #080F12
        dark:  Color(red: 0.031, green: 0.059, blue: 0.071))   // #080F12
    /// Panel surface for the chats + activity columns — sits BETWEEN ground and card.
    static let columnBg = Color(
        light: Color(red: 0.984, green: 0.973, blue: 0.949),   // #FBF8F2 warm greige
        dark:  Color(red: 0.063, green: 0.106, blue: 0.118))   // #101B1E

    // MARK: Lines — warm hairline (identity --line)
    // A hair quieter than the identity value so edges recede and material
    // contrast carries separation (minimalist pass).
    static let hairline = Color(
        light: Color(red: 0.918, green: 0.890, blue: 0.851),   // #EAE3D9 (was #E7DED2)
        dark:  Color(red: 0.114, green: 0.176, blue: 0.196))   // #1D2D32 (was #22343A)

    // MARK: Text on materials — warm ink-dim / mono-dim (identity)
    static let secondaryOnMaterial = Color(
        light: Color(red: 0.365, green: 0.416, blue: 0.404),   // #5D6A67 ink-dim (AA 5.6:1 on white)
        dark:  Color(red: 0.525, green: 0.627, blue: 0.627))   // #86A0A0
    static let tertiaryOnMaterial = Color(
        light: Color(red: 0.431, green: 0.392, blue: 0.349),   // #6E6459 mono-dim (keeps AA on the warmer inset)
        dark:  Color(red: 0.494, green: 0.604, blue: 0.604))   // #7E9A9A (AA on inset)

    // MARK: Status (aligned to the Coral identity)
    static let success = Color(
        light: Color(red: 0.090, green: 0.518, blue: 0.263),   // #178443 (was #35B06A ≈2.5:1 as text)
        dark:  Color(red: 0.306, green: 0.796, blue: 0.557))   // #4ECB8E
    static let warning = Color(
        light: Color(red: 0.898, green: 0.631, blue: 0.227),   // #E5A13A amber (fills/icons)
        dark:  Color(red: 1.000, green: 0.773, blue: 0.239))   // #FFC53D
    /// Amber can't pass AA as text on white without going brown — use this for warning
    /// TEXT/labels on light surfaces; `warning` stays for fills/dots/icons.
    static let warningText = Color(
        light: Color(red: 0.561, green: 0.353, blue: 0.000),   // #8F5A00 amber-brown (AA 5.8:1)
        dark:  Color(red: 1.000, green: 0.773, blue: 0.239))   // #FFC53D
    /// Danger repainted off the coral hue (was #F03E27 ≈ coral): a cooler crimson so error
    /// reads unmistakably "not-brand" and stays distinct for red-blind users.
    static let danger = Color(
        light: Color(red: 0.831, green: 0.176, blue: 0.247),   // #D42D3F crimson (AA 4.9:1, hue ~353°)
        dark:  Color(red: 1.000, green: 0.361, blue: 0.424))   // #FF5C6C

    // MARK: Team spectrum (governed) — muted, cool-leaning teammate hues so the coral
    // ORCHESTRATOR stays the unmistakable hero in any topology. Desaturated ~25% from the
    // old full-strength set; reviewer/researcher no longer collide with warning/success.
    static let teamBlue   = Color(red: 0.329, green: 0.471, blue: 0.659)   // #5478A8 planner
    static let teamGreen  = Color(red: 0.290, green: 0.588, blue: 0.439)   // #4A9670 researcher (≠ success)
    static let teamViolet = Color(red: 0.502, green: 0.451, blue: 0.682)   // #8073AE advisor
    static let teamAmber  = Color(red: 0.710, green: 0.541, blue: 0.322)   // #B58A52 reviewer (≠ warning)
    static let teamRose   = Color(red: 0.745, green: 0.498, blue: 0.596)   // #BE7F98 specialist

    // MARK: Metrics — softer, more rounded (reference-style)
    /// Top inset for column headers so their content clears the floating traffic
    /// lights / hidden titlebar (content fills to the window edge; this pushes the
    /// header text down to a comfortable toolbar height instead of the very edge).
    static let titlebarInset: CGFloat = 30
    // Corner radii — soft & modern (reference "Aetheris" glass aesthetic): generous
    // rounding on cards, pills and bubbles for an airy, friendly surface.
    static let corner: CGFloat = 20
    static let innerCorner: CGFloat = 16
    /// Chat message bubble radius.
    static let bubbleCorner: CGFloat = 18
    /// Corner radius for the pill action buttons (`.moon` / `.reefOutline`).
    static let buttonCorner: CGFloat = 14
    /// Tight radius for list/nav ROW selection highlights, so the coral "spotlight"
    /// hugs the row instead of floating as a loose lozenge.
    static let rowCorner: CGFloat = 9
    static let sectionSpacing: CGFloat = 20
    /// Vertical gap between chat messages (Claude/Superhuman-like breathing room).
    static let messageSpacing: CGFloat = 18
    /// Extra gap added above a user message to separate conversation turns.
    static let turnGap: CGFloat = 10
    /// Extra line spacing for body copy so long replies read comfortably.
    static let bodyLineSpacing: CGFloat = 3
}

// MARK: - Coral brand mark

/// The Coral brand mark: a branching-coral glyph that doubles as the agent
/// topology — one root fanning out to four tips. Matches the app icon. Drawn in
/// the coral accent by default; pass a color for monochrome contexts.
struct CoralMark: View {
    var size: CGFloat = 22
    var color: Color = Theme.coral

    // (startX, startY, controlX, controlY, endX, endY) on a 0…100 canvas.
    private static let branches: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (50, 84, 50, 70, 50, 60),
        (50, 60, 40, 52, 29, 40),
        (29, 40, 24, 31, 21, 24),
        (29, 40, 34, 31, 39, 25),
        (50, 60, 60, 52, 71, 40),
        (71, 40, 76, 31, 79, 24),
        (71, 40, 66, 31, 61, 25),
    ]
    private static let nodes: [(CGFloat, CGFloat, CGFloat)] = [
        (50, 84, 7.6), (21, 24, 5.6), (39, 25, 5.6), (61, 25, 5.6), (79, 24, 5.6),
    ]

    var body: some View {
        Canvas { ctx, sz in
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x / 100 * sz.width, y: y / 100 * sz.height)
            }
            var path = Path()
            for b in Self.branches {
                path.move(to: pt(b.0, b.1))
                path.addQuadCurve(to: pt(b.4, b.5), control: pt(b.2, b.3))
            }
            ctx.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: sz.width * 0.062, lineCap: .round, lineJoin: .round))
            for n in Self.nodes {
                let r = n.2 / 100 * sz.width
                let c = pt(n.0, n.1)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .color(color))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The official GitHub mark (octicon, template-rendered so it takes the current
/// foreground color). Use wherever the app talks to GitHub (repos, clone, PRs).
struct GitHubMark: View {
    var size: CGFloat = 16
    var body: some View {
        Image("GitHubMark")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Primary "Deep sea" button style

/// The primary action button: a living-coral gradient fill with white text.
struct MoonButtonStyle: ButtonStyle {
    // Explicit type: bare `Configuration` collides with the app's Configuration model.
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        MoonButtonBody(configuration: configuration)
    }
}

private struct MoonButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var sheenSweeps = 0   // bumped on pointer-enter → one sheen pass
    var body: some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(Theme.onAccent)
            .shadow(color: Theme.coralTextShadow, radius: 0.5, x: 0, y: 0.5)   // legible on bright coral
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .background(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous).fill(Theme.primaryFill))
            // One-shot specular sheen when the pointer enters — not a loop.
            .overlay(sheen)
            // Hover: the coral brightens a touch and its glow deepens — alive
            // without moving (safe under Reduce Motion; it's a tint, not motion).
            .brightness(hovering ? 0.05 : 0)
            .shadow(color: Theme.accent.opacity(hovering ? 0.42 : 0.32),
                    radius: hovering ? 8 : 6, x: 0, y: 2)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.18), value: hovering)
            .onHover { over in
                let nowHovering = isEnabled && over
                if nowHovering && !hovering && !reduceMotion { sheenSweeps += 1 }
                hovering = nowHovering
            }
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed)
            .contentShape(Rectangle())
    }

    /// A diagonal white band that sweeps the coral fill once per pointer-enter,
    /// parked off-bounds (clipped away) whenever it isn't animating.
    private var sheen: some View {
        GeometryReader { geo in
            let w = geo.size.width
            LinearGradient(colors: [.clear, .white.opacity(0.4), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: w * 0.55, height: geo.size.height * 2.2)
                .rotationEffect(.degrees(24))
                .keyframeAnimator(initialValue: -0.8, trigger: sheenSweeps) { view, x in
                    view.offset(x: w * x, y: -geo.size.height * 0.6)
                } keyframes: { _ in
                    KeyframeTrack {
                        // Instant reset off-bounds so EVERY pointer-enter sweeps
                        // (a lone end-keyframe would leave the band parked at 1.3
                        // and make every sweep after the first invisible).
                        MoveKeyframe(-0.8)
                        CubicKeyframe(1.3, duration: 0.55)
                    }
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous))
        .allowsHitTesting(false)
    }
}
extension ButtonStyle where Self == MoonButtonStyle {
    /// Primary living-coral button.
    static var moon: MoonButtonStyle { MoonButtonStyle() }
}

// MARK: - Secondary "Reef outline" button style

/// The secondary action next to `.moon`: a flat, hairline-outlined button (neutral at
/// rest so the coral primary leads) that warms to coral on hover. Same height/padding
/// as `.moon` so the pair aligns. This is the reference's outline-secondary look.
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        OutlineButtonBody(configuration: configuration)
    }
}

private struct OutlineButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false
    var body: some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(hovering ? Theme.accent : Theme.ink)
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .background(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                .fill(hovering ? Theme.accentSoft : .clear))
            .overlay(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                .strokeBorder(hovering ? Theme.accent.opacity(0.35) : Theme.hairline, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.18), value: hovering)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: configuration.isPressed)
            .onHover { hovering = isEnabled && $0 }
            .contentShape(Rectangle())
    }
}
extension ButtonStyle where Self == OutlineButtonStyle {
    /// Secondary hairline-outline button (warms to coral on hover).
    static var reefOutline: OutlineButtonStyle { OutlineButtonStyle() }
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
    /// Tight bold display for the hero title / brand (no serif). Larger + heavier so a
    /// hero greeting reads as a designed moment against its sphere, not a card title.
    /// Apply `.tracking(-0.5)` at hero sites for the ceñido look.
    static let sfDisplay = Font.system(.largeTitle, design: .default).weight(.bold)      // ~26
    static let sfCardTitle = Font.system(.title3).weight(.semibold)                     // ~15
    static let sfBodyM = Font.system(.body)                                             // ~13
    static let sfCallout = Font.system(.callout)                                        // ~12
    static let sfCaption2 = Font.system(.subheadline)                                   // ~11
    /// Monospaced, all-caps field labels — the technical fingerprint.
    static let sfFieldLabel = Font.system(.caption, design: .monospaced).weight(.semibold) // ~10
    static let sfCode = Font.system(.callout, design: .monospaced)                      // ~12
    /// Monospaced wordmark / model tags.
    static let sfMono = Font.system(.body, design: .monospaced).weight(.semibold)       // ~13

    /// Accessibility floor: no text should render below this. Fixed `.system(size:)`
    /// fonts don't scale with Dynamic Type and several sat at 7–9pt; use `.scaledFont`
    /// (below) which both clamps to this floor AND scales with the user's text size.
    static let minFontSize: CGFloat = 10
}

/// A fixed-size system font that (a) never renders below `Theme.minFontSize` and (b)
/// scales with Dynamic Type — the drop-in for `.font(.system(size:))` at small sizes.
private struct ScaledSystemFont: ViewModifier {
    let weight: Font.Weight
    let design: Font.Design
    @ScaledMetric private var size: CGFloat

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        self.weight = weight
        self.design = design
        // @ScaledMetric scales the (floored) base size with the user's Dynamic Type setting.
        self._size = ScaledMetric(wrappedValue: max(size, Font.minFontSize))
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    /// Dynamic-Type-scaling system font with a 10pt accessibility floor. Prefer this over
    /// `.font(.system(size:))` for fixed sizes so tiny labels can't drop below 10pt and
    /// still grow with the user's text-size setting.
    ///
    /// Micro-type ramp (design review A6): because of the 10pt floor, **every `size` below
    /// 10 renders identically** (7, 8, 8.5, 9 all floor to 10 and then scale together), so
    /// the sub-10 number is cosmetic — it does NOT make text smaller. Use **9** as the one
    /// sanctioned micro size for eyebrow/caption labels; reach past `scaledFont` (e.g.
    /// `sfCaption2`, `sfFieldLabel`) only when you want a size that actually differs. For
    /// the semantic split, keep `design: .monospaced` for static labels/ids and `.rounded`
    /// for live numbers.
    func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular,
                    design: Font.Design = .default) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design))
    }
}

// MARK: - Elevation (physical depth: objects resting on the reef)

/// An elevation level — a floating card reads as a physical object because it casts BOTH a
/// soft ambient shadow and a tight contact shadow, and (critically on dark) the ambient must
/// be 2–3× stronger than a flat 0.12 or it vanishes on reef ink (premium review, wave 1).
enum Elevation { case e1, e2, e3, e4 }

private struct ElevationModifier: ViewModifier {
    let level: Elevation
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let p = Self.params(level: level, dark: scheme == .dark)
        content
            .shadow(color: .black.opacity(p.aA), radius: p.aR, x: 0, y: p.aY)   // ambient (soft, spread)
            .shadow(color: .black.opacity(p.cA), radius: p.cR, x: 0, y: p.cY)   // contact (tight, grounding)
    }
    /// (ambient alpha/radius/y, contact alpha/radius/y) per level × appearance.
    static func params(level: Elevation, dark: Bool)
        -> (aA: Double, aR: CGFloat, aY: CGFloat, cA: Double, cR: CGFloat, cY: CGFloat) {
        switch (level, dark) {
        case (.e1, true):  return (0.28, 14,  6, 0.22, 2, 1)
        case (.e1, false): return (0.06, 10,  4, 0.05, 1.5, 1)
        case (.e2, true):  return (0.34, 22, 10, 0.26, 3, 1)
        case (.e2, false): return (0.10, 18,  8, 0.06, 2, 1)
        case (.e3, true):  return (0.40, 30, 14, 0.30, 4, 2)
        case (.e3, false): return (0.14, 26, 12, 0.08, 3, 1)
        case (.e4, true):  return (0.48, 40, 20, 0.34, 5, 2)
        case (.e4, false): return (0.20, 34, 16, 0.10, 4, 2)
        }
    }
}

extension View {
    /// A dark-mode-aware elevation (ambient + contact shadow) so a surface reads as a
    /// physical object resting on the reef. e1 = inline cards, e2 = floating cards,
    /// e3 = popovers, e4 = sheets / command palette.
    func elevation(_ level: Elevation) -> some View { modifier(ElevationModifier(level: level)) }
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
                    .elevation(.e2)   // floats above the reef with ambient + contact depth
            )
    }
}

extension View {
    /// Wrap content in a solid card with subtle depth — material contrast carries
    /// separation (no hairline edge), for a calmer, more minimal surface.
    func card(padding: CGFloat = 20) -> some View {
        modifier(CardModifier(padding: padding))
    }

    /// Like `card`, but stretches to fill its container's height — so cards laid out
    /// side by side in a grid row all share the tallest one's height (uniform boxes).
    func equalCard(padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.cardBg)
                    .elevation(.e2)
            )
    }

    // MARK: Glass language (the three tiers — keep surfaces on the right one)
    //
    // The app has THREE glass treatments; new surfaces must pick the matching tier
    // rather than inventing a fourth. They are intentionally distinct — the goal of the
    // #38 convergence is that each surface uses the RIGHT one consistently, not that they
    // all look identical:
    //
    //  1. `.glassEffect(.regular…)` — native Liquid Glass (macOS 26). FLOATING, often
    //     INTERACTIVE chrome that sits over content and should refract it: the composer
    //     send button, floating chips/pills, the running badge. Prefer `.interactive()`
    //     for anything tappable. This is the canonical target; migrate a surface here
    //     once it's been re-validated rendered on 26 in light AND dark.
    //  2. `glassPanel()` — STATIC cards/sheets: sheets, onboarding cards, the advisor
    //     card, loop editor sections. Now routes through the SAME native `.glassEffect`
    //     (converged in #38), so it's really tier 1 for non-interactive surfaces — one
    //     glass engine, not a hand-rolled material that drifts from the real thing.
    //  3. `translucentColumn()` — the fixed SIDE COLUMNS (nav rail, chat list). Reads as a
    //     flat neutral column that shares the chat surface's color, NOT floating glass;
    //     do not swap these to `.glassEffect` (they must not refract the content beside
    //     them or the two-column layout stops reading as one surface).
    //
    /// A translucent side-column surface tinted to the app's neutral CHAT color
    /// (`Theme.columnBg`) instead of the aurora: a frosted material for the glassy feel,
    /// with a `columnBg` wash over it so the left columns read as the SAME color as the
    /// chat + activity panel while staying translucent (the aurora only whispers through).
    func translucentColumn(tint: Double = 0.52) -> some View {
        modifier(TranslucentColumnModifier(tint: tint))
    }

    /// The navigation RAIL's surface: the native macOS `.sidebar` vibrancy so the far-left
    /// rail reads as a true sidebar, distinct from the content columns (which use
    /// `translucentColumn`). This is the "rail ≠ content" separation (design review D5).
    /// Opaque `railBg` fallback under Reduce Transparency.
    func railColumn() -> some View {
        modifier(RailColumnModifier())
    }

    /// A frosted glass panel for static cards/sheets. Converged (#38) onto the SAME
    /// native Liquid Glass engine as `.glassEffect` so the app speaks one glass language
    /// instead of three. Falls back to an opaque card under Reduce Transparency.
    /// (Dropped the old `material:`/`strokeOpacity:` params — the modifier always renders
    /// `.glassEffect(.regular)`, so those knobs did nothing but mislead callers.)
    func glassPanel(cornerRadius: CGFloat = Theme.corner) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius))
    }
}

/// Translucent side column, with an opaque fallback when Reduce Transparency is on.
private struct TranslucentColumnModifier: ViewModifier {
    var tint: Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Theme.columnBg)                       // solid, no material
        } else {
            content.background(Theme.columnBg.opacity(tint)).background(.ultraThinMaterial)
        }
    }
}

/// The rail's surface: a DENSER material (`.regularMaterial`) than the airy
/// `.ultraThinMaterial` content columns, over a faint `columnBg` wash, so the far-left
/// rail reads as a more substantial sidebar distinct from the chat list / activity panel
/// — predictable and in-window (text contrast unchanged). Opaque `railBg` fallback under
/// Reduce Transparency.
private struct RailColumnModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Theme.insetBg)   // a neutral step from the columns' columnBg, text-safe
        } else {
            content.background(Theme.columnBg.opacity(0.30)).background(.regularMaterial)
        }
    }
}

/// Native Liquid Glass panel, with an opaque card fallback under Reduce Transparency.
private struct GlassPanelModifier: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content.background(shape.fill(Theme.cardBg))
                .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 1))
                .clipShape(shape)
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}

// MARK: - Motion primitives (the "alive" layer)

/// macOS hover feedback for tappable cards: a whisper of scale (1.01) and a
/// slightly deeper shadow, ~0.18s ease. Under Reduce Motion there is no scale —
/// a subtle warm tint overlay marks the hover instead.
struct HoverLift: ViewModifier {
    var enabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    func body(content: Content) -> some View {
        let lift = enabled && hovering && !reduceMotion
        let tint = enabled && hovering && reduceMotion
        content
            .overlay(
                RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                    .fill(Theme.accentSoft.opacity(tint ? 0.6 : 0))
                    .allowsHitTesting(false)
            )
            .scaleEffect(lift ? 1.01 : 1)
            .shadow(color: .black.opacity(lift ? 0.10 : 0), radius: 12, x: 0, y: 5)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hovering)
            .onHover { hovering = enabled && $0 }
    }
}

/// The list-row variant of `hoverLift`: no scale or shadow (rows have clear
/// backgrounds, so a shadow would halo the text) — just a quiet neutral fill
/// behind the row while the pointer is over it.
struct HoverTint: ViewModifier {
    var cornerRadius: CGFloat = Theme.innerCorner
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.045 : 0))
            )
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
    }
}

/// A slow (~3s) breathing glow for brand marks and live elements: the shadow's
/// opacity and radius swell and settle forever. Rests as a static soft glow
/// under Reduce Motion.
struct BreathingGlow: ViewModifier {
    var color: Color
    var enabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(breathing ? 0.45 : 0.18),
                    radius: breathing ? 10 : 5)
            .onAppear {
                guard enabled && !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
    }
}

/// A sweeping specular highlight for streaming/loading states: a diagonal
/// white band crosses the content every ~1.8 s while `active`. The band lives
/// in a clipped overlay, so layout never changes. No band at all when idle or
/// under Reduce Motion.
struct ShimmerModifier: ViewModifier {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var sweep = false

    func body(content: Content) -> some View {
        content.overlay {
            if active && !reduceMotion {
                GeometryReader { geo in
                    let w = geo.size.width
                    LinearGradient(colors: [.clear,
                                            .white.opacity(scheme == .dark ? 0.35 : 0.5),
                                            .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: max(w * 0.35, 48), height: geo.size.height * 2.4)
                        .rotationEffect(.degrees(35))
                        .offset(x: sweep ? w * 1.25 : -w * 0.6, y: -geo.size.height * 0.7)
                        .onAppear {
                            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                                sweep = true
                            }
                        }
                        .onDisappear { sweep = false }   // rearm for the next run
                }
                .blendMode(.overlay)
                .clipped()
                .allowsHitTesting(false)
            }
        }
    }
}

/// One-shot entrance: fade + 8 pt rise, delayed by `index` × 50 ms (capped at
/// ~0.4 s so deep lists don't crawl). Instant under Reduce Motion.
struct StaggeredAppear: ViewModifier {
    var index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .onAppear {
                guard !shown else { return }
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)
                        .delay(Double(min(index, 8)) * 0.05)) {
                        shown = true
                    }
                }
            }
    }
}

/// A refined selection treatment for list rows and cards: soft coral tint, 1pt
/// hairline border, and a 3pt leading coral bar (the non-color shape cue). Selection
/// ≠ focus: this never draws a glow, and hover stays a separate (neutral) layer.
struct SelectedRow: ViewModifier {
    var isSelected: Bool
    var cornerRadius: CGFloat = 8
    /// Base fill when unselected (e.g. Theme.cardBg for cards, .clear for list rows).
    var restingFill: Color = .clear
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isSelected ? Theme.selectionFill : restingFill))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? Theme.selectionBorder : .clear, lineWidth: 1))
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Theme.accent)
                        .frame(width: 3)
                        .padding(.vertical, 6)
                }
            }
    }
}

extension View {
    /// Selection treatment (tint + border + leading bar). Pass `restingFill` for card
    /// surfaces that need a base color when unselected.
    func selectedRow(_ isSelected: Bool, cornerRadius: CGFloat = 8,
                     restingFill: Color = .clear) -> some View {
        modifier(SelectedRow(isSelected: isSelected, cornerRadius: cornerRadius, restingFill: restingFill))
    }
    /// Hover lift for tappable cards (scale + shadow; tint-only under Reduce Motion).
    func hoverLift(_ enabled: Bool = true) -> some View {
        modifier(HoverLift(enabled: enabled))
    }
    /// Hover background tint for list rows (no scale/shadow).
    func hoverTint(cornerRadius: CGFloat = Theme.innerCorner) -> some View {
        modifier(HoverTint(cornerRadius: cornerRadius))
    }
    /// Slow breathing shadow for brand marks / live elements.
    func breathingGlow(color: Color, enabled: Bool = true) -> some View {
        modifier(BreathingGlow(color: color, enabled: enabled))
    }
    /// A sweeping specular highlight for streaming/loading states.
    func shimmer(_ active: Bool) -> some View {
        modifier(ShimmerModifier(active: active))
    }
    /// One-shot entrance: fade + 8pt rise, delayed by index*50ms.
    /// Instant under Reduce Motion.
    func staggeredAppear(index: Int) -> some View {
        modifier(StaggeredAppear(index: index))
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
            .background(
                Circle()
                    .fill(Theme.accentSoft)
                    // A whisper of inner light from the top lifts the badge off
                    // the card without adding an edge — flat fills read cheap.
                    .overlay(
                        Circle().fill(LinearGradient(
                            colors: [.white.opacity(0.22), .clear],
                            startPoint: .top, endPoint: .center))
                    )
            )
    }
}

// MARK: - Section header (icon)

struct SectionHeader<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    /// When true, the leading badge shows the GitHub mark instead of an SF Symbol.
    var useGitHubMark = false
    @ViewBuilder var trailing: Trailing

    init(_ icon: String, _ title: String, subtitle: String? = nil, useGitHubMark: Bool = false,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.useGitHubMark = useGitHubMark
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                if useGitHubMark {
                    GitHubMark(size: 17)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Theme.accentSoft))
                } else {
                    IconBadge(systemName: icon)
                }
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

// MARK: - App-wide banner (shared)

/// App-wide banner capsule: renders `AppModel.banner` (success/failure) wherever
/// it's hosted; the ✕ calls `model.dismissBanner()`. Port of ContentView's old
/// private GlobalBanner, promoted so window roots AND sheets can host it.
struct BannerCapsule: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let banner = model.banner {
            let isSuccess: Bool = { if case .success = banner { return true } else { return false } }()
            let text: String = { if case .success(let m) = banner { return m }
                                 if case .failure(let m) = banner { return m }; return "" }()
            HStack(spacing: Space.s) {
                Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                Text(text).font(.sfCallout.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                // Failures are actionable: fix (Connected Services) + export the log.
                if !isSuccess {
                    Button { model.openConnectedServices() } label: {
                        Text(model.t("banner.fix")).font(.sfCaption2.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(.white.opacity(0.22)))
                    Button { model.exportDiagnostics() } label: {
                        Text(model.t("banner.exportLog")).font(.sfCaption2.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(.white.opacity(0.22)))
                }
                // Undo (e.g. after deleting a chat) — restores it and clears the banner.
                if let undo = model.bannerCenter.pendingUndo {
                    Button { model.bannerCenter.performUndo() } label: {
                        Text(undo.label).font(.sfCaption2.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(.white.opacity(0.22)))
                }
                Button { model.dismissBanner() } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                        .padding(6)                    // a comfortable hit target, not a 10pt speck
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)       // Esc also closes it
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Space.l).padding(.vertical, Space.m)
            .background(Capsule().fill(isSuccess ? Theme.success : Theme.danger)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4))
            .padding(.top, Space.m)
            .frame(maxWidth: 720)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

extension View {
    /// Top-aligned overlay hosting the shared banner. Apply to window roots AND
    /// sheet roots that can emit banners (sheets otherwise hide the window's).
    func bannerOverlay() -> some View { overlay(alignment: .top) { BannerCapsule() } }
}

// MARK: - Copy button (shared)

/// Icon-only borderless copy button: copies `text` to the pasteboard, flips its
/// icon to a checkmark for ~1.5 s, and (when `flashKey` is set) flashes the
/// shared success banner with that localized message.
struct CopyButton: View {
    /// Copied to NSPasteboard on tap.
    let text: String
    /// Tooltip + accessibility label.
    var help: String
    /// When set: `model.flashSuccess(model.t(flashKey!))` on tap.
    var flashKey: String? = nil
    @Environment(AppModel.self) private var model
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            if let flashKey { model.flashSuccess(model.t(flashKey)) }
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                .foregroundStyle(copied ? Theme.success : Theme.accent)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
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
