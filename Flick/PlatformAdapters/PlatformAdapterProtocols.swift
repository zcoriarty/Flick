//
//  PlatformAdapterProtocols.swift
//  Flick
//

import Foundation

struct PlatformAccountStatus: Hashable {
    var accountID: UUID
    var status: AccountStatus
    var scopes: [String]
    var canDirectPublish: Bool
    var privacyOptions: [String]
    var lastCheckedAt: Date
}

struct PreparedPlatformMedia: Hashable {
    var mode: PublishMode
    var imageURLs: [URL]
    var videoURL: URL?
    var warnings: [String]
}

struct PublishResult: Hashable {
    var platform: SocialPlatform
    var platformPostID: String
    var platformURL: URL?
    var publishedAt: Date
    var platformStatus: String?
    var rawResponse: String
}

struct CreatorPublishingInfo: Hashable {
    var privacyOptions: [String]
    var commentsAllowed: Bool
    var duetAllowed: Bool
    var stitchAllowed: Bool
    var directPostAllowed: Bool
}

protocol SocialPlatformPublishing {
    var platform: SocialPlatform { get }
    func validateAccount(_ account: ConnectedAccount) async throws -> PlatformAccountStatus
    func publish(_ job: PublishingJob, media: PreparedPlatformMedia) async throws -> PublishResult
}

protocol SocialPlatformAdapter: SocialPlatformPublishing {
    func connectAccount() async throws -> ConnectedAccount
    func prepareMedia(_ draft: SlideshowDraft, mode: PublishMode) async throws -> PreparedPlatformMedia
}

enum PlatformAdapterError: LocalizedError, Equatable {
    case notConfigured(String)
    case missingAccountToken
    case unsupportedMode(PublishMode)
    case directPublishingRequiresCreatorInfo
    case futurePlatform(SocialPlatform)

    var errorDescription: String? {
        switch self {
        case let .notConfigured(message):
            message
        case .missingAccountToken:
            "A valid OAuth token must be stored in Keychain before publishing."
        case let .unsupportedMode(mode):
            "\(mode.rawValue) is not supported by this adapter yet."
        case .directPublishingRequiresCreatorInfo:
            "Creator publishing info must be refreshed before direct publishing."
        case let .futurePlatform(platform):
            "\(platform.displayName) is modeled for future support but is not enabled in V1."
        }
    }
}
