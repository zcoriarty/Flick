//
//  TikTokRedirectPolicy.swift
//  Flick
//

import Foundation

enum TikTokRedirectPolicy {
    static let associatedDomain = "thready.it.com"
    static let callbackPath = "/oauth/tiktok/callback"
    static let recommendedRedirectURIString = "https://thready.it.com/oauth/tiktok/callback"

    static var recommendedRedirectURI: URL {
        URL(string: recommendedRedirectURIString)!
    }

    static func validateLoginKitRedirectURI(_ redirectURI: URL) throws {
        guard redirectURI.scheme == "https", redirectURI.host?.isEmpty == false else {
            throw LoginKitError.notConfigured("TikTok Login Kit for iOS requires an HTTPS universal-link redirect URI.")
        }
        guard redirectURI.absoluteString == recommendedRedirectURIString else {
            throw LoginKitError.notConfigured("Set TIKTOK_REDIRECT_URI to \(recommendedRedirectURIString). Current value: \(redirectURI.absoluteString). TikTok Login Kit must return to Flick's registered Universal Link, not the App Store URL.")
        }
    }
}
