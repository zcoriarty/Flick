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
            Section("Platform") {
                LabeledContent("Adapter", value: adapterStatus)
                LabeledContent("Authorized accounts", value: accounts.count.formatted())
                LabeledContent("Publishing", value: publishingStatus)
            }

            if sortedAccounts.isEmpty {
                Section("Accounts") {
                    Text("No authorized \(platform.displayName) accounts")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(sortedAccounts) { account in
                    Section(account.displayName) {
                        LabeledContent("Status", value: account.status.displayName)
                        LabeledContent("Publishing", value: account.isPublishingEnabled ? "Enabled" : "Disabled")
                        LabeledContent("Default privacy", value: account.defaultPrivacyLevel)
                        LabeledContent("Token", value: account.tokenStatus.displayName)
                        LabeledContent("Platform ID", value: account.platformUserID.isEmpty ? "Not set" : account.platformUserID)
                        LabeledContent("Scopes") {
                            Text(account.scopes.isEmpty ? "None" : account.scopes.joined(separator: ", "))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Validated") {
                            if let lastValidatedAt = account.lastValidatedAt {
                                Text(lastValidatedAt, style: .relative)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Never")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Post Options") {
                if platform == .tiktok {
                    LabeledContent("Privacy levels") {
                        Text(TikTokPrivacyLevel.directPostOptions.joined(separator: ", "))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Comments", value: "Allowed")
                    LabeledContent("Duet", value: "Refresh before post")
                    LabeledContent("Stitch", value: "Refresh before post")
                    LabeledContent("Commercial flags", value: "Brand organic per job")
                } else {
                    LabeledContent("Availability", value: "Future adapter")
                }
            }
        }
        .listStyle(.plain)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("\(platform.displayName) Publish Settings")
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
}
