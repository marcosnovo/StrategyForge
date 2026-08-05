//
//  CursorParticleField.swift
//  StrategyForge
//
//  The Antigravity landing-page background, retuned to Coral: a whole FIELD of tiny drifting
//  specks scattered across the view that SCATTER AWAY from the cursor — the pointer opens a
//  calm bubble in the field, and the specks ease back to their home spots when it leaves. Not a
//  comet glued to the cursor (that was the earlier miss); an ambient constellation that reacts.
//  Coral-family colours, faint, one cheap Canvas. Blank/static under Reduce Motion.
//

import SwiftUI
import AppKit

/// The mutable field state — a reference type so the mouse monitor and the per-frame step mutate
/// it without churning SwiftUI @State (the Canvas just reads it each frame).
private final class CursorFieldState {
    struct Speck {
        var hx: Double            // home position, as a fraction of the canvas (0…1)
        var hy: Double
        var x: CGFloat = 0        // live pixel position
        var y: CGFloat = 0
        var vx: CGFloat = 0
        var vy: CGFloat = 0
        var len: CGFloat          // half-length of the little dash
        var ang: Double           // orientation
        var colorIndex: Int
    }
    var specks: [Speck] = []
    var cursor: CGPoint = .zero
    var hasCursor = false
    private var seeded = false
    private var size: CGSize = .zero

    /// Lay `count` specks with homes biased AWAY from the centre (so they don't crowd the hero
    /// text) — sampled once. Pixel positions start at home.
    func seed(count: Int, size: CGSize) {
        guard !seeded || self.size != size else { return }
        self.size = size
        if !seeded {
            specks = (0..<count).map { _ in
                // Reject a central ellipse a couple of times so density thins toward the middle.
                var hx = Double.random(in: 0...1), hy = Double.random(in: 0...1)
                for _ in 0..<2 {
                    let dx = hx - 0.5, dy = hy - 0.5
                    if (dx * dx) / (0.30 * 0.30) + (dy * dy) / (0.24 * 0.24) < 1 {
                        hx = Double.random(in: 0...1); hy = Double.random(in: 0...1)
                    }
                }
                return Speck(hx: hx, hy: hy,
                             len: CGFloat.random(in: 1.4...3.0),
                             ang: Double.random(in: 0..<(2 * .pi)),
                             colorIndex: Int.random(in: 0..<4))
            }
            seeded = true
        }
        for i in specks.indices {
            specks[i].x = CGFloat(specks[i].hx) * size.width
            specks[i].y = CGFloat(specks[i].hy) * size.height
        }
    }

    /// One physics step: spring gently toward home, get PUSHED away from the cursor within a
    /// radius (the bubble), damp, integrate. Frame-rate-agnostic enough at ~60fps.
    func step(size: CGSize) {
        guard seeded else { return }
        let radius: CGFloat = 150
        for i in specks.indices {
            var p = specks[i]
            let homeX = CGFloat(p.hx) * size.width
            let homeY = CGFloat(p.hy) * size.height
            p.vx += (homeX - p.x) * 0.020
            p.vy += (homeY - p.y) * 0.020
            if hasCursor {
                let dx = p.x - cursor.x, dy = p.y - cursor.y
                let d2 = dx * dx + dy * dy
                if d2 < radius * radius {
                    let d = max(sqrt(d2), 0.01)
                    let push = (1 - d / radius) * 3.2          // stronger the closer it is
                    p.vx += dx / d * push
                    p.vy += dy / d * push
                }
            }
            p.vx *= 0.90; p.vy *= 0.90
            p.x += p.vx; p.y += p.vy
            specks[i] = p
        }
    }
}

/// Installs a scoped mouse monitor + tracking area so the field follows the cursor while it's over
/// this view (and forgets it on exit → specks drift home), without stealing SwiftUI gestures.
private struct FieldTracker: NSViewRepresentable {
    let field: CursorFieldState
    func makeNSView(context: Context) -> NSView { TrackingView(field: field) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class TrackingView: NSView {
        weak var field: CursorFieldState?
        private var monitor: Any?
        init(field: CursorFieldState) { self.field = field; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Without this AppKit never generates .mouseMoved, so nothing would react.
            window?.acceptsMouseMovedEvents = true
            if monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
                    guard let self, let window = self.window, event.window === window else { return event }
                    let p = self.convert(event.locationInWindow, from: nil)
                    if let field = self.field {
                        if self.bounds.contains(p) {
                            field.cursor = CGPoint(x: p.x, y: self.bounds.height - p.y)   // AppKit→SwiftUI y-flip
                            field.hasCursor = true
                        } else {
                            field.hasCursor = false
                        }
                    }
                    return event
                }
            }
        }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds,
                                           options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self, userInfo: nil))
        }
        override func mouseMoved(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            field?.cursor = CGPoint(x: p.x, y: bounds.height - p.y)
            field?.hasCursor = true
        }
        override func mouseExited(with event: NSEvent) { field?.hasCursor = false }
        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
    }
}

struct CursorParticleField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How many specks fill the field. Cheap enough to be generous.
    var count: Int = 150
    @State private var field = CursorFieldState()

    /// Coral-family palette — warm, on-brand (no cool blues like the reference).
    private static let palette: [Color] = [Theme.coral, Theme.coralDeep, Theme.warning, Theme.accent]

    var body: some View {
        if reduceMotion {
            Color.clear
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { _ in
                Canvas { ctx, size in
                    field.seed(count: count, size: size)
                    field.step(size: size)
                    for p in field.specks {
                        let c = Self.palette[p.colorIndex % Self.palette.count]
                        let hx = CGFloat(cos(p.ang)) * p.len
                        let hy = CGFloat(sin(p.ang)) * p.len
                        var path = Path()
                        path.move(to: CGPoint(x: p.x - hx, y: p.y - hy))
                        path.addLine(to: CGPoint(x: p.x + hx, y: p.y + hy))
                        ctx.stroke(path, with: .color(c.opacity(0.55)),
                                   style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    }
                }
                .background(FieldTracker(field: field))
                .allowsHitTesting(false)   // purely decorative — never eat clicks
            }
        }
    }
}
