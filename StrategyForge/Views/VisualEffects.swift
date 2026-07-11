//
//  VisualEffects.swift
//  StrategyForge
//
//  True "behind-window" glass: an NSVisualEffectView that blurs the DESKTOP behind
//  the window (not just content within it), plus a small configurator that makes the
//  window non-opaque so that translucency reads — the floating-glass look from the
//  reference. Frosted panels (columns, chat) layer on top with within-window material.
//

import SwiftUI
import AppKit

/// A desktop-blurring vibrancy layer for the window background.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
        v.state = .active
    }
}

/// Makes the hosting window non-opaque with a clear background so the behind-window
/// vibrancy shows the desktop, and keeps the titlebar transparent for a seamless
/// floating panel. Drop it in a `.background { WindowConfigurator() }`.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { [weak v] in
            guard let window = v?.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            // Let the whole window be dragged from empty chrome (like the reference).
            window.isMovableByWindowBackground = true
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Titlebar double-click to zoom

/// Toggles the key window between its zoomed ("maximized") frame and its previous
/// size — the standard macOS green-button / titlebar-double-click behaviour, which a
/// hidden titlebar otherwise loses. Respects the user's "double-click to" preference.
@MainActor func zoomKeyWindow() {
    (NSApp.keyWindow ?? NSApp.mainWindow)?.performZoom(nil)
}

extension View {
    /// Add standard "double-click the header to zoom the window" behaviour to a
    /// custom header bar. Uses a simultaneous gesture so child controls still work.
    func zoomWindowOnDoubleClick() -> some View {
        simultaneousGesture(TapGesture(count: 2).onEnded { zoomKeyWindow() })
    }
}

// MARK: - Resizable divider

/// A draggable vertical divider that resizes an adjacent column, borrowing width
/// from the flexible neighbour. Bind it to the column's width; `sign` is +1 when the
/// divider sits on the column's trailing edge (drag right → wider), -1 on the leading
/// edge (e.g. a right-hand panel that grows as you drag left).
struct ResizableDivider: View {
    @Binding var width: CGFloat
    var range: ClosedRange<CGFloat>
    var sign: CGFloat = 1
    @State private var startWidth: CGFloat?
    @State private var hovering = false

    var body: some View {
        Divider()
            .overlay(
                // A wider invisible hit area so the 1pt line is easy to grab.
                Rectangle().fill(Color.clear).frame(width: 10).contentShape(Rectangle())
                    .onHover { h in
                        hovering = h
                        if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { v in
                                let base = startWidth ?? width
                                if startWidth == nil { startWidth = width }
                                let proposed = base + sign * v.translation.width
                                width = min(max(proposed, range.lowerBound), range.upperBound)
                            }
                            .onEnded { _ in startWidth = nil }
                    )
            )
            .background(hovering ? Theme.accent.opacity(0.5) : .clear)
    }
}
