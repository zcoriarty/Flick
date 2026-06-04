//
//  AccountManagementPolicy.swift
//  Flick
//

import Foundation

enum AccountManagementPolicy {
    static var canAuthorizeAccountsOnThisDevice: Bool {
        SocialPlatform.allCases.contains { platform in
            switch platform {
            case .tiktok:
                #if os(iOS) && !targetEnvironment(macCatalyst)
                true
                #else
                false
                #endif
            case .youtubeShorts:
                true
            case .instagram, .threads, .x:
                false
            }
        }
    }

    static func canAuthorize(_ platform: SocialPlatform) -> Bool {
        switch platform {
        case .tiktok:
            #if os(iOS) && !targetEnvironment(macCatalyst)
            true
            #else
            false
            #endif
        case .youtubeShorts:
            true
        case .instagram, .threads, .x:
            false
        }
    }

    static var unavailableTitle: String {
        "No account connectors available"
    }

    static var unavailableMessage: String {
        "This device cannot start any supported account authorization flow."
    }

    static func unavailableMessage(for platform: SocialPlatform) -> String {
        switch platform {
        case .tiktok:
            "Use the iOS app to connect or refresh TikTok accounts. Synced Login Kit credentials remain available here for publishing."
        case .youtubeShorts:
            "Authorize YouTube on this device before using it for publishing."
        case .instagram, .threads, .x:
            "\(platform.displayName) account connection is not enabled yet."
        }
    }
}
