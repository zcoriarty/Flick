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

    func testDeletingCreateDraftRemovesDraftSlidesAndDraftOwnedAssetsFromCoreData() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let persistenceController = PersistenceController(inMemory: true)
        let context = persistenceController.container.viewContext
        let repository = CoreDataFlickRepository(
            context: context,
            cloudAvailability: { false }
        )
        let generatedAsset = makeMediaAsset(
            source: .generated,
            localFilePath: "/tmp/flick-generated-\(UUID().uuidString).png",
            now: now
        )
        let renderedAsset = makeMediaAsset(
            source: .rendered,
            localFilePath: "/tmp/flick-rendered-\(UUID().uuidString).png",
            now: now
        )
        let uploadedAsset = makeMediaAsset(
            source: .uploaded,
            localFilePath: "/tmp/flick-uploaded-\(UUID().uuidString).png",
            now: now
        )
        var draft = makeSlideshowDraft(
            slides: [
                makeSlide(imageAssetID: generatedAsset.id, generationStatus: .complete, now: now),
                makeSlide(imageAssetID: uploadedAsset.id, generationStatus: .complete, now: now)
            ],
            now: now
        )
        draft.exportedImageAssetIDs = [renderedAsset.id]
        var state = FlickEmptyState.make(now: now)
        state.assets = [generatedAsset, renderedAsset, uploadedAsset]
        state.drafts = [draft]

        try await repository.saveOverview(state)

        let model = FlickAppModel(repository: repository, configuration: .current)
        await model.refresh()
        model.selectCreateDraft(id: draft.id)
        await model.deleteCreateDraft(id: draft.id)
        let loaded = try await repository.loadOverview()

        XCTAssertNil(model.activeCreateDraftID)
        XCTAssertTrue(model.overview.drafts.isEmpty)
        XCTAssertTrue(loaded.drafts.isEmpty)
        XCTAssertEqual(Set(model.overview.assets.map(\.id)), [uploadedAsset.id])
        XCTAssertEqual(Set(loaded.assets.map(\.id)), [uploadedAsset.id])
        XCTAssertEqual(try managedObjectCount(entityName: "CDSlideshowDraft", in: context), 0)
        XCTAssertEqual(try managedObjectCount(entityName: "CDSlide", in: context), 0)
        XCTAssertEqual(try managedObjectCount(entityName: "CDAsset", in: context), 1)
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

    func testTikTokAdapterRefreshesExpiredAccessTokenBeforePublishing() async throws {
        let secretStore = MemorySecretStore()
        let account = LoginKitAccountMapper.connectedAccount(
            from: LoginKitAuthorizedUser(
                platform: .tiktok,
                openID: "real-open-id",
                displayName: "@realaccount",
                avatarURL: nil,
                scopes: ["user.info.basic", "video.publish", "video.upload"]
            )
        )
        let expiredBundle = LoginKitTokenBundle(
            platform: .tiktok,
            platformUserID: account.platformUserID,
            accessToken: "expired-access-token",
            refreshToken: "refresh-token",
            tokenType: "Bearer",
            scopes: account.scopes,
            accessTokenExpiresAt: Date(timeIntervalSinceNow: -60),
            refreshTokenExpiresAt: Date(timeIntervalSinceNow: 3_600),
            updatedAt: Date(timeIntervalSinceNow: -120)
        )
        try LoginKitTokenStore(store: secretStore).save(expiredBundle, for: account)

        let publishAuthorizationHeader = CapturingURLProtocol.CapturedValue()
        CapturingURLProtocol.requestHandler = { request in
            switch request.url?.path.removingTrailingSlash {
            case "/v2/oauth/token":
                let body = request.encodedBodyString
                XCTAssertTrue(body.contains("grant_type=refresh_token"))
                XCTAssertTrue(body.contains("refresh_token=refresh-token"))
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(
                        """
                        {
                            "access_token": "refreshed-access-token",
                            "expires_in": 86400,
                            "open_id": "real-open-id",
                            "refresh_expires_in": 31536000,
                            "refresh_token": "new-refresh-token",
                            "scope": "user.info.basic,video.publish,video.upload",
                            "token_type": "Bearer"
                        }
                        """.utf8
                    )
                )
            case "/v2/post/publish/content/init":
                publishAuthorizationHeader.value = request.value(forHTTPHeaderField: "Authorization")
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(
                        """
                        {
                            "data": {
                                "publish_id": "p_pub_url~v2.123"
                            },
                            "error": {
                                "code": "ok",
                                "message": "",
                                "log_id": "log-123"
                            }
                        }
                        """.utf8
                    )
                )
            default:
                XCTFail("Unexpected request URL: \(request.url?.absoluteString ?? "nil")")
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!,
                    Data()
                )
            }
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let adapter = TikTokAdapter(
            configuration: TikTokConfiguration(values: [
                "TIKTOK_CLIENT_ID": "client-key",
                "TIKTOK_CLIENT_SECRET": "client-secret",
                "TIKTOK_VERIFIED_BASE_URL": "https://example.com"
            ]),
            tokenStore: secretStore,
            urlSession: session
        )
        var job = makePublishingJob()
        job.accountID = account.id
        let result = try await adapter.publish(
            job,
            account: account,
            media: PreparedPlatformMedia(
                mode: .photoDirectPost,
                imageURLs: [try XCTUnwrap(URL(string: "https://example.com/rendered-slide.png"))],
                videoURL: nil,
                warnings: []
            ),
            settings: TikTokManualPublishSettings(
                title: "Launch",
                description: "Try Flick",
                postAsDraft: false,
                privacyLevel: .selfOnly,
                allowComment: true,
                allowDuet: false,
                allowStitch: false,
                disclosesVideoContent: false,
                promotesYourBrand: false,
                promotesBrandedContent: false
            )
        )

        XCTAssertEqual(result.platformPostID, "p_pub_url~v2.123")
        XCTAssertEqual(publishAuthorizationHeader.value, "Bearer refreshed-access-token")
        let storedBundle = try XCTUnwrap(LoginKitTokenStore(store: secretStore).tokenBundle(for: account))
        XCTAssertEqual(storedBundle.accessToken, "refreshed-access-token")
        XCTAssertEqual(storedBundle.refreshToken, "new-refresh-token")
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

        XCTAssertEqual(SlideshowImageGenerationSettings.finalExport.size, "1024x1536")
        XCTAssertEqual(SlideshowImageGenerationSettings.finalExport.width, 1024)
        XCTAssertEqual(SlideshowImageGenerationSettings.finalExport.height, 1536)
        XCTAssertEqual(SlideshowImageGenerationSettings.finalExport.aspectRatio, 2.0 / 3.0)
    }

    func testSlideshowImageGenerationSettingsRejectHorizontalAssets() {
        let verticalAsset = makeMediaAsset(width: 1024, height: 1536)
        let horizontalAsset = makeMediaAsset(width: 2560, height: 1440)

        XCTAssertTrue(SlideshowImageGenerationSettings.finalExport.isSatisfied(by: verticalAsset))
        XCTAssertFalse(SlideshowImageGenerationSettings.finalExport.isSatisfied(by: horizontalAsset))
    }

    func testGeneratedImagePromptOverridesStaleHorizontalFormat() {
        let prompt = SlideshowImagePromptFormatter.applyVerticalOutputContract(
            to: "Create a 16:9 horizontal social slideshow image with no readable text.",
            settings: .draft
        )

        XCTAssertTrue(prompt.contains("vertical portrait image"))
        XCTAssertTrue(prompt.contains("720x1280 portrait canvas"))
        XCTAssertTrue(prompt.contains("ignore that stale format instruction"))
        XCTAssertTrue(prompt.contains("stale output size"))
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
    width: Int = 1024,
    height: Int = 1536,
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

private func managedObjectCount(entityName: String, in context: NSManagedObjectContext) throws -> Int {
    let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
    return try context.count(for: request)
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

private final class CapturingURLProtocol: URLProtocol {
    final class CapturedValue {
        var value: String?
    }

    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension Array where Element == URLQueryItem {
    func value(named name: String) -> String? {
        first { $0.name == name }?.value
    }
}

private extension Optional where Wrapped == String {
    var removingTrailingSlash: String? {
        guard let self else { return nil }
        return self.hasSuffix("/") ? String(self.dropLast()) : self
    }
}

private extension String {
    var removingTrailingSlash: String {
        hasSuffix("/") ? String(dropLast()) : self
    }
}

private extension URLRequest {
    var encodedBodyString: String {
        if let httpBody {
            return String(data: httpBody, encoding: .utf8) ?? ""
        }

        guard let httpBodyStream else { return "" }
        httpBodyStream.open()
        defer { httpBodyStream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while httpBodyStream.hasBytesAvailable {
            let readCount = httpBodyStream.read(buffer, maxLength: bufferSize)
            guard readCount > 0 else { break }
            data.append(buffer, count: readCount)
        }

        return String(data: data, encoding: .utf8) ?? ""
    }
}
