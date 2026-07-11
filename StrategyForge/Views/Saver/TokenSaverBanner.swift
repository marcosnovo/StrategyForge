//
//  TokenSaverBanner.swift
//  StrategyForge
//
//  The Token Saver's chat-side UI: a compact one-line tip banner (at most one
//  tip at a time, dismissible) and a tiny context-weight pill that shows how
//  heavy the conversation's re-read cost has become. The coordinator mounts
//  both in ChatView and wires the actions; this file is purely presentational.
//

import SwiftUI

// MARK: - Tip banner

/// A pill-style, single-tip banner (~44pt tall): saver glyph, title + one-line
/// body (full body in the tooltip), optional action button, and a dismiss ✕.
struct TokenSaverBanner: View {
    @Environment(AppModel.self) private var model
    let tip: TokenSaverEngine.Tip
    let onAction: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.success)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(model.t(tip.titleKey))
                    .font(.sfCallout.weight(.semibold))
                    .lineLimit(1)
                Text(model.t(tip.bodyKey))
                    .font(.sfCaption2)
                    .foregroundStyle(Theme.inkDim)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .help(model.t(tip.bodyKey))   // the full body lives in the tooltip

            Spacer(minLength: Space.s)

            if let actionKey = tip.actionKey {
                Button(model.t(actionKey), action: onAction)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(model.t("saver.dismiss"))
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                .fill(Theme.insetBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        // Slide in gently from the composer's edge; fade out on dismiss.
        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity))
    }
}

// MARK: - Context weight pill

/// A tiny 3-dot gauge + compact token count ("48k"), tinted green/amber/red by
/// TokenSaverEngine.weight. The tooltip explains WHY weight matters: Claude
/// re-reads the whole conversation on every message.
struct ContextWeightPill: View {
    @Environment(AppModel.self) private var model
    let tokens: Int

    private var weight: TokenSaverEngine.ContextWeight {
        TokenSaverEngine.weight(forTokens: tokens)
    }

    private var tint: Color {
        switch weight {
        case .light:  return Theme.success
        case .medium: return Theme.warning
        case .heavy:  return Theme.danger
        }
    }

    /// How many of the 3 gauge dots are lit (1 = light, 2 = medium, 3 = heavy).
    private var litDots: Int {
        switch weight {
        case .light: return 1
        case .medium: return 2
        case .heavy: return 3
        }
    }

    private var weightNameKey: String {
        switch weight {
        case .light:  return "saver.weight.light"
        case .medium: return "saver.weight.medium"
        case .heavy:  return "saver.weight.heavy"
        }
    }

    var body: some View {
        HStack(spacing: Space.xs) {
            HStack(spacing: 2.5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i < litDots ? tint : Theme.hairline)
                        .frame(width: 4.5, height: 4.5)
                }
            }
            Text(Self.compactCount(tokens))
                .font(.sfCaption2)
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, 3)
        .background(Capsule().fill(Theme.insetBg))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        .help("\(model.t(weightNameKey)) — \(model.t("saver.weight.help"))")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.t(weightNameKey)), \(Self.compactCount(tokens)) tokens")
    }

    /// Compact token formatting: 950 → "950", 48_300 → "48k", 1_200_000 → "1.2M".
    private static func compactCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fk", Double(n) / 1_000) }
        return "\(n)"
    }
}
