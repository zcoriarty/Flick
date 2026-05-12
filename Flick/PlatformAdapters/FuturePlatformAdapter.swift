//
//  FuturePlatformAdapter.swift
//  Flick
//

import Foundation

struct FuturePlatformAdapter: SocialPlatformAdapter {
    let platform: SocialPlatform

    func connectAccount() async throws -> ConnectedAccount {
        throw PlatformAdapterError.futurePlatform(platform)
    }

    func validateAccount(_ account: ConnectedAccount) async throws -> PlatformAccountStatus {
        throw PlatformAdapterError.futurePlatform(account.platform)
    }

    func prepareMedia(_ draft: SlideshowDraft, mode: PublishMode) async throws -> PreparedPlatformMedia {
        _ = draft
        _ = mode
        throw PlatformAdapterError.futurePlatform(platform)
    }

    func publish(_ job: PublishingJob, media: PreparedPlatformMedia) async throws -> PublishResult {
        _ = job
        _ = media
        throw PlatformAdapterError.futurePlatform(platform)
    }

    func fetchAnalytics(for post: PublishedPost) async throws -> AnalyticsSnapshot {
        _ = post
        throw PlatformAdapterError.futurePlatform(platform)
    }
}
