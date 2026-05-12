//
//  FlickDomainModels.swift
//  Flick
//
//  Shared product models from FlickOverview.md.
//

import Foundation

enum SocialPlatform: String, CaseIterable, Codable, Identifiable, Hashable {
    case tiktok
    case instagram
    case threads
    case x

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiktok: "TikTok"
        case .instagram: "Instagram"
        case .threads: "Threads"
        case .x: "X"
        }
    }
}

enum FlickDevicePlatform: String, CaseIterable, Codable, Identifiable {
    case iPhone
    case mac
    case iPad
    case vision

    var id: String { rawValue }
}

enum AccountStatus: String, CaseIterable, Codable, Identifiable {
    case connected
    case needsAuth
    case missingScope
    case rateLimited
    case disabled
    case comingSoon

    var id: String { rawValue }
}

enum OAuthTokenStatus: String, CaseIterable, Codable, Identifiable {
    case valid
    case expiresSoon
    case expired
    case notStored

    var id: String { rawValue }
}

enum AccountAuthorizationSource: String, CaseIterable, Codable, Identifiable {
    case loginKit
    case manualImport
    case unavailable

    var id: String { rawValue }
}

enum CampaignStatus: String, CaseIterable, Codable, Identifiable {
    case planning
    case active
    case paused
    case archived

    var id: String { rawValue }
}

enum TrendStatus: String, CaseIterable, Codable, Identifiable {
    case new
    case active
    case testing
    case winning
    case declining
    case archived

    var id: String { rawValue }
}

enum TrendTagCategory: String, CaseIterable, Codable, Identifiable {
    case hook
    case template
    case visualStyle
    case niche
    case appFeature
    case emotion
    case cta
    case pacing
    case textDensity
    case platform

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .visualStyle: "Visual style"
        case .appFeature: "App feature"
        case .textDensity: "Text density"
        default: rawValue.capitalized
        }
    }
}

enum AssetMediaType: String, CaseIterable, Codable, Identifiable {
    case image
    case video
    case thumbnail

    var id: String { rawValue }
}

enum AssetSource: String, CaseIterable, Codable, Identifiable {
    case generated
    case uploaded
    case reference
    case rendered

    var id: String { rawValue }
}

enum SlideshowDraftStatus: String, CaseIterable, Codable, Identifiable {
    case draft
    case needsReview
    case approved
    case queued
    case published
    case archived

    var id: String { rawValue }
}

enum SlideRole: String, CaseIterable, Codable, Identifiable {
    case hook
    case problem
    case proof
    case demo
    case benefit
    case cta

    var id: String { rawValue }
}

enum TextPosition: String, CaseIterable, Codable, Identifiable {
    case top
    case center
    case bottom
    case split

    var id: String { rawValue }
}

enum TransitionStyle: String, CaseIterable, Codable, Identifiable {
    case none
    case dissolve
    case push
    case scale

    var id: String { rawValue }
}

enum PublishMode: String, CaseIterable, Codable, Identifiable {
    case photoDirectPost
    case photoUploadForCompletion
    case videoDirectPost
    case videoUploadForCompletion

    var id: String { rawValue }
}

enum PublishingJobStatus: String, CaseIterable, Codable, Identifiable {
    case draft
    case queued
    case awaitingApproval
    case approved
    case rendering
    case uploadingMedia
    case publishing
    case published
    case failed
    case canceled
    case paused

    var id: String { rawValue }

    var isTerminal: Bool {
        switch self {
        case .published, .failed, .canceled:
            true
        default:
            false
        }
    }

    func canTransition(to next: PublishingJobStatus) -> Bool {
        switch (self, next) {
        case (.draft, .queued),
             (.queued, .awaitingApproval),
             (.queued, .approved),
             (.awaitingApproval, .approved),
             (.approved, .rendering),
             (.rendering, .uploadingMedia),
             (.uploadingMedia, .publishing),
             (.publishing, .published),
             (.publishing, .failed),
             (.rendering, .failed),
             (.uploadingMedia, .failed),
             (.failed, .queued),
             (.queued, .paused),
             (.paused, .queued),
             (.awaitingApproval, .canceled),
             (.queued, .canceled),
             (.approved, .canceled):
            true
        default:
            false
        }
    }
}

