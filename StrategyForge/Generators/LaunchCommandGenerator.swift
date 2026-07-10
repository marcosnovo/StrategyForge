//
//  LaunchCommandGenerator.swift
//  StrategyForge
//
//  Produces the exact command to start Claude Code with the orchestrator's model,
//  since that model is a launch setting rather than agent frontmatter.
//

import Foundation

/// Builds the copyable launch command and the equivalent in-session instruction.
enum LaunchCommandGenerator {

    /// The shell command to launch Claude Code with the orchestrator model.
    ///
    /// - Parameters:
    ///   - strategy: the strategy whose orchestrator model is used.
    ///   - binary: the `claude` binary name or absolute path (default `claude`).
    static func command(for strategy: Strategy, binary: String = "claude") -> String {
        let model = strategy.orchestrator?.model.rawValue ?? ClaudeModel.fable5.rawValue
        return "\(binary) --model \(model)"
    }

    /// Shell command that stages, commits AND pushes the generated config, so the
    /// team-shared configuration is versioned and lands on the remote (e.g. GitHub).
    /// Guards against a non-git folder so the user gets a clear message instead of
    /// a raw error.
    static func gitCommitCommand() -> String {
        "if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then "
        + "git add .claude CLAUDE.md && git commit -m \"Add Claude Code multi-agent config (Coral)\" && git push; "
        + "else echo '⚠️  This folder is not a git repository — nothing to push. Run: git init, add a remote, then commit & push.'; fi"
    }

    /// The equivalent instruction for switching model from inside a running session.
    static func inSessionInstruction(for strategy: Strategy) -> String {
        let model = strategy.orchestrator?.model.rawValue ?? ClaudeModel.fable5.rawValue
        return "/model \(model)"
    }

    /// Both forms as a short human-readable block for the CLAUDE.md / preview.
    static func instructions(for strategy: Strategy, binary: String = "claude") -> String {
        let modelName = strategy.orchestrator?.model.displayName ?? "the orchestrator model"
        return """
        Launch Claude Code in this repo with the orchestrator model (\(modelName)):

            \(command(for: strategy, binary: binary))

        Or, from inside an already-running session, switch with:

            \(inSessionInstruction(for: strategy))
        """
    }
}
