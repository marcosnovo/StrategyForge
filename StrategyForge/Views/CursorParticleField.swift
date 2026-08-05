//
//  CursorParticleField.swift
//  StrategyForge
//
//  An ambient background that trails the cursor with a soft comet of Coral particles — the
//  Antigravity landing-page feel, retuned to Coral's palette. A chain of nodes eases toward the
//  pointer (head follows the cursor, each node follows the one ahead), drawn as fading coral
//  glows with faint connecting veins, so moving the mouse leaves a warm, living wake. Purely
//  decorative and cheap (a handful of points, one Canvas). Static/blank under Reduce Motion.
//

import SwiftUI
import AppKit

/// The mutable trail state. A reference type so the mouse monitor and the per-frame step can
/// mutate it without churning SwiftUI @State (the Canvas just reads it each frame).
private final class CursorTrail {
    struct Node { var pos: CGPoint }
    var nodes: [Node] = []
    var target: CGPoint = .zero
    var hasTarget = false
    private var seeded = false

    /// Advance the comet one frame: the head eases toward the cursor, each following node eases
    /// toward the one ahead — a smooth, self-damping tail with no springy overshoot.
    func step(count: Int) {
        guard hasTarget else { return }
        if !seeded || nodes.count != count {
            nodes = Array(repeating: Node(pos: target), count: count)
            seeded = true
        }
        let follow: CGFloat = 0.30
        nodes[0].pos.x += (target.x - nodes[0].pos.x) * follow
        nodes[0].pos.y += (target.y - nodes[0].pos.y) * follow
        for i in 1..<nodes.count {
            nodes[i].pos.x += (nodes[i - 1].pos.x - nodes[i].pos.x) * follow
            nodes[i].pos.y += (nodes[i - 1].pos.y - nodes[i].pos.y) * follow
        }
    }
}

/// Installs a scoped mouse-moved/dragged monitor so the field follows the cursor while it's over
/// this view — without stealing SwiftUI's gestures (a local NSEvent monitor, like the Map's
/// scroll-zoom installer). Coordinates are converted to the view's SwiftUI (top-left) space.
private struct CursorTracker: NSViewRepresentable {
    let trail: CursorTrail
    func makeNSView(context: Context) -> NSView {
        let v = TrackingView()
        v.trail = trail
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class TrackingView: NSView {
        weak var trail: CursorTrail?
        private var monitor: Any?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
                    guard let self, let window = self.window, event.window === window else { return event }
                    let p = self.convert(event.locationInWindow, from: nil)
                    if self.bounds.contains(p), let trail = self.trail {
                        // AppKit is bottom-left; SwiftUI Canvas is top-left → flip y.
                        trail.target = CGPoint(x: p.x, y: self.bounds.height - p.y)
                        trail.hasTarget = true
                    }
                    return event
                }
            }
        }
        // Also catch passive moves even when another view is first responder.
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds,
                                           options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                           owner: self, userInfo: nil))
        }
        override func mouseMoved(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            trail?.target = CGPoint(x: p.x, y: bounds.height - p.y)
            trail?.hasTarget = true
        }
        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
    }
}

struct CursorParticleField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Length of the comet (head + tail nodes). Short enough to stay cheap and calm.
    var count: Int = 18
    @State private var trail = CursorTrail()

    var body: some View {
        if reduceMotion {
            Color.clear   // no ambient motion when the user asked for none
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { _ in
                Canvas { ctx, _ in
                    trail.step(count: count)
                    guard trail.hasTarget, trail.nodes.count == count else { return }

                    // Soft connecting veins between consecutive nodes (the wake).
                    for i in 1..<trail.nodes.count {
                        let a = trail.nodes[i - 1].pos, b = trail.nodes[i].pos
                        let t = Double(i) / Double(count)
                        var path = Path()
                        path.move(to: a); path.addLine(to: b)
                        ctx.stroke(path, with: .color(Theme.coral.opacity(0.10 * (1 - t))),
                                   style: StrokeStyle(lineWidth: 2.2 * (1 - CGFloat(t)), lineCap: .round))
                    }
                    // The particles themselves: coral → warm gold along the tail, each a small
                    // glow (a tiered stack of discs = a cheap gaussian), fading toward the tip.
                    for (i, node) in trail.nodes.enumerated() {
                        let t = Double(i) / Double(count)
                        let r = CGFloat(7.5 * (1 - t) + 1.5)
                        let tint = Theme.coral.mix(with: Theme.warning, by: t * 0.5)
                        for (mult, op): (CGFloat, Double) in [(2.6, 0.05), (1.6, 0.10), (1.0, 0.22)] {
                            let gr = r * mult
                            ctx.fill(Path(ellipseIn: CGRect(x: node.pos.x - gr, y: node.pos.y - gr,
                                                            width: 2 * gr, height: 2 * gr)),
                                     with: .color(tint.opacity(op * (1 - t * 0.7))))
                        }
                    }
                }
                .background(CursorTracker(trail: trail))
                .allowsHitTesting(false)   // purely decorative — never eat clicks
            }
        }
    }
}
