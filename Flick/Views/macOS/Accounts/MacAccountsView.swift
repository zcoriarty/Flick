//
//  MacAccountsView.swift
//  Flick
//

#if os(macOS) || targetEnvironment(macCatalyst)
import SwiftUI

struct MacAccountsView: View {
    @Environment(FlickAppModel.self) private var appModel
    @State private var selectedPlatform: SocialPlatform?

    private var authorizedAccounts: [ConnectedAccount] {
        appModel.overview.accounts.filter { $0.authorizationSource == .loginKit || $0.authorizationSource == .nativeOAuth }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            MacWorkspaceHeader(
                title: "Accounts",
                subtitle: "Review platform authorization, publishing readiness, tokens, and privacy defaults.",
                metrics: [
                    MacWorkspaceMetric(title: "Authorized", value: authorizedAccounts.count.formatted()),
                    MacWorkspaceMetric(title: "Publishing", value: authorizedAccounts.filter(\.isPublishingEnabled).count.formatted()),
                    MacWorkspaceMetric(title: "Platforms", value: SocialPlatform.allCases.count.formatted())
                ]
            )

            connectionStatus

            MacAccountPlatformMatrix(
                accounts: authorizedAccounts,
                selectAction: { selectedPlatform = $0 }
            )
        }
        .macWorkspacePage()
        .navigationTitle("Accounts")
        .toolbar {
            if appModel.canManageAccounts {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(SocialPlatform.allCases) { platform in
                            Button {
                                connect(platform)
                            } label: {
                                PlatformMenuLabel(platform: platform)
                            }
                            .disabled(!appModel.canConnectAccount(platform: platform))
                        }
                    } label: {
                        Label("Add Account", systemImage: "plus")
                    }
                    .disabled(appModel.connectingPlatform != nil)
                }
            }
        }
        .sheet(item: $selectedPlatform) { platform in
            NavigationStack {
                PlatformPublishSettingsView(
                    platform: platform,
                    accounts: accounts(for: platform),
                    deleteAction: deleteAccount
                )
            }
            .frame(minWidth: 520, minHeight: 620)
        }
    }

    @ViewBuilder
    private var connectionStatus: some View {
        if !appModel.canManageAccounts {
            MacAccountStatusPanel(
                title: appModel.accountManagementUnavailableTitle,
                message: appModel.accountManagementUnavailableMessage,
                systemImage: "iphone",
                tint: .blue,
                showsProgress: false
            )
        } else if let platform = appModel.connectingPlatform {
            MacAccountStatusPanel(
                title: "Connecting \(platform.displayName)",
                message: "Complete the authorization window to add this account.",
                systemImage: "person.crop.circle",
                tint: platform.tint,
                showsProgress: true
            )
        } else if let message = appModel.accountConnectionMessage {
            MacAccountStatusPanel(
                title: "Account connected",
                message: message,
                systemImage: "checkmark.circle",
                tint: .green,
                showsProgress: false
            )
        } else if let message = appModel.lastErrorMessage {
            MacAccountStatusPanel(
                title: "Account connection failed",
                message: message,
                systemImage: "exclamationmark.triangle",
                tint: .orange,
                showsProgress: false
            )
        }
    }

    private func accounts(for platform: SocialPlatform) -> [ConnectedAccount] {
        authorizedAccounts.filter { $0.platform == platform }
    }

    private func connect(_ platform: SocialPlatform) {
        guard appModel.canConnectAccount(platform: platform) else { return }
        Task {
            await appModel.connectAccount(platform: platform)
        }
    }

    private func deleteAccount(_ account: ConnectedAccount) {
        Task {
            do {
                try await appModel.deleteConnectedAccount(id: account.id)
            } catch {
                appModel.lastErrorMessage = error.localizedDescription
            }
        }
    }
}

private struct MacAccountPlatformMatrix: View {
    var accounts: [ConnectedAccount]
    var selectAction: (SocialPlatform) -> Void

    var body: some View {
        MacWorkspaceSection(title: "Platforms", systemImage: "square.grid.2x2") {
            VStack(spacing: 12) {
                ForEach(SocialPlatform.allCases) { platform in
                    Button {
                        selectAction(platform)
                    } label: {
                        MacAccountPlatformRow(
                            platform: platform,
                            accounts: accounts(for: platform)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func accounts(for platform: SocialPlatform) -> [ConnectedAccount] {
        accounts.filter { $0.platform == platform }
    }
}

private struct MacAccountPlatformRow: View {
    var platform: SocialPlatform
    var accounts: [ConnectedAccount]

    private var publishingEnabledCount: Int {
        accounts.filter(\.isPublishingEnabled).count
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PlatformIcon(platform: platform, size: 28, frameSize: 32)

            SettingsMessageRow(
                title: platform.displayName,
                message: "\(accounts.count.formatted()) accounts, \(publishingEnabledCount.formatted()) publishing enabled"
            )

            Spacer(minLength: 12)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
    }
}

private struct MacAccountStatusPanel: View {
    var title: String
    var message: String
    var systemImage: String
    var tint: Color
    var showsProgress: Bool

    var body: some View {
        MacWorkspacePanel {
            HStack(alignment: .top, spacing: 12) {
                if showsProgress {
                    ProgressView()
                        .tint(tint)
                        .frame(width: 26, height: 26)
                } else {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .foregroundStyle(tint)
                        .frame(width: 26, height: 26)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
#endif
