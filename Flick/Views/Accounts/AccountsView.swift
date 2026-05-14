//
//  AccountsView.swift
//  Flick
//

import SwiftUI

struct AccountsView: View {
    @Environment(FlickAppModel.self) private var appModel

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: FlickStyle.sectionSpacing) {
                accountScale
                connectionStatus
                connectedAccounts
                futurePlatforms
                publishingSettings
            }
            .flickScrollablePage()
            .navigationTitle("Accounts")
            .toolbar {
                if appModel.canManageAccounts {
                    ToolbarItem(placement: .primaryAction) {
                        Menu("Add account", systemImage: "plus") {
                            ForEach(SocialPlatform.allCases) { platform in
                                Button(platform.displayName, systemImage: platform.systemImage) {
                                    Task {
                                        await appModel.connectAccount(platform: platform)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(appModel.connectingPlatform != nil)
                    }
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

    private var accountScale: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Accounts by platform", subtitle: "Account records are per handle, so each platform can hold many publishing identities", systemImage: "person.3")
            ResponsiveGrid(minimum: 180) {
                ForEach(SocialPlatform.allCases) { platform in
                    let accounts = accounts(for: platform)
                    FlickGlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: platform.systemImage)
                                .font(.title2)
                                .foregroundStyle(platform.tint)
                            Text(platform.displayName)
                                .font(.headline)
                            Text("\(accounts.count) accounts")
                                .font(.title3.weight(.bold))
                            Text("\(accounts.filter(\.isPublishingEnabled).count) publishing enabled")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var connectedAccounts: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Authorized accounts", subtitle: "Only real accounts returned by platform Login Kit authorization appear here", systemImage: "person.2.badge.gearshape")
            if authorizedAccounts.isEmpty {
                NoAuthorizedAccountsView()
            } else {
                ResponsiveGrid(minimum: 320) {
                    ForEach(authorizedAccounts.sortedForAccountsView) { account in
                        AccountCard(account: account)
                    }
                }
            }
        }
    }

    private var futurePlatforms: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Platform adapters", subtitle: "TikTok is V1; Instagram, Threads, and X are isolated future adapters", systemImage: "point.3.connected.trianglepath.dotted")
            ResponsiveGrid(minimum: 220) {
                ForEach(SocialPlatform.allCases) { platform in
                    let enabled = platform == .tiktok
                    FlickGlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: platform.systemImage)
                                    .foregroundStyle(platform.tint)
                                Text(platform.displayName)
                                    .font(.headline)
                            }
                            StatusBadge(title: enabled ? "V1 adapter" : "Future stub", tint: enabled ? .green : .secondary, systemImage: "circle.fill")
                        }
                    }
                }
            }
        }
    }

    private var publishingSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "TikTok publish settings", subtitle: "Creator info should drive final privacy and interaction options", systemImage: "slider.horizontal.3")
            FlickGlassCard {
                ResponsiveGrid(minimum: 210) {
                    SettingSummary(title: "Default privacy", value: defaultTikTokAccount?.defaultPrivacyLevel ?? "Not connected", systemImage: "lock")
                    SettingSummary(title: "Comments", value: "Allowed unless creator info says otherwise", systemImage: "text.bubble")
                    SettingSummary(title: "Duet", value: "Refresh before direct post", systemImage: "person.2.wave.2")
                    SettingSummary(title: "Commercial flags", value: "Brand organic per job", systemImage: "checkmark.shield")
                }
            }
        }
    }

    private var defaultTikTokAccount: ConnectedAccount? {
        authorizedAccounts.first { $0.platform == .tiktok }
    }

    private var authorizedAccounts: [ConnectedAccount] {
        appModel.overview.accounts.filter { $0.authorizationSource == .loginKit }
    }

    private func accounts(for platform: SocialPlatform) -> [ConnectedAccount] {
        authorizedAccounts.filter { $0.platform == platform }
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

private extension Array where Element == ConnectedAccount {
    var sortedForAccountsView: [ConnectedAccount] {
        sorted {
            if $0.platform.rawValue == $1.platform.rawValue {
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            return $0.platform.displayName < $1.platform.displayName
        }
    }
}

private extension SocialPlatform {
    var tint: Color {
        switch self {
        case .tiktok: .pink
        case .instagram: .purple
        case .threads: .indigo
        case .x: .primary
        }
    }
}

private struct SettingSummary: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.orange)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .lineLimit(3)
            }
        }
    }
}

private extension OAuthTokenStatus {
    var displayName: String {
        switch self {
        case .valid: "Valid"
        case .expiresSoon: "Expires soon"
        case .expired: "Expired"
        case .notStored: "Not stored"
        }
    }
}
