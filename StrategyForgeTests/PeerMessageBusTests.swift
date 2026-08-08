//
//  PeerMessageBusTests.swift
//  StrategyForgeTests
//
//  The delivery rules for cross-chat messaging. The bus takes its clock as a
//  parameter, so every window (dedup, rate limit) is exercised without sleeping.
//

import Testing
import Foundation
@testable import Coral

@MainActor
struct PeerMessageBusTests {

    private let sender = UUID()
    private let receiver = UUID()
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func message(_ text: String, from: UUID? = nil, at: Date? = nil) -> PeerMessage {
        PeerMessage(fromChatID: from ?? sender, fromName: "Sender",
                    text: text, sentAt: at ?? t0)
    }

    // MARK: - Accept

    @Test func acceptedMessageIsQueuedAndDrainsInOrder() {
        let bus = PeerMessageBus()
        #expect(bus.offer(message("first"), to: receiver, policy: .accept, now: t0) == .queued)
        #expect(bus.offer(message("second"), to: receiver, policy: .accept,
                          now: t0.addingTimeInterval(1)) == .queued)

        #expect(bus.queuedCount(for: receiver) == 2)
        let drained = bus.drainQueued(for: receiver)
        #expect(drained.map(\.text) == ["first", "second"])
        // Draining clears it — a message is delivered once.
        #expect(bus.drainQueued(for: receiver).isEmpty)
    }

    @Test func drainingAnEmptyInboxIsHarmless() {
        let bus = PeerMessageBus()
        #expect(bus.drainQueued(for: receiver).isEmpty)
        #expect(bus.queuedCount(for: receiver) == 0)
    }

    // MARK: - Validation

    @Test func emptyTextIsRefused() {
        let bus = PeerMessageBus()
        #expect(bus.offer(message("   \n "), to: receiver, policy: .accept, now: t0)
                == .refused(.empty))
        #expect(bus.queuedCount(for: receiver) == 0)
    }

    @Test func aChatCannotMessageItself() {
        let bus = PeerMessageBus()
        #expect(bus.offer(message("hi", from: receiver), to: receiver, policy: .accept, now: t0)
                == .refused(.selfAddressed))
    }

    // MARK: - Loop throttle

    @Test func identicalRepeatInsideTheWindowIsDropped() {
        let bus = PeerMessageBus()
        #expect(bus.offer(message("same"), to: receiver, policy: .accept, now: t0) == .queued)
        #expect(bus.offer(message("same"), to: receiver, policy: .accept,
                          now: t0.addingTimeInterval(5)) == .refused(.duplicate))
        #expect(bus.queuedCount(for: receiver) == 1)
    }

    @Test func identicalRepeatAfterTheWindowGoesThrough() {
        let bus = PeerMessageBus()
        _ = bus.offer(message("same"), to: receiver, policy: .accept, now: t0)
        let later = t0.addingTimeInterval(PeerMessageBus.duplicateWindow + 1)
        #expect(bus.offer(message("same"), to: receiver, policy: .accept, now: later) == .queued)
        #expect(bus.queuedCount(for: receiver) == 2)
    }

    @Test func differentTextIsNotADuplicate() {
        let bus = PeerMessageBus()
        _ = bus.offer(message("one"), to: receiver, policy: .accept, now: t0)
        #expect(bus.offer(message("two"), to: receiver, policy: .accept,
                          now: t0.addingTimeInterval(1)) == .queued)
    }

    /// The whole point of the throttle: two chats answering each other stop on their own.
    @Test func aTwoChatLoopStopsOnItsOwn() {
        let bus = PeerMessageBus()
        var delivered = 0
        for i in 0..<40 {
            let now = t0.addingTimeInterval(Double(i))
            // A ping-pong of the same two lines, alternating direction.
            let outcome = i.isMultiple(of: 2)
                ? bus.offer(message("ping", from: sender, at: now), to: receiver,
                            policy: .accept, now: now)
                : bus.offer(message("pong", from: receiver, at: now), to: sender,
                            policy: .accept, now: now)
            if outcome == .queued { delivered += 1 }
        }
        // Not 40. The dedup window plus the per-route allowance cut it right down.
        #expect(delivered <= PeerMessageBus.maxPerRateWindow * 2)
    }

    // MARK: - Rate limit

    @Test func rateLimitAppliesPerRouteAndRecovers() {
        let bus = PeerMessageBus()
        // Distinct texts, so only the rate limit can stop them.
        for i in 0..<PeerMessageBus.maxPerRateWindow {
            let now = t0.addingTimeInterval(Double(i))
            #expect(bus.offer(message("m\(i)"), to: receiver, policy: .accept, now: now) == .queued)
        }
        let blocked = t0.addingTimeInterval(Double(PeerMessageBus.maxPerRateWindow))
        #expect(bus.offer(message("over"), to: receiver, policy: .accept, now: blocked)
                == .refused(.rateLimited))

        // Once the window rolls past, the route opens again.
        let recovered = t0.addingTimeInterval(PeerMessageBus.rateWindow + 1)
        #expect(bus.offer(message("after"), to: receiver, policy: .accept, now: recovered) == .queued)
    }

    @Test func oneBusyRouteDoesNotThrottleAnother() {
        let bus = PeerMessageBus()
        let other = UUID()
        for i in 0...PeerMessageBus.maxPerRateWindow {
            _ = bus.offer(message("m\(i)"), to: receiver, policy: .accept,
                          now: t0.addingTimeInterval(Double(i)))
        }
        // The sender is throttled toward `receiver`, but `other` is a different route.
        #expect(bus.offer(message("hello"), to: other, policy: .accept, now: t0) == .queued)
    }

    @Test func aRefusalDoesNotConsumeTheAllowance() {
        let bus = PeerMessageBus()
        // Ten refusals against a receiver that drops everything.
        for i in 0..<10 {
            #expect(bus.offer(message("m\(i)"), to: receiver, policy: .refuse,
                              now: t0.addingTimeInterval(Double(i))) == .refused(.inboundRefuse))
        }
        // The route is untouched, so a later accept still has its full allowance.
        for i in 0..<PeerMessageBus.maxPerRateWindow {
            let now = t0.addingTimeInterval(100 + Double(i))
            #expect(bus.offer(message("ok\(i)"), to: receiver, policy: .accept, now: now) == .queued)
        }
    }

    // MARK: - Caps

    @Test func unreadQueueIsCapped() {
        let bus = PeerMessageBus()
        // Push past the cap using distinct senders, so neither throttle interferes.
        var accepted = 0
        for i in 0..<(PeerMessageBus.maxQueued + 10) {
            let outcome = bus.offer(message("m\(i)", from: UUID()), to: receiver,
                                    policy: .accept, now: t0)
            if outcome == .queued { accepted += 1 } else { #expect(outcome == .refused(.queueFull)) }
        }
        #expect(accepted == PeerMessageBus.maxQueued)
        #expect(bus.queuedCount(for: receiver) == PeerMessageBus.maxQueued)
    }

    @Test func heldQueueDropsTheOldestPastItsCap() {
        let bus = PeerMessageBus()
        for i in 0..<(PeerMessageBus.maxHeld + 5) {
            _ = bus.offer(message("m\(i)", from: UUID()), to: receiver, policy: .hold, now: t0)
        }
        let held = bus.heldMessages(for: receiver)
        #expect(held.count == PeerMessageBus.maxHeld)
        // The first five aged out; the newest survived.
        #expect(held.first?.text == "m5")
        #expect(held.last?.text == "m\(PeerMessageBus.maxHeld + 4)")
    }

    // MARK: - Hold / approve / deny

    @Test func heldMessageReachesTheChatOnlyOnApproval() {
        let bus = PeerMessageBus()
        #expect(bus.offer(message("wait"), to: receiver, policy: .hold, now: t0) == .held)
        #expect(bus.queuedCount(for: receiver) == 0)

        let held = bus.heldMessages(for: receiver)
        #expect(held.count == 1)
        #expect(bus.approveHeld(held[0].id, for: receiver))
        #expect(bus.heldMessages(for: receiver).isEmpty)
        #expect(bus.drainQueued(for: receiver).map(\.text) == ["wait"])
    }

    @Test func denyingAHeldMessageDropsIt() {
        let bus = PeerMessageBus()
        _ = bus.offer(message("nope"), to: receiver, policy: .hold, now: t0)
        let held = bus.heldMessages(for: receiver)
        #expect(bus.dropHeld(held[0].id, for: receiver))
        #expect(bus.heldMessages(for: receiver).isEmpty)
        #expect(bus.queuedCount(for: receiver) == 0)
        // Dropping twice is a no-op, not a crash.
        #expect(!bus.dropHeld(held[0].id, for: receiver))
    }

    @Test func switchingToAcceptReleasesHeldMessagesInOrder() {
        let bus = PeerMessageBus()
        _ = bus.offer(message("a", from: UUID()), to: receiver, policy: .hold, now: t0)
        _ = bus.offer(message("b", from: UUID()), to: receiver, policy: .hold, now: t0)

        bus.applyPolicyChange(.accept, for: receiver)
        #expect(bus.heldMessages(for: receiver).isEmpty)
        #expect(bus.drainQueued(for: receiver).map(\.text) == ["a", "b"])
    }

    @Test func switchingToRefuseDropsHeldMessages() {
        let bus = PeerMessageBus()
        _ = bus.offer(message("a", from: UUID()), to: receiver, policy: .hold, now: t0)
        bus.applyPolicyChange(.refuse, for: receiver)
        #expect(bus.heldMessages(for: receiver).isEmpty)
        #expect(bus.queuedCount(for: receiver) == 0)
    }

    @Test func switchingToHoldLeavesHeldMessagesAlone() {
        let bus = PeerMessageBus()
        _ = bus.offer(message("a", from: UUID()), to: receiver, policy: .hold, now: t0)
        bus.applyPolicyChange(.hold, for: receiver)
        #expect(bus.heldMessages(for: receiver).count == 1)
    }

    // MARK: - Lifecycle

    @Test func forgettingAChatClearsItsMailAndItsRoutes() {
        let bus = PeerMessageBus()
        _ = bus.offer(message("queued"), to: receiver, policy: .accept, now: t0)
        _ = bus.offer(message("held", from: UUID()), to: receiver, policy: .hold, now: t0)

        bus.forget(receiver)
        #expect(bus.queuedCount(for: receiver) == 0)
        #expect(bus.heldMessages(for: receiver).isEmpty)

        // The route is gone too, so the identical text isn't mistaken for a repeat.
        #expect(bus.offer(message("queued"), to: receiver, policy: .accept,
                          now: t0.addingTimeInterval(1)) == .queued)
    }

    /// Eviction is a memory decision; it must not cost the chat its mail. And the
    /// messages must NOT go back through `offer` — the dedup window would swallow them.
    @Test func requeuePutsMailBackAtTheFrontAndSkipsTheThrottles() {
        let bus = PeerMessageBus()
        _ = bus.offer(message("newer"), to: receiver, policy: .accept, now: t0)
        let returned = PeerMessage(fromChatID: sender, fromName: "Sender",
                                   text: "older", sentAt: t0)
        bus.requeue([returned], for: receiver)

        #expect(bus.drainQueued(for: receiver).map(\.text) == ["older", "newer"])
    }

    @Test func requeueIsANoOpForNothing() {
        let bus = PeerMessageBus()
        bus.requeue([], for: receiver)
        #expect(bus.queuedCount(for: receiver) == 0)
    }

    @Test func requeueRespectsTheQueueCap() {
        let bus = PeerMessageBus()
        let many = (0..<(PeerMessageBus.maxQueued + 10)).map {
            PeerMessage(fromChatID: sender, fromName: "S", text: "m\($0)", sentAt: t0)
        }
        bus.requeue(many, for: receiver)
        #expect(bus.queuedCount(for: receiver) == PeerMessageBus.maxQueued)
        // The front is kept — those are the oldest, and dropping them would reorder.
        #expect(bus.drainQueued(for: receiver).first?.text == "m0")
    }

    @Test func chatsWithMailCoversBothQueuedAndHeld() {
        let bus = PeerMessageBus()
        let other = UUID()
        _ = bus.offer(message("q"), to: receiver, policy: .accept, now: t0)
        _ = bus.offer(message("h"), to: other, policy: .hold, now: t0)
        #expect(bus.chatsWithMail == Set([receiver, other]))

        _ = bus.drainQueued(for: receiver)
        #expect(bus.chatsWithMail == Set([other]))
    }

    // MARK: - Framing

    @Test func promptCarriesTheSenderAndTheGuardRails() {
        let m = PeerMessage(fromChatID: sender, fromName: "payments-api",
                            text: "Schema migration finished.", sentAt: t0)
        let prompt = m.promptForModel
        #expect(prompt.contains("payments-api"))
        #expect(prompt.contains("Schema migration finished."))
        // The limits have to travel with the text — the receiving run is headless.
        #expect(prompt.contains("not the user's"))
        #expect(prompt.contains("plain text"))
    }
}
