//
//  YouTubeSettingsSheet.swift
//  Flick
//

import SwiftUI

struct YouTubeSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var accounts: [ConnectedAccount]
    @Binding var selectedAccountIDs: [UUID]
    @Binding var title: String
    @Binding var description: String
    @Binding var tags: [String]
    @Binding var privacyStatus: YouTubePrivacyStatus
    @Binding var categoryID: String
    @Binding var selfDeclaredMadeForKids: Bool
    @Binding var containsSyntheticMedia: Bool
    @Binding var notifySubscribers: Bool

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
            return "\(selectedAccounts.count) channels"
        }
        if !selectedAccountIDs.isEmpty {
            return "Unavailable channel"
        }
        return "Select channels"
    }

    private var isAccountReady: Bool {
        !selectedAccounts.isEmpty && selectedAccounts.allSatisfy { account in
            account.platform == .youtubeShorts
                && account.authorizationSource == .nativeOAuth
                && account.status == .connected
                && account.isPublishingEnabled
        }
    }

    var body: some View {
        NavigationStack {
            List {
                accountSection
                metadataSection
                publishingSection
                disclosureSection
            }
            .flickSettingsListStyle()
            .flickToolbarTitle("YouTube Shorts Settings")
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
    }

    private var accountSection: some View {
        Section("Channels") {
            if sortedAccounts.isEmpty {
                FlickSettingsValueRow(
                    title: "Posting channels",
                    systemImage: "person.crop.circle.badge.xmark",
                    iconColor: .orange,
                    value: "No YouTube channels"
                )
            } else {
                FlickSettingsRow(
                    title: "Posting channels",
                    systemImage: "person.crop.circle",
                    iconColor: isAccountReady ? .blue : .orange
                ) {
                    Text(accountSummary)
                        .foregroundStyle(isAccountReady ? Color.secondary : Color.orange)
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
                    .disabled(!account.isPublishingEnabled || account.status != .connected)
                }

                if selectedAccountIDs.isEmpty {
                    CreateMessageRow(
                        title: "Select YouTube channels",
                        message: "Choose every YouTube channel Flick should post this Short to."
                    )
                } else if !isAccountReady {
                    CreateMessageRow(
                        title: "Selected channel unavailable",
                        message: "Reconnect YouTube with upload permission, or authorize the selected channel on the Mac runner before scheduled publishing."
                    )
                }
            }
        }
    }

    private var metadataSection: some View {
        Section("Metadata") {
            CreateTextEditorRow(
                title: "Title",
                systemImage: "square.and.pencil",
                text: $title,
                placeholder: "Use draft title",
                minHeight: 64
            )
            CreateTextEditorRow(
                title: "Description",
                systemImage: "text.alignleft",
                text: $description,
                placeholder: "Use draft caption and hashtags",
                minHeight: 96
            )
            FlickSettingsRow(
                title: "Tags",
                systemImage: "number",
                iconColor: .purple
            ) {
                TextField("Tags", text: tagsTextBinding)
                    .multilineTextAlignment(.trailing)
            }
            FlickSettingsRow(
                title: "Category",
                systemImage: "tag",
                iconColor: .purple
            ) {
                TextField("22", text: $categoryID)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
            }
        }
    }

    private var publishingSection: some View {
        Section("Publishing") {
            Menu {
                ForEach(YouTubePrivacyStatus.allCases) { status in
                    Button {
                        privacyStatus = status
                    } label: {
                        if privacyStatus == status {
                            Label(status.displayName, systemImage: "checkmark")
                        } else {
                            Text(status.displayName)
                        }
                    }
                }
            } label: {
                FlickSettingsRow(
                    title: "Visibility",
                    systemImage: "eye",
                    iconColor: .blue
                ) {
                    Text(privacyStatus.displayName)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            FlickSettingsRow(
                title: "Notify subscribers",
                systemImage: "bell",
                iconColor: .orange
            ) {
                Toggle("Notify subscribers", isOn: $notifySubscribers)
                    .labelsHidden()
            }
        }
    }

    private var disclosureSection: some View {
        Section("Disclosure") {
            FlickSettingsRow(
                title: "Made for kids",
                systemImage: "figure.2.and.child.holdinghands",
                iconColor: .teal
            ) {
                Toggle("Made for kids", isOn: $selfDeclaredMadeForKids)
                    .labelsHidden()
            }
            FlickSettingsRow(
                title: "Synthetic media",
                systemImage: "sparkles",
                iconColor: FlickStyle.appTint
            ) {
                Toggle("Synthetic media", isOn: $containsSyntheticMedia)
                    .labelsHidden()
            }
        }
    }

    private var tagsTextBinding: Binding<String> {
        Binding(
            get: { tags.joined(separator: ", ") },
            set: { newValue in
                tags = newValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# \n\t")) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private func toggleAccount(_ account: ConnectedAccount) {
        if selectedAccountIDs.contains(account.id) {
            selectedAccountIDs.removeAll { $0 == account.id }
        } else {
            selectedAccountIDs.append(account.id)
        }
    }
}
