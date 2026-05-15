//
//  TikTokSettingsRows.swift
//  Flick
//

import SwiftUI

struct VisibilityMenuRow: View {
    @Binding var selectedVisibility: TikTokAudience?
    var disablesPrivate: Bool

    var body: some View {
        FlickSettingsRow(
            title: "Who can view",
            systemImage: "eye",
            iconColor: .blue
        ) {
            Menu {
                ForEach(TikTokAudience.allCases) { visibility in
                    Button {
                        selectedVisibility = visibility
                    } label: {
                        if selectedVisibility == visibility {
                            Label(visibility.title, systemImage: "checkmark")
                        } else {
                            Text(visibility.title)
                        }
                    }
                    .disabled(visibility == .selfOnly && disablesPrivate)
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedVisibility?.title ?? "Select")
                        .foregroundStyle(selectedVisibility == nil ? .orange : .secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }

        if disablesPrivate {
            Text("Branded content visibility cannot be set to private.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 36)
        }
    }
}

struct TikTokChecklistRow: View {
    var title: String
    var systemImage: String
    var iconColor: Color
    @Binding var isOn: Bool
    var isDisabled = false
    var disabledMessage: String?

    var body: some View {
        Button {
            guard !isDisabled else { return }
            isOn.toggle()
        } label: {
            FlickSettingsRow(
                title: title,
                systemImage: systemImage,
                iconColor: iconColor
            ) {
                HStack(spacing: 8) {
                    if isDisabled, let disabledMessage {
                        Text(disabledMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Image(systemName: isOn ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundStyle(isOn ? Color.indigo : Color.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
        .accessibilityValue(isOn ? "Selected" : "Not selected")
    }
}

struct CommercialDisclosureNotice: View {
    var promotesYourBrand: Bool
    var promotesBrandedContent: Bool

    private var notice: (message: String, systemImage: String, tint: Color) {
        if !promotesYourBrand && !promotesBrandedContent {
            return ("Select at least one disclosure type.", "exclamationmark.triangle", .orange)
        } else if promotesBrandedContent {
            return ("Your photo/video will be labeled as 'Paid partnership'.", "tag", .purple)
        } else {
            return ("Your photo/video will be labeled as 'Promotional content'.", "megaphone", .blue)
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: notice.systemImage)
                .frame(width: 16, alignment: .center)

            Text(notice.message)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(notice.tint)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct TikTokDeclarationRow: View {
    var promotesBrandedContent: Bool

    private var declaration: AttributedString {
        if promotesBrandedContent {
            return attributedDeclaration(
                "By posting, you agree to TikTok's Branded Content Policy and [Music Usage Confirmation](https://www.tiktok.com/legal/page/global/music-usage-confirmation/en)."
            )
        }
        return attributedDeclaration(
            "By posting, you agree to TikTok's [Music Usage Confirmation](https://www.tiktok.com/legal/page/global/music-usage-confirmation/en)."
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal")
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(declaration)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .tint(.blue)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func attributedDeclaration(_ markdown: String) -> AttributedString {
        (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }
}
