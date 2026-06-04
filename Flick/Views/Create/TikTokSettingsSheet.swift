//
//  TikTokSettingsSheet.swift
//  Flick
//

import SwiftUI

struct TikTokSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var accounts: [ConnectedAccount]
    @Binding var selectedAccountIDs: [UUID]
    @Binding var postTitle: String
    @Binding var postAsDraft: Bool
    @Binding var selectedVisibility: TikTokAudience?
    @Binding var allowComment: Bool
    @Binding var allowDuet: Bool
    @Binding var allowStitch: Bool
    @Binding var disclosesVideoContent: Bool
    @Binding var promotesYourBrand: Bool
    @Binding var promotesBrandedContent: Bool
    var allowsDraftUpload = true

    private var sortedAccounts: [ConnectedAccount] {
        accounts.sortedForAccountsView
    }

    private var selectedAccounts: [ConnectedAccount] {
        selectedAccountIDs.compactMap { accountID in
            accounts.first { $0.id == accountID }
        }
    }

    private var accountSummary: String {
        if selectedAccounts.count == 1, let account = selectedAccounts.first {
            return account.displayName
        }
        if selectedAccounts.count > 1 {
            return "\(selectedAccounts.count) accounts"
        }
        if !selectedAccountIDs.isEmpty {
            return "Unavailable account"
        }
        return "Select accounts"
    }

    private var isSelectedAccountReady: Bool {
        !selectedAccounts.isEmpty && selectedAccounts.allSatisfy(\.canPublishToTikTok)
    }

    var body: some View {
        NavigationStack {
            List {
                accountSection
                titleSection
                publishingSection
                if postAsDraft {
                    draftFlowSection
                } else {
                    interactionsSection
                    disclosureSection
                    declarationSection
                }
            }
            .flickSettingsListStyle()
            .flickToolbarTitle("TikTok Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            if !allowsDraftUpload {
                postAsDraft = false
            }
        }
        .onChange(of: selectedVisibility) { _, newValue in
            if newValue == .selfOnly {
                promotesBrandedContent = false
            }
        }
        .onChange(of: promotesBrandedContent) { _, isEnabled in
            if isEnabled, selectedVisibility == .selfOnly {
                selectedVisibility = nil
            }
        }
        .onChange(of: disclosesVideoContent) { _, isEnabled in
            if !isEnabled {
                promotesYourBrand = false
                promotesBrandedContent = false
            }
        }
    }

    private var accountSection: some View {
        Section("Account") {
            if sortedAccounts.isEmpty {
                FlickSettingsValueRow(
                    title: "Posting accounts",
                    systemImage: "person.crop.circle.badge.xmark",
                    iconColor: .orange,
                    value: "No TikTok accounts"
                )
            } else {
                FlickSettingsRow(
                    title: "Posting accounts",
                    systemImage: "person.crop.circle",
                    iconColor: isSelectedAccountReady ? .blue : .orange
                ) {
                    Text(accountSummary)
                        .foregroundStyle(isSelectedAccountReady ? Color.secondary : Color.orange)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                }

                ForEach(sortedAccounts) { account in
                    Button {
                        toggleAccount(account)
                    } label: {
                        HStack(spacing: 12) {
                            AccountPickerOptionLabel(
                                account: account,
                                isSelected: selectedAccountIDs.contains(account.id)
                            )
                            Spacer(minLength: 12)
                            if selectedAccountIDs.contains(account.id) {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .disabled(!account.canPublishToTikTok)
                }

                if selectedAccountIDs.isEmpty {
                    CreateMessageRow(
                        title: "Select TikTok accounts",
                        message: "Choose every TikTok account Flick should post to."
                    )
                } else if !isSelectedAccountReady {
                    CreateMessageRow(
                        title: "Selected account unavailable",
                        message: selectedAccountUnavailableMessage
                    )
                }
            }
        }
    }

    private var selectedAccountUnavailableMessage: String {
        guard let selectedAccount = selectedAccounts.first(where: { !$0.canPublishToTikTok }) else {
            return "This synced account no longer exists on this device. Reconnect it or choose another account."
        }
        if selectedAccount.tokenStatus == .notStored {
            return "This account's Login Kit token is not available on this device yet. Reconnect TikTok or wait for credentials to sync."
        }
        if selectedAccount.tokenStatus == .refreshFailed {
            return "This account's Login Kit token could not be refreshed. Reconnect TikTok before publishing."
        }
        if selectedAccount.tokenStatus == .expired {
            return "This account's Login Kit token expired. Reconnect TikTok before publishing."
        }
        if selectedAccount.status != .connected {
            return "This account is missing required TikTok authorization. Reconnect it from Accounts."
        }
        if !selectedAccount.isPublishingEnabled {
            return "This account is not publishing enabled. Reconnect TikTok with the required publishing scope."
        }
        return "Choose another TikTok account or reconnect this one from Accounts."
    }

    private func toggleAccount(_ account: ConnectedAccount) {
        if selectedAccountIDs.contains(account.id) {
            selectedAccountIDs.removeAll { $0 == account.id }
        } else {
            selectedAccountIDs.append(account.id)
        }
    }

    private var titleSection: some View {
        Section("Title") {
            CreateTextEditorRow(
                title: "Post title",
                systemImage: "square.and.pencil",
                text: $postTitle,
                placeholder: "Add a post title (optional).",
                minHeight: 78
            )
            .padding(.vertical, 2)
        }
    }

    private var publishingSection: some View {
        Section("Publishing") {
            if allowsDraftUpload {
                FlickSettingsRow(
                    title: "Create TikTok draft",
                    systemImage: "doc.badge.clock",
                    iconColor: .teal
                ) {
                    Toggle("Create TikTok draft", isOn: $postAsDraft)
                        .labelsHidden()
                }
            }

            if !postAsDraft {
                VisibilityMenuRow(
                    selectedVisibility: $selectedVisibility,
                    disablesPrivate: promotesBrandedContent
                )
            }
        }
    }

    private var draftFlowSection: some View {
        Section("Draft Flow") {
            FlickSettingsRow(
                title: "Open in TikTok",
                systemImage: "bell.badge",
                iconColor: .orange
            ) {
                Text("Use the inbox notification")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
        }
    }

    private var interactionsSection: some View {
        Section("Allow users to") {
            TikTokChecklistRow(
                title: "Comment",
                systemImage: "bubble.left",
                iconColor: .green,
                isOn: $allowComment
            )
            TikTokChecklistRow(
                title: "Duet",
                systemImage: "person.2",
                iconColor: .orange,
                isOn: $allowDuet
            )
            TikTokChecklistRow(
                title: "Stitch",
                systemImage: "rectangle.on.rectangle",
                iconColor: .orange,
                isOn: $allowStitch
            )
        }
    }

    private var disclosureSection: some View {
        Section("Disclosure") {
            FlickSettingsRow(
                title: "Disclose video content",
                systemImage: "megaphone",
                iconColor: FlickStyle.appTint
            ) {
                Toggle("Disclose video content", isOn: $disclosesVideoContent)
                    .labelsHidden()
            }

            if disclosesVideoContent {
                TikTokChecklistRow(
                    title: "Your brand",
                    systemImage: "building.2",
                    iconColor: .blue,
                    isOn: $promotesYourBrand
                )
                TikTokChecklistRow(
                    title: "Branded content",
                    systemImage: "tag",
                    iconColor: .purple,
                    isOn: $promotesBrandedContent,
                    isDisabled: selectedVisibility == .selfOnly,
                    disabledMessage: "Unavailable for private videos"
                )
                CommercialDisclosureNotice(
                    promotesYourBrand: promotesYourBrand,
                    promotesBrandedContent: promotesBrandedContent
                )
            }
        }
    }

    private var declarationSection: some View {
        Section("Declaration") {
            TikTokDeclarationRow(promotesBrandedContent: disclosesVideoContent && promotesBrandedContent)
        }
    }
}

struct AccountPickerOptionLabel: View {
    var account: ConnectedAccount
    var isSelected: Bool

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                Text(accountStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "person.crop.circle")
        }
    }

    private var accountStatus: String {
        account.canPublishToTikTok ? "Ready to publish" : "Unavailable"
    }
}
