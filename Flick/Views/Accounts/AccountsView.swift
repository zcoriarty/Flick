//
//  AccountsView.swift
//  Flick
//

import SwiftUI

struct AccountsView: View {
    @Environment(FlickAppModel.self) private var appModel

    private var authorizedAccounts: [ConnectedAccount] {
        appModel.overview.accounts.filter { $0.authorizationSource == .loginKit }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: FlickStyle.sectionSpacing) {
                PlatformAccountTilesSection(authorizedAccounts: authorizedAccounts)
                connectionStatus
                AuthorizedAccountsSection(accounts: authorizedAccounts)
                PlatformAdaptersSection()
            }
            .flickScrollablePage()
            .navigationDestination(for: SocialPlatform.self) { platform in
                PlatformPublishSettingsView(platform: platform, accounts: accounts(for: platform))
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Accounts")
            }
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
                message: "Complete the Login Kit authorization window to add this account.",
                systemImage: platform.systemImage,
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
        Task {
            await appModel.connectAccount(platform: platform)
        }
    }
}

private struct PlatformAccountTilesSection: View {
    var authorizedAccounts: [ConnectedAccount]

    var body: some View {
        ResponsiveGrid(minimum: 180) {
            ForEach(SocialPlatform.allCases) { platform in
                NavigationLink(value: platform) {
                    PlatformAccountTile(
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

private struct PlatformAccountTile: View {
    var platform: SocialPlatform
    var accounts: [ConnectedAccount]

    private var publishingEnabledCount: Int {
        accounts.filter(\.isPublishingEnabled).count
    }

    var body: some View {
        FlickGlassCard(interactive: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: platform.systemImage)
                        .font(.title2)
                        .foregroundStyle(platform.tint)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                Text(platform.displayName)
                    .font(.headline)

                Text("\(accounts.count) accounts")
                    .font(.title3.weight(.bold))

                Text("\(publishingEnabledCount) publishing enabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AuthorizedAccountsSection: View {
    var accounts: [ConnectedAccount]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Authorized accounts")
            if accounts.isEmpty {
                NoAuthorizedAccountsView()
            } else {
                ResponsiveGrid(minimum: 320) {
                    ForEach(accounts.sortedForAccountsView) { account in
                        AccountCard(account: account)
                    }
                }
            }
        }
    }
}

private struct PlatformAdaptersSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Platform adapters")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(SocialPlatform.allCases) { platform in
                        PlatformAdapterChip(platform: platform)
                    }
                }
            }
        }
    }
}

private struct PlatformAdapterChip: View {
    var platform: SocialPlatform

    private var isEnabled: Bool {
        platform == .tiktok
    }

    var body: some View {
        FlickGlassCard {
            HStack(spacing: 10) {
                Image(systemName: platform.systemImage)
                    .foregroundStyle(platform.tint)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(platform.displayName)
                        .font(.callout.weight(.semibold))
                    Text(isEnabled ? "V1 adapter" : "Future")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
        .frame(width: 150)
        .accessibilityElement(children: .combine)
    }
}

private struct AccountCard: View {
    var account: ConnectedAccount

    var body: some View {
        FlickGlassCard(interactive: account.platform == .tiktok) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Image(systemName: account.platform.systemImage)
                                .foregroundStyle(account.platform.tint)
                            Text(account.displayName)
                                .font(.headline)
                        }
                        Text(account.platform.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(title: account.status.displayName, tint: account.status.tint, systemImage: "circle.fill")
                }

                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    GridRow {
                        Text("Source")
                            .foregroundStyle(.secondary)
                        Text("Login Kit")
                    }
                    GridRow {
                        Text("Platform ID")
                            .foregroundStyle(.secondary)
                        Text(account.platformUserID.isEmpty ? "Not set" : account.platformUserID)
                            .lineLimit(1)
                    }
                    GridRow {
                        Text("Token")
                            .foregroundStyle(.secondary)
                        Text(account.tokenStatus.displayName)
                    }
                    GridRow {
                        Text("Privacy")
                            .foregroundStyle(.secondary)
                        Text(account.defaultPrivacyLevel)
                    }
                    GridRow {
                        Text("Validated")
                            .foregroundStyle(.secondary)
                        if let lastValidatedAt = account.lastValidatedAt {
                            Text(lastValidatedAt, style: .relative)
                        } else {
                            Text("Never")
                        }
                    }
                }
                .font(.caption)

                Text(account.scopes.isEmpty ? "Scopes are not connected yet." : account.scopes.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }
}

private struct NoAuthorizedAccountsView: View {
    var body: some View {
        FlickGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("No authorized accounts yet")
                            .font(.headline)
                        Text("Accounts are created only after a platform Login Kit flow returns an authorization code, the app exchanges it for tokens, and `/v2/user/info/` returns the real account identity.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    StatusBadge(title: "TikTok Login Kit", tint: .pink, systemImage: "music.note")
                    StatusBadge(title: "Real account metadata required", tint: .blue, systemImage: "checkmark.shield")
                }
            }
        }
    }
}

private struct AccountConnectionStatusView: View {
    var title: String
    var message: String
    var systemImage: String
    var tint: Color
    var showsProgress: Bool

    var body: some View {
        FlickGlassCard {
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