enum PlatformErrorKind: String, CaseIterable, Codable, Identifiable {
    case authExpired
    case missingScope
    case rateLimit
    case mediaURLInaccessible
    case urlOwnershipUnverified
    case invalidPrivacySetting
    case unauditedClient
    case platformProcessingFailed
    case unknownServerError

    var id: String { rawValue }

    var isRetryable: Bool {
        switch self {
        case .rateLimit, .platformProcessingFailed, .unknownServerError:
            true
        default:
            false
        }
    }
}

enum ApprovalMode: String, CaseIterable, Codable, Identifiable {
    case manualOnly
    case approveGeneratedBatch
    case trustedTemplates
    case fullyAutonomous

    var id: String { rawValue }
}

struct FlickWorkspace: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var defaultCadence: CadenceRule
    var automationPaused: Bool
    var primaryWorkerDeviceID: UUID?
    var createdAt: Date
    var updatedAt: Date
}

struct FlickDevice: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var platform: FlickDevicePlatform
    var isPrimaryWorker: Bool
    var lastSeenAt: Date
    var capabilities: [String]
    var appVersion: String
}

struct ConnectedAccount: Identifiable, Codable, Hashable {
    var id: UUID
    var platform: SocialPlatform
    var displayName: String
    var platformUserID: String
    var avatarURL: URL?
    var scopes: [String]
    var status: AccountStatus
    var authorizationSource: AccountAuthorizationSource
    var tokenStatus: OAuthTokenStatus
    var isPublishingEnabled: Bool
    var defaultPrivacyLevel: String
    var lastValidatedAt: Date?
    var createdAt: Date
    var updatedAt: Date
}

struct Campaign: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var goal: String
    var appFeature: String
    var audience: String
    var status: CampaignStatus
    var createdAt: Date
    var updatedAt: Date
}

struct TrendTag: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var category: TrendTagCategory
    var colorHex: String
    var createdAt: Date
}

struct Trend: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var source: String
    var sourceURL: URL?
    var notes: String
    var status: TrendStatus
    var tags: [TrendTag]
    var referenceAssetIDs: [UUID]
    var examples: [String]
    var performanceSummary: String
    var createdAt: Date
    var updatedAt: Date
}

struct MediaAsset: Identifiable, Codable, Hashable {
    var id: UUID
    var mediaType: AssetMediaType
    var source: AssetSource
    var localFilePath: String?
    var storageBucket: String?
    var storagePath: String?
    var publicURL: URL?
    var signedURLExpiration: Date?
    var width: Int
    var height: Int
    var duration: TimeInterval?
    var fileSize: Int64?
    var checksum: String?
    var trendTags: [TrendTag]
    var createdAt: Date
    var updatedAt: Date
}

struct SlideTextStyle: Codable, Hashable {
    var fontName: String
    var weight: String
    var foregroundHex: String
    var backgroundHex: String
    var alignment: String
}

struct Slide: Identifiable, Codable, Hashable {
    var id: UUID
    var index: Int
    var role: SlideRole
    var imageAssetID: UUID?
    var prompt: String
    var overlayText: String
    var textPosition: TextPosition
    var textStyle: SlideTextStyle
    var duration: TimeInterval
    var transition: TransitionStyle
    var createdAt: Date
    var updatedAt: Date
}

struct CreativeTemplate: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var description: String
    var platform: SocialPlatform
    var slideCount: Int
    var styleJSON: String
    var defaultTextRules: String
    var tags: [TrendTag]
    var createdAt: Date
    var updatedAt: Date
}

struct SlideshowDraft: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var campaignID: UUID?
    var templateID: UUID?
    var sourceTrendID: UUID?
    var slides: [Slide]
    var caption: String
    var hashtags: [String]
    var targetPlatforms: [SocialPlatform]
    var status: SlideshowDraftStatus
    var createdAt: Date
    var updatedAt: Date
}

