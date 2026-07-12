//
//  CodeLauncherView.swift
//  StrategyForge
//
//  The repo-first "door" for the Code section: connect a repo (clone a GitHub URL
//  or pick a folder), or resume the last one, and drop straight into a single-agent
//  Claude Code session with the diffs/terminal/git workspace. No team design — as
//  simple as Claude Code: connect a repo and start talking.
//

import SwiftUI

struct CodeLauncherView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("code.lastRepo") private var lastRepo = ""
    @State private var cloneURL = ""
    @State private var cloning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                hero
                if !lastRepo.isEmpty, FileManager.default.fileExists(atPath: lastRepo) { resumeCard }
                // Open a LOCAL folder first — that's the Claude-Code habit (work on a
                // checkout you already have, nothing is cloned). Clone is the shortcut
                // for when you don't have it locally yet.
                pickCard
                cloneCard
                credentialsNote
                if !CodeGit.isAvailable { gitMissingNote }
            }
            .frame(maxWidth: 640)
            .padding(Space.xl)
            .frame(maxWidth: .infinity)   // center the column
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBg)
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .top, spacing: Space.m) {
            IconBadge(systemName: "chevron.left.forwardslash.chevron.right")
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(model.t("code.launcher.title")).font(.sfDisplay)
                Text(model.t("code.launcher.subtitle"))
                    .font(.sfCallout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Clone from GitHub

    private var cloneCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("arrow.down.circle", model.t("code.clone.title"),
                          subtitle: model.t("code.clone.subtitle"))
            HStack(spacing: Space.s) {
                TextField("https://github.com/owner/repo", text: $cloneURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.sfCode)
                    .disabled(cloning)
                    .onSubmit(clone)
                Button(action: clone) {
                    if cloning {
                        HStack(spacing: Space.s) { WorkingLogo(size: 15, color: Theme.onAccent); Text(model.t("code.cloning")) }
                    } else {
                        Label(model.t("code.clone.action"), systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(.moon)
                .disabled(cloning || cloneURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .card()
    }

    private func clone() {
        let url = cloneURL
        guard !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !cloning else { return }
        cloning = true
        Task {
            await model.cloneAndOpenCodeChat(url: url)
            cloning = false
        }
    }

    // MARK: Pick a folder

    private var pickCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("folder", model.t("code.pick.title"),
                          subtitle: model.t("code.pick.subtitle")) {
                Button(model.t("code.pick.action")) { model.pickAndOpenCodeChat() }
                    .buttonStyle(.bordered)
            }
        }
        .card()
    }

    // MARK: Resume last

    private var resumeCard: some View {
        Button {
            model.openCodeChat(repoURL: URL(fileURLWithPath: lastRepo))
        } label: {
            HStack(spacing: Space.m) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 18)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.t("code.resume.title")).font(.sfCardTitle)
                    Text((lastRepo as NSString).lastPathComponent).font(.sfCaption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .card()
    }

    /// Clarify that there's no in-app GitHub login — it uses the user's own creds.
    private var credentialsNote: some View {
        Label(model.t("code.credsNote"), systemImage: "info.circle")
            .font(.sfCaption2).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var gitMissingNote: some View {
        Label(model.t("code.gitMissing"), systemImage: "exclamationmark.triangle.fill")
            .font(.sfCaption2).foregroundStyle(Theme.warning)
            .fixedSize(horizontal: false, vertical: true)
    }
}
