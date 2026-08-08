//
//  PeerMessageBus.swift
//  StrategyForge
//
//  The inbox behind cross-chat messaging (see `PeerMessage`).
//
//  Deliberately pure bookkeeping: no processes, no files, no SwiftUI, and the clock is
//  a parameter. Every delivery rule that's easy to get subtly wrong — the loop
//  throttle, the rate limit, the queue caps, releasing held messages when the policy
//  changes — is therefore exercisable by the unit suite without spawning anything.
//
//  Why this lives in the app and not in the CLI: Coral spawns a fresh `claude` process
//  per turn and it exits when the turn ends (see ClaudeRunner.stream), so a Coral chat
//  has no inbox socket of its own while it sits idle. The long-lived process here is
//  Coral, so Coral holds the inbox and hands each message to the chat on its next idle
//  moment. That also means a chat whose ChatViewModel was evicted for memory
//  (AppModel.evictIdleChatVMs) still keeps its mail — the bus outlives the VM.
//

import Foundation

/// `@Observable` so the approval UI actually refreshes: the inbox is read from a view
/// body, and approving or discarding a held message has to redraw the list.
@Observable
@MainActor
final class PeerMessageBus {

    // Caps and windows, matching Claude Code's published behavior.

    /// Accepted messages a chat hasn't read yet.
    static let maxQueued = 50
    /// Messages held for the user's approval; past this the oldest is dropped.
    static let maxHeld = 100
    /// Identical text on the same route inside this window is dropped. This is what
    /// makes a two-chat message loop die on its own.
    static let duplicateWindow: TimeInterval = 30
    /// Rate-limit window and its allowance, per sender→receiver route.
    static let rateWindow: TimeInterval = 60
    static let maxPerRateWindow = 5

    /// One sender→receiver pair. Throttling is per route, so a chatty sender can't
    /// starve an unrelated pair.
    private struct Route: Hashable {
        let from: UUID
        let to: UUID
    }

    /// receiver → accepted messages it hasn't read yet.
    private(set) var queued: [UUID: [PeerMessage]] = [:]
    /// receiver → messages waiting on the user's approval.
    private(set) var held: [UUID: [PeerMessage]] = [:]

    private var sendTimes: [Route: [Date]] = [:]
    private var lastText: [Route: (text: String, at: Date)] = [:]

    // MARK: - Sending

    /// Offer `message` to `receiver`'s inbox under its `policy`.
    ///
    /// Refusals never consume the route's allowance: a message that was dropped didn't
    /// cost the sender anything, so a receiver set to `refuse` can't rate-limit a
    /// sender out of talking to somebody else.
    @discardableResult
    func offer(_ message: PeerMessage, to receiver: UUID, policy: PeerInbound,
               now: Date) -> PeerDeliveryOutcome {
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .refused(.empty) }
        guard message.fromChatID != receiver else { return .refused(.selfAddressed) }
        guard policy != .refuse else { return .refused(.inboundRefuse) }

        let route = Route(from: message.fromChatID, to: receiver)

        // The loop throttle: the same thing said twice in a row, too soon.
        if let last = lastText[route], last.text == text,
           now.timeIntervalSince(last.at) < Self.duplicateWindow {
            return .refused(.duplicate)
        }

        // Drop timestamps that have aged out, then check the allowance.
        var times = (sendTimes[route] ?? []).filter { now.timeIntervalSince($0) < Self.rateWindow }
        guard times.count < Self.maxPerRateWindow else {
            sendTimes[route] = times      // keep the pruned list even on a refusal
            return .refused(.rateLimited)
        }

        let outcome: PeerDeliveryOutcome
        switch policy {
        case .hold:
            var box = held[receiver] ?? []
            box.append(message)
            if box.count > Self.maxHeld { box.removeFirst(box.count - Self.maxHeld) }
            held[receiver] = box
            outcome = .held
        case .accept:
            var box = queued[receiver] ?? []
            guard box.count < Self.maxQueued else { return .refused(.queueFull) }
            box.append(message)
            queued[receiver] = box
            outcome = .queued
        case .refuse:
            return .refused(.inboundRefuse)   // unreachable; guarded above
        }

