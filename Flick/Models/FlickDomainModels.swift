//
//  FlickDomainModels.swift
//  Flick
//
//  Shared product models from FlickOverview.md.
//

import Foundation

enum SocialPlatform: String, CaseIterable, Codable, Identifiable, Hashable {
    case tiktok
    case youtubeShorts = "youtube_shorts"
    case instagram
    case threads
    case x

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiktok: "TikTok"
        case .youtubeShorts: "YouTube Shorts"
        case .instagram: "Instagram"
        case .threads: "Threads"
        case .x: "X"
        }
    }
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
    case refreshFailed
    case expired
    case notStored

    var id: String { rawValue }
}

enum AccountAuthorizationSource: String, CaseIterable, Codable, Identifiable {
    case loginKit
    case nativeOAuth
    case manualImport
    case unavailable

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

enum PublishMode: String, CaseIterable, Codable, Identifiable {
    case photoDirectPost
    case photoUploadForCompletion
    case videoDirectPost
    case videoUploadForCompletion

    var id: String { rawValue }
}

enum PublishingJobStatus: String, CaseIterable, Codable, Identifiable {
    case rendering
    case publishing
    case awaitingUserCompletion
    case published
    case failed

    var id: String { rawValue }

    var isTerminal: Bool {
        switch self {
        case .awaitingUserCompletion, .published, .failed:
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

struct PlatformAccountSelection: Identifiable, Codable, Hashable {
    var platform: SocialPlatform
    var accountID: UUID

    var id: String {
        "\(platform.rawValue)-\(accountID.uuidString)"
    }
}

extension Array where Element == PlatformAccountSelection {
    func accountID(for platform: SocialPlatform) -> UUID? {
        first { $0.platform == platform }?.accountID
    }

    func accountIDs(for platform: SocialPlatform) -> [UUID] {
        filter { $0.platform == platform }.map(\.accountID)
    }

    func contains(accountID: UUID, for platform: SocialPlatform) -> Bool {
        contains { $0.platform == platform && $0.accountID == accountID }
    }

    func normalizedUniqueSelections() -> [PlatformAccountSelection] {
        var seen = Set<String>()
        var selections: [PlatformAccountSelection] = []
        for selection in self {
            let key = selection.id
            guard seen.insert(key).inserted else { continue }
            selections.append(selection)
        }
        return selections
    }

    func normalizedOnePerPlatform() -> [PlatformAccountSelection] {
        normalizedUniqueSelections()
    }

    mutating func setAccountID(_ accountID: UUID?, for platform: SocialPlatform) {
        removeAll { $0.platform == platform }
        guard let accountID else { return }
        append(PlatformAccountSelection(platform: platform, accountID: accountID))
        self = normalizedUniqueSelections()
    }

    mutating func setAccountIDs(_ accountIDs: [UUID], for platform: SocialPlatform) {
        removeAll { $0.platform == platform }
        append(contentsOf: accountIDs.map { PlatformAccountSelection(platform: platform, accountID: $0) })
        self = normalizedUniqueSelections()
    }

    mutating func setAccountID(_ accountID: UUID, isSelected: Bool, for platform: SocialPlatform) {
        if isSelected {
            append(PlatformAccountSelection(platform: platform, accountID: accountID))
        } else {
            removeAll { $0.platform == platform && $0.accountID == accountID }
        }
        self = normalizedUniqueSelections()
    }
}

extension ConnectedAccount {
    var canPublishToTikTok: Bool {
        platform == .tiktok
            && authorizationSource == .loginKit
            && status == .connected
            && isPublishingEnabled
            && tokenStatus != .refreshFailed
            && tokenStatus != .expired
            && tokenStatus != .notStored
    }

    var canPublishToYouTubeShorts: Bool {
        platform == .youtubeShorts
            && authorizationSource == .nativeOAuth
            && status == .connected
            && isPublishingEnabled
            && tokenStatus != .refreshFailed
            && tokenStatus != .expired
            && tokenStatus != .notStored
    }
}

struct FlickProduct: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var summary: String
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
    var productIDs: [UUID]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        mediaType: AssetMediaType,
        source: AssetSource,
        localFilePath: String?,
        storageBucket: String?,
        storagePath: String?,
        publicURL: URL?,
        signedURLExpiration: Date?,
        width: Int,
        height: Int,
        duration: TimeInterval?,
        fileSize: Int64?,
        checksum: String?,
        trendTags: [TrendTag],
        productIDs: [UUID] = [],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.mediaType = mediaType
        self.source = source
        self.localFilePath = localFilePath
        self.storageBucket = storageBucket
        self.storagePath = storagePath
        self.publicURL = publicURL
        self.signedURLExpiration = signedURLExpiration
        self.width = width
        self.height = height
        self.duration = duration
        self.fileSize = fileSize
        self.checksum = checksum
        self.trendTags = trendTags
        self.productIDs = productIDs.uniqued()
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case mediaType
        case source
        case localFilePath
        case storageBucket
        case storagePath
        case publicURL
        case signedURLExpiration
        case width
        case height
        case duration
        case fileSize
        case checksum
        case trendTags
        case productIDs
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            mediaType: try container.decode(AssetMediaType.self, forKey: .mediaType),
            source: try container.decode(AssetSource.self, forKey: .source),
            localFilePath: try container.decodeIfPresent(String.self, forKey: .localFilePath),
            storageBucket: try container.decodeIfPresent(String.self, forKey: .storageBucket),
            storagePath: try container.decodeIfPresent(String.self, forKey: .storagePath),
            publicURL: try container.decodeIfPresent(URL.self, forKey: .publicURL),
            signedURLExpiration: try container.decodeIfPresent(Date.self, forKey: .signedURLExpiration),
            width: try container.decode(Int.self, forKey: .width),
            height: try container.decode(Int.self, forKey: .height),
            duration: try container.decodeIfPresent(TimeInterval.self, forKey: .duration),
            fileSize: try container.decodeIfPresent(Int64.self, forKey: .fileSize),
            checksum: try container.decodeIfPresent(String.self, forKey: .checksum),
            trendTags: try container.decode([TrendTag].self, forKey: .trendTags),
            productIDs: try container.decodeIfPresent([UUID].self, forKey: .productIDs) ?? [],
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt)
        )
    }
}

