//
//  FlickAppModel.swift
//  Flick
//

import Foundation
import CoreData
import ImageIO
import Observation
import OSLog
import UniformTypeIdentifiers

enum MoveDirection {
    case earlier
    case later
}

enum ProductManagementError: LocalizedError {
    case missingName
    case missingProductSelection
    case unavailableProduct
    case missingMediaAsset

    var errorDescription: String? {
        switch self {
        case .missingName:
            "Add a product name first."
        case .missingProductSelection:
            "Select at least one product before uploading media."
        case .unavailableProduct:
            "One of the selected products is no longer available."
        case .missingMediaAsset:
            "That media item is no longer available."
        }
    }
}

enum CreationModelManagementError: LocalizedError {
    case missingName
    case unavailableModel

    var errorDescription: String? {
        switch self {
        case .missingName:
            "Add a model name first."
        case .unavailableModel:
            "That model is no longer available."
        }
    }
}

private struct LocalMediaMetadata {
    var width: Int
    var height: Int
    var duration: TimeInterval?
}

@MainActor
@Observable
final class FlickAppModel {
    var overview: FlickOverviewState
    var configuration: AppConfiguration
    var selectedSection: FlickSection = .dashboard
    var lastErrorMessage: String?
    var credentialMessage: String?
    var accountConnectionMessage: String?
    var connectingPlatform: SocialPlatform?
    var refreshingAccountID: UUID?
    var isR2SmokeTestRunning = false
    var r2SmokeTestResult: R2StorageSmokeTestResult?
    var r2SmokeTestErrorMessage: String?
    var activeCreateDraftID: UUID?
    var automationEditRequestID: UUID?
    var createWorkflowMessage: String?
    var isPlanningSlideshow = false
    var isGeneratingSlideshowImages = false
    var isPublishingSlideshow = false
    var isProcessingAutomations = false
    var manualPublishProgress: ManualPublishProgress?
    var pendingShareImport: ShareImportSession?
    var shareImportErrorMessage: String?

    @ObservationIgnored private let repository: FlickRepository
    @ObservationIgnored private let credentialVault = CredentialVault()
    @ObservationIgnored private let loginKitAccountStore = LoginKitAccountStore()
    @ObservationIgnored private let tiktokLoginKitClient: TikTokLoginKitClient
    @ObservationIgnored private let youtubeOAuthClient: YouTubeOAuthClient
    @ObservationIgnored private let localMediaLibrary = LocalMediaLibrary(directoryName: "ProductMedia")
    @ObservationIgnored private let generatedImageLibrary = LocalMediaLibrary(directoryName: "GeneratedImages")
    @ObservationIgnored private let templateImportMediaLibrary = LocalMediaLibrary(directoryName: "TemplateImports")
    @ObservationIgnored private let shareImportService = ShareImportService()
    @ObservationIgnored private let publishedPostNotificationPublisher: any PublishedPostNotificationPublishing
    @ObservationIgnored private let openAIClientFactory: @MainActor ([String: String]) -> OpenAIClient
    @ObservationIgnored private let mediaStorageFactory: @MainActor ([String: String]) -> any MediaStorageProviding
    @ObservationIgnored private let templateAnalysisStorageFactory: @MainActor ([String: String]) -> any TemplateAnalysisStorageProviding
    @ObservationIgnored private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.orion.Flick", category: "Publishing")
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var isRefreshPending = false
    @ObservationIgnored private var tikTokStatusRefreshCooldownsByJobID: [UUID: Date] = [:]
    @ObservationIgnored private var tikTokStatusRefreshCooldownsByAccountID: [UUID: Date] = [:]
    @ObservationIgnored private var tikTokNextPublishAllowedAtByAccountID: [UUID: Date] = [:]
    @ObservationIgnored private let tikTokPendingInboxStatusRefreshInterval: TimeInterval = 15 * 60
    @ObservationIgnored private let tikTokStatusRateLimitCooldown: TimeInterval = 15 * 60
    @ObservationIgnored private let tikTokPublishRequestSpacing: TimeInterval = 12

    init(
        repository: FlickRepository,
        configuration: AppConfiguration,
        publishedPostNotificationPublisher: (any PublishedPostNotificationPublishing)? = nil,
        tiktokLoginKitClient: TikTokLoginKitClient? = nil,
        youtubeOAuthClient: YouTubeOAuthClient? = nil,
        openAIClientFactory: @escaping @MainActor ([String: String]) -> OpenAIClient = { OpenAIClient(credentials: $0) },
        mediaStorageFactory: @escaping @MainActor ([String: String]) -> any MediaStorageProviding = { R2StorageService(credentials: $0) },
        templateAnalysisStorageFactory: @escaping @MainActor ([String: String]) -> any TemplateAnalysisStorageProviding = { R2StorageService(credentials: $0) }
    ) {
        self.repository = repository
        self.configuration = configuration
        self.publishedPostNotificationPublisher = publishedPostNotificationPublisher ?? CloudKitPublishedPostNotificationPublisher.live
        self.tiktokLoginKitClient = tiktokLoginKitClient ?? TikTokLoginKitClient()
        self.youtubeOAuthClient = youtubeOAuthClient ?? YouTubeOAuthClient()
        self.openAIClientFactory = openAIClientFactory
        self.mediaStorageFactory = mediaStorageFactory
        self.templateAnalysisStorageFactory = templateAnalysisStorageFactory
        self.overview = FlickEmptyState.make()
        applyConnectedAccounts()
        applyCredentialHealth()
    }

    static func live() -> FlickAppModel {
        FlickAppModel(repository: EmptyFlickRepository(), configuration: .current)
    }

    static func live(persistenceController: PersistenceController) -> FlickAppModel {
        FlickAppModel(
            repository: CoreDataFlickRepository(context: persistenceController.container.viewContext),
            configuration: .current
        )
    }

    var canManageAccounts: Bool {
        AccountManagementPolicy.canAuthorizeAccountsOnThisDevice
    }

    func canConnectAccount(platform: SocialPlatform) -> Bool {
        AccountManagementPolicy.canAuthorize(platform)
    }

    var accountManagementUnavailableTitle: String {
        AccountManagementPolicy.unavailableTitle
    }

    var accountManagementUnavailableMessage: String {
        AccountManagementPolicy.unavailableMessage
    }

    var productMediaAssets: [MediaAsset] {
        overview.assets.filter { asset in
            asset.source == .uploaded && (asset.mediaType == .image || asset.mediaType == .video)
        }
    }

    func productMediaAssets(for productIDs: Set<UUID>) -> [MediaAsset] {
        guard !productIDs.isEmpty else { return [] }

        return productMediaAssets.filter { asset in
            !Set(asset.productIDs).isDisjoint(with: productIDs)
        }
    }

    var createDrafts: [SlideshowDraft] {
        overview.drafts.filter(\.isAvailableInCreateDrafts)
    }

    var activeAutomations: [ContentAutomation] {
        overview.automations.filter { $0.status == .active }
    }

    var activeCreateDraft: SlideshowDraft? {
        guard let activeCreateDraftID else { return nil }
        return createDrafts.first { $0.id == activeCreateDraftID }
    }

    func refresh() async {
        guard !isRefreshing else {
            isRefreshPending = true
            return
        }

        isRefreshing = true
        defer {
            isRefreshing = false
        }

        repeat {
            isRefreshPending = false
            await performRefresh()
        } while isRefreshPending
    }