        times.append(now)
        sendTimes[route] = times
        lastText[route] = (text, now)
        return outcome
    }

    // MARK: - Receiving

    /// Everything `receiver` has waiting, in arrival order. Clears the queue — the
    /// caller owns delivery from here.
    func drainQueued(for receiver: UUID) -> [PeerMessage] {
        guard let box = queued[receiver], !box.isEmpty else { return [] }
        queued[receiver] = nil
        return box
    }

    func queuedCount(for receiver: UUID) -> Int { queued[receiver]?.count ?? 0 }
    func heldMessages(for receiver: UUID) -> [PeerMessage] { held[receiver] ?? [] }

    /// Chats with mail waiting, so the UI can badge them.
    var chatsWithMail: Set<UUID> {
        var ids = Set(queued.filter { !$0.value.isEmpty }.keys)
        ids.formUnion(held.filter { !$0.value.isEmpty }.keys)
        return ids
    }

    // MARK: - Held messages

    /// The user approved one held message: move it into the delivery queue.
    @discardableResult
    func approveHeld(_ id: PeerMessage.ID, for receiver: UUID) -> Bool {
        guard var box = held[receiver], let i = box.firstIndex(where: { $0.id == id }) else { return false }
        var q = queued[receiver] ?? []
        guard q.count < Self.maxQueued else { return false }   // leave it held rather than lose it
        let message = box.remove(at: i)
        held[receiver] = box.isEmpty ? nil : box
        q.append(message)
        queued[receiver] = q
        return true
    }

    /// The user denied one held message, or its approval dialog expired.
    @discardableResult
    func dropHeld(_ id: PeerMessage.ID, for receiver: UUID) -> Bool {
        guard var box = held[receiver], let i = box.firstIndex(where: { $0.id == id }) else { return false }
        box.remove(at: i)
        held[receiver] = box.isEmpty ? nil : box
        return true
    }

    /// A settings change made `accept` apply to this chat: release everything held, in
    /// arrival order, up to the unread cap. Whatever doesn't fit stays held.
    @discardableResult
    func releaseHeld(for receiver: UUID) -> Int {
        guard let box = held[receiver], !box.isEmpty else { return 0 }
        var q = queued[receiver] ?? []
        let room = max(0, Self.maxQueued - q.count)
        guard room > 0 else { return 0 }
        let releasing = Array(box.prefix(room))
        q.append(contentsOf: releasing)
        queued[receiver] = q
        let rest = Array(box.dropFirst(releasing.count))
        held[receiver] = rest.isEmpty ? nil : rest
        return releasing.count
    }

    /// A `refuse` now applies: drop everything held for this chat.
    func dropAllHeld(for receiver: UUID) { held[receiver] = nil }

    /// Re-apply the inbound rules to a chat whose policy just changed.
    func applyPolicyChange(_ policy: PeerInbound, for receiver: UUID) {
        switch policy {
        case .accept: _ = releaseHeld(for: receiver)
        case .refuse: dropAllHeld(for: receiver)
        case .hold:   break
        }
    }

    // MARK: - Lifecycle

    /// Put messages back at the FRONT of a chat's queue, untouched by the throttles.
    ///
    /// Used when a ChatViewModel is torn down (eviction, a repo re-bind) while it still
    /// holds undelivered mail: the messages already passed the inbound rules once, so
    /// re-running them through `offer` would be wrong — the dedup window would swallow
    /// them and they'd be lost for good.
    func requeue(_ messages: [PeerMessage], for receiver: UUID) {
        guard !messages.isEmpty else { return }
        var box = queued[receiver] ?? []
        box.insert(contentsOf: messages, at: 0)
        if box.count > Self.maxQueued { box.removeLast(box.count - Self.maxQueued) }
        queued[receiver] = box
    }

    /// A chat was deleted: forget its inbox and every route that touched it, so a
    /// recycled id can't inherit a stale rate limit.
    func forget(_ chatID: UUID) {
        queued[chatID] = nil
        held[chatID] = nil
        sendTimes = sendTimes.filter { $0.key.from != chatID && $0.key.to != chatID }
        lastText = lastText.filter { $0.key.from != chatID && $0.key.to != chatID }
    }
}
