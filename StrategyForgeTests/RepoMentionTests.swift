//
//  RepoMentionTests.swift
//  StrategyForgeTests
//
//  The pure code/repo detector behind the "attach a folder" contextual reveal.
//

import Testing
@testable import Coral

struct RepoMentionTests {

    @Test func detectsCodeAndRepoTalk() {
        #expect(RepoMention.mentionsCode("Fix the bug in the auth module"))
        #expect(RepoMention.mentionsCode("review this repo for security issues"))
        #expect(RepoMention.mentionsCode("open a PR with the changes"))
        #expect(RepoMention.mentionsCode("https://github.com/acme/app failing test"))
        #expect(RepoMention.mentionsCode("refactoriza el código de este repositorio"))
    }

    @Test func ignoresNonCodeChat() {
        #expect(!RepoMention.mentionsCode("Write a poem about the sea"))
        #expect(!RepoMention.mentionsCode("Summarize this PDF for me"))
        #expect(!RepoMention.mentionsCode("What's the capital of France?"))
    }
}