struct SlideTextStyle: Codable, Hashable {
    var fontName: String
    var weight: String
    var sizeScale: Double
    var foregroundHex: String
    var outlineColorHex: String

    init(
        fontName: String = "System",
        weight: String = "Semibold",
        sizeScale: Double = 0.7,
        foregroundHex: String = "#FFFFFF",
        outlineColorHex: String = "#000000"
    ) {
        self.fontName = fontName
        self.weight = weight
        self.sizeScale = min(max(sizeScale, 0.7), 1.5)
        self.foregroundHex = foregroundHex
        self.outlineColorHex = outlineColorHex
    }

    private enum CodingKeys: String, CodingKey {
        case fontName
        case weight
        case sizeScale
        case foregroundHex
        case outlineColorHex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontName = try container.decodeIfPresent(String.self, forKey: .fontName) ?? "System"
        weight = try container.decodeIfPresent(String.self, forKey: .weight) ?? "Semibold"
        let decodedSizeScale = try container.decodeIfPresent(Double.self, forKey: .sizeScale) ?? 0.7
        sizeScale = min(max(decodedSizeScale, 0.7), 1.5)
        foregroundHex = try container.decodeIfPresent(String.self, forKey: .foregroundHex) ?? "#FFFFFF"
        outlineColorHex = try container.decodeIfPresent(String.self, forKey: .outlineColorHex) ?? "#000000"
    }
}

struct Slide: Identifiable, Codable, Hashable {
    var id: UUID
    var index: Int
    var imageAssetID: UUID?
    var prompt: String
    var text: String
    var textPosition: TextPosition
    var textStyle: SlideTextStyle
    var selectedVisualSummary: String
    var generationStatus: SlideGenerationStatus
    var generationErrorMessage: String?
    var promptVersion: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        index: Int,
        imageAssetID: UUID?,
        prompt: String,
        text: String,
        textPosition: TextPosition,
        textStyle: SlideTextStyle,
        selectedVisualSummary: String = "",
        generationStatus: SlideGenerationStatus = .notStarted,
        generationErrorMessage: String? = nil,
        promptVersion: Int = 1,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.index = index
        self.imageAssetID = imageAssetID
        self.prompt = prompt
        self.text = text
        self.textPosition = textPosition
        self.textStyle = textStyle
        self.selectedVisualSummary = selectedVisualSummary
        self.generationStatus = generationStatus
        self.generationErrorMessage = generationErrorMessage
        self.promptVersion = promptVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case index
        case imageAssetID
        case prompt
        case text
        case textPosition
        case textStyle
        case selectedVisualSummary
        case generationStatus
        case generationErrorMessage
        case promptVersion
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        index = try container.decode(Int.self, forKey: .index)
        imageAssetID = try container.decodeIfPresent(UUID.self, forKey: .imageAssetID)
        prompt = try container.decode(String.self, forKey: .prompt)
        text = try container.decode(String.self, forKey: .text)
        textPosition = try container.decode(TextPosition.self, forKey: .textPosition)
        textStyle = try container.decode(SlideTextStyle.self, forKey: .textStyle)
        selectedVisualSummary = try container.decodeIfPresent(String.self, forKey: .selectedVisualSummary) ?? ""
        generationStatus = try container.decodeIfPresent(SlideGenerationStatus.self, forKey: .generationStatus) ?? .notStarted
        generationErrorMessage = try container.decodeIfPresent(String.self, forKey: .generationErrorMessage)
        promptVersion = try container.decodeIfPresent(Int.self, forKey: .promptVersion) ?? 1
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
    var sourceTemplateID: String? = nil
    var sourceTemplateFingerprint: String? = nil
    var analysisSchemaVersion: Int? = nil
    var tags: [TrendTag]
    var createdAt: Date
    var updatedAt: Date
}

