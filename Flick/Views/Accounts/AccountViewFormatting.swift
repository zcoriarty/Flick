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

    var body: some View {
        Image(platform.assetImageName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
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
