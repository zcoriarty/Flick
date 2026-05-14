//
//  PlatformPublishSettingsView.swift
//  Flick
//

import SwiftUI

struct PlatformPublishSettingsView: View {
    var platform: SocialPlatform
    var accounts: [ConnectedAccount]

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
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("\(platform.displayName) Publish Settings")
                    .font(.system(.body, weight: .semibold))
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    private var platformSection: some View {
        Section("Platform") {
            FlickSettingsValueRow(
                title: "Adapter",
                systemImage: "square.stack.3d.up",
                iconColor: platform.tint,
                value: adapterStatus
            )
            FlickSettingsValueRow(
                title: "Authorized accounts",
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
            ForEach(sortedAccounts) { account in
                accountSection(account)
            }
        }
    }

    private func accountSection(_ account: ConnectedAccount) -> some View {
        Section(account.displayName) {
            FlickSettingsValueRow(
                title: "Status",
                systemImage: "checkmark.circle",
                iconColor: account.status.tint,
                value: account.status.displayName
            )
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
            FlickSettingsValueRow(
                title: "Token",
                systemImage: "key",
                iconColor: tokenTint(for: account.tokenStatus),
                value: account.tokenStatus.displayName
            )
            FlickSettingsValueRow(
                title: "Platform ID",
                systemImage: "number",
                iconColor: .secondary,
                value: account.platformUserID.isEmpty ? "Not set" : account.platformUserID
            )
            FlickSettingsValueRow(
                title: "Scopes",
                systemImage: "checklist",
                iconColor: .purple,
                value: account.scopes.isEmpty ? "None" : account.scopes.joined(separator: ", "),
                valueLineLimit: 2
            )
            FlickSettingsRow(
                title: "Validated",
                systemImage: "calendar.badge.checkmark",
                iconColor: .teal
            ) {
                validatedAccessory(for: account)
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
                    iconColor: .indigo,
                    value: "Brand organic per job",
                    valueLineLimit: 2
                )
            } else {
                FlickSettingsValueRow(
                    title: "Availability",
                    systemImage: "clock",
                    iconColor: .secondary,
                    value: "Future adapter"
                )
            }
        }
    }

    private var adapterStatus: String {
        platform == .tiktok ? "V1 adapter" : "Future adapter"
    }

    private var publishingStatus: String {
        if accounts.contains(where: \.isPublishingEnabled) {
            return "Enabled"
        }
        return platform == .tiktok ? "Needs account" : "Not enabled"
    }

    private var publishingTint: Color {
        accounts.contains(where: \.isPublishingEnabled) ? .green : .orange
    }

    private func tokenTint(for status: OAuthTokenStatus) -> Color {
        switch status {
        case .valid:
            .green
        case .expiresSoon:
            .orange
        case .expired:
            .red
        case .notStored:
            .secondary
        }
    }

    private func validatedAccessory(for account: ConnectedAccount) -> some View {
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
