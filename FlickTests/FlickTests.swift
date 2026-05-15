//
//  FlickTests.swift
//  FlickTests
//

import CoreData
import XCTest
@testable import Flick

@MainActor
final class FlickTests: XCTestCase {
    func testPublishingStatusTransitionsGuardInvalidJumps() throws {
        XCTAssertTrue(PublishingJobStatus.awaitingApproval.canTransition(to: .approved))
        XCTAssertTrue(PublishingJobStatus.approved.canTransition(to: .rendering))
        XCTAssertTrue(PublishingJobStatus.uploadingMedia.canTransition(to: .publishing))
        XCTAssertFalse(PublishingJobStatus.draft.canTransition(to: .published))
        XCTAssertFalse(PublishingJobStatus.published.canTransition(to: .queued))
    }

    func testSchedulerClaimsOnlyUnleasedEligibleJobs() {
        let scheduler = PublishingScheduler()
        let workerDeviceID = UUID()
        let secondWorkerDeviceID = UUID()
        let job = makePublishingJob()
        let claimed = scheduler.claim(job, workerDeviceID: workerDeviceID, leaseDuration: 60)

        XCTAssertEqual(claimed?.workerDeviceID, workerDeviceID)
        XCTAssertNotNil(claimed?.workerLeaseExpiresAt)
        XCTAssertNil(claimed.flatMap { scheduler.claim($0, workerDeviceID: secondWorkerDeviceID, leaseDuration: 60) })
    }

    func testLiveAppModelStartsWithoutSeedData() {
        let model = LiveAppModelTestCache.model

        XCTAssertTrue(model.overview.drafts.isEmpty)
        XCTAssertTrue(model.overview.publishingJobs.isEmpty)
        XCTAssertTrue(model.overview.analyticsPerformance.isEmpty)
    }

    func testCreateFlowDoesNotAutoSelectPersistedDraftOnRefresh() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let draft = makeSlideshowDraft(now: now)
        var state = FlickEmptyState.make(now: now)
        state.drafts = [draft]

        let model = FlickAppModel(
            repository: InMemoryFlickRepository(state: state),
            configuration: .current
        )

        await model.refresh()

        XCTAssertNil(model.activeCreateDraftID)
        XCTAssertNil(model.activeCreateDraft)
        XCTAssertEqual(model.createDrafts.map(\.id), [draft.id])

        model.selectCreateDraft(id: draft.id)

