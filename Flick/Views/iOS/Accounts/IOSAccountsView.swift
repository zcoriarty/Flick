//
//  IOSAccountsView.swift
//  Flick
//

import SwiftUI

#if !os(macOS)
struct IOSAccountsView: View {
    @Environment(FlickAppModel.self) private var appModel
    @State private var selectedPlatform: SocialPlatform?

    private var authorizedAccounts: [ConnectedAccount] {
        appModel.overview.accounts.filter { $0.authorizationSource == .loginKit || $0.authorizationSource == .nativeOAuth }
    }

    var body: some View {
        List {
            PlatformAccountRowsSection(authorizedAccounts: authorizedAccounts) { platform in
                selectedPlatform = platform
            }
            connectionStatus
        }
        .flickSettingsListStyle()
        .sheet(item: $selectedPlatform) { platform in
            NavigationStack {
                PlatformPublishSettingsView(
                    platform: platform,
                    accounts: accounts(for: platform),
                    deleteAction: deleteAccount
                )
            }
        }
        .flickToolbarTitle("Accounts")
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
    }

    @ViewBuilder
    private var connectionStatus: some View {
        if !appModel.canManageAccounts {
            AccountConnectionStatusView(
                title: appModel.accountManagementUnavailableTitle,
                message: appModel.accountManagementUnavailableMessage,
                systemImage: "iphone",
                tint: .blue,
                showsProgress: false
            )
        } else if let platform = appModel.connectingPlatform {
            AccountConnectionStatusView(
                title: "Connecting \(platform.displayName)",
                message: "Complete the authorization window to add this account.",
                systemImage: "person.crop.circle",
                tint: platform.tint,
                showsProgress: true
            )
        } else if let message = appModel.accountConnectionMessage {
            AccountConnectionStatusView(
                title: "Account connected",
                message: message,
                systemImage: "checkmark.circle",
                tint: .green,
                showsProgress: false
            )
        } else if let message = appModel.lastErrorMessage {
            AccountConnectionStatusView(
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

private struct PlatformAccountRowsSection: View {
    var authorizedAccounts: [ConnectedAccount]
    var onSelectPlatform: (SocialPlatform) -> Void

    var body: some View {
        Section("Platforms") {
            ForEach(SocialPlatform.allCases) { platform in
                Button {
                    onSelectPlatform(platform)
                } label: {
                    PlatformAccountMessageRow(
                        platform: platform,
                        accounts: accounts(for: platform)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func accounts(for platform: SocialPlatform) -> [ConnectedAccount] {
        authorizedAccounts.filter { $0.platform == platform }
    }
}

private struct PlatformAccountMessageRow: View {
    var platform: SocialPlatform
    var accounts: [ConnectedAccount]

    var body: some View {
        HStack(spacing: 12) {
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
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var publishingEnabledCount: Int {
        accounts.filter(\.isPublishingEnabled).count
    }
}

private struct AccountConnectionStatusView: View {
    var title: String
    var message: String
    var systemImage: String
    var tint: Color
    var showsProgress: Bool

    var body: some View {
        Section {
            HStack(alignment: .center, spacing: 12) {
                statusIcon

                SettingsMessageRow(title: title, message: message)
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if showsProgress {
            ProgressView()
                .tint(tint)
                .frame(width: 24, height: 24)
        } else {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
        }
    }
}
#endif