struct SlideshowDraft: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var templateID: UUID?
    var creationModel: SlideshowCreationModelReference?
    var imageVibe: SlideshowImageVibe
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
    var accountSelections: [PlatformAccountSelection]
    var tikTokSettings: DraftTikTokSettings?
    var youtubeSettings: DraftYouTubeSettings?
    var selectedSongs: [SelectedSong]
    var status: SlideshowDraftStatus
    var exportedImageAssetIDs: [UUID]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        title: String,
        templateID: UUID?,
        creationModel: SlideshowCreationModelReference? = nil,
        imageVibe: SlideshowImageVibe = .defaultValue,
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
        accountSelections: [PlatformAccountSelection] = [],
        tikTokSettings: DraftTikTokSettings? = nil,
        youtubeSettings: DraftYouTubeSettings? = nil,
        selectedSongs: [SelectedSong] = [],
        status: SlideshowDraftStatus,
        exportedImageAssetIDs: [UUID] = [],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.templateID = templateID
        self.creationModel = creationModel
        self.imageVibe = imageVibe
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
        self.accountSelections = accountSelections.normalizedUniqueSelections()
        self.tikTokSettings = tikTokSettings
        self.youtubeSettings = youtubeSettings
        self.selectedSongs = selectedSongs
        self.status = status
        self.exportedImageAssetIDs = exportedImageAssetIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case templateID
        case creationModel
        case imageVibe
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
        case accountSelections
        case tikTokSettings
        case youtubeSettings
        case selectedSongs
        case status
        case exportedImageAssetIDs
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        templateID = try container.decodeIfPresent(UUID.self, forKey: .templateID)
        creationModel = try container.decodeIfPresent(SlideshowCreationModelReference.self, forKey: .creationModel)
        imageVibe = try container.decodeIfPresent(SlideshowImageVibe.self, forKey: .imageVibe) ?? .defaultValue
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
        accountSelections = try container.decodeIfPresent([PlatformAccountSelection].self, forKey: .accountSelections)?
            .normalizedUniqueSelections()
            ?? []
        tikTokSettings = try container.decodeIfPresent(DraftTikTokSettings.self, forKey: .tikTokSettings)
        youtubeSettings = try container.decodeIfPresent(DraftYouTubeSettings.self, forKey: .youtubeSettings)
        selectedSongs = try container.decodeIfPresent([SelectedSong].self, forKey: .selectedSongs) ?? []
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
    var automationID: UUID?
    var draftID: UUID
    var status: PublishingJobStatus
    var publishMode: PublishMode
    var attemptCount: Int
    var lastAttemptAt: Date?
    var lastError: PlatformFailure?
    var platformPublishID: String?
    var createdAt: Date
    var updatedAt: Date
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
    var automationID: UUID?
    var platformPostID: String
    var platformURL: URL?
    var publishedAt: Date
    var draftID: UUID
    var templateID: UUID?
    var trendTags: [TrendTag]
    var caption: String
    var createdAt: Date
    var updatedAt: Date
}

struct SyncHealth: Codable, Hashable {
    var iCloudAvailable: Bool
}

struct APIHealthStatus: Identifiable, Codable, Hashable {
    var id: String { serviceName }
    var serviceName: String
    var isConfigured: Bool
    var statusText: String
    var lastCheckedAt: Date?
}

struct MacRunnerHeartbeat: Codable, Hashable {
    static let staleAfter: TimeInterval = 3 * 60

    var lastSeenAt: Date?

    init(lastSeenAt: Date? = nil) {
        self.lastSeenAt = lastSeenAt
    }

    func isFresh(asOf now: Date = Date(), staleAfter: TimeInterval = Self.staleAfter) -> Bool {
        guard let lastSeenAt else { return false }
        return now.timeIntervalSince(lastSeenAt) <= staleAfter
            && lastSeenAt <= now.addingTimeInterval(staleAfter)
    }
}

struct DashboardSnapshot: Codable, Hashable {
    var failedJobCount: Int
    var activeAutomationCount: Int
    var nextAutomationPostAt: Date?
    var connectedAccounts: [ConnectedAccount]
    var syncHealth: SyncHealth
    var apiHealth: [APIHealthStatus]
}

struct FlickOverviewState: Codable, Hashable {
    var accounts: [ConnectedAccount]
    var products: [FlickProduct]
    var creationModels: [FlickCreationModel]
    var assets: [MediaAsset]
    var drafts: [SlideshowDraft]
    var templates: [CreativeTemplate]
    var automations: [ContentAutomation]
    var automationPostProgresses: [AutomationPostProgress]
    var macRunnerHeartbeat: MacRunnerHeartbeat
    var publishingJobs: [PublishingJob]
    var publishedPosts: [PublishedPost]
    var dashboard: DashboardSnapshot
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension FlickOverviewState {
    mutating func refreshDerivedState() {
        dashboard.failedJobCount = publishingJobs.filter { $0.status == .failed }.count
        dashboard.activeAutomationCount = automations.filter { $0.status == .active }.count
        dashboard.nextAutomationPostAt = automations
            .filter { $0.status == .active }
            .compactMap(\.nextScheduledAt)
            .min()
    }
}
