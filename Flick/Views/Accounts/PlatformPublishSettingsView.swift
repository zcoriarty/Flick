//
//  PlatformPublishSettingsView.swift
//  Flick
//

import SwiftUI

struct PlatformPublishSettingsView: View {
    var platform: SocialPlatform
    var accounts: [ConnectedAccount]
    var deleteAction: (ConnectedAccount) -> Void
    var refreshAction: (ConnectedAccount) -> Void
    var refreshingAccountID: UUID?

    private var sortedAccounts: [ConnectedAccount] {
        accounts.sortedForAccountsView
    }

    var body: some View {
        List {
            platformSection
            accountsSection
            postOptionsSection
        }
        .flickSettingsListStyle()
        .flickToolbarTitle("\(platform.displayName) Publish Settings")
    }

    private var platformSection: some View {
        Section("Platform") {
            FlickSettingsValueRow(
                title: "Accounts",
                systemImage: "person.2",
                iconColor: .blue,
                value: accounts.count.formatted()
            )
            FlickSettingsValueRow(
                title: "Publishing",
                systemImage: "paperplane",
                iconColor: publishingTint,
                value: publishingStatus
            )
        }
    }

    @ViewBuilder
    private var accountsSection: some View {
        if sortedAccounts.isEmpty {
            Section("Accounts") {
                FlickSettingsValueRow(
                    title: "No authorized \(platform.displayName) accounts",
                    systemImage: "person.crop.circle.badge.xmark",
                    iconColor: .secondary
                )
            }
        } else {
            Section("Accounts") {
                ForEach(sortedAccounts) { account in
                    NavigationLink {
                        PlatformAccountDetailView(
                            account: account,
                            deleteAction: deleteAction,
                            refreshAction: refreshAction,
                            isRefreshing: refreshingAccountID == account.id
                        )
                    } label: {
                        PlatformAccountRow(account: account)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var postOptionsSection: some View {
        Section("Post Options") {
            if platform == .tiktok {
                FlickSettingsValueRow(
                    title: "Privacy levels",
                    systemImage: "eye",
                    iconColor: .blue,
                    value: TikTokPrivacyLevel.directPostOptions.joined(separator: ", "),
                    valueLineLimit: 2
                )
                FlickSettingsValueRow(
                    title: "Comments",
                    systemImage: "bubble.left",
                    iconColor: .green,
                    value: "Allowed"
                )
                FlickSettingsValueRow(
                    title: "Duet",
                    systemImage: "person.2",
                    iconColor: .orange,
                    value: "Refresh before post"
                )
                FlickSettingsValueRow(
                    title: "Stitch",
                    systemImage: "rectangle.on.rectangle",
                    iconColor: .orange,
                    value: "Refresh before post"
                )
                FlickSettingsValueRow(
                    title: "Commercial flags",
                    systemImage: "tag",
                    iconColor: FlickStyle.appTint,
                    value: "Brand organic per job",
                    valueLineLimit: 2
                )
            } else if platform == .youtubeShorts {
                FlickSettingsValueRow(
                    title: "Upload format",
                    systemImage: "film",
                    iconColor: .red,
                    value: "Vertical MP4"
                )
                FlickSettingsValueRow(
                    title: "Privacy levels",
                    systemImage: "eye",
                    iconColor: .blue,
                    value: YouTubePrivacyStatus.allCases.map(\.displayName).joined(separator: ", "),
                    valueLineLimit: 2
                )
                FlickSettingsValueRow(
                    title: "Default category",
                    systemImage: "tag",
                    iconColor: .purple,
                    value: "People & Blogs"
                )
                FlickSettingsValueRow(
                    title: "Scheduled posting",
                    systemImage: "desktopcomputer",
                    iconColor: .teal,
                    value: "Authorize on the Mac runner"
                )
            } else {
                FlickSettingsValueRow(
                    title: "Availability",
                    systemImage: "clock",
                    iconColor: .secondary,
                    value: "Coming soon"
                )
            }
        }
    }

    private var publishingStatus: String {
        if accounts.contains(where: \.isPublishingEnabled) {
            return "Enabled"
        }
        return platform == .tiktok || platform == .youtubeShorts ? "Needs account" : "Not enabled"
    }

    private var publishingTint: Color {
        accounts.contains(where: \.isPublishingEnabled) ? .green : .orange
    }

}

private struct PlatformAccountRow: View {
    var account: ConnectedAccount

    var body: some View {
        HStack(spacing: 12) {
            PlatformIcon(platform: account.platform, size: 28, frameSize: 32)
            SettingsMessageRow(title: account.displayName, message: message)
        }
    }

    private var message: String {
        let platformID = account.platformUserID.isEmpty ? account.platform.displayName : account.platformUserID
        return "\(platformID)\n\(account.status.displayName), \(account.tokenStatus.displayName)"
    }
}

private struct PlatformAccountDetailView: View {
    @Environment(\.dismiss) private var dismiss

    var account: ConnectedAccount
    var deleteAction: (ConnectedAccount) -> Void
    var refreshAction: (ConnectedAccount) -> Void
    var isRefreshing: Bool

    var body: some View {
        List {
            accountSection
            publishingSection
            tokenSection
            scopesSection
        }
        .flickSettingsListStyle()
        .flickToolbarTitle(account.displayName)
        .safeAreaInset(edge: .bottom) {
            bottomActions
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(.regularMaterial)
        }
    }

    private var accountSection: some View {
        Section("Account") {
            PlatformSettingsValueRow(
                title: "Platform",
                platform: account.platform,
                value: account.platform.displayName
            )
            FlickSettingsValueRow(
                title: "Status",
                systemImage: "checkmark.circle",
                iconColor: account.status.tint,
                value: account.status.displayName
            )
            FlickSettingsValueRow(
                title: "Platform ID",
                systemImage: "number",
                iconColor: .secondary,
                value: account.platformUserID.isEmpty ? "Not set" : account.platformUserID,
                valueLineLimit: 2
            )
        }
    }

    private var publishingSection: some View {
        Section("Publishing") {
            FlickSettingsValueRow(
                title: "Publishing",
                systemImage: "paperplane",
                iconColor: account.isPublishingEnabled ? .green : .secondary,
                value: account.isPublishingEnabled ? "Enabled" : "Disabled"
            )
            FlickSettingsValueRow(
                title: "Default privacy",
                systemImage: "lock.shield",
                iconColor: .blue,
                value: account.defaultPrivacyLevel,
                valueLineLimit: 2
            )
        }
    }

    private var tokenSection: some View {
        Section("Token") {
            FlickSettingsValueRow(
                title: "Token",
                systemImage: "key",
                iconColor: platformAccountTokenTint(for: account.tokenStatus),
                value: account.tokenStatus.displayName
            )
            FlickSettingsRow(
                title: "Validated",
                systemImage: "calendar.badge.checkmark",
                iconColor: .teal
            ) {
                validatedAccessory
            }
        }
    }

    private var scopesSection: some View {
        Section("Scopes") {
            FlickSettingsValueRow(
                title: "Scopes",
                systemImage: "checklist",
                iconColor: .purple,
                value: account.scopes.isEmpty ? "None" : account.scopes.joined(separator: ", "),
                valueLineLimit: 4
            )
        }
    }

    private var bottomActions: some View {
        VStack(spacing: 10) {
            if canRefreshAuthorization {
                refreshButton
            }

            removeButton
        }
    }

    private var refreshButton: some View {
        Button {
            refreshAction(account)
        } label: {
            HStack(spacing: 8) {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: authActionSystemImage)
                }

                Text(authActionTitle)
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.blue)
        .background(.blue.opacity(0.12), in: .capsule)
        .glassEffect(.regular.interactive(), in: .capsule)
        .disabled(isRefreshing)
        .accessibilityIdentifier("refresh-platform-account-auth-button")
    }

    private var authActionTitle: String {
        if account.platform == .youtubeShorts {
            return isRefreshing ? "Reconnecting YouTube" : "Reconnect YouTube"
        }
        return isRefreshing ? "Refreshing Auth" : "Refresh Auth"
    }

    private var authActionSystemImage: String {
        account.platform == .youtubeShorts ? "arrow.clockwise.circle" : "arrow.clockwise"
    }

    private var removeButton: some View {
        Button(role: .destructive) {
            deleteAction(account)
            dismiss()
        } label: {
            Label("Remove Account", systemImage: "trash")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
        .background(.red.opacity(0.12), in: .capsule)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityIdentifier("remove-platform-account-button")
    }

    private var canRefreshAuthorization: Bool {
        switch account.authorizationSource {
        case .loginKit, .nativeOAuth:
            true
        case .manualImport, .unavailable:
            false
        }
    }

    private var validatedAccessory: some View {
        Group {
            if let lastValidatedAt = account.lastValidatedAt {
                Text(lastValidatedAt, style: .relative)
            } else {
                Text("Never")
            }
        }
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.trailing)
    }
}

private func platformAccountTokenTint(for status: OAuthTokenStatus) -> Color {
    switch status {
    case .valid:
        .green
    case .expiresSoon:
        .orange
    case .refreshFailed:
        .red
    case .expired:
        .red
    case .notStored:
        .secondary
    }
}
