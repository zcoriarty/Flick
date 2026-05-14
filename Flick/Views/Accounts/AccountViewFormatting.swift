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
    var tint: Color {
        switch self {
        case .tiktok: .pink
        case .instagram: .purple
        case .threads: .indigo
        case .x: .primary
        }
    }
}

extension OAuthTokenStatus {
    var displayName: String {
        switch self {
        case .valid: "Valid"
        case .expiresSoon: "Expires soon"
        case .expired: "Expired"
        case .notStored: "Not stored"
        }
    }
}