        XCTAssertEqual(model.activeCreateDraftID, draft.id)
        XCTAssertEqual(model.activeCreateDraft?.id, draft.id)
    }

    func testCreateDraftsExcludePostedAndArchivedDrafts() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let draft = makeSlideshowDraft(now: now)
        var published = makeSlideshowDraft(now: now)
        published.status = .published
        var archived = makeSlideshowDraft(now: now)
        archived.status = .archived

        var state = FlickEmptyState.make(now: now)
        state.drafts = [published, draft, archived]

        let model = FlickAppModel(
            repository: InMemoryFlickRepository(state: state),
            configuration: .current
        )

        await model.refresh()

        XCTAssertEqual(model.createDrafts.map(\.id), [draft.id])
    }

    func testCoreDataRoundTripsGeneratedSlideImageAsset() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let persistenceController = PersistenceController(inMemory: true)
        let repository = CoreDataFlickRepository(
            context: persistenceController.container.viewContext,
            cloudAvailability: { false }
        )
        let asset = makeMediaAsset(
            source: .generated,
            localFilePath: "/tmp/flick-generated-\(UUID().uuidString).png",
            publicURL: URL(string: "https://example.com/generated-slide.png"),
            now: now
        )
        let slide = makeSlide(imageAssetID: asset.id, generationStatus: .complete, now: now)
        let draft = makeSlideshowDraft(slides: [slide], now: now)
        var state = FlickEmptyState.make(now: now)
        state.assets = [asset]
        state.drafts = [draft]

        try await repository.saveOverview(state)
        let loaded = try await repository.loadOverview()
        let loadedDraft = try XCTUnwrap(loaded.drafts.first)
        let loadedSlide = try XCTUnwrap(loadedDraft.slides.first)
        let loadedAsset = try XCTUnwrap(loaded.assets.first)

        XCTAssertEqual(loadedSlide.imageAssetID, asset.id)
        XCTAssertEqual(loadedSlide.generationStatus, .complete)
        XCTAssertEqual(loadedAsset.id, asset.id)
        XCTAssertEqual(loadedAsset.source, .generated)
        XCTAssertEqual(loadedAsset.publicURL, asset.publicURL)
    }

    func testGeneratedAssetWithMissingLocalFileCanUsePublicURL() throws {
        let asset = makeMediaAsset(
            source: .generated,
            localFilePath: "/tmp/flick-missing-\(UUID().uuidString).png",
            publicURL: try XCTUnwrap(URL(string: "https://example.com/generated-slide.png"))
        )

        XCTAssertNil(asset.localFileURL)
        XCTAssertTrue(asset.hasAvailableMediaLocation)
    }

    func testRefreshRepairsFailedStatusWhenGeneratedImageExists() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let asset = makeMediaAsset(
            source: .generated,
            localFilePath: "/tmp/flick-missing-\(UUID().uuidString).png",
            publicURL: try XCTUnwrap(URL(string: "https://example.com/generated-slide.png")),
            now: now
        )
        var slide = makeSlide(imageAssetID: asset.id, generationStatus: .failed, now: now)
        slide.generationErrorMessage = "Summary failed after image upload."
        let draft = makeSlideshowDraft(slides: [slide], now: now)
        var state = FlickEmptyState.make(now: now)
        state.assets = [asset]
        state.drafts = [draft]

        let repository = InMemoryFlickRepository(state: state)
        let model = FlickAppModel(repository: repository, configuration: .current)

        await model.refresh()

        let repairedSlide = try XCTUnwrap(model.overview.drafts.first?.slides.first)
        XCTAssertEqual(repairedSlide.generationStatus, .complete)
        XCTAssertNil(repairedSlide.generationErrorMessage)
        XCTAssertEqual(repository.state.drafts.first?.slides.first?.generationStatus, .complete)
    }

    func testCredentialVaultStoresOnlySupportedNonEmptyValues() throws {
        let store = MemorySecretStore()
        let vault = CredentialVault(store: store)

        try vault.storeValue("client-id", for: "TIKTOK_CLIENT_ID")
        XCTAssertThrowsError(try vault.storeValue("ignored", for: "UNKNOWN_KEY"))
        XCTAssertThrowsError(try vault.storeValue("", for: "OPENAI_API_KEY"))
        XCTAssertEqual(String(data: try XCTUnwrap(store.data(for: "TIKTOK_CLIENT_ID")), encoding: .utf8), "client-id")
    }

    func testSupabaseConfigurationRecognizesPublishableKey() {
        let configuration = SupabaseConfiguration(values: [
            "SUPABASE_URL": "https://example.supabase.co",
            "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_test"
        ])

        XCTAssertEqual(configuration.url?.absoluteString, "https://example.supabase.co")
        XCTAssertTrue(configuration.publishableKeyPresent)
        XCTAssertTrue(configuration.apiKeyPresent)
        XCTAssertFalse(configuration.anonKeyPresent)
    }

    func testSupabaseStorageServiceBuildsPublicURLWithSDK() throws {
        let service = SupabaseStorageService(credentials: [
            "SUPABASE_URL": "https://example.supabase.co",
            "SUPABASE_ANON_KEY": "anon-key"
        ])

        let url = try service.publicURL(bucket: "flick-generated-images", path: "drafts/slide-01.png")

        XCTAssertEqual(
            url.absoluteString,
            "https://example.supabase.co/storage/v1/object/public/flick-generated-images/drafts/slide-01.png"
        )
    }

    func testSupabaseStorageServicePrefersServiceRoleKeyWhenPresent() async throws {
        let service = SupabaseStorageService(credentials: [
            "SUPABASE_URL": "https://example.supabase.co",
            "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_test",
            "SUPABASE_SERVICE_ROLE_KEY": "service-role-key"
        ])

        let status = try await service.ensureAuthenticatedSession()

        XCTAssertEqual(status.mode, .serviceRole)
    }

    func testStorageBucketsExposeEveryConfiguredBucket() {
        let buckets = StorageBuckets()

        XCTAssertEqual(
            buckets.all,
            [
                buckets.generatedImages,
                buckets.renderedVideos,
                buckets.referenceImages,
                buckets.thumbnails
            ]
        )
    }

    func testTikTokAuthorizationParametersRequireUniversalLinkRedirect() throws {
        let configuration = TikTokConfiguration(values: [
            "TIKTOK_CLIENT_ID": "client-id",
            "TIKTOK_REDIRECT_URI": TikTokRedirectPolicy.recommendedRedirectURIString,
            "TIKTOK_SCOPES": "user.info.basic,video.publish"
        ])

        let parameters = try TikTokLoginKitAuthorizationParameters(
            configuration: configuration,
            state: "state-token"
        )

        XCTAssertEqual(parameters.redirectURI, TikTokRedirectPolicy.recommendedRedirectURIString)
        XCTAssertEqual(parameters.scopes, ["user.info.basic", "video.publish"])
        XCTAssertEqual(parameters.state, "state-token")
    }

    func testTikTokAuthorizationParametersRejectCustomSchemeRedirect() throws {
        let configuration = TikTokConfiguration(values: [
            "TIKTOK_CLIENT_ID": "client-id",
            "TIKTOK_REDIRECT_URI": "flick://oauth/tiktok",
            "TIKTOK_SCOPES": "user.info.basic,video.publish"
        ])

        XCTAssertThrowsError(
            try TikTokLoginKitAuthorizationParameters(configuration: configuration)
        )
    }

    func testTikTokAuthorizationParametersRejectAppStoreRedirect() throws {
        let configuration = TikTokConfiguration(values: [
            "TIKTOK_CLIENT_ID": "client-id",
            "TIKTOK_REDIRECT_URI": "https://apps.apple.com/us/app/flick-go-viral/id6768433016",
            "TIKTOK_SCOPES": "user.info.basic,video.publish"
        ])

        XCTAssertThrowsError(
            try TikTokLoginKitAuthorizationParameters(configuration: configuration)
        )
    }

    func testLoginKitAccountStoreOnlyReturnsLoginKitAccounts() throws {
        let store = MemorySecretStore()
        let accountStore = LoginKitAccountStore(store: store)
        let loginKitAccount = LoginKitAccountMapper.connectedAccount(
            from: LoginKitAuthorizedUser(
                platform: .tiktok,
                openID: "real-open-id",
                displayName: "@realaccount",
                avatarURL: nil,
                scopes: ["user.info.basic", "video.publish"]
            )
        )
        var manualAccount = loginKitAccount
        manualAccount.id = UUID()
        manualAccount.platformUserID = "manual"
        manualAccount.authorizationSource = .manualImport

        try accountStore.saveAccounts([manualAccount, loginKitAccount])

        let accounts = accountStore.loadAccounts()
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts.first?.platformUserID, "real-open-id")
        XCTAssertEqual(accounts.first?.displayName, "@realaccount")
        XCTAssertEqual(accounts.first?.authorizationSource, .loginKit)
    }

    func testLoginKitAccountMapperDefaultsTikTokPrivacyToEveryone() {
        let account = LoginKitAccountMapper.connectedAccount(
            from: LoginKitAuthorizedUser(
                platform: .tiktok,
                openID: "real-open-id",
                displayName: "@realaccount",
                avatarURL: nil,
                scopes: ["user.info.basic", "video.publish"]
            )
        )

        XCTAssertEqual(account.defaultPrivacyLevel, TikTokPrivacyLevel.publicToEveryone.rawValue)
    }

    func testLoginKitAccountStoreNormalizesExistingTikTokSelfOnlyPrivacy() throws {
        let store = MemorySecretStore()
        let accountStore = LoginKitAccountStore(store: store)
        var account = LoginKitAccountMapper.connectedAccount(
            from: LoginKitAuthorizedUser(
                platform: .tiktok,
                openID: "real-open-id",
                displayName: "@realaccount",
                avatarURL: nil,
                scopes: ["user.info.basic", "video.publish"]
            )
        )
        account.defaultPrivacyLevel = TikTokPrivacyLevel.selfOnly.rawValue

        try accountStore.saveAccounts([account])

        XCTAssertEqual(accountStore.loadAccounts().first?.defaultPrivacyLevel, TikTokPrivacyLevel.publicToEveryone.rawValue)
    }

    func testTikTokAdapterUsesCurrentPrivacyOptions() async throws {
        let adapter = TikTokAdapter(
            configuration: TikTokConfiguration(values: [:]),
            tokenStore: MemorySecretStore()
        )
        let account = LoginKitAccountMapper.connectedAccount(
            from: LoginKitAuthorizedUser(
                platform: .tiktok,
                openID: "real-open-id",
                displayName: "@realaccount",
                avatarURL: nil,
                scopes: ["user.info.basic", "video.publish"]
            )
        )

        let status = try await adapter.validateAccount(account)

        XCTAssertEqual(status.privacyOptions, TikTokPrivacyLevel.directPostOptions)
        XCTAssertTrue(status.privacyOptions.contains(TikTokPrivacyLevel.publicToEveryone.rawValue))
    }

    func testAccountManagementPolicyIsIOSOnly() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        XCTAssertTrue(AccountManagementPolicy.canAuthorizeAccountsOnThisDevice)
        #else
        XCTAssertFalse(AccountManagementPolicy.canAuthorizeAccountsOnThisDevice)
        #endif
    }

    func testLoginKitStoresUseSynchronizableKeychainByDefault() {
        let accountStore = LoginKitAccountStore()
        let tokenStore = LoginKitTokenStore()

        XCTAssertEqual((accountStore.store as? KeychainSecretStore)?.synchronizesAcrossDevices, true)
        XCTAssertEqual((tokenStore.store as? KeychainSecretStore)?.synchronizesAcrossDevices, true)
    }

    func testSlideshowImageGenerationSettingsUseVerticalReelsFormat() {
        XCTAssertEqual(SlideshowImageGenerationSettings.draft.size, "720x1280")
        XCTAssertEqual(SlideshowImageGenerationSettings.draft.width, 720)
        XCTAssertEqual(SlideshowImageGenerationSettings.draft.height, 1280)
        XCTAssertLessThan(SlideshowImageGenerationSettings.draft.aspectRatio, 1)

        XCTAssertEqual(SlideshowImageGenerationSettings.finalExport.size, "1080x1920")
        XCTAssertEqual(SlideshowImageGenerationSettings.finalExport.width, 1080)
        XCTAssertEqual(SlideshowImageGenerationSettings.finalExport.height, 1920)
        XCTAssertEqual(SlideshowImageGenerationSettings.finalExport.aspectRatio, 9.0 / 16.0)
    }

    func testSlideshowImageGenerationSettingsRejectHorizontalAssets() {
        let verticalAsset = makeMediaAsset(width: 1080, height: 1920)
        let horizontalAsset = makeMediaAsset(width: 2560, height: 1440)

        XCTAssertTrue(SlideshowImageGenerationSettings.finalExport.isSatisfied(by: verticalAsset))
        XCTAssertFalse(SlideshowImageGenerationSettings.finalExport.isSatisfied(by: horizontalAsset))
    }

    func testGeneratedImagePromptOverridesStaleHorizontalFormat() {
        let prompt = SlideshowImagePromptFormatter.applyVerticalOutputContract(
            to: "Create a 16:9 horizontal social slideshow image with no readable text.",
            settings: .draft
        )

        XCTAssertTrue(prompt.contains("vertical 9:16 image"))
        XCTAssertTrue(prompt.contains("720x1280 portrait canvas"))
        XCTAssertTrue(prompt.contains("ignore that stale format instruction"))
    }
}

