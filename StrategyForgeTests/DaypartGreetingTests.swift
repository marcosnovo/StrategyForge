//
//  DaypartGreetingTests.swift
//  StrategyForgeTests
//
//  Unit tests for the casual, time-of-day-aware greeting shown on a fresh, empty
//  chat: daypart bucketing, deterministic seeding, name interpolation, and that the
//  English and Spanish pools diverge.
//

import Testing
import Foundation
@testable import Coral

struct DaypartGreetingTests {

    // seed 0 → unsigned modulo picks index 0, so the first pool entry is deterministic.

    @Test func morningEnglishWithNameHitsFirstVariant() {
        let line = DaypartGreeting.line(langCode: "en", hour: 9, seed: 0, name: "Marcos")
        #expect(line == "Morning, Marcos! ☀️ What are we building?")
    }

    @Test func morningSpanishAnonHitsFirstVariant() {
        let line = DaypartGreeting.line(langCode: "es", hour: 9, seed: 0, name: nil)
        #expect(line == "¡Buenos días! ☀️ ¿Qué construimos?")
    }

    @Test func daypartBucketsPickTheRightPool() {
        // A fixed seed/name isolates the daypart as the only variable.
        let morning = DaypartGreeting.line(langCode: "en", hour: 5, seed: 0, name: nil)
        let afternoon = DaypartGreeting.line(langCode: "en", hour: 12, seed: 0, name: nil)
        let evening = DaypartGreeting.line(langCode: "en", hour: 19, seed: 0, name: nil)
        let lateNight = DaypartGreeting.line(langCode: "en", hour: 3, seed: 0, name: nil)
        #expect(morning == "Morning! ☀️ What are we building?")
        #expect(afternoon == "Good afternoon! What's on your plate?")
        #expect(evening == "Evening! 🌙 What's the mission?")
        #expect(lateNight == "Up late? 🌙 Let's make it count.")
        // All four dayparts are distinct lines.
        #expect(Set([morning, afternoon, evening, lateNight]).count == 4)
    }

    @Test func sameSeedIsDeterministicDifferentSeedsVary() {
        let a = DaypartGreeting.line(langCode: "en", hour: 14, seed: 42, name: "Sam")
        let b = DaypartGreeting.line(langCode: "en", hour: 14, seed: 42, name: "Sam")
        #expect(a == b)   // stable per chat — never reshuffles on redraw
        // Across the four afternoon variants, different seeds reach different lines.
        let lines = Set((0..<4).map {
            DaypartGreeting.line(langCode: "en", hour: 14, seed: $0, name: "Sam")
        })
        #expect(lines.count == 4)
    }

    @Test func anonNeverLeaksAFormatPlaceholder() {
        for hour in 0..<24 {
            for lang in ["en", "es"] {
                for seed in 0..<8 {
                    let line = DaypartGreeting.line(langCode: lang, hour: hour, seed: seed, name: nil)
                    #expect(!line.isEmpty)
                    #expect(!line.contains("%@"))
                }
            }
        }
    }

    @Test func namedVariantWeavesInTheName() {
        for hour in 0..<24 {
            let line = DaypartGreeting.line(langCode: "en", hour: hour, seed: 1, name: "Robin")
            #expect(line.contains("Robin"))
            #expect(!line.contains("%@"))
        }
    }

    @Test func blankNameFallsBackToAnonVariant() {
        let anon = DaypartGreeting.line(langCode: "en", hour: 9, seed: 0, name: nil)
        let blank = DaypartGreeting.line(langCode: "en", hour: 9, seed: 0, name: "   ")
        #expect(anon == blank)
    }

    @Test func englishAndSpanishDiverge() {
        let en = DaypartGreeting.line(langCode: "en", hour: 9, seed: 2, name: "Alex")
        let es = DaypartGreeting.line(langCode: "es", hour: 9, seed: 2, name: "Alex")
        #expect(en != es)
    }
}
