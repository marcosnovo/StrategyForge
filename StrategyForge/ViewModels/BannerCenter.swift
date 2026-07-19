//
//  BannerCenter.swift
//  StrategyForge
//
//  The app-wide transient banner (success / failure), extracted from AppModel as the
//  first phase of the incremental AppModel breakup (#35). Owns the banner state and its
//  auto-dismiss timing; AppModel keeps thin forwarders (flashSuccess/flashFailure/
//  dismissBanner/banner) so no call site changed.
//

import SwiftUI

@Observable
@MainActor
final class BannerCenter {
    /// Transient banner shown after actions.
    enum Banner: Equatable {
        case success(String)
        case failure(String)
    }
    var banner: Banner?

    /// An optional "Undo" action attached to the current banner (e.g. after a delete).
    /// The closure can't live in the Equatable `Banner` enum (used in the auto-dismiss
    /// `banner == banner` check), so it rides alongside as its own observed value.
    struct UndoAction { let label: String; let perform: () -> Void }
    var pendingUndo: UndoAction?

    /// Cancels a pending auto-dismiss when a new banner supersedes it.
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    /// True while the current banner is a failure — the capsule then offers the
    /// "Export log" / "Fix" actions.
    var isFailure: Bool { if case .failure = banner { return true } else { return false } }

    /// An auto-dismissing success banner.
    func success(_ message: String) { pendingUndo = nil; show(.success(message)) }

    /// A sticky failure banner. Every failure is also written to the diagnostics log so
    /// it can be exported later.
    func failure(_ message: String) {
        pendingUndo = nil
        DiagnosticsLog.record(message)
        show(.failure(message))
    }

    /// A success banner that also offers an Undo action for its lifetime (e.g. delete).
    func showWithUndo(_ message: String, undoLabel: String, undo: @escaping () -> Void) {
        pendingUndo = UndoAction(label: undoLabel, perform: undo)
        show(.success(message))
    }

    /// Run the pending Undo (if any) and clear the banner.
    func performUndo() {
        let action = pendingUndo
        dismiss()
        action?.perform()
    }

    /// Dismiss the current banner (the capsule's close button).
    func dismiss() {
        withAnimation {
            banner = nil
            pendingUndo = nil
            dismissTask?.cancel()
        }
    }

    /// Show a banner and always schedule its auto-dismiss — success after a few seconds,
    /// failures after a longer window (long enough to read + hit Fix/Export, short enough
    /// that a stuck error banner never lingers reading as "the app is frozen"). The ✕
    /// still dismisses either immediately.
    func show(_ banner: Banner) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            self.banner = banner
        }
        dismissTask?.cancel()
        let delay: Duration = { if case .success = banner { return .seconds(4) } else { return .seconds(12) } }()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            if self.banner == banner {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self.banner = nil
                    self.pendingUndo = nil
                }
            }
        }
    }
}
