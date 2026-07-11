//
//  WorkingLogo.swift
//  StrategyForge
//
//  The "working / waiting" indicator. Now the app's dot-particle spinner (see
//  ParticleField) so all waiting states share one coral motion identity.
//

import SwiftUI

struct WorkingLogo: View {
    var size: CGFloat = 18
    var body: some View { DotSpinner(size: size) }
}
