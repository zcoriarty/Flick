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

enum SlideGenerationStatus: String, CaseIterable, Codable, Identifiable {
    case notStarted = "not_started"
    case generating
    case complete
    case failed

    var id: String { rawValue }
}

enum TextPosition: String, CaseIterable, Codable, Identifiable {
    case left
    case right
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
    var fontPreset: String? = nil
}

struct Slide: Identifiable, Codable, Hashable {
    var id: UUID
    var index: Int
    var role: SlideRole
    var imageAssetID: UUID?
    var prompt: String
    var overlayText: String
    var supportingText: String
    var ctaText: String
    var visualGoal: String
    var textPosition: TextPosition
    var textSafeArea: String
    var mainSubjectArea: String
    var textStyle: SlideTextStyle
    var selectedVisualSummary: String
    var generationStatus: SlideGenerationStatus
    var generationErrorMessage: String?
    var promptVersion: Int
    var duration: TimeInterval
    var transition: TransitionStyle
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        index: Int,
        role: SlideRole,
        imageAssetID: UUID?,
        prompt: String,
        overlayText: String,
        supportingText: String = "",
        ctaText: String = "",
        visualGoal: String = "",
        textPosition: TextPosition,
        textSafeArea: String = "",
        mainSubjectArea: String = "",
        textStyle: SlideTextStyle,
        selectedVisualSummary: String = "",
        generationStatus: SlideGenerationStatus = .notStarted,
        generationErrorMessage: String? = nil,
        promptVersion: Int = 1,
        duration: TimeInterval,
        transition: TransitionStyle,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.index = index
        self.role = role
        self.imageAssetID = imageAssetID
        self.prompt = prompt
        self.overlayText = overlayText
        self.supportingText = supportingText
        self.ctaText = ctaText
        self.visualGoal = visualGoal
        self.textPosition = textPosition
        self.textSafeArea = textSafeArea
        self.mainSubjectArea = mainSubjectArea
        self.textStyle = textStyle
        self.selectedVisualSummary = selectedVisualSummary
        self.generationStatus = generationStatus
        self.generationErrorMessage = generationErrorMessage
        self.promptVersion = promptVersion
        self.duration = duration
        self.transition = transition
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case index
        case role
        case imageAssetID
        case prompt
        case overlayText
        case supportingText
        case ctaText
        case visualGoal
        case textPosition
        case textSafeArea
        case mainSubjectArea
        case textStyle
        case selectedVisualSummary
        case generationStatus
        case generationErrorMessage
        case promptVersion
        case duration
        case transition
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        index = try container.decode(Int.self, forKey: .index)
        role = try container.decode(SlideRole.self, forKey: .role)
        imageAssetID = try container.decodeIfPresent(UUID.self, forKey: .imageAssetID)
        prompt = try container.decode(String.self, forKey: .prompt)
        overlayText = try container.decode(String.self, forKey: .overlayText)
        supportingText = try container.decodeIfPresent(String.self, forKey: .supportingText) ?? ""
        ctaText = try container.decodeIfPresent(String.self, forKey: .ctaText) ?? ""
        visualGoal = try container.decodeIfPresent(String.self, forKey: .visualGoal) ?? ""
        textPosition = try container.decode(TextPosition.self, forKey: .textPosition)
        textSafeArea = try container.decodeIfPresent(String.self, forKey: .textSafeArea) ?? ""
        mainSubjectArea = try container.decodeIfPresent(String.self, forKey: .mainSubjectArea) ?? ""
        textStyle = try container.decode(SlideTextStyle.self, forKey: .textStyle)
        selectedVisualSummary = try container.decodeIfPresent(String.self, forKey: .selectedVisualSummary) ?? ""
        generationStatus = try container.decodeIfPresent(SlideGenerationStatus.self, forKey: .generationStatus) ?? .notStarted
        generationErrorMessage = try container.decodeIfPresent(String.self, forKey: .generationErrorMessage)
        promptVersion = try container.decodeIfPresent(Int.self, forKey: .promptVersion) ?? 1
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        transition = try container.decode(TransitionStyle.self, forKey: .transition)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
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
    var brief: String
    var topic: String
    var audience: String
    var goal: String
    var tone: String
    var narrativeArc: [String]
    var globalVisualMotif: String
    var planSummary: String
    var slides: [Slide]
    var caption: String
    var hashtags: [String]
    var targetPlatforms: [SocialPlatform]
    var status: SlideshowDraftStatus
    var exportedImageAssetIDs: [UUID]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        title: String,
        campaignID: UUID?,
        templateID: UUID?,
        brief: String = "",
        topic: String = "",
        audience: String = "",
        goal: String = "",
        tone: String = "",
        narrativeArc: [String] = [],
        globalVisualMotif: String = "",
        planSummary: String = "",
        slides: [Slide],
        caption: String,
        hashtags: [String],
        targetPlatforms: [SocialPlatform],
        status: SlideshowDraftStatus,
        exportedImageAssetIDs: [UUID] = [],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.campaignID = campaignID
        self.templateID = templateID
        self.brief = brief
        self.topic = topic
        self.audience = audience
        self.goal = goal
        self.tone = tone
        self.narrativeArc = narrativeArc
        self.globalVisualMotif = globalVisualMotif
        self.planSummary = planSummary
        self.slides = slides
        self.caption = caption
        self.hashtags = hashtags
        self.targetPlatforms = targetPlatforms
        self.status = status
        self.exportedImageAssetIDs = exportedImageAssetIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case campaignID
        case templateID
        case brief
        case topic
        case audience
        case goal
        case tone
        case narrativeArc
        case globalVisualMotif
        case planSummary
        case slides
        case caption
        case hashtags
        case targetPlatforms
        case status
        case exportedImageAssetIDs
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        campaignID = try container.decodeIfPresent(UUID.self, forKey: .campaignID)
        templateID = try container.decodeIfPresent(UUID.self, forKey: .templateID)
        brief = try container.decodeIfPresent(String.self, forKey: .brief) ?? ""
        topic = try container.decodeIfPresent(String.self, forKey: .topic) ?? ""
        audience = try container.decodeIfPresent(String.self, forKey: .audience) ?? ""
        goal = try container.decodeIfPresent(String.self, forKey: .goal) ?? ""
        tone = try container.decodeIfPresent(String.self, forKey: .tone) ?? ""
        narrativeArc = try container.decodeIfPresent([String].self, forKey: .narrativeArc) ?? []
        globalVisualMotif = try container.decodeIfPresent(String.self, forKey: .globalVisualMotif) ?? ""
        planSummary = try container.decodeIfPresent(String.self, forKey: .planSummary) ?? ""
        slides = try container.decode([Slide].self, forKey: .slides)
        caption = try container.decode(String.self, forKey: .caption)
        hashtags = try container.decode([String].self, forKey: .hashtags)
        targetPlatforms = try container.decode([SocialPlatform].self, forKey: .targetPlatforms)
        status = try container.decode(SlideshowDraftStatus.self, forKey: .status)
        exportedImageAssetIDs = try container.decodeIfPresent([UUID].self, forKey: .exportedImageAssetIDs) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

extension SlideshowDraft {
    var isAvailableInCreateDrafts: Bool {
        status != .published && status != .archived
    }
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
