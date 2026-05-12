//
//  TikTokAdapter.swift
//  Flick
//

import Foundation

struct TikTokAdapter: SocialPlatformAdapter {
    let configuration: TikTokConfiguration
    let tokenStore: SecretStoring

    var platform: SocialPlatform { .tiktok }

    func connectAccount() async throws -> ConnectedAccount {
        guard configuration.clientIDPresent, configuration.redirectURI != nil else {
            throw PlatformAdapterError.notConfigured("TikTok OAuth requires a client ID and redirect URI.")
        }

        throw PlatformAdapterError.missingAccountToken
    }

    func validateAccount(_ account: ConnectedAccount) async throws -> PlatformAccountStatus {
        guard account.platform == .tiktok else {
            throw PlatformAdapterError.futurePlatform(account.platform)
        }
        guard account.tokenStatus == .valid else {
            throw PlatformAdapterError.missingAccountToken
        }

        return PlatformAccountStatus(
            accountID: account.id,
            status: account.status,
            scopes: account.scopes,
            canDirectPublish: account.scopes.contains("video.publish"),
            privacyOptions: ["PUBLIC_TO_EVERYONE", "MUTUAL_FOLLOW_FRIENDS", "SELF_ONLY"],
            lastCheckedAt: Date()
        )
    }

    func prepareMedia(_ draft: SlideshowDraft, mode: PublishMode) async throws -> PreparedPlatformMedia {
        switch mode {
        case .photoDirectPost, .photoUploadForCompletion:
            return PreparedPlatformMedia(mode: mode, imageURLs: [], videoURL: nil, warnings: missingImageWarnings(for: draft))
        case .videoDirectPost, .videoUploadForCompletion:
            return PreparedPlatformMedia(mode: mode, imageURLs: [], videoURL: nil, warnings: ["Video rendering must complete before TikTok upload."])
        }
    }

    func publish(_ job: PublishingJob, media: PreparedPlatformMedia) async throws -> PublishResult {
        guard job.platform == .tiktok else {
            throw PlatformAdapterError.futurePlatform(job.platform)
        }
        guard configuration.clientIDPresent else {
            throw PlatformAdapterError.notConfigured("TikTok client ID is missing.")
        }
        guard configuration.verifiedBaseURL != nil || media.mode == .videoUploadForCompletion || media.mode == .videoDirectPost else {
            throw PlatformAdapterError.notConfigured("TikTok photo publishing requires a verified media URL prefix.")
        }

        throw PlatformAdapterError.missingAccountToken
    }

    func fetchAnalytics(for post: PublishedPost) async throws -> AnalyticsSnapshot {
        guard post.platform == .tiktok else {
            throw PlatformAdapterError.futurePlatform(post.platform)
        }
        throw PlatformAdapterError.missingAccountToken
    }

    private func missingImageWarnings(for draft: SlideshowDraft) -> [String] {
        let missingImageCount = draft.slides.filter { $0.imageAssetID == nil }.count
        guard missingImageCount > 0 else { return [] }
        return ["\(missingImageCount) slide images still need generated or uploaded Supabase URLs."]
    }
}
