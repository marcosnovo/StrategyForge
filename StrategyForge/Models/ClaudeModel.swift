//
//  ClaudeModel.swift
//  StrategyForge
//
//  The set of Claude models that can be assigned to a role. Raw values are the
//  exact model ids passed to Claude Code; display metadata is read from the
//  centralized catalog in `Constants` so there is a single source of truth.
//

import Foundation

/// A Claude model selectable for a role. The raw value is the model id used both
/// in subagent frontmatter (`model:`) and in the launch command (`--model`).
enum ClaudeModel: String, Codable, CaseIterable, Identifiable, Hashable {
    case opus48 = "claude-opus-4-8"
    case fable5 = "claude-fable-5"
    case sonnet5 = "claude-sonnet-5"
    case haiku45 = "claude-haiku-4-5"

    var id: String { rawValue }

    /// The metadata entry from the centralized catalog, if present.
    private var info: Constants.ModelInfo? {
        Constants.models.first { $0.id == rawValue }
    }

    /// Human-friendly name for pickers (falls back to the id).
    var displayName: String {
        info?.displayName ?? rawValue
    }

    /// Optional localization key for the safeguard note surfaced as a tooltip
    /// (e.g. Fable → Opus redirect). Resolve via `AppModel.t(_:)` at render time.
    var safeguardNoteKey: String? {
        info?.safeguardNoteKey
    }

    // MARK: - Capability tier (educational framing)

    /// A plain-language "what kind of mind is this" framing — the model setting is
    /// about how CAPABLE the model is (what it knows), distinct from effort (how
    /// hard it works). Values are localization keys resolved in the UI.
    var tierNameKey: String {
        switch self {
        case .fable5:  return "model.tier.specialist"
        case .opus48:  return "model.tier.expert"
        case .sonnet5: return "model.tier.generalist"
        case .haiku45: return "model.tier.fast"
        }
    }

    /// A one-line hint about when to reach for this tier.
    var tierBlurbKey: String { tierNameKey + ".blurb" }

    /// An SF Symbol that conveys the tier at a glance in the model grid.
    var tierIcon: String {
        switch self {
        case .opus48:  return "star.fill"          // Expert
        case .fable5:  return "scope"              // Specialist
        case .sonnet5: return "book.fill"          // Generalist
        case .haiku45: return "bolt.fill"          // Fast
        }
    }
}
