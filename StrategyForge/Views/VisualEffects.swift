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
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
