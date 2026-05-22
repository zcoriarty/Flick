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
        appModel.overview.accounts.filter { $0.authorizationSource == .loginKit }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            MacWorkspaceHeader(
                title: "Accounts",
                subtitle: "Review platform authorization, publishing readiness, tokens, privacy defaults, and adapter availability.",
                metrics: [
                    MacWorkspaceMetric(title: "Authorized", value: authorizedAccounts.count.formatted()),
                    MacWorkspaceMetric(title: "Publishing", value: authorizedAccounts.filter(\.isPublishingEnabled).count.formatted()),
                    MacWorkspaceMetric(title: "Platforms", value: SocialPlatform.allCases.count.formatted())
                ]
            )

            connectionStatus

            HStack(alignment: .top, spacing: 18) {
                MacAccountPlatformMatrix(
                    accounts: authorizedAccounts,
                    selectAction: { selectedPlatform = $0 }
                )
                .frame(minWidth: 360, maxWidth: 460)

                MacAuthorizedAccountsPanel(
                    accounts: authorizedAccounts,
                    deleteAction: deleteAccount
                )
            }

            MacPlatformAdaptersPanel()
        }
        .macWorkspacePage()
        .navigationTitle("Accounts")
        .toolbar {
            if appModel.canManageAccounts {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(SocialPlatform.allCases) { platform in
                            Button(platform.displayName, systemImage: platform.systemImage) {
                                connect(platform)
                            }
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
                PlatformPublishSettingsView(platform: platform, accounts: accounts(for: platform))
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
                message: "Complete the Login Kit authorization window to add this account.",
                systemImage: platform.systemImage,
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
        MacWorkspacePanel {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: platform.systemImage)
                    .font(.title2)
                    .foregroundStyle(platform.tint)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(platform.displayName)
                        .font(.headline)
                    Text("\(accounts.count.formatted()) authorized, \(publishingEnabledCount.formatted()) publishing enabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                StatusBadge(
                    title: platform == .tiktok ? "V1" : "Future",
                    tint: platform == .tiktok ? .green : .secondary,
                    systemImage: platform == .tiktok ? "checkmark.circle" : "clock"
                )
            }
        }
        .contentShape(.rect(cornerRadius: 20))
    }
}

private struct MacAuthorizedAccountsPanel: View {
    var accounts: [ConnectedAccount]
    var deleteAction: (ConnectedAccount) -> Void

    var body: some View {
        MacWorkspaceSection(
            title: "Authorized Accounts",
            subtitle: accounts.isEmpty ? nil : "\(accounts.count.formatted()) login-kit accounts",
            systemImage: "person.2"
        ) {
            if accounts.isEmpty {
                MacInlineEmptyState(
                    title: "No authorized accounts",
                    message: "Connected platform identities appear here after Login Kit completes and account metadata syncs.",
                    systemImage: "person.crop.circle.badge.plus"
                )
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 330, maximum: 520), spacing: 14, alignment: .top)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(accounts.sortedForAccountsView) { account in
                        MacAccountCard(account: account, deleteAction: deleteAction)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct MacAccountCard: View {
    var account: ConnectedAccount
    var deleteAction: (ConnectedAccount) -> Void

    var body: some View {
        MacWorkspacePanel(minHeight: 224) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: account.platform.systemImage)
                        .font(.title3)
                        .foregroundStyle(account.platform.tint)
                        .frame(width: 26, height: 26)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.displayName)
                            .font(.headline)
                            .lineLimit(1)
                        Text(account.platform.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 8)

                    StatusBadge(title: account.status.displayName, tint: account.status.tint, systemImage: "circle.fill")
                }

                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    MacDetailRow(title: "Platform ID", value: account.platformUserID.isEmpty ? "Not set" : account.platformUserID)
                    MacDetailRow(title: "Token", value: account.tokenStatus.displayName)
                    MacDetailRow(title: "Privacy", value: account.defaultPrivacyLevel, valueLineLimit: 2)
                    MacDetailRow(title: "Validated", value: account.lastValidatedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                    MacDetailRow(title: "Scopes", value: account.scopes.isEmpty ? "None" : account.scopes.joined(separator: ", "), valueLineLimit: 2)
                }
                .font(.caption)

                Spacer(minLength: 0)

                HStack {
                    StatusBadge(
                        title: account.isPublishingEnabled ? "Publishing enabled" : "Publishing off",
                        tint: account.isPublishingEnabled ? .green : .secondary,
                        systemImage: account.isPublishingEnabled ? "paperplane.fill" : "paperplane"
                    )

                    Spacer(minLength: 10)

                    Button("Remove", systemImage: "trash", role: .destructive) {
                        deleteAction(account)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}

private struct MacPlatformAdaptersPanel: View {
    var body: some View {
        MacWorkspaceSection(title: "Platform Adapters", systemImage: "square.stack.3d.up") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 12, alignment: .top)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(SocialPlatform.allCases) { platform in
                    MacPlatformAdapterTile(platform: platform)
                }
            }
        }
    }
}

private struct MacPlatformAdapterTile: View {
    var platform: SocialPlatform

    private var isEnabled: Bool {
        platform == .tiktok
    }

    var body: some View {
        MacWorkspacePanel {
            HStack(spacing: 12) {
                Image(systemName: platform.systemImage)
                    .font(.title3)
                    .foregroundStyle(platform.tint)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 3) {
                    Text(platform.displayName)
                        .font(.callout.weight(.semibold))
                    Text(isEnabled ? "V1 adapter" : "Future adapter")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
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
