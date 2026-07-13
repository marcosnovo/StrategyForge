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

    /// Accent = coral. Small text/icon tints resolve a hair deeper on light ground.
    static let accent = Color(
        light: Color(red: 0.862, green: 0.290, blue: 0.180),   // #DC4A2E readable coral
        dark:  Color(red: 1.000, green: 0.420, blue: 0.330))   // #FF6B54
    static let accentHover = Color(
        light: Color(red: 0.784, green: 0.243, blue: 0.145),   // #C83E25
        dark:  Color(red: 1.000, green: 0.541, blue: 0.451))   // #FF8A73
    static let accentSoft = Color(
        light: Color(red: 1.000, green: 0.420, blue: 0.330).opacity(0.12),
        dark:  Color(red: 1.000, green: 0.420, blue: 0.330).opacity(0.16))
    static let accentGlow = Color(
        light: Color(red: 1.000, green: 0.420, blue: 0.330).opacity(0.22),
        dark:  Color(red: 1.000, green: 0.420, blue: 0.330).opacity(0.30))
    /// Readable text/foreground to place ON a solid accent (coral) fill.
    static let onAccent = Color.white

    /// Primary/body text — warm "ink" (identity), instead of cool system black/gray.
    static let ink = Color(
        light: Color(red: 0.102, green: 0.141, blue: 0.149),   // #1A2426
        dark:  Color(red: 0.918, green: 0.953, blue: 0.945))   // #EAF3F1
    static let inkDim = Color(
        light: Color(red: 0.431, green: 0.482, blue: 0.471),   // #6E7B78
        dark:  Color(red: 0.525, green: 0.627, blue: 0.627))   // #86A0A0

    /// Primary button fill — the identity CTA gradient (158°, coral-lo → coral-hi).
    static let primaryFill = LinearGradient(
        colors: [Color(red: 1.000, green: 0.541, blue: 0.431),   // #FF8A6E coral-lo
                 Color(red: 0.941, green: 0.243, blue: 0.153)],  // #F03E27 coral-hi
        startPoint: .topLeading, endPoint: .bottomTrailing)

    // MARK: Surfaces — warm paper in light, "reef ink" (teal-tinted) in dark
    static let appBg = Color(
        light: Color(red: 0.968, green: 0.953, blue: 0.933),   // #F7F3EE warm paper
        dark:  Color(red: 0.047, green: 0.075, blue: 0.082))   // #0C1315 reef ink
    static let cardBg = Color(
        light: .white,                                          // #FFFFFF
        dark:  Color(red: 0.071, green: 0.118, blue: 0.129))   // #121E21 reef surface
    static let insetBg = Color(
        light: Color(red: 0.984, green: 0.969, blue: 0.945),   // #FBF7F1 surface-2
        dark:  Color(red: 0.086, green: 0.149, blue: 0.165))   // #16262A
    /// Warm near-black surface for the left navigation rail.
    static let railBg = Color(
        light: Color(red: 0.047, green: 0.075, blue: 0.082),   // #0C1315
        dark:  Color(red: 0.031, green: 0.055, blue: 0.063))   // #081014
    /// Panel surface for the chats + activity columns (warm white / reef surface).
    static let columnBg = Color(
        light: .white,
        dark:  Color(red: 0.071, green: 0.118, blue: 0.129))   // #121E21

    // MARK: Lines — warm hairline (identity --line)
    // A hair quieter than the identity value so edges recede and material
    // contrast carries separation (minimalist pass).
    static let hairline = Color(
        light: Color(red: 0.918, green: 0.890, blue: 0.851),   // #EAE3D9 (was #E7DED2)
        dark:  Color(red: 0.114, green: 0.176, blue: 0.196))   // #1D2D32 (was #22343A)

    // MARK: Text on materials — warm ink-dim / mono-dim (identity)
    static let secondaryOnMaterial = Color(
        light: Color(red: 0.431, green: 0.482, blue: 0.471),   // #6E7B78 ink-dim
        dark:  Color(red: 0.525, green: 0.627, blue: 0.627))   // #86A0A0
    static let tertiaryOnMaterial = Color(
        light: Color(red: 0.576, green: 0.525, blue: 0.478),   // #93867A mono-dim
        dark:  Color(red: 0.431, green: 0.541, blue: 0.541))   // #6E8A8A

    // MARK: Status (aligned to the Coral identity)
    static let success = Color(
        light: Color(red: 0.208, green: 0.690, blue: 0.416),   // #35B06A green
        dark:  Color(red: 0.306, green: 0.796, blue: 0.557))   // #4ECB8E
    static let warning = Color(
        light: Color(red: 0.898, green: 0.631, blue: 0.227),   // #E5A13A amber
        dark:  Color(red: 1.000, green: 0.773, blue: 0.239))   // #FFC53D
    static let danger = Color(
        light: Color(red: 0.941, green: 0.243, blue: 0.153),   // #F03E27 coral-hi
        dark:  Color(red: 1.000, green: 0.361, blue: 0.424))   // #FF5C6C

    // MARK: Metrics — softer, more rounded (reference-style)
    /// Top inset for column headers so their content clears the floating traffic
    /// lights / hidden titlebar (content fills to the window edge; this pushes the
    /// header text down to a comfortable toolbar height instead of the very edge).
    static let titlebarInset: CGFloat = 30
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
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.primaryFill))
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
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .allowsHitTesting(false)
    }
}
extension ButtonStyle where Self == MoonButtonStyle {
    /// Primary living-coral button.
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
                    // Modern "float": a larger, softer, lower-alpha shadow instead
                    // of a hard drop — cards hover over the paper rather than sit on it.
                    .shadow(color: .black.opacity(0.12), radius: 22, x: 0, y: 9)
            )
    }
}

extension View {
    /// Wrap content in a solid card with subtle depth — material contrast carries
    /// separation (no hairline edge), for a calmer, more minimal surface.
    func card(padding: CGFloat = 20) -> some View {
        modifier(CardModifier(padding: padding))
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

extension View {
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
                Button { model.dismissBanner() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.plain)
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
