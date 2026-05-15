//
//  TikTokSettingsSheet.swift
//  Flick
//

import SwiftUI

struct TikTokSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var accountName: String?
    @Binding var postTitle: String
    @Binding var postAsDraft: Bool
    @Binding var selectedVisibility: TikTokAudience?
    @Binding var allowComment: Bool
    @Binding var allowDuet: Bool
    @Binding var allowStitch: Bool
    @Binding var disclosesVideoContent: Bool
    @Binding var promotesYourBrand: Bool
    @Binding var promotesBrandedContent: Bool

    var body: some View {
        NavigationStack {
            List {
                accountSection
                titleSection
                publishingSection
                interactionsSection
                disclosureSection
                declarationSection
            }
            .flickSettingsListStyle()
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("TikTok Settings")
                        .font(.system(.body, weight: .semibold))
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
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
            FlickSettingsRow(
                title: "Posting account",
                systemImage: "person.crop.circle",
                iconColor: accountName == nil ? .orange : .blue
            ) {
                Text(accountName ?? "Not connected")
                    .foregroundStyle(accountName == nil ? .orange : .secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
            }
        }
    }

    private var titleSection: some View {
        Section("Title") {
            CreateTextEditorRow(
                title: "Post title",
                systemImage: "square.and.pencil",
                text: $postTitle,
                placeholder: "Add a post title.",
                minHeight: 78
            )
            .padding(.vertical, 2)
        }
    }

    private var publishingSection: some View {
        Section("Publishing") {
            FlickSettingsRow(
                title: "Post as draft",
                systemImage: "doc.badge.clock",
                iconColor: .teal
            ) {
                Toggle("Post as draft", isOn: $postAsDraft)
                    .labelsHidden()
            }

            VisibilityMenuRow(
                selectedVisibility: $selectedVisibility,
                disablesPrivate: promotesBrandedContent
            )
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
                iconColor: .indigo
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
