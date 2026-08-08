//
//  PeerDeliveryOrderTests.swift
//  StrategyForgeTests
//
//  Pins the two properties `ChatViewModel.receive` exists to guarantee, both of which
//  were broken in review and are invisible from the PeerMessageBus tests:
//
//  1. Peer mail joins the SAME queue as the user's type-ahead, in arrival order.
//  2. Receiving never starts a turn synchronously — AppModel delivers mail from inside
//     `isRunning`'s `didSet`, and starting a turn there cancels the run task whose
//     epilogue is mid-flight, letting it remove the placeholder at a stale index.
//

import Testing
import Foundation
@testable import Coral

@MainActor
struct PeerDeliveryOrderTests {

    private func makeVM() -> ChatViewModel {
        let config = Configuration(name: "T", strategy: StrategyLibrary.solo())
        return ChatViewModel(config: config, binary: "claude")
    }

    private func peer(_ text: String) -> PeerMessage {
        PeerMessage(fromChatID: UUID(), fromName: "Other", text: text,
                    sentAt: Date(timeIntervalSince1970: 1_000_000))
    }

    @Test func peerMailQueuesBehindTypeAheadTheUserEnteredFirst() {
        let vm = makeVM()
        vm.isRunning = true            // a turn is in flight

        vm.input = "the user typed this first"
        vm.submit()                    // queued behind the running turn
        vm.receive(peer("this arrived after"))

        #expect(vm.queued.count == 2)
        #expect(vm.queued[0].peer == nil)
        #expect(vm.queued[0].text == "the user typed this first")
        #expect(vm.queued[1].peer?.text == "this arrived after")
    }

    @Test func typeAheadEnteredAfterMailQueuesBehindIt() {
        let vm = makeVM()
        vm.isRunning = true

        vm.receive(peer("mail first"))
        vm.input = "typed second"
        vm.submit()

        #expect(vm.queued.map(\.peer?.text) == ["mail first", nil])
    }

    /// The reentrancy guard. `receive` runs from inside `isRunning`'s `didSet`, so it
    /// must only enqueue — the turn starts later, from the epilogue's own flush.
    @Test func receivingWhileIdleDoesNotStartATurnSynchronously() {
        let vm = makeVM()
        #expect(!vm.isRunning)

        vm.receive(peer("hello"))

        #expect(!vm.isRunning)         // nothing started on this tick
        #expect(vm.queued.count == 1)  // it's waiting, not lost
    }

    /// A stop drops the user's own type-ahead by design, but peer mail was never seen
    /// by the user — it goes back to the bus instead of vanishing.
    @Test func stopReturnsPeerMailInsteadOfDroppingIt() {
        let vm = makeVM()
        var returned: [PeerMessage] = []
        vm.onPeerMailReturned = { returned.append(contentsOf: $0) }

        vm.isRunning = true
        vm.input = "user type-ahead"
        vm.submit()
        vm.receive(peer("unseen mail"))

        vm.stop()

        #expect(vm.queued.isEmpty)                       // queue cleared, as before
        #expect(returned.map(\.text) == ["unseen mail"]) // but the mail survived
    }

    @Test func stopWithNoPeerMailReportsNothing() {
        let vm = makeVM()
        var calls = 0
        vm.onPeerMailReturned = { _ in calls += 1 }

        vm.isRunning = true
        vm.input = "just the user"
        vm.submit()
        vm.stop()

        #expect(vm.queued.isEmpty)
        #expect(calls == 0)
    }

    @Test func undeliveredPeersReportsOnlyPeerItems() {
        let vm = makeVM()
        vm.isRunning = true
        vm.input = "typed"
        vm.submit()
        vm.receive(peer("mail"))

        #expect(vm.undeliveredPeers.map(\.text) == ["mail"])
    }
}
