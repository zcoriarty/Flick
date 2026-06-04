//
//  AccountViewFormatting.swift
//  Flick
//

import SwiftUI

extension Array where Element == ConnectedAccount {
    var sortedForAccountsView: [ConnectedAccount] {
        sorted {
            if $0.platform.rawValue == $1.platform.rawValue {
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            return $0.platform.displayName < $1.platform.displayName
        }
    }
}

extension SocialPlatform {
    var assetImageName: String {
        switch self {
        case .tiktok: "tiktok_icon"
        case .youtubeShorts: "Youtube_shorts_icon.svg"
        case .instagram: "instagram_icon"
        case .threads: "threads_icon"
        case .x: "X_twitter_icon"
        }
    }

    var tint: Color {
        switch self {
        case .tiktok: .pink
        case .youtubeShorts: .red
        case .instagram: .purple
        case .threads: .indigo
        case .x: .primary
        }
    }
}

struct PlatformIcon: View {
    var platform: SocialPlatform
    var size: CGFloat = 24
    var frameSize: CGFloat?

    var body: some View {
        Image(platform.assetImageName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .frame(width: frameSize ?? size, height: frameSize ?? size)
            .accessibilityHidden(true)
    }
}

struct PlatformMenuLabel: View {
    var platform: SocialPlatform

    var body: some View {
        Label {
            Text(platform.displayName)
        } icon: {
            PlatformIcon(platform: platform, size: 16, frameSize: 20)
        }
    }
}

struct PlatformSettingsValueRow: View {
    var title: String
    var platform: SocialPlatform
    var value: String?
    var valueLineLimit: Int? = 1

    var body: some View {
        HStack(spacing: 12) {
            PlatformIcon(platform: platform, size: 22, frameSize: 24)

            Text(title)
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            if let value {
                Text(value)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(valueLineLimit)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension OAuthTokenStatus {
    var displayName: String {
        switch self {
        case .valid: "Valid"
        case .expiresSoon: "Expires soon"
        case .refreshFailed: "Refresh failed"
        case .expired: "Expired"
        case .notStored: "Not stored"
        }
    }
}
