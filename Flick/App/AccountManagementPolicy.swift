//
//  AccountManagementPolicy.swift
//  Flick
//

import Foundation

enum AccountManagementPolicy {
    static var canAuthorizeAccountsOnThisDevice: Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

    static var unavailableTitle: String {
        "Manage accounts in the iOS app"
    }

    static var unavailableMessage: String {
        "Use the iOS app to connect or refresh TikTok accounts. Synced Login Kit credentials remain available here for publishing."
    }
}