struct PublishingJob: Identifiable, Codable, Hashable {
    var id: UUID
    var platform: SocialPlatform
    var accountID: UUID
    var draftID: UUID
    var scheduledAt: Date
    var status: PublishingJobStatus
    var publishMode: PublishMode
    var requiresApproval: Bool
    var approvedAt: Date?
    var approvedByDeviceID: UUID?
    var workerDeviceID: UUID?
    var workerLeaseExpiresAt: Date?
    var attemptCount: Int
    var lastAttemptAt: Date?
    var lastError: PlatformFailure?
    var platformPublishID: String?
    var createdAt: Date
    var updatedAt: Date

    var isLeaseActive: Bool {
        guard let workerLeaseExpiresAt else { return false }
        return workerLeaseExpiresAt > Date()
    }
}

struct PlatformFailure: Codable, Hashable {
    var kind: PlatformErrorKind
    var message: String
    var suggestedFix: String
    var rawResponse: String?
}

struct PublishedPost: Identifiable, Codable, Hashable {
    var id: UUID
    var platform: SocialPlatform
    var accountID: UUID
    var platformPostID: String
    var platformURL: URL?
    var publishedAt: Date
    var draftID: UUID
    var campaignID: UUID?
    var templateID: UUID?
    var trendTags: [TrendTag]
    var caption: String
    var createdAt: Date
    var updatedAt: Date
}

struct AnalyticsSnapshot: Identifiable, Codable, Hashable {
    var id: UUID
    var publishedPostID: UUID
    var capturedAt: Date
    var views: Int
    var likes: Int
    var comments: Int
    var shares: Int
    var saves: Int
    var engagementRate: Double
    var watchTime: TimeInterval?
    var completionRate: Double?
    var profileVisits: Int?
    var follows: Int?
    var rawJSON: String
}

struct AnalyticsPostPerformance: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var platform: SocialPlatform
    var views: Int
    var engagementRate: Double
    var savesPerView: Double
    var publishedAt: Date
    var tags: [TrendTag]
}

struct CadenceRule: Identifiable, Codable, Hashable {
    var id: UUID
    var accountID: UUID?
    var postsPerDay: Int
    var allowedTimeWindows: [String]
    var minimumGapMinutes: Int
    var requireApproval: Bool
    var maxRetries: Int
    var pauseOnErrorCount: Int
}

struct SyncHealth: Codable, Hashable {
    var lastCloudKitImport: Date?
    var lastCloudKitExport: Date?
    var pendingChanges: Int
    var iCloudAvailable: Bool
    var primaryWorkerOnline: Bool
    var errors: [String]
}

struct WorkerStatus: Codable, Hashable {
    var deviceName: String
    var isPrimary: Bool
    var isOnline: Bool
    var automationPaused: Bool
    var lastSeenAt: Date
    var activeJobID: UUID?
}

struct APIHealthStatus: Identifiable, Codable, Hashable {
    var id: String { serviceName }
    var serviceName: String
    var isConfigured: Bool
    var statusText: String
    var lastCheckedAt: Date?
}

struct DashboardSnapshot: Codable, Hashable {
    var scheduledTodayCount: Int
    var awaitingApprovalCount: Int
    var failedJobCount: Int
    var bestRecentPost: AnalyticsPostPerformance?
    var workerStatus: WorkerStatus
    var connectedAccounts: [ConnectedAccount]
    var syncHealth: SyncHealth
    var apiHealth: [APIHealthStatus]
}

struct FlickOverviewState: Codable, Hashable {
    var workspace: FlickWorkspace
    var devices: [FlickDevice]
    var accounts: [ConnectedAccount]
    var campaigns: [Campaign]
    var trends: [Trend]
    var trendTags: [TrendTag]
    var assets: [MediaAsset]
    var drafts: [SlideshowDraft]
    var templates: [CreativeTemplate]
    var publishingJobs: [PublishingJob]
    var publishedPosts: [PublishedPost]
    var analyticsSnapshots: [AnalyticsSnapshot]
    var analyticsPerformance: [AnalyticsPostPerformance]
    var cadenceRules: [CadenceRule]
    var dashboard: DashboardSnapshot
}
