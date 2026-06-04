//
//  CreateTikTokSettingsSection.swift
//  Flick
//

import SwiftUI

struct CreateTikTokSettingsSection: View {
    var accountSummary: String
    var isAccountReady: Bool
    var hasConfiguredSettings: Bool
    var postAsDraft: Bool
    var selectedVisibility: TikTokAudience?
    var disclosesVideoContent: Bool
    var promotesYourBrand: Bool
    var promotesBrandedContent: Bool
    var action: () -> Void

    private var settingsSummary: String {
        guard hasConfiguredSettings else { return "Select settings" }

        if postAsDraft {
            return "TikTok draft"
        }

        let destination = "Direct post"
        guard let selectedVisibility else { return "\(destination), select visibility" }

        let disclosure = disclosureSummary
        guard !disclosure.isEmpty else { return "\(destination), \(selectedVisibility.title)" }
        return "\(destination), \(selectedVisibility.title), \(disclosure)"
    }

    private var disclosureSummary: String {
        guard disclosesVideoContent else { return "" }
        return switch (promotesYourBrand, promotesBrandedContent) {
        case (true, true): "brand + paid"
        case (true, false): "brand"
        case (false, true): "paid"
        case (false, false): "disclosure needed"
        }
    }

    var body: some View {
        Section("TikTok") {
            Button(action: action) {
                FlickSettingsRow(
                    title: "Settings",
                    systemImage: "slider.horizontal.3",
                    iconColor: FlickStyle.appTint
                ) {
                    Text(settingsSummary)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            FlickSettingsRow(
                title: "Posting account",
                systemImage: "person.crop.circle",
                iconColor: isAccountReady ? .blue : .orange
            ) {
                Text(accountSummary)
                    .foregroundStyle(isAccountReady ? Color.secondary : Color.orange)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
            }
        }
    }
}