    private func performRefresh() async {

        do {
            overview = try await repository.loadOverview()
            configuration = .current
            let didReconcileMediaURLs = reconcileStoredMediaPublicURLs()
            let didReconcileLoginKitTokens = reconcileLoginKitAccountTokenStatus()
            let didReconcileAutomationProductImages = reconcileAutomationProductImageSelections()
            applyConnectedAccounts()
            applyCredentialHealth()
            overview.refreshDerivedState()
            let publishedPostIDsBeforeDerivedUpdates = currentPublishedPostIDs()
            let didUpdateTikTokStatuses = await refreshTikTokPublishStatuses()
            let didReconcilePublishedPosts = reconcilePublishedPostsFromCompletedJobs()
            clearActiveCreateDraftIfUnavailable()
            let didPruneProgresses = pruneAutomationPostProgresses()
            if didReconcileMediaURLs
                || didReconcileLoginKitTokens
                || reconcileCompletedSlideImages()
                || didUpdateTikTokStatuses
                || didReconcilePublishedPosts
                || didReconcileAutomationProductImages
                || didPruneProgresses
            {
                overview.refreshDerivedState()
                try await repository.saveOverview(overview)
                await publishNotificationsForNewPosts(since: publishedPostIDsBeforeDerivedUpdates)
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func refreshOnCloudKitStoreChanges() async {
        let notifications = NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange)

        for await _ in notifications {
            await refresh()
        }
    }

    func selectCreateDraft(id: UUID) {
        guard createDrafts.contains(where: { $0.id == id }) else { return }
        activeCreateDraftID = id
        selectedSection = .create
    }

    func clearActiveCreateDraft() {
        activeCreateDraftID = nil
    }

    func requestAutomationEdit(id automationID: UUID) {
        automationEditRequestID = automationID
        selectedSection = .create
    }

    func clearAutomationEditRequest(id automationID: UUID) {
        guard automationEditRequestID == automationID else { return }
        automationEditRequestID = nil
    }

    func deleteCreateDraft(id draftID: UUID) async {
        guard
            let draftIndex = overview.drafts.firstIndex(where: { $0.id == draftID }),
            overview.drafts[draftIndex].isAvailableInCreateDrafts
        else {
            return
        }

        let previousOverview = overview
        let previousActiveCreateDraftID = activeCreateDraftID
        let deletedDraft = overview.drafts.remove(at: draftIndex)

        if activeCreateDraftID == draftID {
            activeCreateDraftID = nil
        }
        removeDraftOwnedMediaAssets(referencedBy: deletedDraft)

        do {
            try await repository.saveOverview(overview)
            lastErrorMessage = nil
        } catch {
            overview = previousOverview
            activeCreateDraftID = previousActiveCreateDraftID
            lastErrorMessage = error.localizedDescription
        }
    }

    private func clearActiveCreateDraftIfUnavailable() {
        guard activeCreateDraftID != nil, activeCreateDraft == nil else { return }
        activeCreateDraftID = nil
    }

    private func removeDraftOwnedMediaAssets(referencedBy deletedDraft: SlideshowDraft) {
        let deletedAssetIDs = deletedDraft.referencedAssetIDs
        guard !deletedAssetIDs.isEmpty else { return }

        let retainedAssetIDs = overview.drafts.reduce(into: Set<UUID>()) { result, draft in
            result.formUnion(draft.referencedAssetIDs)
        }

        overview.assets.removeAll { asset in
            deletedAssetIDs.contains(asset.id)
                && !retainedAssetIDs.contains(asset.id)
                && asset.source != .uploaded
        }
    }

    func connectAccount(platform: SocialPlatform) async {
        guard connectingPlatform == nil else { return }
        guard canManageAccounts else {
            accountConnectionMessage = accountManagementUnavailableMessage
            lastErrorMessage = nil
            return
        }

        connectingPlatform = platform
        accountConnectionMessage = nil
        lastErrorMessage = nil

        defer {
            connectingPlatform = nil
        }

        do {
            switch platform {
            case .tiktok:
                let account = try await tiktokLoginKitClient.authorize(configuration: configuration.tiktok)
                try await upsertConnectedAccount(account)
                accountConnectionMessage = "Connected \(account.displayName)."
            case .youtubeShorts:
                let account = try await youtubeOAuthClient.authorize(configuration: configuration.youtube)
                try await upsertConnectedAccount(account)
                accountConnectionMessage = "Connected \(account.displayName)."
            case .instagram, .threads, .x:
                throw PlatformAdapterError.futurePlatform(platform)
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func refreshAccountAuthorization(accountID: UUID) async {
        guard refreshingAccountID == nil else { return }
        guard let account = overview.accounts.first(where: { $0.id == accountID }) else { return }

        refreshingAccountID = accountID
        accountConnectionMessage = nil
        lastErrorMessage = nil

        defer {
            refreshingAccountID = nil
        }

        do {
            let refreshedAccount = try await refreshedAuthorizationAccount(for: account)
            try await upsertConnectedAccount(refreshedAccount)
            accountConnectionMessage = "Refreshed \(refreshedAccount.displayName)."
        } catch {
            let didMarkAccountUnavailable = markAccountTokenUnavailableIfNeeded(
                error,
                accountID: account.id,
                platform: account.platform
            )
            if didMarkAccountUnavailable {
                do {
                    overview.refreshDerivedState()
                    try await repository.saveOverview(overview)
                } catch {
                    lastErrorMessage = error.localizedDescription
                    return
                }
            }
            lastErrorMessage = error.localizedDescription
        }
    }

    private func refreshedAuthorizationAccount(for account: ConnectedAccount) async throws -> ConnectedAccount {
        switch account.platform {
        case .tiktok:
            let adapter = TikTokAdapter(configuration: configuration.tiktok)
            let bundle = try await adapter.validTokenBundle(for: account, forceRefresh: true)
            let scopes = bundle.scopes.isEmpty ? account.scopes : bundle.scopes
            return try await tiktokLoginKitClient.refreshAuthorizedAccount(
                accessToken: bundle.accessToken,
                scopes: scopes
            )
        case .youtubeShorts:
            let adapter = YouTubeShortsAdapter(configuration: configuration.youtube)
            let bundle = try await adapter.validTokenBundle(for: account, forceRefresh: true)
            let scopes = bundle.scopes.isEmpty ? account.scopes : bundle.scopes
            return try await youtubeOAuthClient.refreshAuthorizedAccount(
                accessToken: bundle.accessToken,
                scopes: scopes
            )
        case .instagram, .threads, .x:
            throw PlatformAdapterError.futurePlatform(account.platform)
        }
    }

    func upsertConnectedAccount(_ account: ConnectedAccount) async throws {
        var syncedAccount = account
        syncedAccount.updatedAt = Date()
        let previousAccounts = overview.accounts

        if let existingIndex = overview.accounts.firstIndex(where: { $0.id == syncedAccount.id }) {
            syncedAccount.createdAt = overview.accounts[existingIndex].createdAt
            overview.accounts[existingIndex] = syncedAccount
        } else {
            overview.accounts.append(syncedAccount)
        }
        applyConnectedAccounts()

        do {
            try await repository.upsertConnectedAccount(syncedAccount)
            lastErrorMessage = nil
        } catch {
            overview.accounts = previousAccounts
            applyConnectedAccounts()
            throw error
        }
    }

    func deleteConnectedAccount(id accountID: UUID) async throws {
        guard let accountIndex = overview.accounts.firstIndex(where: { $0.id == accountID }) else { return }

        let removedAccount = overview.accounts.remove(at: accountIndex)
        applyConnectedAccounts()

        do {
            try await repository.deleteConnectedAccount(id: accountID)
            if removedAccount.authorizationSource == .loginKit {
                try? loginKitAccountStore.deleteAccount(id: accountID)
                try? tiktokLoginKitClient.tokenStore.deleteTokenBundle(for: removedAccount)
            }
            if removedAccount.authorizationSource == .nativeOAuth {
                try? youtubeOAuthClient.tokenStore.deleteTokenBundle(for: removedAccount)
            }
            lastErrorMessage = nil
        } catch {
            overview.accounts.insert(removedAccount, at: min(accountIndex, overview.accounts.count))
            applyConnectedAccounts()
            throw error
        }
    }

    func duplicateDraft(_ draft: SlideshowDraft) {
        let now = Date()
        var copy = draft
        copy.id = UUID()
        copy.title = "\(draft.title) remix"
        copy.slides = draft.slides.map { slide in
            var copiedSlide = slide
            copiedSlide.id = UUID()
            copiedSlide.createdAt = now
            copiedSlide.updatedAt = now
            return copiedSlide
        }
        copy.status = .draft
        copy.createdAt = now
        copy.updatedAt = now
        overview.drafts.insert(copy, at: 0)
        activeCreateDraftID = copy.id
        selectedSection = .create
        Task { @MainActor in
            do {
                try await repository.saveOverview(overview)
                lastErrorMessage = nil
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    func createDraft(from template: ExampleSlideshowTemplate) {
        let now = Date()
        let templateID = UUID()
        let mediaAssets = template.slides.map { slide in
            MediaAsset(
                id: UUID(),
                mediaType: .image,
                source: .reference,
                localFilePath: slide.remoteURL == nil ? slide.localURL.path : nil,
                storageBucket: nil,
                storagePath: nil,
                publicURL: slide.remoteURL,
                signedURLExpiration: nil,
                width: 0,
                height: 0,
                duration: nil,
                fileSize: slide.remoteURL == nil ? fileSize(at: slide.localURL) : nil,
                checksum: nil,
                trendTags: [],
                createdAt: now,
                updatedAt: now
            )
        }

        let slides = zip(template.slides, mediaAssets).enumerated().map { offset, pair in
            let sourceSlide = pair.0
            let asset = pair.1
            return Slide(
                id: UUID(),
                index: offset,
                imageAssetID: asset.id,
                prompt: "Use slide \(sourceSlide.index) from @\(template.profile) as the visual reference.",
                text: "Slide \(offset + 1)",
                textPosition: .center,
                textStyle: SlideTextStyle(),
                createdAt: now,
                updatedAt: now
            )
        }

        let creativeTemplate = CreativeTemplate(
            id: templateID,
            name: "\(template.niche) template from @\(template.profile)",
            description: template.subtitle,
            platform: .tiktok,
            slideCount: template.slideCount,
            styleJSON: "{\"source\":\"ReelFarm\",\"templateID\":\"\(template.id)\"}",
            defaultTextRules: "Use the saved example slides as visual structure references.",
            tags: [],
            createdAt: now,
            updatedAt: now
        )

        let draft = SlideshowDraft(
            id: UUID(),
            title: "\(template.niche) template - @\(template.profile)",
            templateID: templateID,
            slides: slides,
            caption: "Draft based on @\(template.profile)'s \(template.niche.lowercased()) slideshow format.",
            hashtags: templateHashtags(for: template),
            targetPlatforms: [.tiktok, .youtubeShorts],
            youtubeSettings: DraftYouTubeSettings(),
            status: .draft,
            createdAt: now,
            updatedAt: now
        )

        overview.assets.append(contentsOf: mediaAssets)
        overview.templates.insert(creativeTemplate, at: 0)
        overview.drafts.insert(draft, at: 0)
        activeCreateDraftID = draft.id
        selectedSection = .create
    }

    func canHandleShareImportURL(_ url: URL) -> Bool {
        ShareImportService.importID(from: url) != nil
    }

    func handleShareImportURL(_ url: URL) async {
        guard let importID = ShareImportService.importID(from: url) else {
            shareImportErrorMessage = ShareImportError.invalidURL.localizedDescription
            return
        }

        await loadShareImport(id: importID)
    }

    func loadPendingShareImportIfNeeded() async {
        guard pendingShareImport == nil else { return }

        do {
            if let session = try shareImportService.loadMostRecentImport() {
                pendingShareImport = session
                selectedSection = .create
                shareImportErrorMessage = nil
            }
        } catch {
            shareImportErrorMessage = error.localizedDescription
        }
    }

    func discardPendingShareImport() {
        guard let pendingShareImport else { return }

        do {
            try shareImportService.discardImport(id: pendingShareImport.id)
            self.pendingShareImport = nil
            shareImportErrorMessage = nil
        } catch {
            shareImportErrorMessage = error.localizedDescription
        }
    }

    func createTemplateFromPendingShareImport(
        title: String,
        niche: String,
        openMode: ShareImportOpenMode
    ) async -> ShareTemplateImportResult? {
        guard let pendingShareImport else { return nil }

        do {
            let result = try await createTemplate(
                from: pendingShareImport,
                title: title,
                niche: niche,
                openMode: openMode
            )
            try? shareImportService.discardImport(id: pendingShareImport.id)
            self.pendingShareImport = nil
            shareImportErrorMessage = nil
            return result
        } catch {
            shareImportErrorMessage = error.localizedDescription
            return nil
        }
    }

    func localAutomationTemplates() -> [ExampleSlideshowTemplate] {
        let assetsByID = Dictionary(uniqueKeysWithValues: overview.assets.map { ($0.id, $0) })
        let drafts = overview.drafts.sorted { $0.updatedAt > $1.updatedAt }

        return overview.templates.compactMap { template in
            guard
                template.sourceTemplateID?.hasPrefix("share-import:") == true,
                let draft = drafts.first(where: { draft in
                    draft.templateID == template.id && draftHasImportedTemplateSlides(draft, assetsByID: assetsByID)
                })
            else {
                return nil
            }
            return localAutomationTemplate(from: template, draft: draft, assetsByID: assetsByID)
        }
        .filter(\.hasDisplayablePreview)
    }

    private func loadShareImport(id importID: UUID) async {
        do {
            pendingShareImport = try shareImportService.loadImport(id: importID)
            selectedSection = .create
            shareImportErrorMessage = nil
        } catch {
            shareImportErrorMessage = error.localizedDescription
        }
    }

    private func createTemplate(
        from session: ShareImportSession,
        title: String,
        niche: String,
        openMode: ShareImportOpenMode
    ) async throws -> ShareTemplateImportResult {
        let now = Date()
        let normalizedNiche = normalizedShareImportNiche(niche)
        let normalizedTitle = normalizedShareImportTitle(title, niche: normalizedNiche)
        let templateID = UUID()

        let importedMedia = try session.images.enumerated().map { offset, image in
            let storedMedia = try templateImportMediaLibrary.store(fileURL: image.fileURL, contentType: image.contentType)
            let metadata = localMediaMetadata(for: storedMedia)
            let assetID = UUID()
            let asset = MediaAsset(
                id: assetID,
                mediaType: AssetMediaType(contentType: storedMedia.contentType),
                source: .uploaded,
                localFilePath: storedMedia.fileURL.path,
                storageBucket: nil,
                storagePath: nil,
                publicURL: nil,
                signedURLExpiration: nil,
                width: metadata.width,
                height: metadata.height,
                duration: metadata.duration,
                fileSize: storedMedia.fileSize,
                checksum: nil,
                trendTags: [],
                createdAt: now,
                updatedAt: now
            )
            let slide = Slide(
                id: UUID(),
                index: offset,
                imageAssetID: assetID,
                prompt: "Imported photo \(offset + 1) from the iOS share sheet.",
                text: "",
                textPosition: .center,
                textStyle: SlideTextStyle(),
                selectedVisualSummary: "Imported photo \(offset + 1).",
                generationStatus: .complete,
                generationErrorMessage: nil,
                promptVersion: 1,
                createdAt: now,
                updatedAt: now
            )
            return (asset, slide)
        }

        let assets = importedMedia.map(\.0)
        let slides = importedMedia.map(\.1)
        guard !slides.isEmpty else {
            throw ShareImportError.emptyImport
        }

        let styleGuide = shareImportedStyleGuide(title: normalizedTitle, niche: normalizedNiche)
        let creativeTemplate = CreativeTemplate(
            id: templateID,
            name: normalizedTitle,
            description: "\(normalizedNiche) template imported from Photos.",
            platform: .tiktok,
            slideCount: slides.count,
            styleJSON: styleGuide.encodedJSONString(),
            defaultTextRules: "Imported photos are ready-to-use slide visuals. Add or edit text overlays in Create.",
            sourceTemplateID: "share-import:\(session.id.uuidString)",
            sourceTemplateFingerprint: nil,
            analysisSchemaVersion: nil,
            tags: shareImportTags(niche: normalizedNiche, now: now),
            createdAt: now,
            updatedAt: now
        )

        let draft = SlideshowDraft(
            id: UUID(),
            title: normalizedTitle,
            templateID: templateID,
            imageVibe: .defaultValue,
            brief: "",
            topic: normalizedNiche,
            audience: "",
            goal: "",
            tone: "",
            narrativeArc: [],
            globalVisualMotif: "",
            planSummary: "Imported \(slides.count) photos from the share sheet as a reusable \(normalizedNiche) template.",
            slides: slides,
            caption: "",
            hashtags: shareImportHashtags(niche: normalizedNiche),
            targetPlatforms: [.tiktok, .youtubeShorts],
            accountSelections: [],
            tikTokSettings: DraftTikTokSettings(title: normalizedTitle, postAsDraft: true),
            youtubeSettings: DraftYouTubeSettings(title: normalizedTitle),
            status: .draft,
            createdAt: now,
            updatedAt: now
        )

        let previousOverview = overview
        let previousActiveCreateDraftID = activeCreateDraftID
        overview.assets.insert(contentsOf: assets, at: 0)
        overview.templates.insert(creativeTemplate, at: 0)
        overview.drafts.insert(draft, at: 0)
        activeCreateDraftID = draft.id
        selectedSection = .create

        do {
            try await repository.saveOverview(overview)
            lastErrorMessage = nil
        } catch {
            overview = previousOverview
            activeCreateDraftID = previousActiveCreateDraftID
            throw error
        }

        return ShareTemplateImportResult(
            templateID: templateID,
            draftID: draft.id,
            automationTemplateID: LocalAutomationTemplateIdentifier.id(for: templateID),
            openMode: openMode
        )
    }

    func deleteLocalAnalysis(for template: ExampleSlideshowTemplate) async {
        let fingerprint = TemplateAnalysisCacheService.fingerprint(for: template)
        let originalCount = overview.templates.count
        overview.templates.removeAll {
            $0.sourceTemplateID == template.id
                && $0.sourceTemplateFingerprint == fingerprint
                && $0.analysisSchemaVersion == TemplateAnalysisCacheService.schemaVersion
        }

        guard overview.templates.count != originalCount else { return }

        do {
            try await repository.saveOverview(overview)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func createProduct(name: String, summary: String) async throws -> FlickProduct {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw ProductManagementError.missingName
        }

        let now = Date()
        let product = FlickProduct(
            id: UUID(),
            name: normalizedName,
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: now,
            updatedAt: now
        )

        overview.products.insert(product, at: 0)
        do {
            try await repository.upsertProduct(product)
            lastErrorMessage = nil
            return product
        } catch {
            overview.products.removeAll { $0.id == product.id }
            throw error
        }
    }

    func createCreationModel(name: String) async throws -> FlickCreationModel {
        try await createCreationModel(name: name, metadata: CreationModelMetadata())
    }

    func createCreationModel(name: String, metadata: CreationModelMetadata) async throws -> FlickCreationModel {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw CreationModelManagementError.missingName
        }

        let now = Date()
        let creationModel = FlickCreationModel(
            name: normalizedName,
            metadata: metadata,
            createdAt: now,
            updatedAt: now
        )

        overview.creationModels.insert(creationModel, at: 0)
        do {
            try await repository.saveOverview(overview)
            lastErrorMessage = nil
            return creationModel
        } catch {
            overview.creationModels.removeAll { $0.id == creationModel.id }
            throw error
        }
    }

    func updateCreationModel(_ creationModel: FlickCreationModel) async throws {
        guard let existingIndex = overview.creationModels.firstIndex(where: { $0.id == creationModel.id }) else {
            throw CreationModelManagementError.unavailableModel
        }

        let normalizedName = creationModel.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw CreationModelManagementError.missingName
        }

        let previousOverview = overview
        var updatedModel = creationModel
        updatedModel.name = normalizedName
        updatedModel.createdAt = overview.creationModels[existingIndex].createdAt
        updatedModel.updatedAt = Date()
        overview.creationModels.removeAll { $0.id == updatedModel.id }
        overview.creationModels.insert(updatedModel, at: 0)

        do {
            try await repository.saveOverview(overview)
            lastErrorMessage = nil
        } catch {
            overview = previousOverview
            throw error
        }
    }

    func deleteCreationModel(id modelID: UUID) async throws {
        guard overview.creationModels.contains(where: { $0.id == modelID }) else { return }

        let previousOverview = overview
        overview.creationModels.removeAll { $0.id == modelID }

        do {
            try await repository.saveOverview(overview)
            lastErrorMessage = nil
        } catch {
            overview = previousOverview
            throw error
        }
    }

    func deleteProduct(id productID: UUID) async throws {
        guard overview.products.contains(where: { $0.id == productID }) else { return }

        let previousOverview = overview
        let now = Date()
        overview.products.removeAll { $0.id == productID }
        overview.assets = overview.assets.compactMap { asset in
            guard asset.productIDs.contains(productID) else { return asset }

            let retainedProductIDs = asset.productIDs.filter { $0 != productID }
            guard !retainedProductIDs.isEmpty else { return nil }

            var updatedAsset = asset
            updatedAsset.productIDs = retainedProductIDs
            updatedAsset.updatedAt = now
            return updatedAsset
        }
        if reconcileAutomationProductImageSelections(now: now) {
            overview.refreshDerivedState()
        }

        do {
            try await repository.saveOverview(overview)
            lastErrorMessage = nil
        } catch {
            overview = previousOverview
            throw error
        }
    }

    func addProductMedia(data: Data, contentType: UTType, productIDs: Set<UUID>) async throws {
        let storedMedia = try localMediaLibrary.store(data: data, contentType: contentType)
        try await addProductMedia(storedMedia, productIDs: productIDs)
    }

    func addProductMedia(fileURL: URL, contentType: UTType, productIDs: Set<UUID>) async throws {
        let storedMedia = try localMediaLibrary.store(fileURL: fileURL, contentType: contentType)
        try await addProductMedia(storedMedia, productIDs: productIDs)
    }

    private func addProductMedia(_ storedMedia: StoredLocalMedia, productIDs: Set<UUID>) async throws {
        let resolvedProductIDs = try validateProductIDs(productIDs)
        let mediaMetadata = localMediaMetadata(for: storedMedia)
        let now = Date()
        let assetID = UUID()
        let objectPath = productMediaStoragePath(
            productIDs: resolvedProductIDs,
            assetID: assetID,
            contentType: storedMedia.contentType,
            fileURL: storedMedia.fileURL
        )
        let data = try Data(contentsOf: storedMedia.fileURL)
        let remote = try await mediaStorageFactory(credentialVault.loadValues())
            .uploadAsset(
                LocalMediaAsset(
                    data: data,
                    contentType: storedMedia.contentType.preferredMIMEType ?? "application/octet-stream"
                ),
                path: objectPath
            )
        let asset = MediaAsset(
            id: assetID,
            mediaType: AssetMediaType(contentType: storedMedia.contentType),
            source: .uploaded,
            localFilePath: storedMedia.fileURL.path,
            storageBucket: remote.storageBucket,
            storagePath: remote.storagePath,
            publicURL: remote.publicURL,
            signedURLExpiration: remote.signedURLExpiration,
            width: mediaMetadata.width,
            height: mediaMetadata.height,
            duration: mediaMetadata.duration,
            fileSize: storedMedia.fileSize,
            checksum: nil,
            trendTags: [],
            productIDs: resolvedProductIDs,
            createdAt: now,
            updatedAt: now
        )

        overview.assets.insert(asset, at: 0)
        do {
            try await repository.upsertAsset(asset)
            lastErrorMessage = nil
        } catch {
            overview.assets.removeAll { $0.id == asset.id }
            throw error
        }
    }

    private func localMediaMetadata(for storedMedia: StoredLocalMedia) -> LocalMediaMetadata {
        if storedMedia.contentType.conforms(to: .image), let dimensions = imageDimensions(at: storedMedia.fileURL) {
            return LocalMediaMetadata(width: dimensions.width, height: dimensions.height, duration: nil)
        }

        return LocalMediaMetadata(width: 0, height: 0, duration: nil)
    }

    private func imageDimensions(at fileURL: URL) -> (width: Int, height: Int)? {
        guard
            let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
            let width = mediaDimensionValue(properties[kCGImagePropertyPixelWidth]),
            let height = mediaDimensionValue(properties[kCGImagePropertyPixelHeight])
        else {
            return nil
        }

        return (width, height)
    }

    private func mediaDimensionValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let intValue = value as? Int {
            return intValue
        }
        return nil
    }

    func updateProductMediaProducts(assetID: UUID, productIDs: Set<UUID>) async throws {
        let resolvedProductIDs = try validateProductIDs(productIDs)
        guard let assetIndex = overview.assets.firstIndex(where: { $0.id == assetID }) else {
            throw ProductManagementError.missingMediaAsset
        }

        let previousOverview = overview
        let now = Date()
        overview.assets[assetIndex].productIDs = resolvedProductIDs
        overview.assets[assetIndex].updatedAt = now
        if reconcileAutomationProductImageSelections(now: now) {
            overview.refreshDerivedState()
        }

        do {
            try await repository.saveOverview(overview)
            lastErrorMessage = nil
        } catch {
            overview = previousOverview
            throw error
        }
    }

    func removeProductMedia(_ asset: MediaAsset) async throws {
        guard let index = overview.assets.firstIndex(where: { $0.id == asset.id }) else { return }
        let previousOverview = overview
        overview.assets.remove(at: index)
        if reconcileAutomationProductImageSelections() {
            overview.refreshDerivedState()
        }

        do {
            try await repository.saveOverview(overview)
            lastErrorMessage = nil
        } catch {
            overview = previousOverview
            throw error
        }
    }

    @discardableResult
    private func reconcileAutomationProductImageSelections(now: Date = Date()) -> Bool {
        let productsByID = Dictionary(uniqueKeysWithValues: overview.products.map { ($0.id, $0) })
        let assetsByID = Dictionary(uniqueKeysWithValues: overview.assets.map { ($0.id, $0) })
        var didChange = false

        for index in overview.automations.indices {
            guard let productID = overview.automations[index].productID else {
                continue
            }

            guard let product = productsByID[productID] else {
                if overview.automations[index].productID != nil || !overview.automations[index].productImageAssetIDs.isEmpty {
                    overview.automations[index].productID = nil
                    overview.automations[index].productImageAssetIDs = []
                    overview.automations[index].updatedAt = now
                    didChange = true
                }
                if pauseAutomationForProductImageChange(
                    at: index,
                    message: "The selected product was deleted. Choose a new product and images before reactivating this automation.",
                    now: now
                ) {
                    didChange = true
                }
                continue
            }

            let validImageAssetIDs = overview.automations[index].productImageAssetIDs.filter { assetID in
                guard let asset = assetsByID[assetID] else { return false }
                return asset.mediaType == .image && asset.productIDs.contains(productID)
            }

            if validImageAssetIDs != overview.automations[index].productImageAssetIDs {
                overview.automations[index].productImageAssetIDs = validImageAssetIDs
                overview.automations[index].updatedAt = now
                didChange = true
            }

            if validImageAssetIDs.isEmpty {
                if pauseAutomationForProductImageChange(
                    at: index,
                    message: "All selected product images were removed from \(product.name). Choose at least one product image before reactivating this automation.",
                    now: now
                ) {
                    didChange = true
                }
            }
        }

        return didChange
    }

    private func pauseAutomationForProductImageChange(at index: Int, message: String, now: Date) -> Bool {
        guard overview.automations[index].status != .paused
            || overview.automations[index].nextScheduledAt != nil
            || overview.automations[index].lastErrorMessage != message
        else {
            return false
        }

        overview.automations[index].status = .paused
        overview.automations[index].nextScheduledAt = nil
        overview.automations[index].lastErrorMessage = message
        overview.automations[index].updatedAt = now
        return true
    }

    private func validateProductIDs(_ productIDs: Set<UUID>) throws -> [UUID] {
        guard !productIDs.isEmpty else {
            throw ProductManagementError.missingProductSelection
        }

        let availableProductIDs = Set(overview.products.map(\.id))
        guard productIDs.isSubset(of: availableProductIDs) else {
            throw ProductManagementError.unavailableProduct
        }

        return overview.products.map(\.id).filter { productIDs.contains($0) }
    }

    func persistCreateState() async {
        do {
            overview.refreshDerivedState()
            try await repository.saveOverview(overview)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func upsertAutomation(_ automation: ContentAutomation) async -> Bool {
        var automation = automation
        let now = Date()
        automation.updatedAt = now
        if automation.nextScheduledAt == nil {
            automation.nextScheduledAt = automation.nextOccurrence(after: now)
        }

        let previousOverview = overview
        let isEditingExistingAutomation: Bool
        if let existingIndex = overview.automations.firstIndex(where: { $0.id == automation.id }) {
            isEditingExistingAutomation = true
            automation.createdAt = overview.automations[existingIndex].createdAt
            overview.automations[existingIndex] = automation
        } else {
            isEditingExistingAutomation = false
            overview.automations.insert(automation, at: 0)
        }
        overview.refreshDerivedState()

        do {
            try await repository.saveOverview(overview)
            createWorkflowMessage = isEditingExistingAutomation ? "Automation updated." : "Automation started."
            lastErrorMessage = nil
            return true
        } catch {
            overview = previousOverview
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    func deleteAutomation(id automationID: UUID) async {
        guard overview.automations.contains(where: { $0.id == automationID }) else { return }

        let previousOverview = overview
        overview.automations.removeAll { $0.id == automationID }
        overview.refreshDerivedState()

        do {
            try await repository.saveOverview(overview)
            lastErrorMessage = nil
        } catch {
            overview = previousOverview
            lastErrorMessage = error.localizedDescription
        }
    }

    func updateAutomationStatus(id automationID: UUID, status: ContentAutomationStatus) async {
        guard let index = overview.automations.firstIndex(where: { $0.id == automationID }) else { return }
        guard overview.automations[index].status != status else { return }

        let previousOverview = overview
        let now = Date()
        overview.automations[index].status = status
        overview.automations[index].nextScheduledAt = status == .active
            ? overview.automations[index].nextOccurrence(after: now)
            : nil
        overview.automations[index].updatedAt = now
        overview.refreshDerivedState()

        do {
            try await repository.saveOverview(overview)
            lastErrorMessage = nil
        } catch {
            overview = previousOverview
            lastErrorMessage = error.localizedDescription
        }
    }

    func runAutomationNow(id automationID: UUID) async {
        guard !isProcessingAutomations else { return }
        guard let automation = overview.automations.first(where: { $0.id == automationID }) else { return }

        isProcessingAutomations = true
        defer {
            isProcessingAutomations = false
        }

        let now = Date()
        let preservedNextScheduledAt = automation.nextScheduledAt

        do {
            try await publishAutomationInstance(automation, scheduledAt: now)
            markAutomationManualRun(automationID, succeededAt: now, preservingNextScheduledAt: preservedNextScheduledAt)
            createWorkflowMessage = "Automation run completed."
        } catch {
            markAutomationManualRun(automationID, failedAt: now, error: error, preservingNextScheduledAt: preservedNextScheduledAt)
        }

        do {
            overview.refreshDerivedState()
            try await repository.saveOverview(overview)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func processDueAutomations(now: Date = Date()) async {
        guard !isProcessingAutomations else { return }
        isProcessingAutomations = true
        defer {
            isProcessingAutomations = false
        }

        let dueAutomationIDs = overview.automations.compactMap { automation -> UUID? in
            guard automation.status == .active else { return nil }
            guard let nextScheduledAt = automation.nextScheduledAt else { return nil }
            return nextScheduledAt <= now ? automation.id : nil
        }

        for automationID in dueAutomationIDs {
            await processDueAutomation(id: automationID, now: now)
        }
    }

    private func processDueAutomation(id automationID: UUID, now: Date) async {
        guard let automation = overview.automations.first(where: { $0.id == automationID }) else { return }
        let scheduledAt = automation.nextScheduledAt ?? now

        do {
            try await publishAutomationInstance(automation, scheduledAt: scheduledAt)
            markAutomation(automationID, succeededAt: now)
        } catch {
            markAutomation(automationID, failedAt: now, error: error)
        }

        do {
            overview.refreshDerivedState()
            try await repository.saveOverview(overview)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func runAutomationWorkerLoop(interval: Duration = .seconds(60)) async {
        while !Task.isCancelled {
            await processDueAutomations()
            try? await Task.sleep(for: interval)
        }
    }

    func runMacRunnerHeartbeatLoop(interval: Duration = .seconds(60)) async {
        while !Task.isCancelled {
            await recordMacRunnerHeartbeat()
            try? await Task.sleep(for: interval)
        }
    }

    func recordMacRunnerHeartbeat(now: Date = Date()) async {
        let heartbeat = MacRunnerHeartbeat(lastSeenAt: now)
        overview.macRunnerHeartbeat = heartbeat

        do {
            try await repository.saveMacRunnerHeartbeat(heartbeat)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func runTikTokPublishStatusRefreshLoop(interval: Duration = .seconds(60)) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            await refreshAndPersistTikTokPublishStatuses()
        }
    }

    func createAISlideshow(
        brief: String,
        from template: ExampleSlideshowTemplate,
        creationModel: SlideshowCreationModelReference? = nil,
        productImage: SlideshowProductImage? = nil,
        imageVibe: SlideshowImageVibe = .defaultValue
    ) async {
        guard !isPlanningSlideshow else { return }

        let normalizedBrief = brief.trimmingCharacters(in: .whitespacesAndNewlines)
        let planningBrief = normalizedBrief.isEmpty ? templateAnalysisBrief(for: template) : normalizedBrief

        reloadCredentialConfiguration()
        isPlanningSlideshow = true
        createWorkflowMessage = "Creating template style guide..."
        lastErrorMessage = nil

        defer {
            isPlanningSlideshow = false
        }

        do {
            let result = try await createAISlideshowResult(
                brief: planningBrief,
                template: template,
                creationModel: creationModel,
                productImage: productImage,
                imageVibe: imageVibe
            )
            if result.shouldInsertCreativeTemplate {
                overview.templates.insert(result.creativeTemplate, at: 0)
            }
            overview.drafts.insert(result.draft, at: 0)
            activeCreateDraftID = result.draft.id
            try await repository.saveOverview(overview)
            createWorkflowMessage = "Plan ready. Generate slide images when the text and prompts look right."
            lastErrorMessage = nil
        } catch {
            createWorkflowMessage = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    func rewritePrompt(for slideID: UUID, in draftID: UUID, instruction: String) async {
        let normalizedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedInstruction.isEmpty else {
            lastErrorMessage = "Add a prompt rewrite instruction first."
            return
        }

        do {
            let openAIClient = makeOpenAIClient()
            guard
                let draftIndex = overview.drafts.firstIndex(where: { $0.id == draftID }),
                let slideIndex = overview.drafts[draftIndex].slides.firstIndex(where: { $0.id == slideID })
            else {
                throw SlideshowCreationError.missingDraft
            }

            let draft = overview.drafts[draftIndex]
            let slide = draft.slides[slideIndex]
            let styleGuide = try styleGuide(for: draft)
            let previousSummary = previousVisualSummary(before: slideIndex, in: draft)
            let rewrite = try await SlideshowPlannerService(client: openAIClient).rewritePrompt(
                draft: draft,
                slide: slide,
                styleGuide: styleGuide,
                previousVisualSummary: previousSummary,
                instruction: normalizedInstruction,
                imageVibe: draft.imageVibe
            )

            let now = Date()
            overview.drafts[draftIndex].slides[slideIndex].prompt = rewrite.imagePrompt
            overview.drafts[draftIndex].slides[slideIndex].selectedVisualSummary = rewrite.selectedVisualSummary
            overview.drafts[draftIndex].slides[slideIndex].promptVersion += 1
            overview.drafts[draftIndex].slides[slideIndex].updatedAt = now
            overview.drafts[draftIndex].updatedAt = now
            try await repository.saveOverview(overview)
            createWorkflowMessage = "Updated slide \(slide.index + 1) prompt."
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func generateMissingSlideImages(for draftID: UUID, automationProgressID: UUID? = nil) async {
        await generateSlideImages(for: draftID, replacingExisting: false, automationProgressID: automationProgressID)
    }

    func regenerateSlideImages(for draftID: UUID) async {
        await generateSlideImages(for: draftID, replacingExisting: true, automationProgressID: nil)
    }

    private func generateSlideImages(
        for draftID: UUID,
        replacingExisting: Bool,
        automationProgressID: UUID?
    ) async {
        guard !isGeneratingSlideshowImages else { return }
        isGeneratingSlideshowImages = true
        defer {
            isGeneratingSlideshowImages = false
        }

        do {
            guard let draftIndex = overview.drafts.firstIndex(where: { $0.id == draftID }) else {
                throw SlideshowCreationError.missingDraft
            }

            let assetsByID = Dictionary(uniqueKeysWithValues: overview.assets.map { ($0.id, $0) })
            let slideIDs = overview.drafts[draftIndex].slides
                .sorted { $0.index < $1.index }
                .filter { slide in
                    if slideUsesAvailableUploadedImage(slide, assetsByID: assetsByID) {
                        return false
                    }
                    guard !replacingExisting else { return true }
                    guard let imageAssetID = slide.imageAssetID else { return true }
                    return assetsByID[imageAssetID]?.hasAvailableMediaLocation != true
                }
                .map(\.id)

            let totalImageCount = slideIDs.count
            for (offset, slideID) in slideIDs.enumerated() {
                let imageNumber = offset + 1
                createWorkflowMessage = totalImageCount == 1
                    ? "Generating slide image..."
                    : "Generating slide image \(imageNumber) of \(totalImageCount)..."
                await startAutomationPostProgressStep(
                    automationProgressID,
                    AutomationPostProgressStepID.generateImages,
                    detail: "Generating image \(imageNumber) of \(totalImageCount).",
                    imageProgress: AutomationStepImageProgress(
                        completedImageCount: offset,
                        totalImageCount: totalImageCount,
                        currentImageIndex: imageNumber
                    )
                )

                try await generateImage(
                    for: slideID,
                    in: draftID,
                    instruction: nil,
                    settings: .draft,
                    retryHandler: { [weak self] event in
                        await self?.startAutomationPostProgressStep(
                            automationProgressID,
                            AutomationPostProgressStepID.generateImages,
                            detail: "Retrying image \(imageNumber) of \(totalImageCount).",
                            imageProgress: AutomationStepImageProgress(
                                completedImageCount: offset,
                                totalImageCount: totalImageCount,
                                currentImageIndex: imageNumber,
                                attemptDetail: "Attempt \(event.nextAttempt) of \(event.maxAttempts) after \(event.reason)."
                            )
                        )
                    }
                )

                let completedImageCount = offset + 1
                await startAutomationPostProgressStep(
                    automationProgressID,
                    AutomationPostProgressStepID.generateImages,
                    detail: "\(completedImageCount) of \(totalImageCount) images created.",
                    imageProgress: AutomationStepImageProgress(
                        completedImageCount: completedImageCount,
                        totalImageCount: totalImageCount,
                        currentImageIndex: completedImageCount < totalImageCount ? completedImageCount + 1 : nil
                    )
                )
            }

            if replacingExisting {
                createWorkflowMessage = slideIDs.isEmpty ? "No slides to regenerate." : "Regenerated \(slideIDs.count) slide images."
            } else {
                createWorkflowMessage = slideIDs.isEmpty ? "All slides already have generated images." : "Generated \(slideIDs.count) slide images."
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func regenerateSlideImage(slideID: UUID, in draftID: UUID, instruction: String) async {
        guard !isGeneratingSlideshowImages else { return }
        guard !slideUsesAvailableUploadedImage(slideID: slideID, draftID: draftID) else {
            createWorkflowMessage = "This slide uses a selected product image."
            lastErrorMessage = nil
            return
        }
        isGeneratingSlideshowImages = true
        defer {
            isGeneratingSlideshowImages = false
        }

        do {
            try await generateImage(
                for: slideID,
                in: draftID,
                instruction: instruction.trimmingCharacters(in: .whitespacesAndNewlines),
                settings: .draft
            )
            createWorkflowMessage = "Regenerated slide image."
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func beginManualPublishProgress(for draft: SlideshowDraft) {
        manualPublishProgress = ManualPublishProgress.make(for: draft)
        logPublish("Manual publish progress opened draftID=\(draft.id.uuidString) slideCount=\(draft.slides.count)")
    }

    @discardableResult
    func publishManualSlideshow(
        draftID: UUID,
        settings: TikTokManualPublishSettings,
        automationID: UUID? = nil,
        automationProgressID: UUID? = nil
    ) async -> Bool {
        guard !isPublishingSlideshow else { return false }
        isPublishingSlideshow = true
        createWorkflowMessage = "Preparing publish images..."
        lastErrorMessage = nil
        var activeJobID: UUID?

        defer {
            isPublishingSlideshow = false
        }

        do {
            let now = Date()
            guard let draft = overview.drafts.first(where: { $0.id == draftID }) else {
                throw SlideshowCreationError.missingDraft
            }
            if manualPublishProgress == nil || manualPublishProgress?.isFinished == true {
                beginManualPublishProgress(for: draft)
            }
            startPublishStep(ManualPublishProgressStepID.validate, detail: "Checking account, media, and TikTok options.")
            reconcileLoginKitAccountTokenStatus()
            guard let account = publishingTikTokAccount(for: draft) else {
                throw ManualPublishError.missingTikTokAccount
            }
            completePublishStep(ManualPublishProgressStepID.validate, detail: "Ready to publish with \(account.displayName).")

            startPublishStep(ManualPublishProgressStepID.createJob, detail: "Recording this manual publish attempt.")
            var job = PublishingJob(
                id: UUID(),
                platform: .tiktok,
                accountID: account.id,
                automationID: automationID,
                draftID: draftID,
                status: .rendering,
                publishMode: settings.publishMode,
                attemptCount: 1,
                lastAttemptAt: now,
                lastError: nil,
                platformPublishID: nil,
                createdAt: now,
                updatedAt: now
            )
            activeJobID = job.id
            overview.publishingJobs.insert(job, at: 0)
            try await repository.saveOverview(overview)
            completePublishStep(ManualPublishProgressStepID.createJob, detail: "Publish job \(job.id.uuidString.prefix(8)) created.")

            logPublish("Manual TikTok publish started draftID=\(draftID.uuidString) jobID=\(job.id.uuidString) mode=\(settings.publishMode.rawValue)")
            let renderedAssetIDs = try await renderImageSequenceForPublish(
                for: draftID,
                automationProgressID: automationProgressID
            )
            reconcileStoredMediaPublicURLs()

            guard let refreshedDraftIndex = overview.drafts.firstIndex(where: { $0.id == draftID }) else {
                throw SlideshowCreationError.missingDraft
            }
            let refreshedDraft = overview.drafts[refreshedDraftIndex]
            let renderedAssetsByID = Dictionary(uniqueKeysWithValues: overview.assets.map { ($0.id, $0) })
            let imageURLs = renderedAssetIDs.compactMap { renderedAssetsByID[$0]?.publicURL }
            guard imageURLs.count == renderedAssetIDs.count, !imageURLs.isEmpty else {
                throw ManualPublishError.missingPublishableImageURLs
            }

            updatePublishingJob(job.id, status: .publishing)
            job.status = .publishing
            job.updatedAt = Date()
            createWorkflowMessage = "Posting to TikTok..."
            await startAutomationPostProgressStep(
                automationProgressID,
                AutomationPostProgressStepID.publishTikTok,
                detail: "Sending \(imageURLs.count) rendered images to TikTok."
            )
            startPublishStep(ManualPublishProgressStepID.publishTikTok, detail: "Sending \(imageURLs.count) rendered images to TikTok.")
            let media = PreparedPlatformMedia(
                mode: settings.publishMode,
                imageURLs: imageURLs,
                videoURL: nil,
                warnings: []
            )
            let adapter = TikTokAdapter(configuration: configuration.tiktok)
            try await waitForTikTokPublishRequestWindow(accountID: account.id)
            reserveTikTokPublishRequestWindow(accountID: account.id)
            let result = try await adapter.publish(job, account: account, media: media, settings: settings)
            let publishStepDetail = settings.postAsDraft
                ? tikTokDraftUploadDetail(for: result)
                : "TikTok publish ID \(result.platformPostID)."
            completePublishStep(ManualPublishProgressStepID.publishTikTok, detail: publishStepDetail)
            await completeAutomationPostProgressStep(
                automationProgressID,
                AutomationPostProgressStepID.publishTikTok,
                detail: publishStepDetail
            )

            let recordStepDetail = settings.postAsDraft
                ? "Saving the TikTok inbox upload status."
                : "Saving the final publish status."
            await startAutomationPostProgressStep(
                automationProgressID,
                AutomationPostProgressStepID.recordResult,
                detail: recordStepDetail
            )
            startPublishStep(ManualPublishProgressStepID.recordResult, detail: recordStepDetail)
            let publishedPostIDsBeforeRecording = currentPublishedPostIDs()
            if settings.postAsDraft {
                completeDraftUploadJob(job.id, result: result)
            } else {
                completePublishingJob(job.id, result: result, draft: refreshedDraft)
            }
            overview.refreshDerivedState()
            try await repository.saveOverview(overview)
            await publishNotificationsForNewPosts(since: publishedPostIDsBeforeRecording)
            if settings.postAsDraft {
                await publishDraftUploadNotificationIfNeeded(jobID: job.id, result: result)
            }
            let recordCompletionDetail = settings.postAsDraft
                ? "TikTok draft saved. Open TikTok's inbox notification to edit, save, or post."
                : "Publish status saved."
            completePublishStep(ManualPublishProgressStepID.recordResult, detail: recordCompletionDetail)
            await completeAutomationPostProgressStep(
                automationProgressID,
                AutomationPostProgressStepID.recordResult,
                detail: recordCompletionDetail
            )
            finishManualPublishProgress()
            createWorkflowMessage = settings.postAsDraft ? "TikTok draft sent. Open TikTok's inbox notification to finish." : "Published to TikTok."
            lastErrorMessage = nil
            logPublish("Manual TikTok publish completed jobID=\(job.id.uuidString) publishID=\(result.platformPostID)")
            return true
        } catch {
            if let activeJobID {
                if
                    isTikTokRateLimit(error),
                    let accountID = overview.publishingJobs.first(where: { $0.id == activeJobID })?.accountID
                {
                    deferTikTokPublishRequests(
                        forAccountID: accountID,
                        until: Date().addingTimeInterval(tikTokStatusRateLimitCooldown)
                    )
                }
                if let accountID = overview.publishingJobs.first(where: { $0.id == activeJobID })?.accountID {
                    markTikTokAccountTokenUnavailableIfNeeded(error, accountID: accountID)
                }
                failPublishingJob(activeJobID, error: error)
                try? await repository.saveOverview(overview)
            }
            createWorkflowMessage = nil
            lastErrorMessage = error.localizedDescription
            failCurrentPublishStep(error)
            finishManualPublishProgress(errorMessage: error.localizedDescription)
            logPublish("Manual TikTok publish failed draftID=\(draftID.uuidString) \(publishErrorDiagnostics(for: error))")
            return false
        }
    }

    @discardableResult
    func publishManualSlideshow(
        draftID: UUID,
        tikTokSettings: TikTokManualPublishSettings?,
        youtubeSettings: YouTubeManualPublishSettings?,
        automationID: UUID? = nil,
        automationProgressID: UUID? = nil
    ) async -> Bool {
        guard !isPublishingSlideshow else { return false }
        isPublishingSlideshow = true
        createWorkflowMessage = "Preparing publish media..."
        lastErrorMessage = nil
        var activeJobIDs: [UUID] = []

        defer {
            isPublishingSlideshow = false
        }

        do {
            let now = Date()
            guard let draft = overview.drafts.first(where: { $0.id == draftID }) else {
                throw SlideshowCreationError.missingDraft
            }
            if manualPublishProgress == nil || manualPublishProgress?.isFinished == true {
                beginManualPublishProgress(for: draft)
            }

            startPublishStep(ManualPublishProgressStepID.validate, detail: "Checking selected accounts and platform settings.")
            let tikTokAccountIDs = tikTokSettings == nil ? [] : draft.accountSelections.accountIDs(for: .tiktok)
            let youtubeAccountIDs = youtubeSettings == nil ? [] : draft.accountSelections.accountIDs(for: .youtubeShorts)
            guard !tikTokAccountIDs.isEmpty || !youtubeAccountIDs.isEmpty else {
                throw ManualPublishError.missingPlatformAccounts
            }
            completePublishStep(ManualPublishProgressStepID.validate, detail: "Ready for \(tikTokAccountIDs.count + youtubeAccountIDs.count) selected account(s).")

            startPublishStep(ManualPublishProgressStepID.createJob, detail: "Recording publish attempts for selected accounts.")
            var jobs: [PublishingJob] = []
            if let tikTokSettings {
                jobs.append(contentsOf: tikTokAccountIDs.map { accountID in
                    PublishingJob(
                        id: UUID(),
                        platform: .tiktok,
                        accountID: accountID,
                        automationID: automationID,
                        draftID: draftID,
                        status: .rendering,
                        publishMode: tikTokSettings.publishMode,
                        attemptCount: 1,
                        lastAttemptAt: now,
                        lastError: nil,
                        platformPublishID: nil,
                        createdAt: now,
                        updatedAt: now
                    )
                })
            }
            if let youtubeSettings {
                jobs.append(contentsOf: youtubeAccountIDs.map { accountID in
                    PublishingJob(
                        id: UUID(),
                        platform: .youtubeShorts,
                        accountID: accountID,
                        automationID: automationID,
                        draftID: draftID,
                        status: .rendering,
                        publishMode: youtubeSettings.publishMode,
                        attemptCount: 1,
                        lastAttemptAt: now,
                        lastError: nil,
                        platformPublishID: nil,
                        createdAt: now,
                        updatedAt: now
                    )
                })
            }
            activeJobIDs = jobs.map(\.id)
            overview.publishingJobs.insert(contentsOf: jobs, at: 0)
            try await repository.saveOverview(overview)
            completePublishStep(ManualPublishProgressStepID.createJob, detail: "Created \(jobs.count) publish job(s).")

            var tikTokMedia: PreparedPlatformMedia?
            if tikTokSettings != nil, !tikTokAccountIDs.isEmpty {
                let renderedAssetIDs = try await renderImageSequenceForPublish(
                    for: draftID,
                    automationProgressID: automationProgressID
                )
                reconcileStoredMediaPublicURLs()
                let renderedAssetsByID = Dictionary(uniqueKeysWithValues: overview.assets.map { ($0.id, $0) })
                let imageURLs = renderedAssetIDs.compactMap { renderedAssetsByID[$0]?.publicURL }
                guard imageURLs.count == renderedAssetIDs.count, !imageURLs.isEmpty else {
                    throw ManualPublishError.missingPublishableImageURLs
                }
                tikTokMedia = PreparedPlatformMedia(
                    mode: tikTokSettings?.publishMode ?? .photoDirectPost,
                    imageURLs: imageURLs,
                    videoURL: nil,
                    warnings: []
                )
            }

            var youtubeMedia: PreparedPlatformMedia?
            if youtubeSettings != nil, !youtubeAccountIDs.isEmpty {
                let renderedVideo = try await renderYouTubeShortsVideoForPublish(
                    for: draftID,
                    automationProgressID: automationProgressID
                )
                youtubeMedia = PreparedPlatformMedia(
                    mode: .videoDirectPost,
                    imageURLs: [],
                    videoURL: renderedVideo.fileURL,
                    warnings: []
                )
            }

            guard let refreshedDraft = overview.drafts.first(where: { $0.id == draftID }) else {
                throw SlideshowCreationError.missingDraft
            }

            let publishedPostIDsBeforeRecording = currentPublishedPostIDs()
            startPublishStep(ManualPublishProgressStepID.publishTikTok, detail: "Posting to selected platforms.")
            await startAutomationPostProgressStep(
                automationProgressID,
                AutomationPostProgressStepID.publishTikTok,
                detail: "Posting to \(jobs.count) selected account(s)."
            )

            var successfulJobCount = 0
            var lastFailure: Error?
            let accountsByID = Dictionary(uniqueKeysWithValues: overview.accounts.map { ($0.id, $0) })
            let tikTokAdapter = TikTokAdapter(configuration: configuration.tiktok)
            let youtubeAdapter = YouTubeShortsAdapter(configuration: configuration.youtube)

            for job in jobs {
                updatePublishingJob(job.id, status: .publishing)
                do {
                    guard let account = accountsByID[job.accountID] else {
                        throw ManualPublishError.missingPlatformAccounts
                    }
                    guard canPublish(account, on: job.platform) else {
                        switch job.platform {
                        case .tiktok:
                            throw ManualPublishError.missingTikTokAccount
                        case .youtubeShorts:
                            throw YouTubeOAuthError.missingStoredToken(accountID: account.id, platformUserID: account.platformUserID)
                        case .instagram, .threads, .x:
                            throw PlatformAdapterError.futurePlatform(job.platform)
                        }
                    }

                    switch job.platform {
                    case .tiktok:
                        guard let tikTokSettings, let tikTokMedia else {
                            throw ManualPublishError.missingTikTokAccount
                        }
                        try await waitForTikTokPublishRequestWindow(accountID: account.id)
                        reserveTikTokPublishRequestWindow(accountID: account.id)
                        let result = try await tikTokAdapter.publish(job, account: account, media: tikTokMedia, settings: tikTokSettings)
                        if tikTokSettings.postAsDraft {
                            completeDraftUploadJob(job.id, result: result)
                            await publishDraftUploadNotificationIfNeeded(jobID: job.id, result: result)
                        } else {
                            completePublishingJob(job.id, result: result, draft: refreshedDraft)
                        }
                    case .youtubeShorts:
                        guard let youtubeSettings, let youtubeMedia else {
                            throw ManualPublishError.missingYouTubeAccount
                        }
                        let result = try await youtubeAdapter.publish(job, account: account, media: youtubeMedia, settings: youtubeSettings)
                        completePublishingJob(job.id, result: result, draft: refreshedDraft)
                    case .instagram, .threads, .x:
                        throw PlatformAdapterError.futurePlatform(job.platform)
                    }
                    successfulJobCount += 1
                    try await repository.saveOverview(overview)
                } catch {
                    lastFailure = error
                    if job.platform == .tiktok {
                        if isTikTokRateLimit(error) {
                            deferTikTokPublishRequests(
                                forAccountID: job.accountID,
                                until: Date().addingTimeInterval(tikTokStatusRateLimitCooldown)
                            )
                        }
                        markTikTokAccountTokenUnavailableIfNeeded(error, accountID: job.accountID)
                    }
                    failPublishingJob(job.id, error: error)
                    try? await repository.saveOverview(overview)
                }
            }

            guard successfulJobCount > 0 else {
                throw lastFailure ?? ManualPublishError.missingPlatformAccounts
            }

            completePublishStep(ManualPublishProgressStepID.publishTikTok, detail: "Published \(successfulJobCount) of \(jobs.count) account job(s).")
            await completeAutomationPostProgressStep(
                automationProgressID,
                AutomationPostProgressStepID.publishTikTok,
                detail: "Published \(successfulJobCount) of \(jobs.count) selected account job(s)."
            )

            startPublishStep(ManualPublishProgressStepID.recordResult, detail: "Saving publish results.")
            await startAutomationPostProgressStep(
                automationProgressID,
                AutomationPostProgressStepID.recordResult,
                detail: "Saving publish results for every device."
            )
            overview.refreshDerivedState()
            try await repository.saveOverview(overview)
            await publishNotificationsForNewPosts(since: publishedPostIDsBeforeRecording)
            completePublishStep(ManualPublishProgressStepID.recordResult, detail: "Publish results saved.")
            await completeAutomationPostProgressStep(
                automationProgressID,
                AutomationPostProgressStepID.recordResult,
                detail: "Publish results saved."
            )
            finishManualPublishProgress()
            createWorkflowMessage = successfulJobCount == jobs.count
                ? "Published to selected platforms."
                : "Published to \(successfulJobCount) of \(jobs.count) selected account(s)."
            lastErrorMessage = successfulJobCount == jobs.count ? nil : lastFailure?.localizedDescription
            return true
        } catch {
            for jobID in activeJobIDs {
                if overview.publishingJobs.first(where: { $0.id == jobID })?.status.isTerminal == false {
                    failPublishingJob(jobID, error: error)
                }
            }
            try? await repository.saveOverview(overview)
            createWorkflowMessage = nil
            lastErrorMessage = error.localizedDescription
            failCurrentPublishStep(error)
            finishManualPublishProgress(errorMessage: error.localizedDescription)
            return false
        }
    }

    func duplicateSlide(_ slideID: UUID, in draftID: UUID) {
        guard
            let draftIndex = overview.drafts.firstIndex(where: { $0.id == draftID }),
            let slideIndex = overview.drafts[draftIndex].slides.firstIndex(where: { $0.id == slideID })
        else {
            return
        }

        let now = Date()
        var copy = overview.drafts[draftIndex].slides[slideIndex]
        copy.id = UUID()
        copy.index = slideIndex + 1
        copy.imageAssetID = nil
        copy.generationStatus = .notStarted
        copy.generationErrorMessage = nil
        copy.createdAt = now
        copy.updatedAt = now
        overview.drafts[draftIndex].slides.insert(copy, at: slideIndex + 1)
        reindexSlides(in: draftIndex)
    }

    func deleteSlide(_ slideID: UUID, in draftID: UUID) {
        guard let draftIndex = overview.drafts.firstIndex(where: { $0.id == draftID }) else { return }
        overview.drafts[draftIndex].slides.removeAll { $0.id == slideID }
        reindexSlides(in: draftIndex)
    }

    func moveSlide(_ slideID: UUID, in draftID: UUID, direction: MoveDirection) {
        guard
            let draftIndex = overview.drafts.firstIndex(where: { $0.id == draftID }),
            let currentIndex = overview.drafts[draftIndex].slides.firstIndex(where: { $0.id == slideID })
        else {
            return
        }

        let destinationIndex: Int
        switch direction {
        case .earlier:
            destinationIndex = max(0, currentIndex - 1)
        case .later:
            destinationIndex = min(overview.drafts[draftIndex].slides.count - 1, currentIndex + 1)
        }

        guard destinationIndex != currentIndex else { return }
        let slide = overview.drafts[draftIndex].slides.remove(at: currentIndex)
        overview.drafts[draftIndex].slides.insert(slide, at: destinationIndex)
        reindexSlides(in: draftIndex)
    }

    func secureCredentialValues() -> [String: String] {
        credentialVault.loadValues()
    }

    @discardableResult
    func storeCredentialValue(_ value: String, for key: String) -> Bool {
        do {
            try credentialVault.storeValue(value, for: key)
            reloadCredentialConfiguration()
            credentialMessage = "Updated \(CredentialDefinition.definition(for: key)?.name ?? key)."
            lastErrorMessage = nil
            return true
        } catch {
            credentialMessage = nil
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func deleteStoredCredential(for key: String) -> Bool {
        do {
            try credentialVault.deleteValue(for: key)
            reloadCredentialConfiguration()
            credentialMessage = "Deleted \(CredentialDefinition.definition(for: key)?.name ?? key)."
            lastErrorMessage = nil
            return true
        } catch {
            credentialMessage = nil
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func clearStoredCredentials() -> Bool {
        do {
            try credentialVault.clearStoredCredentials()
            reloadCredentialConfiguration()
            credentialMessage = "Cleared stored credentials."
            lastErrorMessage = nil
            return true
        } catch {
            credentialMessage = nil
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    func runR2SmokeTest() async {
        guard !isR2SmokeTestRunning else { return }
        reloadCredentialConfiguration()
        isR2SmokeTestRunning = true
        r2SmokeTestResult = nil
        r2SmokeTestErrorMessage = nil
        credentialMessage = "Testing Cloudflare R2..."
        lastErrorMessage = nil

        defer {
            isR2SmokeTestRunning = false
        }

        do {
            let result = try await R2StorageService().runSmokeTest(
                requiredPrefixes: configuration.storagePaths.all
            )
            r2SmokeTestResult = result
            r2SmokeTestErrorMessage = nil
            credentialMessage = result.summary
            logger.info("Cloudflare R2 smoke test: \(result.summary, privacy: .public)")
            print("[R2SmokeTest] \(result.summary)")
            print("[R2SmokeTest] Object: \(result.bucket)/\(result.path)")
            print("[R2SmokeTest] Prefix placeholders: \(result.ensuredPrefixPaths.joined(separator: ", "))")
            print("[R2SmokeTest] \(result.diagnosticMessages.joined(separator: " | "))")
            lastErrorMessage = nil
        } catch {
            let message = error.localizedDescription
            r2SmokeTestErrorMessage = message
            credentialMessage = "Cloudflare R2 smoke test failed."
            logger.error("Cloudflare R2 smoke test failed: \(message, privacy: .public)")
            print("[R2SmokeTest] Failed: \(message)")
            lastErrorMessage = message
        }
    }

    private func applyConnectedAccounts() {
        overview.accounts = sortedConnectedAccounts(overview.accounts)
        overview.dashboard.connectedAccounts = overview.accounts
    }

    @discardableResult
    func reconcileStoredMediaPublicURLs(now: Date = Date()) -> Bool {
        guard let bucket = configuration.r2.bucket else { return false }
        let storage = mediaStorageFactory(credentialVault.loadValues())
        var didChange = false

        for index in overview.assets.indices {
            guard
                overview.assets[index].storageBucket == bucket,
                let storagePath = overview.assets[index].storagePath
            else {
                continue
            }

            guard let publicURL = try? storage.publicURL(path: storagePath) else {
                continue
            }

            if overview.assets[index].publicURL != publicURL {
                overview.assets[index].publicURL = publicURL
                overview.assets[index].updatedAt = now
                didChange = true
            }
        }

        return didChange
    }

    @discardableResult
    func reconcileLoginKitAccountTokenStatus(now: Date = Date()) -> Bool {
        var didChange = false

        for index in overview.accounts.indices {
            let account = overview.accounts[index]
            guard account.platform == .tiktok, account.authorizationSource == .loginKit else {
                continue
            }

            let bundle: LoginKitTokenBundle?
            do {
                bundle = try tiktokLoginKitClient.tokenStore.tokenBundle(for: account)
            } catch {
                continue
            }

            guard let bundle else {
                continue
            }

            if bundle.refreshTokenExpiresAt <= now {
                didChange = markTikTokAccountTokenUnavailable(
                    accountID: account.id,
                    tokenStatus: .expired,
                    now: now
                ) || didChange
                continue
            }

            if account.tokenStatus == .refreshFailed, bundle.updatedAt <= account.updatedAt {
                didChange = markTikTokAccountTokenUnavailable(
                    accountID: account.id,
                    tokenStatus: .refreshFailed,
                    now: now
                ) || didChange
                continue
            }

            var updatedAccount = account
            updatedAccount.tokenStatus = bundle.accessTokenExpiresAt <= now.addingTimeInterval(60) ? .expiresSoon : .valid
            updatedAccount.status = account.scopes.contains("user.info.basic") ? .connected : .missingScope
            updatedAccount.isPublishingEnabled = updatedAccount.status == .connected
                && account.scopes.contains { $0 == "video.publish" || $0 == "video.upload" }

            if updatedAccount != account {
                updatedAccount.updatedAt = now
                overview.accounts[index] = updatedAccount
                didChange = true
            }
        }

        return didChange
    }

    @discardableResult
    private func markTikTokAccountTokenUnavailableIfNeeded(_ error: Error, accountID: UUID, now: Date = Date()) -> Bool {
        guard let tokenError = error as? TikTokOAuthTokenError else { return false }

        switch tokenError {
        case .missingStoredToken:
            return markAccountTokenUnavailable(accountID: accountID, tokenStatus: .notStored, now: now)
        case .refreshTokenExpired:
            return markAccountTokenUnavailable(accountID: accountID, tokenStatus: .expired, now: now)
        case .keychainReadFailed, .refreshNotConfigured, .refreshRequestFailed:
            logger.error("TikTok account token refresh unavailable accountID=\(accountID.uuidString, privacy: .public) details=\(tokenError.diagnosticDescription, privacy: .public)")
            print("[TikTokPublishing] Account token refresh unavailable accountID=\(accountID.uuidString) details=\(tokenError.diagnosticDescription)")
            return markAccountTokenUnavailable(accountID: accountID, tokenStatus: .refreshFailed, now: now)
        }
    }

    @discardableResult
    private func markYouTubeAccountTokenUnavailableIfNeeded(_ error: Error, accountID: UUID, now: Date = Date()) -> Bool {
        guard let tokenError = error as? YouTubeOAuthError else { return false }

        switch tokenError {
        case .missingStoredToken:
            return markAccountTokenUnavailable(accountID: accountID, tokenStatus: .notStored, now: now)
        case .refreshTokenExpired:
            return markAccountTokenUnavailable(accountID: accountID, tokenStatus: .expired, now: now)
        case .keychainReadFailed, .refreshRequestFailed:
            logger.error("YouTube account token refresh unavailable accountID=\(accountID.uuidString, privacy: .public) details=\(tokenError.diagnosticDescription, privacy: .public)")
            print("[YouTubePublishing] Account token refresh unavailable accountID=\(accountID.uuidString) details=\(tokenError.diagnosticDescription)")
            return markAccountTokenUnavailable(accountID: accountID, tokenStatus: .refreshFailed, now: now)
        case .notConfigured, .tokenExchangeFailed, .channelRequestFailed:
            return markAccountTokenUnavailable(accountID: accountID, tokenStatus: .refreshFailed, now: now)
        case .authorizationUnavailableOnThisPlatform,
             .authorizationCanceled,
             .authorizationFailedMessage,
             .stateMismatch,
             .missingAuthorizationCode,
             .missingRefreshToken:
            return false
        }
    }

    @discardableResult
    private func markAccountTokenUnavailableIfNeeded(
        _ error: Error,
        accountID: UUID,
        platform: SocialPlatform,
        now: Date = Date()
    ) -> Bool {
        switch platform {
        case .tiktok:
            return markTikTokAccountTokenUnavailableIfNeeded(error, accountID: accountID, now: now)
        case .youtubeShorts:
            return markYouTubeAccountTokenUnavailableIfNeeded(error, accountID: accountID, now: now)
        case .instagram, .threads, .x:
            return false
        }
    }

    @discardableResult
    private func markTikTokAccountTokenUnavailable(
        accountID: UUID,
        tokenStatus: OAuthTokenStatus,
        now: Date = Date()
    ) -> Bool {
        markAccountTokenUnavailable(accountID: accountID, tokenStatus: tokenStatus, now: now)
    }

    @discardableResult
    private func markAccountTokenUnavailable(
        accountID: UUID,
        tokenStatus: OAuthTokenStatus,
        now: Date = Date()
    ) -> Bool {
        guard let index = overview.accounts.firstIndex(where: { $0.id == accountID }) else { return false }

        var account = overview.accounts[index]
        guard
            account.tokenStatus != tokenStatus
                || account.status != .needsAuth
                || account.isPublishingEnabled
        else {
            return false
        }

        account.tokenStatus = tokenStatus
        account.status = .needsAuth
        account.isPublishingEnabled = false
        account.updatedAt = now
        overview.accounts[index] = account
        applyConnectedAccounts()
        return true
    }

    private func sortedConnectedAccounts(_ accounts: [ConnectedAccount]) -> [ConnectedAccount] {
        accounts.sorted {
            if $0.platform.rawValue == $1.platform.rawValue {
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            return $0.platform.displayName < $1.platform.displayName
        }
    }

    func selectedAccount(for platform: SocialPlatform, in selections: [PlatformAccountSelection]) -> ConnectedAccount? {
        guard let accountID = selections.accountID(for: platform) else { return nil }
        return overview.accounts.first { $0.id == accountID && $0.platform == platform }
    }

    func selectedAccounts(for platform: SocialPlatform, in selections: [PlatformAccountSelection]) -> [ConnectedAccount] {
        let accountIDs = selections.accountIDs(for: platform)
        guard !accountIDs.isEmpty else { return [] }
        return accountIDs.compactMap { accountID in
            overview.accounts.first { $0.id == accountID && $0.platform == platform }
        }
    }

    func selectedAccountCount(for platform: SocialPlatform, in selections: [PlatformAccountSelection]) -> Int {
        selections.accountIDs(for: platform).count
    }

    func canPublish(_ account: ConnectedAccount, on platform: SocialPlatform) -> Bool {
        switch platform {
        case .tiktok:
            guard
                account.platform == .tiktok,
                account.authorizationSource == .loginKit,
                account.status == .connected,
                account.isPublishingEnabled,
                account.tokenStatus != .refreshFailed,
                account.tokenStatus != .expired
            else {
                return false
            }
            guard let bundle = try? tiktokLoginKitClient.tokenStore.tokenBundle(for: account) else {
                return false
            }
            let now = Date()
            return bundle.refreshTokenExpiresAt > now
                && account.scopes.contains { $0 == "video.publish" || $0 == "video.upload" }
        case .youtubeShorts:
            guard
                account.platform == .youtubeShorts,
                account.authorizationSource == .nativeOAuth,
                account.status == .connected,
                account.isPublishingEnabled
            else {
                return false
            }
            guard let bundle = try? youtubeOAuthClient.tokenStore.tokenBundle(for: account) else {
                return false
            }
            let now = Date()
            return bundle.refreshTokenExpiresAt > now
                && bundle.scopes.contains(YouTubeConfiguration.uploadScope)
        case .instagram, .threads, .x:
            return account.platform == platform && account.isPublishingEnabled
        }
    }

    func publishingAccount(for platform: SocialPlatform, in selections: [PlatformAccountSelection]) -> ConnectedAccount? {
        guard let account = selectedAccount(for: platform, in: selections) else { return nil }
        return canPublish(account, on: platform) ? account : nil
    }

    func publishingAccounts(for platform: SocialPlatform, in selections: [PlatformAccountSelection]) -> [ConnectedAccount] {
        selectedAccounts(for: platform, in: selections)
            .filter { canPublish($0, on: platform) }
            .sortedForAccountsView
    }

    func publishingTikTokAccount(for draft: SlideshowDraft) -> ConnectedAccount? {
        publishingAccount(for: .tiktok, in: draft.accountSelections)
    }

    func publishingTikTokAccount(for automation: ContentAutomation) -> ConnectedAccount? {
        publishingAccount(for: .tiktok, in: automation.accountSelections)
    }

    private func applyCredentialHealth() {
        let statuses = configuration.credentialStatuses
        overview.dashboard.apiHealth = [
            APIHealthStatus(
                serviceName: "TikTok Content Posting",
                isConfigured: statuses.containsPresent("TikTok client ID") && statuses.containsPresent("TikTok redirect URI"),
                statusText: statuses.containsPresent("TikTok client secret") ? "OAuth credentials found locally" : "Client secret not present locally",
                lastCheckedAt: Date()
            ),
            APIHealthStatus(
                serviceName: "YouTube Data API",
                isConfigured: configuration.youtube.clientIDPresent && configuration.youtube.reversedClientIDPresent,
                statusText: configuration.youtube.clientIDPresent && configuration.youtube.reversedClientIDPresent
                    ? "OAuth client configured locally"
                    : "Google OAuth client ID or reversed client ID missing",
                lastCheckedAt: Date()
            ),
            APIHealthStatus(
                serviceName: "Cloudflare R2",
                isConfigured: configuration.r2.isConfigured,
                statusText: r2StatusText(),
                lastCheckedAt: Date()
            ),
            APIHealthStatus(
                serviceName: "OpenAI generation",
                isConfigured: statuses.containsPresent("OpenAI API key"),
                statusText: statuses.containsPresent("OpenAI API key") ? "Generation key found locally" : "Generation key missing",
                lastCheckedAt: Date()
            )
        ]
    }

    private func reloadCredentialConfiguration() {
        configuration = .current
        applyCredentialHealth()
    }

    private func r2StatusText() -> String {
        if configuration.r2.isConfigured {
            return "R2 bucket and S3 credentials found locally"
        }
        return "Cloudflare R2 bucket, custom domain, and S3 credentials expected"
    }
}

private extension Array where Element == CredentialStatus {
    func containsPresent(_ name: String) -> Bool {
        contains { $0.name == name && $0.isPresent }
    }
}

private struct AISlideshowCreationResult {
    var creativeTemplate: CreativeTemplate
    var shouldInsertCreativeTemplate: Bool
    var draft: SlideshowDraft
}

private struct AnalyzedCreativeTemplate {
    var creativeTemplate: CreativeTemplate
    var styleGuide: TemplateStyleGuide
    var shouldInsert: Bool
}

enum SlideshowCreationError: LocalizedError {
    case missingDraft
    case missingStyleGuide
    case planSlideCountMismatch(expected: Int, actual: Int)
    case invalidProductImagePlacement

    var errorDescription: String? {
        switch self {
        case .missingDraft:
            "The slideshow draft could not be found."
        case .missingStyleGuide:
            "Create or repair the template style guide before generating images."
        case let .planSlideCountMismatch(expected, actual):
            "The slideshow plan returned \(actual) slides, but the selected template requires \(expected)."
        case .invalidProductImagePlacement:
            "The slideshow plan did not follow the required product-image placement."
        }
    }
}

enum ManualPublishError: LocalizedError {
    case missingTikTokAccount
    case missingYouTubeAccount
    case missingPlatformAccounts
    case missingPublishableImageURLs

    var errorDescription: String? {
        switch self {
        case .missingTikTokAccount:
            "Connect a TikTok account with publishing access before publishing."
        case .missingYouTubeAccount:
            "Authorize a YouTube channel on this device before publishing Shorts."
        case .missingPlatformAccounts:
            "Select at least one publishable account before publishing."
        case .missingPublishableImageURLs:
            "Rendered slide images need public URLs before TikTok can publish them."
        }
    }
}

enum AutomationRunError: LocalizedError {
    case notReady
    case missingTemplate
    case missingProductImage(String)
    case generationFailed(String)
    case publishFailed(String)

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "Complete the automation templates, product images, cadence, platform settings, and selected accounts before it can publish."
        case .missingTemplate:
            return "One of the automation template selections is no longer available."
        case let .missingProductImage(message):
            return message.isEmpty ? "One of the automation product images is no longer available." : message
        case let .generationFailed(message):
            return message.isEmpty ? "Automated slide image generation failed." : message
        case let .publishFailed(message):
            return message.isEmpty ? "Automated publishing failed." : message
        }
    }
}

private struct AutomationStepImageProgress {
    var completedImageCount: Int
    var totalImageCount: Int
    var currentImageIndex: Int?
    var attemptDetail: String? = nil
}

private extension FlickAppModel {
    func pruneAutomationPostProgresses(now: Date = Date()) -> Bool {
        let originalCount = overview.automationPostProgresses.count
        overview.automationPostProgresses.removeAll { progress in
            if let finishedAt = progress.finishedAt {
                return now.timeIntervalSince(finishedAt) > 10 * 60
            }

            return now.timeIntervalSince(progress.updatedAt) > 12 * 60 * 60
        }
        return overview.automationPostProgresses.count != originalCount
    }

    func beginAutomationPostProgress(
        for automation: ContentAutomation,
        scheduledAt: Date
    ) async -> UUID {
        let progress = AutomationPostProgress.make(
            automationID: automation.id,
            title: automation.displayName(products: overview.products),
            productName: automation.productID.flatMap { productID in
                overview.products.first { $0.id == productID }?.name
            },
            creationModelName: automation.creationModel?.name,
            targetPlatforms: automation.targetPlatforms,
            scheduledAt: scheduledAt
        )
        overview.automationPostProgresses.insert(progress, at: 0)
        await persistAutomationPostProgresses()
        return progress.id
    }

    func startAutomationPostProgressStep(
        _ progressID: UUID?,
        _ stepID: String,
        detail: String,
        imageProgress: AutomationStepImageProgress? = nil
    ) async {
        await updateAutomationPostProgressStep(
            progressID,
            stepID,
            state: .current,
            detail: detail,
            imageProgress: imageProgress
        )
    }

    func completeAutomationPostProgressStep(
        _ progressID: UUID?,
        _ stepID: String,
        detail: String,
        imageProgress: AutomationStepImageProgress? = nil
    ) async {
        await updateAutomationPostProgressStep(
            progressID,
            stepID,
            state: .completed,
            detail: detail,
            imageProgress: imageProgress
        )
    }

    func updateAutomationPostProgress(
        _ progressID: UUID?,
        draftID: UUID? = nil,
        title: String? = nil,
        templateTitle: String? = nil,
        productName: String? = nil,
        creationModelName: String? = nil
    ) async {
        guard
            let progressID,
            let progressIndex = overview.automationPostProgresses.firstIndex(where: { $0.id == progressID })
        else {
            return
        }

        if let draftID {
            overview.automationPostProgresses[progressIndex].draftID = draftID
        }
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            overview.automationPostProgresses[progressIndex].title = title
        }
        if let templateTitle {
            overview.automationPostProgresses[progressIndex].templateTitle = templateTitle
        }
        if let productName {
            overview.automationPostProgresses[progressIndex].productName = productName
        }
        if let creationModelName {
            overview.automationPostProgresses[progressIndex].creationModelName = creationModelName
        }
        overview.automationPostProgresses[progressIndex].updatedAt = Date()
        await persistAutomationPostProgresses()
    }

    func updateAutomationPostProgressStep(
        _ progressID: UUID?,
        _ stepID: String,
        state: AutomationPostProgressStepState,
        detail: String,
        imageProgress: AutomationStepImageProgress? = nil
    ) async {
        guard
            let progressID,
            let progressIndex = overview.automationPostProgresses.firstIndex(where: { $0.id == progressID }),
            let stepIndex = overview.automationPostProgresses[progressIndex].steps.firstIndex(where: { $0.id == stepID })
        else {
            return
        }

        let now = Date()
        if state == .current {
            for index in overview.automationPostProgresses[progressIndex].steps.indices
                where overview.automationPostProgresses[progressIndex].steps[index].state == .current {
                overview.automationPostProgresses[progressIndex].steps[index].state = .pending
            }
        }
        overview.automationPostProgresses[progressIndex].steps[stepIndex].state = state
        overview.automationPostProgresses[progressIndex].steps[stepIndex].detail = detail
        overview.automationPostProgresses[progressIndex].steps[stepIndex].updatedAt = now
        if let imageProgress {
            overview.automationPostProgresses[progressIndex].steps[stepIndex].completedImageCount = imageProgress.completedImageCount
            overview.automationPostProgresses[progressIndex].steps[stepIndex].totalImageCount = imageProgress.totalImageCount
            overview.automationPostProgresses[progressIndex].steps[stepIndex].currentImageIndex = imageProgress.currentImageIndex
            overview.automationPostProgresses[progressIndex].steps[stepIndex].attemptDetail = imageProgress.attemptDetail
        }
        overview.automationPostProgresses[progressIndex].updatedAt = now
        await persistAutomationPostProgresses()
    }

    func failAutomationPostProgress(_ progressID: UUID, error: Error) async {
        guard let progressIndex = overview.automationPostProgresses.firstIndex(where: { $0.id == progressID }) else {
            return
        }

        let now = Date()
        let stepIndex = overview.automationPostProgresses[progressIndex].steps.firstIndex { $0.state == .current }
            ?? overview.automationPostProgresses[progressIndex].steps.firstIndex { $0.state == .pending }
        if let stepIndex {
            overview.automationPostProgresses[progressIndex].steps[stepIndex].state = .failed
            overview.automationPostProgresses[progressIndex].steps[stepIndex].detail = error.localizedDescription
            overview.automationPostProgresses[progressIndex].steps[stepIndex].updatedAt = now
            overview.automationPostProgresses[progressIndex].steps[stepIndex].attemptDetail = nil
        }
        overview.automationPostProgresses[progressIndex].errorMessage = error.localizedDescription
        overview.automationPostProgresses[progressIndex].finishedAt = now
        overview.automationPostProgresses[progressIndex].updatedAt = now
        await persistAutomationPostProgresses()
    }

    func finishAutomationPostProgress(_ progressID: UUID) async {
        guard let progressIndex = overview.automationPostProgresses.firstIndex(where: { $0.id == progressID }) else {
            return
        }

        let now = Date()
        for index in overview.automationPostProgresses[progressIndex].steps.indices
            where overview.automationPostProgresses[progressIndex].steps[index].state == .pending {
            overview.automationPostProgresses[progressIndex].steps[index].state = .completed
            overview.automationPostProgresses[progressIndex].steps[index].updatedAt = now
        }
        overview.automationPostProgresses[progressIndex].finishedAt = now
        overview.automationPostProgresses[progressIndex].updatedAt = now
        await persistAutomationPostProgresses()
    }

    func persistAutomationPostProgresses() async {
        do {
            try await repository.saveOverview(overview)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func makeOpenAIClient() -> OpenAIClient {
        openAIClientFactory(credentialVault.loadValues())
    }

    func createAISlideshowResult(
        brief: String,
        template: ExampleSlideshowTemplate,
        creationModel: SlideshowCreationModelReference?,
        productImage: SlideshowProductImage?,
        imageVibe: SlideshowImageVibe = .defaultValue
    ) async throws -> AISlideshowCreationResult {
        let openAIClient = makeOpenAIClient()
        let analyzedTemplate = try await analyzedCreativeTemplate(from: template, openAIClient: openAIClient)
        let styleGuide = analyzedTemplate.styleGuide
        createWorkflowMessage = "Planning slideshow..."
        let plan = try await SlideshowPlannerService(client: openAIClient).createPlan(
            brief: brief,
            template: template,
            styleGuide: styleGuide,
            creationModel: creationModel,
            productImage: productImage,
            imageVibe: imageVibe
        )

        let expectedSlideCount = expectedPlanSlideCount(
            template: template,
            styleGuide: styleGuide,
            productImage: productImage
        )
        guard plan.slides.count == expectedSlideCount else {
            throw SlideshowCreationError.planSlideCountMismatch(expected: expectedSlideCount, actual: plan.slides.count)
        }
        try validateProductImagePlacement(
            in: plan,
            productImage: productImage,
            styleGuide: styleGuide,
            template: template
        )

        let now = Date()
        let draft = makeDraft(
            from: plan,
            brief: brief,
            templateID: analyzedTemplate.creativeTemplate.id,
            creationModel: creationModel,
            productImage: productImage,
            imageVibe: imageVibe,
            now: now
        )

        return AISlideshowCreationResult(
            creativeTemplate: analyzedTemplate.creativeTemplate,
            shouldInsertCreativeTemplate: analyzedTemplate.shouldInsert,
            draft: draft
        )
    }

    private func analyzedCreativeTemplate(
        from template: ExampleSlideshowTemplate,
        openAIClient: OpenAIClient
    ) async throws -> AnalyzedCreativeTemplate {
        let fingerprint = TemplateAnalysisCacheService.fingerprint(for: template)
        if
            let existingTemplate = overview.templates.first(where: {
                $0.sourceTemplateID == template.id
                    && $0.sourceTemplateFingerprint == fingerprint
                    && $0.analysisSchemaVersion == TemplateAnalysisCacheService.schemaVersion
            }),
            let styleGuide = existingTemplate.decodedStyleGuide
        {
            return AnalyzedCreativeTemplate(
                creativeTemplate: existingTemplate,
                styleGuide: styleGuide,
                shouldInsert: false
            )
        }

        let styleGuide = try await TemplateAnalysisCacheService(
            openAIClient: openAIClient,
            storage: templateAnalysisStorageFactory(credentialVault.loadValues())
        )
        .resolveStyleGuide(for: template)

        let now = Date()
        let creativeTemplate = CreativeTemplate(
            id: UUID(),
            name: "\(styleGuide.styleName.isEmpty ? template.niche : styleGuide.styleName) - @\(template.profile)",
            description: "AI style guide from @\(template.profile)'s \(template.niche.lowercased()) template.",
            platform: .tiktok,
            slideCount: template.slideCount,
            styleJSON: styleGuide.encodedJSONString(),
            defaultTextRules: "Generated backgrounds must contain no readable text. Flick renders all text overlays.",
            sourceTemplateID: template.id,
            sourceTemplateFingerprint: fingerprint,
            analysisSchemaVersion: TemplateAnalysisCacheService.schemaVersion,
            tags: [],
            createdAt: now,
            updatedAt: now
        )

        return AnalyzedCreativeTemplate(
            creativeTemplate: creativeTemplate,
            styleGuide: styleGuide,
            shouldInsert: true
        )
    }

    func publishAutomationInstance(
        _ automation: ContentAutomation,
        scheduledAt: Date
    ) async throws {
        let progressID = await beginAutomationPostProgress(for: automation, scheduledAt: scheduledAt)

        do {
            guard automation.isReadyToSchedule else {
                throw AutomationRunError.notReady
            }

            reconcileLoginKitAccountTokenStatus()

            reloadCredentialConfiguration()
            await startAutomationPostProgressStep(
                progressID,
                AutomationPostProgressStepID.selectTemplate,
                detail: "Choosing a template and product image for this run."
            )
            let template = try await automationTemplate(for: automation, scheduledAt: scheduledAt)
            let productImage = try automationProductImage(for: automation, scheduledAt: scheduledAt)
            await updateAutomationPostProgress(
                progressID,
                templateTitle: template.title,
                productName: productImage.product.name,
                creationModelName: automation.creationModel?.name
            )
            await completeAutomationPostProgressStep(
                progressID,
                AutomationPostProgressStepID.selectTemplate,
                detail: automationSelectionDetail(
                    templateTitle: template.title,
                    productName: productImage.product.name,
                    creationModel: automation.creationModel
                )
            )

            let planningBrief = templateAnalysisBrief(for: template)

            reloadCredentialConfiguration()
            isPlanningSlideshow = true
            createWorkflowMessage = "Creating automated slideshow..."
            lastErrorMessage = nil
            await startAutomationPostProgressStep(
                progressID,
                AutomationPostProgressStepID.planSlideshow,
                detail: "Creating the carousel plan and TikTok caption."
            )

            let result: AISlideshowCreationResult
            do {
                result = try await createAISlideshowResult(
                    brief: planningBrief,
                    template: template,
                    creationModel: automation.creationModel,
                    productImage: productImage,
                    imageVibe: automation.imageVibe
                )
            } catch {
                isPlanningSlideshow = false
                throw error
            }
            isPlanningSlideshow = false
            await completeAutomationPostProgressStep(
                progressID,
                AutomationPostProgressStepID.planSlideshow,
                detail: "Created a \(result.draft.slides.count)-slide post plan."
            )

            if result.shouldInsertCreativeTemplate {
                overview.templates.insert(result.creativeTemplate, at: 0)
            }
            var generatedDraft = result.draft
            generatedDraft.targetPlatforms = automation.targetPlatforms
            generatedDraft.accountSelections = automation.accountSelections.normalizedUniqueSelections()
            generatedDraft.tikTokSettings = automation.tikTokSettings
            generatedDraft.youtubeSettings = automation.youtubeSettings
            generatedDraft.updatedAt = Date()
            let generatedDraftID = generatedDraft.id
            overview.drafts.insert(generatedDraft, at: 0)
            await updateAutomationPostProgress(
                progressID,
                draftID: generatedDraftID,
                title: generatedDraft.title
            )
            try await repository.saveOverview(overview)

            await startAutomationPostProgressStep(
                progressID,
                AutomationPostProgressStepID.generateImages,
                detail: "Preparing image generation for this post."
            )
            await generateMissingSlideImages(for: generatedDraftID, automationProgressID: progressID)
            guard let generatedDraft = overview.drafts.first(where: { $0.id == generatedDraftID }) else {
                throw SlideshowCreationError.missingDraft
            }

            let assetsByID = Dictionary(uniqueKeysWithValues: overview.assets.map { ($0.id, $0) })
            guard generatedDraft.hasCompletedCreateImages(assetsByID: assetsByID) else {
                throw AutomationRunError.generationFailed(lastErrorMessage ?? "")
            }
            await completeAutomationPostProgressStep(
                progressID,
                AutomationPostProgressStepID.generateImages,
                detail: "Generated \(generatedDraft.createReadyImageCount(assetsByID: assetsByID)) slide visuals."
            )

            let targets = automation.targetPlatforms.isEmpty ? [SocialPlatform.tiktok] : automation.targetPlatforms
            let tikTokPublishSettings = targets.contains(.tiktok)
                ? automation.tikTokSettings
                    .fillingTitle(from: generatedDraft.tikTokSettings)
                    .automatedPublishSettings(description: generatedDraft.publishDescription)
                : nil
            let youtubePublishSettings = targets.contains(.youtubeShorts)
                ? automation.youtubeSettings.automatedPublishSettings(
                    fallbackTitle: generatedDraft.title,
                    fallbackDescription: generatedDraft.publishDescription,
                    fallbackHashtags: generatedDraft.hashtags
                )
                : nil
            guard tikTokPublishSettings != nil || youtubePublishSettings != nil else {
                throw AutomationRunError.notReady
            }

            let didPublish = await publishManualSlideshow(
                draftID: generatedDraft.id,
                tikTokSettings: tikTokPublishSettings,
                youtubeSettings: youtubePublishSettings,
                automationID: automation.id,
                automationProgressID: progressID
            )
            guard didPublish else {
                throw AutomationRunError.publishFailed(lastErrorMessage ?? "")
            }

            await finishAutomationPostProgress(progressID)
        } catch {
            isPlanningSlideshow = false
            await failAutomationPostProgress(progressID, error: error)
            throw error
        }
    }

    func automationTemplate(
        for automation: ContentAutomation,
        scheduledAt: Date
    ) async throws -> ExampleSlideshowTemplate {
        let localTemplatesByID = Dictionary(uniqueKeysWithValues: localAutomationTemplates().map { ($0.id, $0) })
        var selectedTemplates = automation.templateIDs.compactMap { localTemplatesByID[$0] }
        var selectedNichePools: [AutomationTemplateNichePool] = []
        var libraryIndex: ExampleSlideshowLibraryIndex?
        let remoteTemplateIDs = automation.templateIDs.filter {
            LocalAutomationTemplateIdentifier.templateID(from: $0) == nil
        }

        if !remoteTemplateIDs.isEmpty || !automation.templateNicheIDs.isEmpty {
            let loadedIndex = try await ExampleSlideshowLibrary.loadIndex(configuration: configuration)
            libraryIndex = loadedIndex
            let selectedNicheIDs = Set(automation.templateNicheIDs)
            let templates = try await ExampleSlideshowLibrary.loadTemplates(
                matching: Set(remoteTemplateIDs),
                index: loadedIndex,
                configuration: configuration
            )
                .filter(\.hasDisplayablePreview)
            let templatesByID = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0) })
            selectedTemplates.append(contentsOf: remoteTemplateIDs
                .compactMap { templatesByID[$0] }
                .filter { template in
                    guard let nicheID = templateNicheID(for: template, in: loadedIndex) else { return true }
                    return !selectedNicheIDs.contains(nicheID)
                }
            )
            selectedNichePools = automation.templateNicheIDs.compactMap { nicheID -> AutomationTemplateNichePool? in
                guard
                    let summary = loadedIndex.collections.first(where: { $0.id == nicheID }),
                    summary.slideshowCount > 0
                else {
                    return nil
                }
                return AutomationTemplateNichePool(summary: summary, count: summary.slideshowCount)
            }
        }

        let selectedTemplateCount = selectedTemplates.count + selectedNichePools.reduce(0) { $0 + $1.count }
        guard selectedTemplateCount > 0 else {
            throw AutomationRunError.missingTemplate
        }

        let index = deterministicIndex(
            seed: "\(automation.id.uuidString)-template-\(scheduledAt.timeIntervalSince1970)",
            count: selectedTemplateCount
        )
        if index < selectedTemplates.count {
            return selectedTemplates[index]
        }

        var nicheOffset = index - selectedTemplates.count
        for pool in selectedNichePools {
            if nicheOffset < pool.count {
                guard let libraryIndex else { break }
                return try await automationTemplate(
                    in: pool.summary,
                    offset: nicheOffset,
                    libraryIndex: libraryIndex
                )
            }
            nicheOffset -= pool.count
        }

        throw AutomationRunError.missingTemplate
    }

    private struct AutomationTemplateNichePool {
        var summary: ExampleSlideshowCollectionSummary
        var count: Int
    }

    private func templateNicheID(
        for template: ExampleSlideshowTemplate,
        in index: ExampleSlideshowLibraryIndex
    ) -> String? {
        index.collections.first { summary in
            summary.nicheSlug == template.nicheSlug
                || summary.title == template.niche
                || summary.folder == template.niche
        }?.id
    }

    private func automationTemplate(
        in summary: ExampleSlideshowCollectionSummary,
        offset: Int,
        libraryIndex: ExampleSlideshowLibraryIndex
    ) async throws -> ExampleSlideshowTemplate {
        let pageSize = [summary.pageSize, libraryIndex.pageSize, ExampleSlideshowLibrary.defaultPageSize, 1].max() ?? 1
        let pageCount = max(summary.pageCount, 1)
        let pageNumber = min(max(offset / pageSize + 1, 1), pageCount)
        let pageOffset = offset % pageSize
        let page = try await ExampleSlideshowLibrary.loadPage(
            nicheID: summary.id,
            pageNumber: pageNumber,
            index: libraryIndex,
            configuration: configuration
        )
        let templates = page.collection.templates.filter(\.hasDisplayablePreview)
        if templates.indices.contains(pageOffset) {
            return templates[pageOffset]
        }
        if let forwardTemplate = try await firstAutomationTemplate(
            after: pageNumber,
            in: summary,
            libraryIndex: libraryIndex
        ) {
            return forwardTemplate
        }
        if let fallbackTemplate = templates.last {
            return fallbackTemplate
        }
        if let backwardTemplate = try await firstAutomationTemplate(
            before: pageNumber,
            in: summary,
            libraryIndex: libraryIndex
        ) {
            return backwardTemplate
        }

        throw AutomationRunError.missingTemplate
    }

    private func firstAutomationTemplate(
        after pageNumber: Int,
        in summary: ExampleSlideshowCollectionSummary,
        libraryIndex: ExampleSlideshowLibraryIndex
    ) async throws -> ExampleSlideshowTemplate? {
        let pageCount = max(summary.pageCount, 1)
        guard pageNumber < pageCount else { return nil }
        for fallbackPageNumber in (pageNumber + 1)...pageCount {
            let page = try await ExampleSlideshowLibrary.loadPage(
                nicheID: summary.id,
                pageNumber: fallbackPageNumber,
                index: libraryIndex,
                configuration: configuration
            )
            if let template = page.collection.templates.first(where: \.hasDisplayablePreview) {
                return template
            }
        }
        return nil
    }

    private func firstAutomationTemplate(
        before pageNumber: Int,
        in summary: ExampleSlideshowCollectionSummary,
        libraryIndex: ExampleSlideshowLibraryIndex
    ) async throws -> ExampleSlideshowTemplate? {
        guard pageNumber > 1 else { return nil }
        for fallbackPageNumber in stride(from: pageNumber - 1, through: 1, by: -1) {
            let page = try await ExampleSlideshowLibrary.loadPage(
                nicheID: summary.id,
                pageNumber: fallbackPageNumber,
                index: libraryIndex,
                configuration: configuration
            )
            if let template = page.collection.templates.first(where: \.hasDisplayablePreview) {
                return template
            }
        }
        return nil
    }

    func automationProductImage(
        for automation: ContentAutomation,
        scheduledAt: Date
    ) throws -> SlideshowProductImage {
        guard
            let productID = automation.productID,
            let product = overview.products.first(where: { $0.id == productID })
        else {
            throw AutomationRunError.missingProductImage("The automation product is no longer available.")
        }

        let selectedAssetIDs = Set(automation.productImageAssetIDs)
        let selectedAssets = overview.assets.filter { selectedAssetIDs.contains($0.id) }
        let productImageAssets = selectedAssets.filter { asset in
            asset.productIDs.contains(productID) && asset.mediaType == .image
        }
        let availableAssets = productImageAssets.filter(\.hasAvailableMediaLocation)

        guard !availableAssets.isEmpty else {
            if selectedAssets.isEmpty {
                throw AutomationRunError.missingProductImage("The automation selected product image records that are no longer available.")
            }
            if productImageAssets.isEmpty {
                throw AutomationRunError.missingProductImage("The selected automation images are no longer attached to \(product.name).")
            }
            throw AutomationRunError.missingProductImage("Flick found the selected product images for \(product.name), but could not read their local files or public URLs.")
        }

        let index = deterministicIndex(
            seed: "\(automation.id.uuidString)-product-image-\(scheduledAt.timeIntervalSince1970)",
            count: availableAssets.count
        )
        return SlideshowProductImage(product: product, asset: availableAssets[index])
    }

    func automationSelectionDetail(
        templateTitle: String,
        productName: String,
        creationModel: SlideshowCreationModelReference?
    ) -> String {
        guard let creationModel else {
            return "Selected \(templateTitle) for \(productName)."
        }

        return "Selected \(templateTitle) for \(productName) with \(creationModel.name)."
    }

    func markAutomation(_ automationID: UUID, succeededAt date: Date) {
        guard let index = overview.automations.firstIndex(where: { $0.id == automationID }) else { return }
        overview.automations[index].lastRunAt = date
        overview.automations[index].lastErrorMessage = nil
        overview.automations[index].consecutiveFailureCount = 0
        overview.automations[index].nextScheduledAt = overview.automations[index].nextOccurrence(after: date)
        overview.automations[index].updatedAt = date
    }

    func markAutomation(_ automationID: UUID, failedAt date: Date, error: Error) {
        guard let index = overview.automations.firstIndex(where: { $0.id == automationID }) else { return }
        overview.automations[index].lastErrorMessage = error.localizedDescription
        overview.automations[index].consecutiveFailureCount += 1
        overview.automations[index].nextScheduledAt = overview.automations[index].nextOccurrence(after: date)
        overview.automations[index].updatedAt = date
    }

    func markAutomationManualRun(
        _ automationID: UUID,
        succeededAt date: Date,
        preservingNextScheduledAt nextScheduledAt: Date?
    ) {
        guard let index = overview.automations.firstIndex(where: { $0.id == automationID }) else { return }
        overview.automations[index].lastRunAt = date
        overview.automations[index].lastErrorMessage = nil
        overview.automations[index].consecutiveFailureCount = 0
        overview.automations[index].nextScheduledAt = nextScheduledAt
        overview.automations[index].updatedAt = date
    }

    func markAutomationManualRun(
        _ automationID: UUID,
        failedAt date: Date,
        error: Error,
        preservingNextScheduledAt nextScheduledAt: Date?
    ) {
        guard let index = overview.automations.firstIndex(where: { $0.id == automationID }) else { return }
        overview.automations[index].lastErrorMessage = error.localizedDescription
        overview.automations[index].consecutiveFailureCount += 1
        overview.automations[index].nextScheduledAt = nextScheduledAt
        overview.automations[index].updatedAt = date
    }

    func deterministicIndex(seed: String, count: Int) -> Int {
        guard count > 1 else { return 0 }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int(hash % UInt64(count))
    }

    func expectedPlanSlideCount(
        template: ExampleSlideshowTemplate,
        styleGuide: TemplateStyleGuide,
        productImage: SlideshowProductImage?
    ) -> Int {
        guard productImage != nil else { return template.slideCount }
        return styleGuide.productImageSlideNumbers(limitedTo: template.slideCount).isEmpty
            ? template.slideCount + 1
            : template.slideCount
    }

    func makeDraft(
        from plan: PlannedSlideshow,
        brief: String,
        templateID: UUID,
        creationModel: SlideshowCreationModelReference?,
        productImage: SlideshowProductImage?,
        imageVibe: SlideshowImageVibe,
        now: Date
    ) -> SlideshowDraft {
        let slides = plan.slides
            .sorted { $0.index < $1.index }
            .enumerated()
            .map { offset, plannedSlide in
                let usesProductImage = productImage != nil && plannedSlide.usesProductImage
                return Slide(
                    id: UUID(),
                    index: offset,
                    imageAssetID: usesProductImage ? productImage?.asset.id : nil,
                    prompt: usesProductImage ? productImagePrompt(for: productImage) : plannedSlide.imagePrompt,
                    text: plannedSlide.text,
                    textPosition: .center,
                    textStyle: SlideTextStyle(),
                    selectedVisualSummary: selectedVisualSummary(for: plannedSlide, productImage: usesProductImage ? productImage : nil),
                    generationStatus: usesProductImage ? .complete : .notStarted,
                    generationErrorMessage: nil,
                    promptVersion: 1,
                    createdAt: now,
                    updatedAt: now
                )
            }

        return SlideshowDraft(
            id: UUID(),
            title: plan.title,
            templateID: templateID,
            creationModel: creationModel,
            imageVibe: imageVibe,
            brief: brief,
            topic: plan.topic,
            audience: plan.audience,
            goal: plan.goal,
            tone: plan.tone,
            narrativeArc: plan.narrativeArc,
            globalVisualMotif: plan.globalVisualMotif,
            planSummary: plan.planSummary,
            slides: slides,
            caption: plan.caption,
            hashtags: plan.hashtags.map { sanitizedHashtag($0) }.filter { !$0.isEmpty },
            targetPlatforms: [.tiktok, .youtubeShorts],
            tikTokSettings: defaultTikTokSettings(from: plan),
            youtubeSettings: DraftYouTubeSettings(
                title: plan.title,
                description: "",
                tags: plan.hashtags.map { sanitizedHashtag($0) }.filter { !$0.isEmpty },
                privacyStatus: .private,
                containsSyntheticMedia: true
            ),
            status: .draft,
            exportedImageAssetIDs: [],
            createdAt: now,
            updatedAt: now
        )
    }

    func defaultTikTokSettings(from plan: PlannedSlideshow) -> DraftTikTokSettings? {
        let title = [plan.tikTokTitle, plan.title]
            .map(normalizedTikTokTitle)
            .first { !$0.isEmpty }
            ?? ""

        guard !title.isEmpty else { return nil }
        return DraftTikTokSettings(title: title)
    }

    func normalizedTikTokTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    func validateProductImagePlacement(
        in plan: PlannedSlideshow,
        productImage: SlideshowProductImage?,
        styleGuide: TemplateStyleGuide,
        template: ExampleSlideshowTemplate
    ) throws {
        let sortedSlides = plan.slides.sorted { $0.index < $1.index }
        let productImagePositions = Set(
            sortedSlides.enumerated().compactMap { offset, slide in
                slide.usesProductImage ? offset + 1 : nil
            }
        )

        guard productImage != nil else {
            guard productImagePositions.isEmpty else {
                throw SlideshowCreationError.invalidProductImagePlacement
            }
            return
        }

        let templateProductImagePositions = Set(styleGuide.productImageSlideNumbers(limitedTo: template.slideCount))
        let expectedPositions: Set<Int> = templateProductImagePositions.isEmpty
            ? [sortedSlides.count]
            : templateProductImagePositions

        guard productImagePositions == expectedPositions else {
            throw SlideshowCreationError.invalidProductImagePlacement
        }
    }

    func productImagePrompt(for productImage: SlideshowProductImage?) -> String {
        guard let productImage else { return "" }
        return "Use the selected product image for \(productImage.product.name) directly. Flick renders the overlay text."
    }

    func selectedVisualSummary(
        for plannedSlide: PlannedSlide,
        productImage: SlideshowProductImage?
    ) -> String {
        guard let productImage else { return plannedSlide.selectedVisualSummary }

        let plannedSummary = plannedSlide.selectedVisualSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let productSummary = productImage.product.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            "Selected product image for \(productImage.product.name).",
            productSummary.isEmpty ? nil : productSummary,
            plannedSummary.isEmpty ? nil : plannedSummary
        ]
        .compactMap(\.self)
        .joined(separator: " ")
    }

    func generateImage(
        for slideID: UUID,
        in draftID: UUID,
        instruction: String?,
        settings: SlideshowImageGenerationSettings,
        retryHandler: ((OpenAIRetryEvent) async -> Void)? = nil
    ) async throws {
        guard
            let draftIndex = overview.drafts.firstIndex(where: { $0.id == draftID }),
            let slideIndex = overview.drafts[draftIndex].slides.firstIndex(where: { $0.id == slideID })
        else {
            throw SlideshowCreationError.missingDraft
        }

        let now = Date()
        overview.drafts[draftIndex].slides[slideIndex].generationStatus = .generating
        overview.drafts[draftIndex].slides[slideIndex].generationErrorMessage = nil
        overview.drafts[draftIndex].slides[slideIndex].updatedAt = now
        overview.drafts[draftIndex].updatedAt = now
        try await repository.saveOverview(overview)

        do {
            var openAIClient = makeOpenAIClient()
            if let retryHandler {
                openAIClient.retryHandler = retryHandler
            }
            let slideshowPlanner = SlideshowPlannerService(client: openAIClient)
            var draft = overview.drafts[draftIndex]
            var slide = draft.slides[slideIndex]
            let styleGuide = try styleGuide(for: draft)
            let previousSummary = previousVisualSummary(before: slideIndex, in: draft)

            if let instruction, !instruction.isEmpty {
                let rewrite = try await slideshowPlanner.rewritePrompt(
                    draft: draft,
                    slide: slide,
                    styleGuide: styleGuide,
                    previousVisualSummary: previousSummary,
                    instruction: instruction,
                    imageVibe: draft.imageVibe
                )
                slide.prompt = rewrite.imagePrompt
                slide.selectedVisualSummary = rewrite.selectedVisualSummary
                slide.promptVersion += 1
                draft.slides[slideIndex] = slide
                overview.drafts[draftIndex] = draft
                try await repository.saveOverview(overview)
            }

            if slide.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                slide.prompt = SlideshowPromptBuilder.imagePrompt(
                    for: slide,
                    draft: draft,
                    styleGuide: styleGuide,
                    previousVisualSummary: previousSummary,
                    imageVibe: draft.imageVibe
                )
            }

            let generatedImage = try await ImageGenerationService(client: openAIClient).generateSlideImage(
                prompt: slide.prompt,
                settings: settings,
                creationModel: draft.creationModel,
                imageVibe: draft.imageVibe
            )
            let generatedContentType = UTType(mimeType: generatedImage.contentType) ?? .jpeg
            let storedMedia = try generatedImageLibrary.store(data: generatedImage.data, contentType: generatedContentType)
            let assetID = UUID()
            let path = generatedStoragePath(
                draftID: draftID,
                slide: slide,
                assetID: assetID,
                settings: settings,
                fileExtension: generatedImage.fileExtension
            )
            let remote = try await mediaStorageFactory(credentialVault.loadValues())
                .uploadAsset(
                    LocalMediaAsset(
                        data: generatedImage.data,
                        contentType: generatedImage.contentType
                    ),
                    path: path
                )

            let asset = MediaAsset(
                id: assetID,
                mediaType: .image,
                source: .generated,
                localFilePath: storedMedia.fileURL.path,
                storageBucket: remote.storageBucket,
                storagePath: remote.storagePath,
                publicURL: remote.publicURL,
                signedURLExpiration: remote.signedURLExpiration,
                width: generatedImage.width,
                height: generatedImage.height,
                duration: nil,
                fileSize: storedMedia.fileSize,
                checksum: nil,
                trendTags: [],
                createdAt: Date(),
                updatedAt: Date()
            )

            overview.assets.insert(asset, at: 0)
            if
                let refreshedDraftIndex = overview.drafts.firstIndex(where: { $0.id == draftID }),
                let refreshedSlideIndex = overview.drafts[refreshedDraftIndex].slides.firstIndex(where: { $0.id == slideID })
            {
                overview.drafts[refreshedDraftIndex].slides[refreshedSlideIndex].prompt = slide.prompt
                overview.drafts[refreshedDraftIndex].slides[refreshedSlideIndex].imageAssetID = assetID
                overview.drafts[refreshedDraftIndex].slides[refreshedSlideIndex].generationStatus = .complete
                overview.drafts[refreshedDraftIndex].slides[refreshedSlideIndex].generationErrorMessage = nil
                overview.drafts[refreshedDraftIndex].slides[refreshedSlideIndex].updatedAt = Date()
                overview.drafts[refreshedDraftIndex].updatedAt = Date()
            }

            try await repository.saveOverview(overview)

            let summary = (try? await slideshowPlanner.summarizeGeneratedImage(
                data: generatedImage.data,
                contentType: generatedImage.contentType,
                slide: slide
            )) ?? slide.selectedVisualSummary

            if
                !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                let refreshedDraftIndex = overview.drafts.firstIndex(where: { $0.id == draftID }),
                let refreshedSlideIndex = overview.drafts[refreshedDraftIndex].slides.firstIndex(where: { $0.id == slideID })
            {
                overview.drafts[refreshedDraftIndex].slides[refreshedSlideIndex].selectedVisualSummary = summary
                overview.drafts[refreshedDraftIndex].slides[refreshedSlideIndex].updatedAt = Date()
                overview.drafts[refreshedDraftIndex].updatedAt = Date()
                try await repository.saveOverview(overview)
            }
        } catch {
            await applyGenerationFailure(error, slideID: slideID, draftID: draftID)
            throw error
        }
    }

    func renderImageSequenceForPublish(
        for draftID: UUID,
        automationProgressID: UUID? = nil
    ) async throws -> [UUID] {
        guard let draftIndex = overview.drafts.firstIndex(where: { $0.id == draftID }) else {
            throw SlideshowCreationError.missingDraft
        }

        await startAutomationPostProgressStep(
            automationProgressID,
            AutomationPostProgressStepID.renderImages,
            detail: "Rendering the current edited slides."
        )
        startPublishStep(ManualPublishProgressStepID.renderImages, detail: "Rendering the current edited slides.")
        createWorkflowMessage = "Snapshotting edited slides..."
        let draft = overview.drafts[draftIndex]
        logPublish("Rendering publish image sequence draftID=\(draftID.uuidString) slideCount=\(draft.slides.count)")
        let renderedImages = try await TextOverlayRenderService(renderDirectory: configuration.renderDirectory)
            .renderImages(
                from: draft,
                assets: overview.assets,
                options: .tikTokPhotoPost
            )
        completePublishStep(ManualPublishProgressStepID.renderImages, detail: "Snapshot \(renderedImages.count) edited slides.")
        await completeAutomationPostProgressStep(
            automationProgressID,
            AutomationPostProgressStepID.renderImages,
            detail: "Rendered \(renderedImages.count) edited slides."
        )

        createWorkflowMessage = "Uploading rendered images..."
        var renderedAssetIDs: [UUID] = []
        for (offset, renderedImage) in renderedImages.enumerated() {
            let uploadStepID = ManualPublishProgressStepID.uploadSlide(renderedImage.slideID)
            await startAutomationPostProgressStep(
                automationProgressID,
                AutomationPostProgressStepID.uploadMedia,
                detail: "Uploading rendered image \(offset + 1) of \(renderedImages.count)."
            )
            startPublishStep(uploadStepID, detail: "Uploading rendered image to Cloudflare R2.")
            let data = try Data(contentsOf: renderedImage.fileURL)
            let assetID = UUID()
            let path = renderedStoragePath(
                draftID: draftID,
                slideID: renderedImage.slideID,
                assetID: assetID
            )
            let remote = try await mediaStorageFactory(credentialVault.loadValues())
                .uploadAsset(
                    LocalMediaAsset(
                        data: data,
                        contentType: renderedImage.contentType
                    ),
                    path: path
                )

            let asset = MediaAsset(
                id: assetID,
                mediaType: .image,
                source: .rendered,
                localFilePath: renderedImage.fileURL.path,
                storageBucket: remote.storageBucket,
                storagePath: remote.storagePath,
                publicURL: remote.publicURL,
                signedURLExpiration: remote.signedURLExpiration,
                width: renderedImage.width,
                height: renderedImage.height,
                duration: nil,
                fileSize: fileSize(at: renderedImage.fileURL),
                checksum: nil,
                trendTags: [],
                createdAt: Date(),
                updatedAt: Date()
            )
            overview.assets.insert(asset, at: 0)
            renderedAssetIDs.append(assetID)
            completePublishStep(uploadStepID, detail: "Uploaded rendered image to Cloudflare R2.")
        }
        await completeAutomationPostProgressStep(
            automationProgressID,
            AutomationPostProgressStepID.uploadMedia,
            detail: "Uploaded \(renderedAssetIDs.count) rendered images."
        )

        if let refreshedDraftIndex = overview.drafts.firstIndex(where: { $0.id == draftID }) {
            overview.drafts[refreshedDraftIndex].exportedImageAssetIDs = renderedAssetIDs
            overview.drafts[refreshedDraftIndex].updatedAt = Date()
        }

        try await repository.saveOverview(overview)
        logPublish("Rendered publish image sequence draftID=\(draftID.uuidString) renderedCount=\(renderedAssetIDs.count)")
        return renderedAssetIDs
    }

    func renderYouTubeShortsVideoForPublish(
        for draftID: UUID,
        automationProgressID: UUID? = nil
    ) async throws -> RenderedVideo {
        guard let draftIndex = overview.drafts.firstIndex(where: { $0.id == draftID }) else {
            throw SlideshowCreationError.missingDraft
        }

        await startAutomationPostProgressStep(
            automationProgressID,
            AutomationPostProgressStepID.renderVideo,
            detail: "Rendering a vertical MP4 for YouTube Shorts."
        )
        startPublishStep(ManualPublishProgressStepID.renderVideo, detail: "Rendering a vertical MP4 for YouTube Shorts.")
        createWorkflowMessage = "Rendering YouTube Shorts video..."

        let draft = overview.drafts[draftIndex]
        let renderedFrames = try await TextOverlayRenderService(renderDirectory: configuration.renderDirectory)
            .renderImages(
                from: draft,
                assets: overview.assets,
                options: .youtubeShortsFrame
            )
        let renderedVideo = try await AVFoundationSlideshowRenderer(renderDirectory: configuration.renderDirectory)
            .renderVideo(
                from: renderedFrames,
                options: .youtubeShorts,
                outputFileName: "youtube-shorts-\(draftID.uuidString)-\(UUID().uuidString).mp4"
            )

        let assetID = UUID()
        let asset = MediaAsset(
            id: assetID,
            mediaType: .video,
            source: .rendered,
            localFilePath: renderedVideo.fileURL.path,
            storageBucket: nil,
            storagePath: nil,
            publicURL: nil,
            signedURLExpiration: nil,
            width: renderedVideo.width,
            height: renderedVideo.height,
            duration: renderedVideo.duration,
            fileSize: fileSize(at: renderedVideo.fileURL),
            checksum: nil,
            trendTags: [],
            createdAt: Date(),
            updatedAt: Date()
        )
        overview.assets.insert(asset, at: 0)
        if let refreshedDraftIndex = overview.drafts.firstIndex(where: { $0.id == draftID }) {
            overview.drafts[refreshedDraftIndex].updatedAt = Date()
        }
        try await repository.saveOverview(overview)

        completePublishStep(ManualPublishProgressStepID.renderVideo, detail: "Rendered a \(Int(renderedVideo.duration.rounded())) second Shorts video.")
        await completeAutomationPostProgressStep(
            automationProgressID,
            AutomationPostProgressStepID.renderVideo,
            detail: "Rendered a \(Int(renderedVideo.duration.rounded())) second Shorts video."
        )
        logPublish("Rendered YouTube Shorts video draftID=\(draftID.uuidString) assetID=\(assetID.uuidString) duration=\(renderedVideo.duration)")
        return renderedVideo
    }

    private func currentPublishedPostIDs() -> Set<UUID> {
        Set(overview.publishedPosts.map(\.id))
    }

    private func publishNotificationsForNewPosts(since existingPostIDs: Set<UUID>) async {
        #if os(macOS) || targetEnvironment(macCatalyst)
        let newPosts = overview.publishedPosts.filter { !existingPostIDs.contains($0.id) }
        guard !newPosts.isEmpty else { return }

        let accountsByID = Dictionary(uniqueKeysWithValues: overview.accounts.map { ($0.id, $0) })
        let draftsByID = Dictionary(uniqueKeysWithValues: overview.drafts.map { ($0.id, $0) })

        for post in newPosts {
            await publishedPostNotificationPublisher.publishNotification(
                for: post,
                account: accountsByID[post.accountID],
                draft: draftsByID[post.draftID]
            )
        }
        #else
        _ = existingPostIDs
        #endif
    }

    private func publishDraftUploadNotificationIfNeeded(jobID: UUID, result: PublishResult) async {
        #if os(macOS) || targetEnvironment(macCatalyst)
        guard
            let job = overview.publishingJobs.first(where: { $0.id == jobID }),
            job.status == .awaitingUserCompletion
        else {
            return
        }

        let account = overview.accounts.first { $0.id == job.accountID }
        let draft = overview.drafts.first { $0.id == job.draftID }
        await publishedPostNotificationPublisher.publishDraftUploadNotification(
            for: job,
            account: account,
            draft: draft,
            result: result
        )
        #else
        _ = jobID
        _ = result
        #endif
    }

    func refreshTikTokPublishStatuses(now: Date = Date()) async -> Bool {
        pruneExpiredTikTokRefreshCooldowns(now: now)
        let awaitingJobs = overview.publishingJobs.filter { job in
            isTikTokStatusRefreshDue(for: job, now: now)
        }
        guard !awaitingJobs.isEmpty else { return false }

        let accountsByID = Dictionary(uniqueKeysWithValues: overview.accounts.map { ($0.id, $0) })
        let adapter = TikTokAdapter(configuration: configuration.tiktok)
        var didChange = false

        for job in awaitingJobs {
            let requestStartedAt = Date()
            guard isTikTokStatusRefreshDue(for: job, now: requestStartedAt) else {
                continue
            }
            guard
                let publishID = job.platformPublishID,
                let account = accountsByID[job.accountID]
            else {
                continue
            }
            guard account.canPublishToTikTok else {
                deferTikTokStatusRefresh(
                    forJobID: job.id,
                    until: Date().addingTimeInterval(tikTokPendingInboxStatusRefreshInterval)
                )
                continue
            }

            do {
                let status = try await adapter.fetchPublishStatus(
                    publishID: publishID,
                    account: account
                )
                let didApplyStatus = applyTikTokPublishStatus(status, to: job.id)
                didChange = didApplyStatus || didChange
                if !status.isPublishComplete && !status.isFailed {
                    deferTikTokStatusRefresh(
                        forJobID: job.id,
                        until: Date().addingTimeInterval(tikTokPendingInboxStatusRefreshInterval)
                    )
                }
            } catch {
                logger.error("TikTok publish status refresh failed jobID=\(job.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                didChange = markTikTokAccountTokenUnavailableIfNeeded(error, accountID: job.accountID) || didChange
                let retryAfter = Date().addingTimeInterval(tikTokStatusRefreshCooldown(for: error))
                deferTikTokStatusRefresh(forJobID: job.id, until: retryAfter)
                if isTikTokRateLimit(error) {
                    deferTikTokStatusRefreshes(forAccountID: job.accountID, until: retryAfter)
                }
            }
        }

        return didChange
    }

    private func isTikTokStatusRefreshDue(for job: PublishingJob, now: Date) -> Bool {
        guard job.platform == .tiktok, job.status == .awaitingUserCompletion else { return false }
        guard job.platformPublishID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return false }
        if let accountCooldown = tikTokStatusRefreshCooldownsByAccountID[job.accountID], accountCooldown > now {
            return false
        }
        if let jobCooldown = tikTokStatusRefreshCooldownsByJobID[job.id], jobCooldown > now {
            return false
        }
        return now.timeIntervalSince(job.updatedAt) >= tikTokPendingInboxStatusRefreshInterval
    }

    private func tikTokStatusRefreshCooldown(for error: Error) -> TimeInterval {
        isTikTokRateLimit(error) ? tikTokStatusRateLimitCooldown : tikTokPendingInboxStatusRefreshInterval
    }

    private func deferTikTokStatusRefresh(forJobID jobID: UUID, until date: Date) {
        if let existingDate = tikTokStatusRefreshCooldownsByJobID[jobID], existingDate > date {
            return
        }
        tikTokStatusRefreshCooldownsByJobID[jobID] = date
    }

    private func deferTikTokStatusRefreshes(forAccountID accountID: UUID, until date: Date) {
        if let existingDate = tikTokStatusRefreshCooldownsByAccountID[accountID], existingDate > date {
            return
        }
        tikTokStatusRefreshCooldownsByAccountID[accountID] = date
    }

    private func pruneExpiredTikTokRefreshCooldowns(now: Date) {
        tikTokStatusRefreshCooldownsByJobID = tikTokStatusRefreshCooldownsByJobID.filter { $0.value > now }
        tikTokStatusRefreshCooldownsByAccountID = tikTokStatusRefreshCooldownsByAccountID.filter { $0.value > now }
        tikTokNextPublishAllowedAtByAccountID = tikTokNextPublishAllowedAtByAccountID.filter { $0.value > now }
    }

    private func waitForTikTokPublishRequestWindow(accountID: UUID) async throws {
        let now = Date()
        pruneExpiredTikTokRefreshCooldowns(now: now)
        guard let nextAllowedAt = tikTokNextPublishAllowedAtByAccountID[accountID] else { return }
        let delay = nextAllowedAt.timeIntervalSince(now)
        guard delay > 0 else {
            tikTokNextPublishAllowedAtByAccountID[accountID] = nil
            return
        }

        let nanoseconds = UInt64(delay * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    private func reserveTikTokPublishRequestWindow(accountID: UUID) {
        deferTikTokPublishRequests(
            forAccountID: accountID,
            until: Date().addingTimeInterval(tikTokPublishRequestSpacing)
        )
    }

    private func deferTikTokPublishRequests(forAccountID accountID: UUID, until date: Date) {
        if let existingDate = tikTokNextPublishAllowedAtByAccountID[accountID], existingDate > date {
            return
        }
        tikTokNextPublishAllowedAtByAccountID[accountID] = date
    }

    private func isTikTokRateLimit(_ error: Error) -> Bool {
        (error as? TikTokPublishAPIError)?.code == "rate_limit_exceeded"
    }

    func refreshAndPersistTikTokPublishStatuses() async {
        let publishedPostIDsBeforeRefresh = currentPublishedPostIDs()
        let didUpdateTikTokStatuses = await refreshTikTokPublishStatuses()
        let didReconcilePublishedPosts = reconcilePublishedPostsFromCompletedJobs()
        guard didUpdateTikTokStatuses || didReconcilePublishedPosts else { return }

        do {
            overview.refreshDerivedState()
            try await repository.saveOverview(overview)
            await publishNotificationsForNewPosts(since: publishedPostIDsBeforeRefresh)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func updatePublishingJob(_ jobID: UUID, status: PublishingJobStatus) {
        guard let jobIndex = overview.publishingJobs.firstIndex(where: { $0.id == jobID }) else { return }
        overview.publishingJobs[jobIndex].status = status
        overview.publishingJobs[jobIndex].updatedAt = Date()
    }

    func completePublishingJob(_ jobID: UUID, result: PublishResult, draft: SlideshowDraft) {
        let now = Date()
        let accountID = overview.publishingJobs.first(where: { $0.id == jobID })?.accountID ?? UUID()
        if let jobIndex = overview.publishingJobs.firstIndex(where: { $0.id == jobID }) {
            overview.publishingJobs[jobIndex].status = .published
            overview.publishingJobs[jobIndex].platformPublishID = result.platformPostID
            overview.publishingJobs[jobIndex].lastError = nil
            overview.publishingJobs[jobIndex].updatedAt = now
        }

        if let draftIndex = overview.drafts.firstIndex(where: { $0.id == draft.id }) {
            overview.drafts[draftIndex].status = .published
            overview.drafts[draftIndex].updatedAt = now
        }

        overview.publishedPosts.insert(
            PublishedPost(
                id: UUID(),
                platform: result.platform,
                accountID: accountID,
                automationID: overview.publishingJobs.first(where: { $0.id == jobID })?.automationID,
                platformPostID: result.platformPostID,
                platformURL: result.platformURL,
                publishedAt: result.publishedAt,
                draftID: draft.id,
                templateID: draft.templateID,
                trendTags: [],
                caption: draft.caption,
                createdAt: now,
                updatedAt: now
            ),
            at: 0
        )
    }

    func completeDraftUploadJob(_ jobID: UUID, result: PublishResult) {
        guard let jobIndex = overview.publishingJobs.firstIndex(where: { $0.id == jobID }) else { return }
        if result.platformStatus == "PUBLISH_COMPLETE" {
            _ = applyTikTokPublishStatus(
                TikTokPublishStatusResult(
                    publishID: result.platformPostID,
                    status: result.platformStatus ?? "PUBLISH_COMPLETE",
                    failReason: nil,
                    publiclyAvailablePostIDs: [],
                    rawResponse: result.rawResponse
                ),
                to: jobID
            )
            return
        }

        overview.publishingJobs[jobIndex].status = .awaitingUserCompletion
        overview.publishingJobs[jobIndex].platformPublishID = result.platformPostID
        overview.publishingJobs[jobIndex].lastError = nil
        overview.publishingJobs[jobIndex].updatedAt = Date()
        deferTikTokStatusRefresh(
            forJobID: jobID,
            until: Date().addingTimeInterval(tikTokPendingInboxStatusRefreshInterval)
        )
    }

    @discardableResult
    func applyTikTokPublishStatus(_ status: TikTokPublishStatusResult, to jobID: UUID) -> Bool {
        guard let jobIndex = overview.publishingJobs.firstIndex(where: { $0.id == jobID }) else {
            return false
        }

        if status.isFailed {
            let failReason = status.failReason ?? "FAILED"
            overview.publishingJobs[jobIndex].status = .failed
            overview.publishingJobs[jobIndex].lastError = PlatformFailure(
                kind: platformFailureKind(forTikTokCode: failReason),
                message: "TikTok reports this draft upload failed: \(failReason).",
                suggestedFix: suggestedFix(for: platformFailureKind(forTikTokCode: failReason)),
                rawResponse: status.rawResponse
            )
            overview.publishingJobs[jobIndex].lastAttemptAt = Date()
            overview.publishingJobs[jobIndex].updatedAt = Date()
            return true
        }

        guard status.isPublishComplete else { return false }

        let now = Date()
        let job = overview.publishingJobs[jobIndex]
        overview.publishingJobs[jobIndex].status = .published
        overview.publishingJobs[jobIndex].platformPublishID = status.publishID
        overview.publishingJobs[jobIndex].lastError = nil
        overview.publishingJobs[jobIndex].updatedAt = now

        let draft = overview.drafts.first { $0.id == job.draftID }
        if let draftIndex = overview.drafts.firstIndex(where: { $0.id == job.draftID }) {
            overview.drafts[draftIndex].status = .published
            overview.drafts[draftIndex].updatedAt = now
        }

        let platformPostIDs = status.publiclyAvailablePostIDs.isEmpty
            ? [status.publishID]
            : status.publiclyAvailablePostIDs

        for platformPostID in platformPostIDs where !publishedPostExists(platformPostID: platformPostID, accountID: job.accountID) {
            overview.publishedPosts.insert(
                PublishedPost(
                    id: UUID(),
                    platform: .tiktok,
                    accountID: job.accountID,
                    automationID: job.automationID,
                    platformPostID: platformPostID,
                    platformURL: nil,
                    publishedAt: now,
                    draftID: job.draftID,
                    templateID: draft?.templateID,
                    trendTags: [],
                    caption: draft?.caption ?? "",
                    createdAt: now,
                    updatedAt: now
                ),
                at: 0
            )
        }

        return true
    }

    @discardableResult
    func reconcilePublishedPostsFromCompletedJobs() -> Bool {
        let publishedJobs = overview.publishingJobs.filter { job in
            job.status == .published
                && job.platformPublishID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        guard !publishedJobs.isEmpty else { return false }

        let draftsByID = Dictionary(uniqueKeysWithValues: overview.drafts.map { ($0.id, $0) })
        let now = Date()
        var didChange = false

        for job in publishedJobs where !publishedPostExists(for: job) {
            guard let platformPostID = job.platformPublishID?.trimmingCharacters(in: .whitespacesAndNewlines), !platformPostID.isEmpty else {
                continue
            }

            let draft = draftsByID[job.draftID]
            overview.publishedPosts.insert(
                PublishedPost(
                    id: UUID(),
                    platform: job.platform,
                    accountID: job.accountID,
                    automationID: job.automationID,
                    platformPostID: platformPostID,
                    platformURL: nil,
                    publishedAt: job.lastAttemptAt ?? job.updatedAt,
                    draftID: job.draftID,
                    templateID: draft?.templateID,
                    trendTags: [],
                    caption: draft?.caption ?? "",
                    createdAt: now,
                    updatedAt: now
                ),
                at: 0
            )
            didChange = true
        }

        return didChange
    }

    func publishedPostExists(platformPostID: String, accountID: UUID) -> Bool {
        publishedPostExists(platform: .tiktok, platformPostID: platformPostID, accountID: accountID)
    }

    func publishedPostExists(platform: SocialPlatform, platformPostID: String, accountID: UUID) -> Bool {
        overview.publishedPosts.contains { post in
            post.platform == platform
                && post.accountID == accountID
                && post.platformPostID == platformPostID
        }
    }

    func publishedPostExists(for job: PublishingJob) -> Bool {
        overview.publishedPosts.contains { post in
            post.platform == job.platform
                && post.accountID == job.accountID
                && post.draftID == job.draftID
                && post.automationID == job.automationID
        }
    }

    func tikTokDraftUploadDetail(for result: PublishResult) -> String {
        switch result.platformStatus {
        case "SEND_TO_USER_INBOX":
            "TikTok draft upload ID \(result.platformPostID). Open TikTok's inbox notification to edit, save, or post."
        case "PUBLISH_COMPLETE":
            "TikTok draft upload ID \(result.platformPostID). TikTok reports this draft was posted."
        case "PROCESSING_DOWNLOAD", "PROCESSING_UPLOAD":
            "TikTok draft upload ID \(result.platformPostID). TikTok is still preparing the draft."
        case nil:
            "TikTok accepted draft upload ID \(result.platformPostID). Check TikTok's inbox shortly."
        default:
            "TikTok draft upload ID \(result.platformPostID). Open TikTok's inbox notification to finish."
        }
    }

    func failPublishingJob(_ jobID: UUID, error: Error) {
        guard let jobIndex = overview.publishingJobs.firstIndex(where: { $0.id == jobID }) else { return }
        overview.publishingJobs[jobIndex].status = .failed
        overview.publishingJobs[jobIndex].lastError = platformFailure(from: error)
        overview.publishingJobs[jobIndex].lastAttemptAt = Date()
        overview.publishingJobs[jobIndex].updatedAt = Date()
    }

    func platformFailure(from error: Error) -> PlatformFailure {
        if let error = error as? TikTokPublishAPIError {
            let kind = platformFailureKind(forTikTokCode: error.code)
            return PlatformFailure(
                kind: kind,
                message: error.errorDescription ?? "TikTok publishing failed.",
                suggestedFix: suggestedFix(for: kind),
                rawResponse: error.rawResponse
            )
        }

        if let error = error as? PlatformAdapterError {
            let kind: PlatformErrorKind = error == .missingAccountToken ? .authExpired : .unknownServerError
            return PlatformFailure(
                kind: kind,
                message: error.localizedDescription,
                suggestedFix: suggestedFix(for: kind),
                rawResponse: nil
            )
        }

        if let error = error as? TikTokOAuthTokenError {
            return PlatformFailure(
                kind: .authExpired,
                message: error.localizedDescription,
                suggestedFix: suggestedFix(for: .authExpired),
                rawResponse: error.diagnosticDescription
            )
        }

        if let error = error as? YouTubeOAuthError {
            return PlatformFailure(
                kind: .authExpired,
                message: error.localizedDescription,
                suggestedFix: suggestedFix(for: .authExpired, platform: .youtubeShorts),
                rawResponse: error.diagnosticDescription
            )
        }

        if let error = error as? YouTubePublishAPIError {
            let kind = platformFailureKind(forYouTubeStatus: error.status)
            return PlatformFailure(
                kind: kind,
                message: error.localizedDescription,
                suggestedFix: suggestedFix(for: kind, platform: .youtubeShorts),
                rawResponse: error.rawResponse
            )
        }

        return PlatformFailure(
            kind: .unknownServerError,
            message: error.localizedDescription,
            suggestedFix: suggestedFix(for: .unknownServerError),
            rawResponse: nil
        )
    }

    func platformFailureKind(forTikTokCode code: String) -> PlatformErrorKind {
        switch code {
        case "access_token_invalid":
            .authExpired
        case "scope_not_authorized":
            .missingScope
        case "rate_limit_exceeded":
            .rateLimit
        case "url_ownership_unverified":
            .urlOwnershipUnverified
        case "media_url_inaccessible", "media_url_redirect", "media_url_invalid_content_type":
            .mediaURLInaccessible
        case "privacy_level_option_mismatch", "invalid_param":
            .invalidPrivacySetting
        case "unaudited_client_can_only_post_to_private_accounts":
            .unauditedClient
        case "video_pull_failed", "photo_pull_failed":
            .mediaURLInaccessible
        case "file_format_check_failed", "picture_size_check_failed":
            .platformProcessingFailed
        case "spam_risk_too_many_posts", "spam_risk_user_banned_from_posting", "spam_risk_too_many_pending_share", "reached_active_user_cap", "app_version_check_failed":
            .platformProcessingFailed
        default:
            .unknownServerError
        }
    }

    func suggestedFix(for kind: PlatformErrorKind) -> String {
        suggestedFix(for: kind, platform: .tiktok)
    }

    func suggestedFix(for kind: PlatformErrorKind, platform: SocialPlatform) -> String {
        if platform == .youtubeShorts {
            switch kind {
            case .authExpired:
                return "Authorize this YouTube channel on the Mac that runs scheduled publishing."
            case .missingScope:
                return "Reconnect YouTube and approve the upload scope."
            case .rateLimit:
                return "Wait for the YouTube API quota or rate limit window to reset."
            case .mediaURLInaccessible:
                return "Render the Shorts video again on the Mac runner."
            case .invalidPrivacySetting:
                return "Choose private, unlisted, or public visibility."
            case .unauditedClient:
                return "Use private visibility until the Google Cloud project completes the required API review."
            case .platformProcessingFailed:
                return "Check the YouTube channel and video processing status, then retry."
            case .urlOwnershipUnverified, .unknownServerError:
                return "Check the YouTube API response and retry after the service recovers."
            }
        }

        switch kind {
        case .authExpired:
            return "Reconnect the TikTok account and try again."
        case .missingScope:
            return "Reconnect TikTok with the required publishing scope."
        case .rateLimit:
            return "Wait for the TikTok rate limit window to reset."
        case .mediaURLInaccessible:
            return "Verify the rendered image URLs are publicly reachable."
        case .urlOwnershipUnverified:
            return "Verify the Cloudflare R2 custom domain or TikTok media URL prefix."
        case .invalidPrivacySetting:
            return "Refresh TikTok creator info and choose a supported visibility option."
        case .unauditedClient:
            return "Use private visibility while the TikTok client is unaudited, or complete app audit."
        case .platformProcessingFailed:
            return "Check the TikTok account and app status, then retry."
        case .unknownServerError:
            return "Check the platform response and retry after the service recovers."
        }
    }

    func platformFailureKind(forYouTubeStatus status: String?) -> PlatformErrorKind {
        switch status {
        case "UNAUTHENTICATED", "PERMISSION_DENIED":
            .authExpired
        case "RESOURCE_EXHAUSTED":
            .rateLimit
        case "INVALID_ARGUMENT", "FAILED_PRECONDITION":
            .invalidPrivacySetting
        case "UNAVAILABLE", "DEADLINE_EXCEEDED", "ABORTED":
            .unknownServerError
        default:
            .unknownServerError
        }
    }

    func startPublishStep(_ id: String, detail: String) {
        updatePublishStep(id, state: .current, detail: detail)
    }

    func completePublishStep(_ id: String, detail: String) {
        updatePublishStep(id, state: .completed, detail: detail)
    }

    func updatePublishStep(_ id: String, state: ManualPublishProgressStepState, detail: String) {
        guard
            var progress = manualPublishProgress,
            let stepIndex = progress.steps.firstIndex(where: { $0.id == id })
        else {
            return
        }

        progress.steps[stepIndex].state = state
        progress.steps[stepIndex].detail = detail
        progress.steps[stepIndex].updatedAt = Date()
        manualPublishProgress = progress
        logPublish("\(progress.steps[stepIndex].title): \(state.rawValue) - \(detail)")
    }

    func failCurrentPublishStep(_ error: Error) {
        guard var progress = manualPublishProgress else { return }
        let stepIndex = progress.steps.firstIndex { $0.state == .current }
            ?? progress.steps.firstIndex { $0.state == .pending }

        guard let stepIndex else { return }
        progress.steps[stepIndex].state = .failed
        progress.steps[stepIndex].detail = error.localizedDescription
        progress.steps[stepIndex].updatedAt = Date()
        progress.errorMessage = error.localizedDescription
        manualPublishProgress = progress
        logPublish("\(progress.steps[stepIndex].title): failed - \(error.localizedDescription)")
    }

    func finishManualPublishProgress(errorMessage: String? = nil) {
        guard var progress = manualPublishProgress else { return }
        progress.finishedAt = Date()
        progress.errorMessage = errorMessage
        manualPublishProgress = progress
    }

    func logPublish(_ message: String) {
        logger.info("[FlickPublish] \(message, privacy: .public)")
        print("[FlickPublish] \(message)")
    }

    func publishErrorDiagnostics(for error: Error) -> String {
        if let error = error as? TikTokPublishAPIError {
            return "error=\(error.localizedDescription) details=\(error.diagnosticDescription)"
        }
        if let error = error as? TikTokOAuthTokenError {
            return "error=\(error.localizedDescription) details=\(error.diagnosticDescription)"
        }
        return "error=\(error.localizedDescription)"
    }

    func applyGenerationFailure(_ error: Error, slideID: UUID, draftID: UUID) async {
        guard
            let draftIndex = overview.drafts.firstIndex(where: { $0.id == draftID }),
            let slideIndex = overview.drafts[draftIndex].slides.firstIndex(where: { $0.id == slideID })
        else {
            return
        }

        let now = Date()
        let slide = overview.drafts[draftIndex].slides[slideIndex]
        let assetsByID = Dictionary(uniqueKeysWithValues: overview.assets.map { ($0.id, $0) })

        if slideHasAvailableCreateImage(slide, assetsByID: assetsByID) {
            overview.drafts[draftIndex].slides[slideIndex].generationStatus = .complete
            overview.drafts[draftIndex].slides[slideIndex].generationErrorMessage = nil
        } else {
            overview.drafts[draftIndex].slides[slideIndex].generationStatus = .failed
            overview.drafts[draftIndex].slides[slideIndex].generationErrorMessage = error.localizedDescription
        }

        overview.drafts[draftIndex].slides[slideIndex].updatedAt = now
        overview.drafts[draftIndex].updatedAt = now
        try? await repository.saveOverview(overview)
    }

    @discardableResult
    func reconcileCompletedSlideImages(now: Date = Date()) -> Bool {
        let assetsByID = Dictionary(uniqueKeysWithValues: overview.assets.map { ($0.id, $0) })
        var didChange = false

        for draftIndex in overview.drafts.indices {
            var didChangeDraft = false

            for slideIndex in overview.drafts[draftIndex].slides.indices {
                let slide = overview.drafts[draftIndex].slides[slideIndex]
                let hasCreateImage = slideHasAvailableCreateImage(slide, assetsByID: assetsByID)

                if hasCreateImage {
                    if slide.generationStatus != .complete || slide.generationErrorMessage != nil {
                        overview.drafts[draftIndex].slides[slideIndex].generationStatus = .complete
                        overview.drafts[draftIndex].slides[slideIndex].generationErrorMessage = nil
                        overview.drafts[draftIndex].slides[slideIndex].updatedAt = now
                        didChange = true
                        didChangeDraft = true
                    }
                } else if slide.generationStatus == .generating || slide.generationStatus == .complete {
                    overview.drafts[draftIndex].slides[slideIndex].generationStatus = .notStarted
                    overview.drafts[draftIndex].slides[slideIndex].generationErrorMessage = nil
                    overview.drafts[draftIndex].slides[slideIndex].updatedAt = now
                    didChange = true
                    didChangeDraft = true
                }
            }

            if didChangeDraft {
                overview.drafts[draftIndex].updatedAt = now
            }
        }

        return didChange
    }

    func slideHasAvailableCreateImage(_ slide: Slide, assetsByID: [UUID: MediaAsset]) -> Bool {
        guard
            let assetID = slide.imageAssetID,
            let asset = assetsByID[assetID],
            asset.source == .generated || asset.source == .uploaded
        else {
            return false
        }

        return asset.hasAvailableMediaLocation
    }

    func slideUsesAvailableUploadedImage(_ slide: Slide, assetsByID: [UUID: MediaAsset]) -> Bool {
        guard
            let assetID = slide.imageAssetID,
            let asset = assetsByID[assetID],
            asset.source == .uploaded
        else {
            return false
        }

        return asset.hasAvailableMediaLocation
    }

    func slideUsesAvailableUploadedImage(slideID: UUID, draftID: UUID) -> Bool {
        guard
            let draft = overview.drafts.first(where: { $0.id == draftID }),
            let slide = draft.slides.first(where: { $0.id == slideID })
        else {
            return false
        }

        let assetsByID = Dictionary(uniqueKeysWithValues: overview.assets.map { ($0.id, $0) })
        return slideUsesAvailableUploadedImage(slide, assetsByID: assetsByID)
    }

    func styleGuide(for draft: SlideshowDraft) throws -> TemplateStyleGuide {
        guard
            let templateID = draft.templateID,
            let template = overview.templates.first(where: { $0.id == templateID }),
            let styleGuide = template.decodedStyleGuide
        else {
            throw SlideshowCreationError.missingStyleGuide
        }
        return styleGuide
    }

    func previousVisualSummary(before slideIndex: Int, in draft: SlideshowDraft) -> String {
        guard slideIndex > 0 else { return "" }
        return draft.slides
            .sorted { $0.index < $1.index }
            .prefix(slideIndex)
            .last?
            .selectedVisualSummary ?? ""
    }

    func generatedStoragePath(
        draftID: UUID,
        slide: Slide,
        assetID: UUID,
        settings: SlideshowImageGenerationSettings,
        fileExtension: String
    ) -> String {
        "\(configuration.storagePaths.generatedImages)/\(draftID.uuidString)/slide-\(String(format: "%02d", slide.index + 1))-v\(slide.promptVersion)-\(settings.width)x\(settings.height)-\(assetID.uuidString).\(fileExtension)"
    }

    func productMediaStoragePath(
        productIDs: [UUID],
        assetID: UUID,
        contentType: UTType,
        fileURL: URL
    ) -> String {
        let productScope = productIDs.map(\.uuidString).sorted().first ?? "unassigned"
        let fileExtension = productMediaFileExtension(contentType: contentType, fileURL: fileURL)
        return "\(configuration.storagePaths.productMedia)/\(productScope)/\(assetID.uuidString).\(fileExtension)"
    }

    func productMediaFileExtension(contentType: UTType, fileURL: URL) -> String {
        let existingExtension = fileURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        if !existingExtension.isEmpty {
            return existingExtension.lowercased()
        }
        if let preferredExtension = contentType.preferredFilenameExtension {
            return preferredExtension.lowercased()
        }
        if contentType.conforms(to: .movie) {
            return "mov"
        }
        if contentType.conforms(to: .image) {
            return "jpg"
        }
        return "dat"
    }

    func renderedStoragePath(
        draftID: UUID,
        slideID: UUID,
        assetID: UUID
    ) -> String {
        "\(configuration.storagePaths.renderedImages)/\(draftID.uuidString)/\(slideID.uuidString)-\(assetID.uuidString).jpg"
    }

    func reindexSlides(in draftIndex: Int) {
        let now = Date()
        for index in overview.drafts[draftIndex].slides.indices {
            overview.drafts[draftIndex].slides[index].index = index
            overview.drafts[draftIndex].slides[index].updatedAt = now
        }
        overview.drafts[draftIndex].updatedAt = now
        Task {
            await persistCreateState()
        }
    }

    func fileSize(at url: URL) -> Int64? {
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber else {
            return nil
        }
        return size.int64Value
    }

    private func normalizedShareImportNiche(_ niche: String) -> String {
        let normalized = niche.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "Imported" : normalized
    }

    private func normalizedShareImportTitle(_ title: String, niche: String) -> String {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "\(niche) photo template" : normalized
    }

    private func shareImportTags(niche: String, now: Date) -> [TrendTag] {
        [
            TrendTag(
                id: UUID(),
                name: niche,
                category: .niche,
                colorHex: "#4F46E5",
                createdAt: now
            ),
            TrendTag(
                id: UUID(),
                name: "Photos Import",
                category: .template,
                colorHex: "#16A34A",
                createdAt: now
            )
        ]
    }

    private func shareImportedStyleGuide(title: String, niche: String) -> TemplateStyleGuide {
        TemplateStyleGuide(
            styleName: title,
            visualTraits: [
                "User-imported photo sequence",
                "Use the original photos as direct slide references",
                "Preserve the selected image order and portrait carousel pacing"
            ],
            colorPalette: [],
            lighting: "Use the lighting and color cues from the imported photos.",
            recurringMotifs: [],
            reuseStructurally: [
                "Reuse the imported photos as ready-made slide visuals.",
                "Keep the \(niche) context unless the creator edits it."
            ],
            avoidCopyingDirectly: [
                "Do not introduce readable text, watermarks, logos, or unrelated products when regenerating.",
                "Do not replace user-imported photos unless explicitly requested."
            ],
            imageGenerationRules: [
                "Imported photos are complete slide visuals.",
                "Generated replacements should match the imported sequence's composition, lighting, and pacing.",
                "Flick renders text overlays separately; generated images should not contain readable text."
            ],
            productImageSlideNumbers: []
        )
    }

    private func shareImportHashtags(niche: String) -> [String] {
        [
            sanitizedHashtag(niche),
            "template",
            "slideshow"
        ]
        .filter { !$0.isEmpty }
    }

    private func draftHasImportedTemplateSlides(_ draft: SlideshowDraft, assetsByID: [UUID: MediaAsset]) -> Bool {
        !draft.slides.isEmpty && draft.slides.allSatisfy { slide in
            guard
                let assetID = slide.imageAssetID,
                let asset = assetsByID[assetID]
            else {
                return false
            }

            return asset.source == .uploaded
                && asset.mediaType == .image
                && asset.hasAvailableMediaLocation
        }
    }

    private func localAutomationTemplate(
        from template: CreativeTemplate,
        draft: SlideshowDraft,
        assetsByID: [UUID: MediaAsset]
    ) -> ExampleSlideshowTemplate? {
        let slides = draft.slides
            .sorted { $0.index < $1.index }
            .compactMap { slide -> ExampleSlideshowSlide? in
                guard
                    let assetID = slide.imageAssetID,
                    let asset = assetsByID[assetID],
                    let fileURL = asset.localFileURL
                else {
                    return nil
                }

                return ExampleSlideshowSlide(
                    id: "\(template.id.uuidString)-slide-\(slide.index + 1)",
                    index: slide.index + 1,
                    filename: fileURL.lastPathComponent,
                    relativePath: asset.localFilePath ?? fileURL.path,
                    localURL: fileURL,
                    sourceURL: nil,
                    remoteURL: asset.publicURL
                )
            }

        guard !slides.isEmpty else { return nil }

        let niche = localTemplateNiche(for: template)
        let nicheSlug = sanitizedHashtag(niche).isEmpty ? "imported" : sanitizedHashtag(niche)
        return ExampleSlideshowTemplate(
            id: LocalAutomationTemplateIdentifier.id(for: template.id),
            niche: niche,
            nicheSlug: nicheSlug,
            sourceURL: nil,
            postNumber: 0,
            profile: "you",
            profileDisplayName: "Imported from Photos",
            folder: "local-\(template.id.uuidString)",
            slideCount: slides.count,
            metrics: ExampleSlideshowMetrics(views: nil, likes: nil, bookmarks: nil, shares: nil),
            product: ExampleSlideshowProduct(
                medium: "Imported photos",
                name: template.name,
                linkInBio: nil
            ),
            creator: ExampleSlideshowCreator(
                followerCount: nil,
                signature: "Imported from Photos",
                avatarURL: nil,
                region: nil
            ),
            slides: slides
        )
    }

    private func localTemplateNiche(for template: CreativeTemplate) -> String {
        template.tags.first { $0.category == .niche }?.name
            ?? template.decodedStyleGuide?.styleName
            ?? "Imported"
    }

    func templateHashtags(for template: ExampleSlideshowTemplate) -> [String] {
        [
            sanitizedHashtag(template.nicheSlug),
            sanitizedHashtag(template.product.medium ?? ""),
            "template",
            "slideshow"
        ]
        .filter { !$0.isEmpty }
    }

    func sanitizedHashtag(_ value: String) -> String {
        value
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    func templateAnalysisBrief(for template: ExampleSlideshowTemplate) -> String {
        """
        Analyze the selected Flick template and create an editable slideshow plan from its structure.
        Template niche: \(template.niche).
        Creator profile: @\(template.profile).
        Template context: \(template.subtitle).
        Preserve the template's pacing, composition rhythm, safe-area behavior, and style guide. Create a plan that can generate one clean vertical portrait background image per slide with Flick-rendered editable text.
        """
    }
}

private extension DraftTikTokSettings {
    func fillingTitle(from generatedSettings: DraftTikTokSettings?) -> DraftTikTokSettings {
        guard title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return self
        }

        guard let generatedTitle = generatedSettings?.title.trimmingCharacters(in: .whitespacesAndNewlines), !generatedTitle.isEmpty else {
            return self
        }

        var settings = self
        settings.title = generatedTitle
        return settings
    }
}

private extension SlideshowDraft {
    var referencedAssetIDs: Set<UUID> {
        Set(slides.compactMap(\.imageAssetID)).union(exportedImageAssetIDs)
    }
}

private extension AssetMediaType {
    init(contentType: UTType) {
        if contentType.conforms(to: .movie) {
            self = .video
        } else if contentType.conforms(to: .image) {
            self = .image
        } else {
            self = .thumbnail
        }
    }
}
