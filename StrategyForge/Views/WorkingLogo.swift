//
//  WorkingLogo.swift
//  StrategyForge
//
//  The "working / waiting" indicator — the app's BRAND loader: a rotating 3D
//  Fibonacci sphere of coral dots (see Particle3DSpinner in ParticleField). Every
//  waiting state in the app routes through this so they all share one identity.
//  Honors Reduce Motion (the sphere freezes to a static frame).
//

import SwiftUI

struct WorkingLogo: View {
    var size: CGFloat = 18
    var color: Color = Theme.accent
    var body: some View { Particle3DSpinner(size: size, color: color, figure: .sphere) }
}
