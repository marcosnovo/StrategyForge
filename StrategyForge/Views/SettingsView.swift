//
//  SettingsView.swift
//  StrategyForge
//
//  App settings: language, the default repos folder, and the path to the
//  `claude` binary used in generated launch commands.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AuthModel.self) private var auth
    @AppStorage(Analytics.enabledKey) private var telemetryEnabled = false

    var body: some View {
        @Bindable var model = model
        Form {
            accountSection

            Section(model.t("settings.languageSection")) {
                Picker(model.t("settings.language"), selection: Binding(
                    get: { model.settings.language },
                    set: { model.settings.language = $0; model.save() }
                )) {
                    Text(model.t("settings.language.system")).tag(AppLanguage.system)
                    Text("English").tag(AppLanguage.en)
                    Text("Español").tag(AppLanguage.es)
                }
            }

            Section(model.t("settings.repos")) {
                LabeledContent(model.t("settings.defaultFolder")) {
                    HStack {
                        Text(model.settings.defaultReposPath ?? model.t("settings.notSet"))
                            .foregroundStyle(model.settings.defaultReposPath == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button(model.t("common.choose")) { model.pickDefaultReposFolder() }
                    }
                }
                Text(model.t("settings.defaultFolder.caption"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(model.t("settings.autonomy.section")) {
                Picker(model.t("settings.autonomy"), selection: Binding(
                    get: { model.settings.chatAutonomy },
                    set: { model.settings.chatAutonomy = $0; model.save() }
                )) {
                    ForEach(ChatAutonomy.allCases) { level in
                        Text(model.t(level.labelKey)).tag(level)
                    }
                }
                Text(model.t("settings.autonomy.caption"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            ConnectedServicesSection()

            Section(model.t("settings.privacy")) {
                Toggle(isOn: Binding(
                    get: { telemetryEnabled },
                    set: { telemetryEnabled = $0; if !$0 { Analytics.clear() } }
                )) {
                    Text(model.t("settings.telemetry"))
                }
                Text(model.t("settings.telemetry.caption"))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 620)
        .onDisappear { model.save() }
    }

    @ViewBuilder
    private var accountSection: some View {
        Section(model.t("account.title")) {
            Text(model.t("account.subtitle"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let account = auth.account {
                LabeledContent(model.t("account.signedInAs", account.label)) {
                    Button(model.t("account.signOut")) { auth.signOut() }
                }
                if account.supportsCloudSync {
                    HStack {
                        Button {
                            Task { await auth.sync(model) }
                        } label: {
                            Label(model.t("account.syncNow"), systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(auth.isBusy)
                        if auth.isBusy { ProgressView().controlSize(.small) }
                        if let msg = auth.lastSyncMessage {
                            Text(msg).font(.caption).foregroundStyle(Theme.success)
                        }
                    }
                    Text(model.t("account.syncScope"))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(model.t("account.googleNote"))
                        .font(.caption).foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Button {
                    Task { await auth.signIn(.apple) }
                } label: {
                    Label(model.t("account.signInApple"), systemImage: "apple.logo")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(auth.isBusy)

                Button {
                    Task { await auth.signIn(.google) }
                } label: {
                    Label(model.t("account.signInGoogle"), systemImage: "g.circle")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(auth.isBusy || !Constants.Auth.isGoogleConfigured)

                if !Constants.Auth.isGoogleConfigured {
                    Text(model.t("account.googleUnconfigured"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if let err = auth.lastError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
