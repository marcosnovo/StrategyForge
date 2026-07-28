//
//  GraphifyServiceTests.swift
//  StrategyForgeTests
//
//  Unit tests for the GitHub URL parsing that powers "map a repo from GitHub" — it must
//  accept full https/ssh URLs, `.git` suffixes, and `owner/repo` shorthand, and reject junk.
//

import Testing
@testable import Coral

@MainActor
struct GraphifyServiceTests {

    @Test func parsesGitHubURLForms() {
        #expect(CodeMapStore.parseOwnerRepo("https://github.com/marcosnovo/StrategyForge")?.0 == "marcosnovo")
        #expect(CodeMapStore.parseOwnerRepo("https://github.com/marcosnovo/StrategyForge")?.1 == "StrategyForge")
        #expect(CodeMapStore.parseOwnerRepo("https://github.com/acme/widget.git")?.1 == "widget")
        #expect(CodeMapStore.parseOwnerRepo("git@github.com:acme/widget.git")?.0 == "acme")
        #expect(CodeMapStore.parseOwnerRepo("acme/widget")?.1 == "widget")
        #expect(CodeMapStore.parseOwnerRepo("  acme/widget  ")?.0 == "acme")
    }

    @Test func rejectsNonRepoInput() {
        #expect(CodeMapStore.parseOwnerRepo("") == nil)
        #expect(CodeMapStore.parseOwnerRepo("justaword") == nil)
        #expect(CodeMapStore.parseOwnerRepo("https://github.com/onlyowner") == nil)
    }
}
