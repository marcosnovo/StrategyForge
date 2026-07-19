//
//  IndependentVerifierSeal.swift
//  StrategyForge
//
//  A small quality seal that surfaces Coral's "reviewer ≠ author" guarantee: the loop
//  verifier runs READ-ONLY, so the judge can't quietly fix the code it's grading. It's a
//  real technical fact (LoopRunner spawns the verifier with disallowed edit tools); this
//  makes it read as the advantage it is, wherever the verifier appears.
//

import SwiftUI

struct IndependentVerifierSeal: View {
    @Environment(AppModel.self) private var model
    /// `.full` shows the title + explanation (editor); `.compact` is a one-line pill
    /// (run panel, next to the verdict).
    enum Style { case full, compact }
    var style: Style = .full

    var body: some View {
        switch style {
        case .full:
            HStack(alignment: .top, spacing: Space.s) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.teal)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.t("seal.verifier.title"))
                        .font(.sfCallout.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text(model.t("seal.verifier.body"))
                        .font(.sfCaption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                .fill(Theme.tealSoft))
            .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                .strokeBorder(Theme.tealEdge, lineWidth: 1))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(model.t("seal.verifier.title")). \(model.t("seal.verifier.body"))")
        case .compact:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text(model.t("seal.verifier.compact"))
                    .font(.sfCaption2.weight(.medium))
            }
            .foregroundStyle(Theme.teal)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Theme.tealSoft))
            .help(model.t("seal.verifier.body"))
            .accessibilityLabel(model.t("seal.verifier.body"))
        }
    }
}