private func makePublishingJob(status: PublishingJobStatus = .queued) -> PublishingJob {
    let now = Date()
    return PublishingJob(
        id: UUID(),
        platform: .tiktok,
        accountID: UUID(),
        draftID: UUID(),
        scheduledAt: now,
        status: status,
        publishMode: .photoDirectPost,
        requiresApproval: true,
        approvedAt: nil,
        approvedByDeviceID: nil,
        workerDeviceID: nil,
        workerLeaseExpiresAt: nil,
        attemptCount: 0,
        lastAttemptAt: nil,
        lastError: nil,
        platformPublishID: nil,
        createdAt: now,
        updatedAt: now
    )
}

private func makeSlideshowDraft(
    id: UUID = UUID(),
    slides: [Slide]? = nil,
    now: Date = Date()
) -> SlideshowDraft {
    SlideshowDraft(
        id: id,
        title: "Launch Carousel",
        campaignID: nil,
        templateID: nil,
        brief: "Launch brief",
        topic: "Product launch",
        audience: "Creators",
        goal: "Increase installs",
        tone: "Direct",
        narrativeArc: ["Hook", "Proof"],
        globalVisualMotif: "Clean product frames",
        planSummary: "Two-slide launch story",
        slides: slides ?? [makeSlide(now: now)],
        caption: "Try Flick",
        hashtags: ["flick"],
        targetPlatforms: [.tiktok],
        status: .draft,
        exportedImageAssetIDs: [],
        createdAt: now,
        updatedAt: now
    )
}

