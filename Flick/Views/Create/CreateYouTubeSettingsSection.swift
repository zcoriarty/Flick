//
//  CreateYouTubeSettingsSection.swift
//  Flick
//

import SwiftUI

struct CreateYouTubeSettingsSection: View {
    var accountSummary: String
    var isAccountReady: Bool
    var hasConfiguredSettings: Bool
    var privacyStatus: YouTubePrivacyStatus
    var containsSyntheticMedia: Bool
    var notifySubscribers: Bool
    var action: () -> Void

    private var settingsSummary: String {
        guard hasConfiguredSettings else { return "Select settings" }
        var parts = [privacyStatus.displayName]
        if containsSyntheticMedia {
            parts.append("synthetic media")
        }
        if notifySubscribers {
            parts.append("notify")
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Section("YouTube Shorts") {
            Button(action: action) {
                FlickSettingsRow(
                    title: "Settings",
                    systemImage: "slider.horizontal.3",
                    iconColor: .red
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
                title: "Posting channels",
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