private func makeSlide(
    id: UUID = UUID(),
    imageAssetID: UUID? = nil,
    generationStatus: SlideGenerationStatus = .notStarted,
    now: Date = Date()
) -> Slide {
    Slide(
        id: id,
        index: 0,
        imageAssetID: imageAssetID,
        prompt: "A polished app screenshot on a phone.",
        text: "Grow faster",
        textPosition: .left,
        textStyle: SlideTextStyle(
            fontName: "System Rounded",
            weight: "Black",
            sizeScale: 1.0,
            foregroundHex: "#FFFFFF",
            outlineColorHex: "#111111"
        ),
        selectedVisualSummary: "Phone with dashboard",
        generationStatus: generationStatus,
        createdAt: now,
        updatedAt: now
    )
}

private func makeMediaAsset(
    id: UUID = UUID(),
    source: AssetSource = .generated,
    localFilePath: String? = nil,
    publicURL: URL? = nil,
    width: Int = 1080,
    height: Int = 1920,
    now: Date = Date()
) -> MediaAsset {
    MediaAsset(
        id: id,
        mediaType: .image,
        source: source,
        localFilePath: localFilePath,
        storageBucket: "flick-generated-images",
        storagePath: "generated-slides/\(id.uuidString).png",
        publicURL: publicURL,
        signedURLExpiration: nil,
        width: width,
        height: height,
        duration: nil,
        fileSize: 1024,
        checksum: nil,
        trendTags: [],
        createdAt: now,
        updatedAt: now
    )
}

@MainActor
private final class InMemoryFlickRepository: FlickRepository {
    var state: FlickOverviewState

    init(state: FlickOverviewState) {
        self.state = state
    }

    func loadOverview() async throws -> FlickOverviewState {
        state
    }

    func saveOverview(_ state: FlickOverviewState) async throws {
        self.state = state
    }

    func upsertAsset(_ asset: MediaAsset) async throws {
        state.assets.removeAll { $0.id == asset.id }
        state.assets.insert(asset, at: 0)
    }

    func deleteAsset(id: UUID) async throws {
        state.assets.removeAll { $0.id == id }
    }
}

@MainActor
private enum LiveAppModelTestCache {
    static let model = FlickAppModel.live()
}

private final class MemorySecretStore: SecretStoring {
    private var values: [String: Data] = [:]

    func data(for key: String) throws -> Data? {
        values[key]
    }

    func save(_ data: Data, for key: String) throws {
        values[key] = data
    }

    func delete(_ key: String) throws {
        values[key] = nil
    }
}

private extension Array where Element == URLQueryItem {
    func value(named name: String) -> String? {
        first { $0.name == name }?.value
    }
}
