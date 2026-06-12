//
//  FlickTests.swift
//  FlickTests
//

import CoreData
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Flick

#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class FlickTests: XCTestCase {
    func testLiveAppModelStartsWithoutSeedData() {
        let model = LiveAppModelTestCache.model

        XCTAssertTrue(model.overview.drafts.isEmpty)
        XCTAssertTrue(model.overview.publishingJobs.isEmpty)
    }

    func testCreateFlowDoesNotAutoSelectPersistedDraftOnRefresh() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let draft = makeSlideshowDraft(now: now)
        var state = FlickEmptyState.make()
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

        var state = FlickEmptyState.make()
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
        let creationModel = makeCreationModel(now: now)
        let slide = makeSlide(imageAssetID: asset.id, generationStatus: .complete, now: now)
        let draft = makeSlideshowDraft(
            slides: [slide],
            creationModel: creationModel.generationReference,
            imageVibe: .warmFilm,
            now: now
        )
        var state = FlickEmptyState.make()
        state.creationModels = [creationModel]
        state.assets = [asset]
        state.drafts = [draft]

        try await repository.saveOverview(state)
        let loaded = try await repository.loadOverview()
        let loadedDraft = try XCTUnwrap(loaded.drafts.first)
        let loadedSlide = try XCTUnwrap(loadedDraft.slides.first)
        let loadedAsset = try XCTUnwrap(loaded.assets.first)

        XCTAssertEqual(loadedSlide.imageAssetID, asset.id)
        XCTAssertEqual(loadedSlide.generationStatus, .complete)
        XCTAssertEqual(loadedDraft.creationModel?.id, creationModel.id)
        XCTAssertEqual(loadedDraft.creationModel?.name, creationModel.name)
        XCTAssertEqual(loadedDraft.imageVibe, .warmFilm)
        XCTAssertEqual(loadedAsset.id, asset.id)
        XCTAssertEqual(loadedAsset.source, .generated)
        XCTAssertEqual(loadedAsset.publicURL, asset.publicURL)
    }

    func testCoreDataRoundTripsProductsAndMediaProductLinks() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let persistenceController = PersistenceController(inMemory: true)
        let repository = CoreDataFlickRepository(
            context: persistenceController.container.viewContext,
            cloudAvailability: { false }
        )
        let product = makeProduct(name: "Flick Pro", now: now)
        let asset = makeMediaAsset(
            source: .uploaded,
            localFilePath: "/tmp/flick-product-\(UUID().uuidString).jpg",
            productIDs: [product.id],
            now: now
        )
        var state = FlickEmptyState.make()
        state.products = [product]
        state.assets = [asset]

        try await repository.saveOverview(state)
        let loaded = try await repository.loadOverview()
        let loadedProduct = try XCTUnwrap(loaded.products.first)
        let loadedAsset = try XCTUnwrap(loaded.assets.first)

        XCTAssertEqual(loadedProduct, product)
        XCTAssertEqual(loadedAsset.productIDs, [product.id])
    }

    func testCoreDataRoundTripsCreationModels() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let persistenceController = PersistenceController(inMemory: true)
        let repository = CoreDataFlickRepository(
            context: persistenceController.container.viewContext,
            cloudAvailability: { false }
        )
        let creationModel = makeCreationModel(now: now)
        var state = FlickEmptyState.make()
        state.creationModels = [creationModel]

        try await repository.saveOverview(state)
        let loaded = try await repository.loadOverview()
        let loadedModel = try XCTUnwrap(loaded.creationModels.first)
        let aiMetadataJSON = try XCTUnwrap(String(data: try loadedModel.aiMetadataJSONData(), encoding: .utf8))

        XCTAssertEqual(loadedModel, creationModel)
        XCTAssertTrue(aiMetadataJSON.contains("\"skin_details\""))
        XCTAssertTrue(aiMetadataJSON.contains("\"style_and_accessories\""))
        XCTAssertTrue(aiMetadataJSON.contains("Cottagecore"))
    }

    func testCoreDataRoundTripsCreativeTemplateSourceFields() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let persistenceController = PersistenceController(inMemory: true)
        let repository = CoreDataFlickRepository(
            context: persistenceController.container.viewContext,
            cloudAvailability: { false }
        )
        let template = CreativeTemplate(
            id: UUID(),
            name: "Cached Fitness Style",
            description: "Shared template analysis",
            platform: .tiktok,
            slideCount: 3,
            styleJSON: makeTemplateStyleGuide(styleName: "Cached Fitness").encodedJSONString(),
            defaultTextRules: "No readable text.",
            sourceTemplateID: "fitness-template-1",
            sourceTemplateFingerprint: "fingerprint-1",
            analysisSchemaVersion: TemplateAnalysisCacheService.schemaVersion,
            tags: [],
            createdAt: now,
            updatedAt: now
        )
        var state = FlickEmptyState.make()
        state.templates = [template]

        try await repository.saveOverview(state)
        let loaded = try await repository.loadOverview()
        let loadedTemplate = try XCTUnwrap(loaded.templates.first)

        XCTAssertEqual(loadedTemplate.sourceTemplateID, template.sourceTemplateID)
        XCTAssertEqual(loadedTemplate.sourceTemplateFingerprint, template.sourceTemplateFingerprint)
        XCTAssertEqual(loadedTemplate.analysisSchemaVersion, template.analysisSchemaVersion)
        XCTAssertEqual(loadedTemplate.decodedStyleGuide?.styleName, "Cached Fitness")
    }

    func testCoreDataRoundTripsConnectedAccounts() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let persistenceController = PersistenceController(inMemory: true)
        let repository = CoreDataFlickRepository(
            context: persistenceController.container.viewContext,
            cloudAvailability: { false }
        )
        let account = makeConnectedAccount(now: now)
        var state = FlickEmptyState.make()
        state.accounts = [account]

        try await repository.saveOverview(state)
        let loaded = try await repository.loadOverview()
        let loadedAccount = try XCTUnwrap(loaded.accounts.first)

        XCTAssertEqual(loadedAccount, account)
        XCTAssertEqual(loaded.dashboard.connectedAccounts, [account])
    }

    func testCoreDataPreservesMacRunnerHeartbeatDuringOverviewSaves() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let persistenceController = PersistenceController(inMemory: true)
        let repository = CoreDataFlickRepository(
            context: persistenceController.container.viewContext,
            cloudAvailability: { false }
        )
        var state = FlickEmptyState.make()
        state.products = [makeProduct(name: "Flick Pro", now: now)]

        try await repository.saveMacRunnerHeartbeat(MacRunnerHeartbeat(lastSeenAt: now))
        try await repository.saveOverview(state)

        let loaded = try await repository.loadOverview()
        XCTAssertEqual(loaded.macRunnerHeartbeat.lastSeenAt, now)
    }

    func testMacRunnerHeartbeatFreshnessExpires() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertTrue(MacRunnerHeartbeat(lastSeenAt: now.addingTimeInterval(-60)).isFresh(asOf: now))
        XCTAssertFalse(
            MacRunnerHeartbeat(lastSeenAt: now.addingTimeInterval(-MacRunnerHeartbeat.staleAfter - 1))
                .isFresh(asOf: now)
        )
        XCTAssertFalse(MacRunnerHeartbeat().isFresh(asOf: now))
    }

    func testPublishingTikTokAccountUsesSelectedAccountID() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let firstAccount = makeConnectedAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            platformUserID: "first-open-id",
            displayName: "@alpha",
            now: now
        )
        let secondAccount = makeConnectedAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            platformUserID: "second-open-id",
            displayName: "@zeta",
            now: now
        )
        var draft = makeSlideshowDraft(now: now)
        draft.accountSelections = [
            PlatformAccountSelection(platform: .tiktok, accountID: secondAccount.id)
        ]
        var state = FlickEmptyState.make()
        state.accounts = [firstAccount, secondAccount]
        state.drafts = [draft]
        let secretStore = MemorySecretStore()
        let tokenStore = LoginKitTokenStore(store: secretStore)
        try tokenStore.save(
            LoginKitTokenBundle(
                platform: .tiktok,
                platformUserID: secondAccount.platformUserID,
                accessToken: "access-token",
                refreshToken: "refresh-token",
                tokenType: "Bearer",
                scopes: secondAccount.scopes,
                accessTokenExpiresAt: now.addingTimeInterval(3_600),
                refreshTokenExpiresAt: now.addingTimeInterval(86_400),
                updatedAt: now
            ),
            for: secondAccount
        )
        let client = TikTokLoginKitClient(
            accountStore: LoginKitAccountStore(store: secretStore),
            tokenStore: tokenStore
        )
        let model = FlickAppModel(
            repository: InMemoryFlickRepository(state: state),
            configuration: .current,
            tiktokLoginKitClient: client
        )
        model.overview = state

        XCTAssertEqual(model.publishingTikTokAccount(for: draft)?.id, secondAccount.id)
    }

    func testPublishingTikTokAccountRequiresSelectedAccount() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let account = makeConnectedAccount(now: now)
        let draft = makeSlideshowDraft(now: now)
        var state = FlickEmptyState.make()
        state.accounts = [account]
        state.drafts = [draft]
        let model = FlickAppModel(repository: InMemoryFlickRepository(state: state), configuration: .current)
        model.overview = state

        XCTAssertNil(model.publishingTikTokAccount(for: draft))
    }

    func testPublishingTikTokAccountUsesGrantedScopesWhenTokenBundleScopesAreMissing() throws {
        let now = Date()
        var account = makeConnectedAccount(now: now)
        account.scopes = ["user.info.basic", "video.upload"]
        account.isPublishingEnabled = true
        var draft = makeSlideshowDraft(now: now)
        draft.accountSelections = [
            PlatformAccountSelection(platform: .tiktok, accountID: account.id)
        ]
        var state = FlickEmptyState.make()
        state.accounts = [account]
        state.drafts = [draft]
        let secretStore = MemorySecretStore()
        let tokenStore = LoginKitTokenStore(store: secretStore)
        try tokenStore.save(
            LoginKitTokenBundle(
                platform: .tiktok,
                platformUserID: account.platformUserID,
                accessToken: "access-token",
                refreshToken: "refresh-token",
                tokenType: "Bearer",
                scopes: [],
                accessTokenExpiresAt: now.addingTimeInterval(3_600),
                refreshTokenExpiresAt: now.addingTimeInterval(86_400),
                updatedAt: now
            ),
            for: account
        )
        let client = TikTokLoginKitClient(
            accountStore: LoginKitAccountStore(store: secretStore),
            tokenStore: tokenStore
        )
        let model = FlickAppModel(
            repository: InMemoryFlickRepository(state: state),
            configuration: makeTestAppConfiguration(),
            tiktokLoginKitClient: client
        )
        model.overview = state

        XCTAssertEqual(model.publishingTikTokAccount(for: draft)?.id, account.id)
    }

    func testPlatformAccountSelectionsNormalizeUniquePlatformAccountPairs() {
        let firstTikTokID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let secondTikTokID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let youtubeID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let selections = [
            PlatformAccountSelection(platform: .tiktok, accountID: firstTikTokID),
            PlatformAccountSelection(platform: .tiktok, accountID: secondTikTokID),
            PlatformAccountSelection(platform: .tiktok, accountID: firstTikTokID),
            PlatformAccountSelection(platform: .youtubeShorts, accountID: youtubeID),
            PlatformAccountSelection(platform: .youtubeShorts, accountID: youtubeID)
        ]

        let normalized = selections.normalizedUniqueSelections()

        XCTAssertEqual(normalized.accountIDs(for: .tiktok), [firstTikTokID, secondTikTokID])
        XCTAssertEqual(normalized.accountIDs(for: .youtubeShorts), [youtubeID])
        XCTAssertEqual(normalized.count, 3)
    }

    func testPublishingAccountsUsesLocalYouTubeTokenStore() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let account = makeYouTubeAccount(now: now)
        let tokenStore = YouTubeTokenStore(store: MemorySecretStore())
        var state = FlickEmptyState.make()
        state.accounts = [account]
        let model = FlickAppModel(
            repository: InMemoryFlickRepository(state: state),
            configuration: makeTestAppConfiguration(),
            youtubeOAuthClient: YouTubeOAuthClient(tokenStore: tokenStore)
        )
        model.overview = state
        let selections = [PlatformAccountSelection(platform: .youtubeShorts, accountID: account.id)]

        XCTAssertTrue(model.publishingAccounts(for: .youtubeShorts, in: selections).isEmpty)

        try tokenStore.save(
            LoginKitTokenBundle(
                platform: .youtubeShorts,
                platformUserID: account.platformUserID,
                accessToken: "access-token",
                refreshToken: "refresh-token",
                tokenType: "Bearer",
                scopes: [YouTubeConfiguration.uploadScope, YouTubeConfiguration.readonlyScope],
                accessTokenExpiresAt: now.addingTimeInterval(3_600),
                refreshTokenExpiresAt: now.addingTimeInterval(86_400),
                updatedAt: now
            ),
            for: account
        )

        XCTAssertEqual(model.publishingAccounts(for: .youtubeShorts, in: selections).map(\.id), [account.id])
    }

    func testYouTubeShortsAdapterBuildsVideosInsertResumableUploadRequest() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let account = makeYouTubeAccount(now: now)
        let tokenStore = YouTubeTokenStore(store: MemorySecretStore())
        try tokenStore.save(
            LoginKitTokenBundle(
                platform: .youtubeShorts,
                platformUserID: account.platformUserID,
                accessToken: "youtube-access-token",
                refreshToken: "youtube-refresh-token",
                tokenType: "Bearer",
                scopes: [YouTubeConfiguration.uploadScope, YouTubeConfiguration.readonlyScope],
                accessTokenExpiresAt: now.addingTimeInterval(3_600),
                refreshTokenExpiresAt: now.addingTimeInterval(86_400),
                updatedAt: now
            ),
            for: account
        )

        let insertURL = CapturingURLProtocol.CapturedValue()
        let insertAuthorizationHeader = CapturingURLProtocol.CapturedValue()
        let insertContentType = CapturingURLProtocol.CapturedValue()
        let uploadContentType = CapturingURLProtocol.CapturedValue()
        let uploadContentLength = CapturingURLProtocol.CapturedValue()
        let insertBody = CapturingURLProtocol.CapturedValue()
        let uploadMethod = CapturingURLProtocol.CapturedValue()
        CapturingURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            if url.host == "www.googleapis.com" {
                insertURL.value = url.absoluteString
                insertAuthorizationHeader.value = request.value(forHTTPHeaderField: "Authorization")
                insertContentType.value = request.value(forHTTPHeaderField: "Content-Type")
                uploadContentType.value = request.value(forHTTPHeaderField: "X-Upload-Content-Type")
                uploadContentLength.value = request.value(forHTTPHeaderField: "X-Upload-Content-Length")
                insertBody.value = request.httpBodyStringForTests
                return (
                    try XCTUnwrap(HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Location": "https://upload.example.com/session"]
                    )),
                    Data()
                )
            }

            uploadMethod.value = request.httpMethod
            return (
                try XCTUnwrap(HTTPURLResponse(
                    url: url,
                    statusCode: 201,
                    httpVersion: nil,
                    headerFields: nil
                )),
                Data("""
                {
                    "id": "shorts-video-id",
                    "status": {
                        "uploadStatus": "uploaded",
                        "privacyStatus": "private"
                    }
                }
                """.utf8)
            )
        }
        defer { CapturingURLProtocol.requestHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let videoURL = FileManager.default.temporaryDirectory
            .appending(path: "youtube-shorts-adapter-\(UUID().uuidString).mp4")
        try Data([0, 1, 2, 3]).write(to: videoURL)
        defer { try? FileManager.default.removeItem(at: videoURL) }
        let adapter = YouTubeShortsAdapter(
            configuration: makeTestAppConfiguration(values: ["GOOGLE_CLIENT_ID": "client-id"]).youtube,
            tokenStore: tokenStore,
            urlSession: session
        )
        let settings = YouTubeManualPublishSettings(
            title: "Shorts title",
            description: "Shorts description",
            tags: ["flick", "launch"],
            privacyStatus: .private,
            categoryID: "22",
            selfDeclaredMadeForKids: false,
            containsSyntheticMedia: true,
            notifySubscribers: false
        )
        let job = PublishingJob(
            id: UUID(),
            platform: .youtubeShorts,
            accountID: account.id,
            automationID: nil,
            draftID: UUID(),
            status: .publishing,
            publishMode: .videoDirectPost,
            attemptCount: 0,
            lastAttemptAt: nil,
            lastError: nil,
            platformPublishID: nil,
            createdAt: now,
            updatedAt: now
        )

        let result = try await adapter.publish(
            job,
            account: account,
            media: PreparedPlatformMedia(mode: .videoDirectPost, imageURLs: [], videoURL: videoURL, warnings: []),
            settings: settings
        )

        XCTAssertEqual(result.platform, .youtubeShorts)
        XCTAssertEqual(result.platformPostID, "shorts-video-id")
        XCTAssertEqual(result.platformURL, URL(string: "https://www.youtube.com/shorts/shorts-video-id"))
        XCTAssertEqual(insertAuthorizationHeader.value, "Bearer youtube-access-token")
        XCTAssertEqual(insertContentType.value, "application/json; charset=UTF-8")
        XCTAssertEqual(uploadContentType.value, "video/mp4")
        XCTAssertEqual(uploadContentLength.value, "4")
        XCTAssertTrue(try XCTUnwrap(insertURL.value).contains("uploadType=resumable"))
        XCTAssertTrue(try XCTUnwrap(insertURL.value).contains("part=snippet,status"))
        XCTAssertTrue(try XCTUnwrap(insertURL.value).contains("notifySubscribers=false"))
        XCTAssertEqual(uploadMethod.value, "PUT")

        let bodyData = Data(try XCTUnwrap(insertBody.value).utf8)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let snippet = try XCTUnwrap(body["snippet"] as? [String: Any])
        let status = try XCTUnwrap(body["status"] as? [String: Any])
        XCTAssertEqual(snippet["title"] as? String, "Shorts title")
        XCTAssertEqual(snippet["description"] as? String, "Shorts description")
        XCTAssertEqual(snippet["tags"] as? [String], ["flick", "launch"])
        XCTAssertEqual(snippet["categoryId"] as? String, "22")
        XCTAssertEqual(status["privacyStatus"] as? String, "private")
        XCTAssertEqual(status["selfDeclaredMadeForKids"] as? Bool, false)
        XCTAssertEqual(status["containsSyntheticMedia"] as? Bool, true)
    }

    func testConnectedAccountUpsertUpdateAndDeleteUseRepository() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let repository = InMemoryFlickRepository(state: FlickEmptyState.make())
        let model = FlickAppModel(repository: repository, configuration: .current)
        var account = makeConnectedAccount(now: now)

        try await model.upsertConnectedAccount(account)

        XCTAssertEqual(model.overview.accounts.map(\.id), [account.id])
        XCTAssertEqual(repository.state.accounts.map(\.id), [account.id])

        account.displayName = "@updated"
        account.isPublishingEnabled = false
        try await model.upsertConnectedAccount(account)

        XCTAssertEqual(model.overview.accounts.first?.displayName, "@updated")
        XCTAssertEqual(repository.state.accounts.first?.displayName, "@updated")
        XCTAssertEqual(repository.state.accounts.first?.isPublishingEnabled, false)

        try await model.deleteConnectedAccount(id: account.id)

        XCTAssertTrue(model.overview.accounts.isEmpty)
        XCTAssertTrue(model.overview.dashboard.connectedAccounts.isEmpty)
        XCTAssertTrue(repository.state.accounts.isEmpty)
    }

    func testRecordingMacRunnerHeartbeatUsesDedicatedRepositoryWrite() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let repository = InMemoryFlickRepository(state: FlickEmptyState.make())
        let model = FlickAppModel(repository: repository, configuration: .current)

        await model.recordMacRunnerHeartbeat(now: now)

        XCTAssertEqual(model.overview.macRunnerHeartbeat.lastSeenAt, now)
        XCTAssertEqual(repository.state.macRunnerHeartbeat.lastSeenAt, now)
    }

    func testCreationModelCreateUpdateAndDeleteUseRepository() async throws {
        let repository = InMemoryFlickRepository(state: FlickEmptyState.make())
        let model = FlickAppModel(repository: repository, configuration: .current)

        let createdModel = try await model.createCreationModel(
            name: "  Launch Host  ",
            metadata: CreationModelPreset.hotBlondeFitnessInfluencer.metadata
        )

        XCTAssertEqual(model.overview.creationModels.map(\.id), [createdModel.id])
        XCTAssertEqual(model.overview.creationModels.first?.name, "Launch Host")
        XCTAssertEqual(model.overview.creationModels.first?.metadata.styleAndAccessories.aesthetic, "Athleisure")
        XCTAssertEqual(repository.state.creationModels.first?.name, "Launch Host")

        var updatedModel = createdModel
        updatedModel.name = "Launch Host v2"
        updatedModel.metadata.hair.color = "Auburn"
        updatedModel.metadata.styleAndAccessories.aesthetic = "Cottagecore"
        try await model.updateCreationModel(updatedModel)

        XCTAssertEqual(model.overview.creationModels.first?.name, "Launch Host v2")
        XCTAssertEqual(repository.state.creationModels.first?.metadata.hair.color, "Auburn")
        XCTAssertEqual(repository.state.creationModels.first?.metadata.styleAndAccessories.aesthetic, "Cottagecore")

        try await model.deleteCreationModel(id: createdModel.id)

        XCTAssertTrue(model.overview.creationModels.isEmpty)
        XCTAssertTrue(repository.state.creationModels.isEmpty)
    }

    func testCreationModelPresetsAndRandomizedMetadataPopulateFields() {
        let presetMetadata = CreationModelPreset.hotBlondeFitnessInfluencer.metadata
        let randomizedMetadata = CreationModelMetadata.randomized()

        XCTAssertEqual(CreationModelPreset.fromScratch.metadata, CreationModelMetadata())
        XCTAssertEqual(presetMetadata.identity.ageRange, "25-30")
        XCTAssertEqual(presetMetadata.styleAndAccessories.aesthetic, "Athleisure")

        for field in CreationModelField.allCases {
            let value = field.value(in: randomizedMetadata)
            XCTAssertFalse(value.isEmpty, "\(field.title) should be populated")
            XCTAssertTrue(field.options.contains(value), "\(field.title) should use a supported option")
        }
    }

    func testAddingProductMediaRequiresAndStoresProductSelection() async throws {
        let repository = InMemoryFlickRepository(state: FlickEmptyState.make())
        let mediaStorage = FakeMediaStorage()
        let model = FlickAppModel(
            repository: repository,
            configuration: .current,
            mediaStorageFactory: { _ in mediaStorage }
        )
        let product = try await model.createProduct(name: "Flick Pro", summary: "Launch assets")
        #if canImport(UIKit)
        let imageData = makeTestJPEGData(width: 72, height: 128)
        #else
        let imageData = Data([0xFF, 0xD8, 0xFF])
        #endif

        try await model.addProductMedia(
            data: imageData,
            contentType: .jpeg,
            productIDs: [product.id]
        )

        let asset = try XCTUnwrap(model.overview.assets.first)
        let uploadedPath = try XCTUnwrap(mediaStorage.uploadedPaths.first)
        XCTAssertEqual(asset.source, .uploaded)
        XCTAssertEqual(asset.productIDs, [product.id])
        XCTAssertEqual(asset.storageBucket, "flick-media")
        XCTAssertEqual(asset.storagePath, uploadedPath)
        XCTAssertEqual(asset.publicURL, URL(string: "https://media.example.com/\(uploadedPath)"))
        XCTAssertEqual(mediaStorage.uploadedContentTypes, ["image/jpeg"])
        XCTAssertEqual(uploadedPath.hasPrefix("product-media/\(product.id.uuidString)/"), true)
        #if canImport(UIKit)
        XCTAssertEqual(asset.width, 72)
        XCTAssertEqual(asset.height, 128)
        #endif
        XCTAssertEqual(repository.state.assets.first?.productIDs, [product.id])
        XCTAssertEqual(repository.state.assets.first?.publicURL, asset.publicURL)
    }

    func testStoredMediaPublicURLReconciliationRefreshesBucketAssets() throws {
        let mediaStorage = FakeMediaStorage()
        let model = FlickAppModel(
            repository: InMemoryFlickRepository(state: FlickEmptyState.make()),
            configuration: makeTestAppConfiguration(),
            mediaStorageFactory: { _ in mediaStorage }
        )
        let path = "rendered-image-sequences/draft-id/slide.jpg"
        let oldURL = try XCTUnwrap(URL(string: "https://flick-media.goingviral.club/flick-media/\(path)"))
        let newURL = try XCTUnwrap(URL(string: "https://media.example.com/\(path)"))
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let reconciledDate = Date(timeIntervalSince1970: 1_800_000_000)
        model.overview.assets = [
            makeMediaAsset(
                storagePath: path,
                publicURL: oldURL,
                now: oldDate
            )
        ]

        XCTAssertTrue(model.reconcileStoredMediaPublicURLs(now: reconciledDate))

        let asset = try XCTUnwrap(model.overview.assets.first)
        XCTAssertEqual(asset.publicURL, newURL)
        XCTAssertEqual(asset.updatedAt, reconciledDate)
    }

    func testDeletingProductRemovesOnlyOwnedMediaAndKeepsSharedMedia() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let deletedProduct = makeProduct(name: "Flick Pro", now: now)
        let retainedProduct = makeProduct(name: "Flick Lite", now: now)
        let onlyOwnedAsset = makeMediaAsset(
            source: .uploaded,
            productIDs: [deletedProduct.id],
            now: now
        )
        let sharedAsset = makeMediaAsset(
            source: .uploaded,
            productIDs: [deletedProduct.id, retainedProduct.id],
            now: now
        )
        var state = FlickEmptyState.make()
        state.products = [deletedProduct, retainedProduct]
        state.assets = [onlyOwnedAsset, sharedAsset]
        let repository = InMemoryFlickRepository(state: state)
        let model = FlickAppModel(repository: repository, configuration: .current)

        await model.refresh()
        try await model.deleteProduct(id: deletedProduct.id)

        XCTAssertEqual(model.overview.products.map(\.id), [retainedProduct.id])
        XCTAssertEqual(model.overview.assets.map(\.id), [sharedAsset.id])
        XCTAssertEqual(model.overview.assets.first?.productIDs, [retainedProduct.id])
        XCTAssertEqual(repository.state.products.map(\.id), [retainedProduct.id])
        XCTAssertEqual(repository.state.assets.map(\.id), [sharedAsset.id])
    }

    func testDeletingProductPausesAutomationAndClearsProductImageSelection() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let product = makeProduct(name: "Flick Pro", now: now)
        let asset = makeMediaAsset(
            source: .uploaded,
            publicURL: try XCTUnwrap(URL(string: "https://example.com/product.jpg")),
            productIDs: [product.id],
            now: now
        )
        let nextScheduledAt = Date(timeInterval: 3_600, since: now)
        let automation = ContentAutomation(
            name: "Product posts",
            templateIDs: ["template-a"],
            productID: product.id,
            productImageAssetIDs: [asset.id],
            schedule: AutomationSchedule(),
            tikTokSettings: DraftTikTokSettings(title: "Try Flick", privacyLevel: .publicToEveryone),
            status: .active,
            nextScheduledAt: nextScheduledAt,
            createdAt: now,
            updatedAt: now
        )
        var state = FlickEmptyState.make()
        state.products = [product]
        state.assets = [asset]
        state.automations = [automation]
        let repository = InMemoryFlickRepository(state: state)
        let model = FlickAppModel(repository: repository, configuration: .current)

        await model.refresh()
        try await model.deleteProduct(id: product.id)

        let updatedAutomation = try XCTUnwrap(model.overview.automations.first)
        XCTAssertNil(updatedAutomation.productID)
        XCTAssertTrue(updatedAutomation.productImageAssetIDs.isEmpty)
        XCTAssertEqual(updatedAutomation.status, .paused)
        XCTAssertNil(updatedAutomation.nextScheduledAt)
        XCTAssertEqual(
            updatedAutomation.lastErrorMessage,
            "The selected product was deleted. Choose a new product and images before reactivating this automation."
        )
        XCTAssertTrue(repository.state.products.isEmpty)
        XCTAssertTrue(repository.state.assets.isEmpty)
        XCTAssertNil(repository.state.automations.first?.productID)
        XCTAssertTrue(repository.state.automations.first?.productImageAssetIDs.isEmpty == true)
    }

    func testRemovingProductMediaPrunesAutomationImageSelection() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let product = makeProduct(name: "Flick Pro", now: now)
        let removedAsset = makeMediaAsset(
            source: .uploaded,
            publicURL: try XCTUnwrap(URL(string: "https://example.com/removed.jpg")),
            productIDs: [product.id],
            now: now
        )
        let retainedAsset = makeMediaAsset(
            source: .uploaded,
            publicURL: try XCTUnwrap(URL(string: "https://example.com/retained.jpg")),
            productIDs: [product.id],
            now: now
        )
        let nextScheduledAt = Date(timeInterval: 3_600, since: now)
        let automation = ContentAutomation(
            name: "Product posts",
            templateIDs: ["template-a"],
            productID: product.id,
            productImageAssetIDs: [removedAsset.id, retainedAsset.id],
            schedule: AutomationSchedule(),
            tikTokSettings: DraftTikTokSettings(title: "Try Flick", privacyLevel: .publicToEveryone),
            status: .active,
            nextScheduledAt: nextScheduledAt,
            createdAt: now,
            updatedAt: now
        )
        var state = FlickEmptyState.make()
        state.products = [product]
        state.assets = [removedAsset, retainedAsset]
        state.automations = [automation]
        let repository = InMemoryFlickRepository(state: state)
        let model = FlickAppModel(repository: repository, configuration: .current)

        await model.refresh()
        try await model.removeProductMedia(removedAsset)

        let updatedAutomation = try XCTUnwrap(model.overview.automations.first)
        XCTAssertEqual(updatedAutomation.productImageAssetIDs, [retainedAsset.id])
        XCTAssertEqual(updatedAutomation.status, .active)
        XCTAssertEqual(updatedAutomation.nextScheduledAt, nextScheduledAt)
        XCTAssertNil(updatedAutomation.lastErrorMessage)
        XCTAssertEqual(repository.state.automations.first?.productImageAssetIDs, [retainedAsset.id])
        XCTAssertEqual(repository.state.assets.map(\.id), [retainedAsset.id])
    }

    func testDetachingLastProductImagePausesAutomation() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let originalProduct = makeProduct(name: "Flick Pro", now: now)
        let retainedProduct = makeProduct(name: "Flick Lite", now: now)
        let asset = makeMediaAsset(
            source: .uploaded,
            publicURL: try XCTUnwrap(URL(string: "https://example.com/product.jpg")),
            productIDs: [originalProduct.id, retainedProduct.id],
            now: now
        )
        let nextScheduledAt = Date(timeInterval: 3_600, since: now)
        let automation = ContentAutomation(
            name: "Product posts",
            templateIDs: ["template-a"],
            productID: originalProduct.id,
            productImageAssetIDs: [asset.id],
            schedule: AutomationSchedule(),
            tikTokSettings: DraftTikTokSettings(title: "Try Flick", privacyLevel: .publicToEveryone),
            status: .active,
            nextScheduledAt: nextScheduledAt,
            createdAt: now,
            updatedAt: now
        )
        var state = FlickEmptyState.make()
        state.products = [originalProduct, retainedProduct]
        state.assets = [asset]
        state.automations = [automation]
        let repository = InMemoryFlickRepository(state: state)
        let model = FlickAppModel(repository: repository, configuration: .current)

        await model.refresh()
        try await model.updateProductMediaProducts(assetID: asset.id, productIDs: [retainedProduct.id])

        let updatedAutomation = try XCTUnwrap(model.overview.automations.first)
        XCTAssertTrue(updatedAutomation.productImageAssetIDs.isEmpty)
        XCTAssertEqual(updatedAutomation.status, .paused)
        XCTAssertNil(updatedAutomation.nextScheduledAt)
        XCTAssertEqual(
            updatedAutomation.lastErrorMessage,
            "All selected product images were removed from Flick Pro. Choose at least one product image before reactivating this automation."
        )
        XCTAssertEqual(repository.state.assets.first?.productIDs, [retainedProduct.id])
        XCTAssertTrue(repository.state.automations.first?.productImageAssetIDs.isEmpty == true)
        XCTAssertEqual(repository.state.automations.first?.status, .paused)
    }

    func testCoreDataRoundTripsCreateDraftPublishFields() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let persistenceController = PersistenceController(inMemory: true)
        let repository = CoreDataFlickRepository(
            context: persistenceController.container.viewContext,
            cloudAvailability: { false }
        )
        let tikTokSettings = DraftTikTokSettings(
            title: "Launch day carousel",
            postAsDraft: false,
            privacyLevel: .publicToEveryone,
            allowComment: true,
            allowDuet: true,
            allowStitch: false,
            disclosesVideoContent: true,
            promotesYourBrand: true,
            promotesBrandedContent: false
        )
        let selectedSongs = [
            SelectedSong(
                id: "12345",
                title: "Morning Run",
                artist: "Flick Library",
                duration: 182
            )
        ]
        var draft = makeSlideshowDraft(now: now)
        let accountSelection = PlatformAccountSelection(platform: .tiktok, accountID: UUID())
        let youtubeAccountSelection = PlatformAccountSelection(platform: .youtubeShorts, accountID: UUID())
        let youtubeSettings = DraftYouTubeSettings(
            title: "Launch Shorts",
            description: "Shorts description",
            tags: ["flick", "launch"],
            privacyStatus: .unlisted,
            categoryID: "22",
            selfDeclaredMadeForKids: false,
            containsSyntheticMedia: true,
            notifySubscribers: true
        )
        draft.accountSelections = [accountSelection]
        draft.accountSelections.append(youtubeAccountSelection)
        draft.tikTokSettings = tikTokSettings
        draft.youtubeSettings = youtubeSettings
        draft.selectedSongs = selectedSongs
        var state = FlickEmptyState.make()
        state.drafts = [draft]

        try await repository.saveOverview(state)
        let loaded = try await repository.loadOverview()
        let loadedDraft = try XCTUnwrap(loaded.drafts.first)

        XCTAssertEqual(loadedDraft.tikTokSettings, tikTokSettings)
        XCTAssertEqual(loadedDraft.youtubeSettings, youtubeSettings)
        XCTAssertEqual(loadedDraft.accountSelections, [accountSelection, youtubeAccountSelection])
        XCTAssertEqual(loadedDraft.selectedSongs, selectedSongs)
    }

    func testSlideshowDraftDecodesLegacyPayloadWithoutAccountSelections() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var draft = makeSlideshowDraft(now: now)
        draft.accountSelections = [PlatformAccountSelection(platform: .tiktok, accountID: UUID())]
        let legacyData = try removingTopLevelJSONKey("accountSelections", from: JSONEncoder().encode(draft))

        let decodedDraft = try JSONDecoder().decode(SlideshowDraft.self, from: legacyData)

        XCTAssertTrue(decodedDraft.accountSelections.isEmpty)
        XCTAssertEqual(decodedDraft.title, draft.title)
        XCTAssertEqual(decodedDraft.targetPlatforms, draft.targetPlatforms)
    }

    func testAutomationScheduleFindsNextFixedOccurrence() throws {
        let automationID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let calendar = Calendar(identifier: .gregorian)
        let schedule = AutomationSchedule(
            weekdays: [.monday, .wednesday],
            fixedTimes: [
                AutomationTimeOfDay(hour: 9),
                AutomationTimeOfDay(hour: 15, minute: 30)
            ]
        )
        let reference = try XCTUnwrap(DateComponents(calendar: calendar, year: 2026, month: 5, day: 18, hour: 10).date)
        let expected = try XCTUnwrap(DateComponents(calendar: calendar, year: 2026, month: 5, day: 18, hour: 15, minute: 30).date)

        XCTAssertEqual(schedule.nextOccurrence(after: reference, automationID: automationID, calendar: calendar), expected)
    }

    func testAutomationScheduleDefaultsToRandomSlot() throws {
        let automationID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let calendar = Calendar(identifier: .gregorian)
        let schedule = AutomationSchedule.default
        let reference = try XCTUnwrap(DateComponents(calendar: calendar, year: 2026, month: 5, day: 18).date)

        let firstOccurrence = try XCTUnwrap(schedule.nextOccurrence(after: reference, automationID: automationID, calendar: calendar))
        let secondOccurrence = try XCTUnwrap(schedule.nextOccurrence(after: reference, automationID: automationID, calendar: calendar))

        XCTAssertEqual(schedule.postsPerDay, 1)
        XCTAssertTrue(schedule.fixedTimes.isEmpty)
        XCTAssertEqual(schedule.summary(calendar: calendar), "Weekdays - 1 post - Random time")
        XCTAssertEqual(firstOccurrence, secondOccurrence)
        XCTAssertGreaterThan(firstOccurrence, reference)
    }

    func testAutomationScheduleAddsRandomSlots() {
        var schedule = AutomationSchedule.default

        schedule.addSlot()

        XCTAssertEqual(schedule.postsPerDay, 2)
        XCTAssertTrue(schedule.postSlots.allSatisfy { $0.time == nil })
        XCTAssertEqual(schedule.summary(), "Weekdays - 2 posts - Random times")
    }

    func testAutomationScheduleFindsNextIntervalOccurrence() throws {
        let automationID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let calendar = Calendar(identifier: .gregorian)
        let schedule = AutomationSchedule(
            weekdays: [.monday],
            cadence: .interval(AutomationIntervalCadence(value: 2, unit: .hours))
        )
        let reference = try XCTUnwrap(DateComponents(calendar: calendar, year: 2026, month: 5, day: 18, hour: 10).date)
        let expected = try XCTUnwrap(DateComponents(calendar: calendar, year: 2026, month: 5, day: 18, hour: 12).date)

        XCTAssertEqual(schedule.nextOccurrence(after: reference, automationID: automationID, calendar: calendar), expected)
        XCTAssertEqual(schedule.summary(calendar: calendar), "M - Every 2 hours")
    }

    func testAutomationScheduleDecodesLegacyFixedTimes() throws {
        let data = Data("""
        {
            "weekdays": [2, 4],
            "fixedTimes": [
                { "hour": 9, "minute": 0 },
                { "hour": 15, "minute": 30 }
            ]
        }
        """.utf8)

        let schedule = try JSONDecoder().decode(AutomationSchedule.self, from: data)

        XCTAssertEqual(schedule.postsPerDay, 2)
        XCTAssertEqual(
            schedule.fixedTimes,
            [
                AutomationTimeOfDay(hour: 9),
                AutomationTimeOfDay(hour: 15, minute: 30)
            ]
        )
    }

    func testAutomationDefaultNameUsesSelectedFields() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let product = makeProduct(name: "Flick Pro", now: now)
        let template = makeExampleSlideshowTemplate(slideCount: 2)
        let automation = ContentAutomation(
            name: "",
            templateIDs: [template.id],
            productID: product.id,
            productImageAssetIDs: [UUID()],
            schedule: AutomationSchedule(
                weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
                fixedTimes: [AutomationTimeOfDay(hour: 12)]
            ),
            tikTokSettings: DraftTikTokSettings(title: "Try Flick", privacyLevel: .publicToEveryone),
            createdAt: now,
            updatedAt: now
        )
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let expectedDate = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: now) ?? now
        let expectedTime = formatter.string(from: expectedDate)

        XCTAssertEqual(
            automation.defaultName(templates: [template], products: [product]),
            "Flick Pro - Productivity - Weekdays - 1 post - \(expectedTime)"
        )
    }

    func testAutomationRequiresSelectedAccountForEveryTargetAndDashboardFansOutTargets() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let tikTokAccount = makeConnectedAccount(now: now)
        let firstYouTubeAccount = makeYouTubeAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
            displayName: "Main Channel",
            now: now
        )
        let secondYouTubeAccount = makeYouTubeAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!,
            platformUserID: "youtube-channel-id-2",
            displayName: "Backup Channel",
            now: now
        )
        var automation = ContentAutomation(
            name: "Weekday launches",
            templateIDs: ["template-a"],
            productID: UUID(),
            productImageAssetIDs: [UUID()],
            schedule: AutomationSchedule.default,
            tikTokSettings: DraftTikTokSettings(title: "Try Flick", privacyLevel: .publicToEveryone),
            youtubeSettings: DraftYouTubeSettings(title: "Try Flick Shorts"),
            targetPlatforms: [.tiktok, .youtubeShorts],
            accountSelections: [
                PlatformAccountSelection(platform: .tiktok, accountID: tikTokAccount.id)
            ],
            createdAt: now,
            updatedAt: now
        )

        XCTAssertFalse(automation.isReadyToSchedule)

        automation.accountSelections.append(contentsOf: [
            PlatformAccountSelection(platform: .youtubeShorts, accountID: firstYouTubeAccount.id),
            PlatformAccountSelection(platform: .youtubeShorts, accountID: secondYouTubeAccount.id)
        ])

        XCTAssertTrue(automation.isReadyToSchedule)

        let targets = AutomationTargetSummary.targets(
            for: automation,
            accounts: [tikTokAccount, firstYouTubeAccount, secondYouTubeAccount]
        )

        XCTAssertEqual(targets.map(\.accountID), [tikTokAccount.id, firstYouTubeAccount.id, secondYouTubeAccount.id])
        XCTAssertEqual(targets.map(\.platform), [.tiktok, .youtubeShorts, .youtubeShorts])
        XCTAssertEqual(targets.map(\.accountName), [tikTokAccount.displayName, "Main Channel", "Backup Channel"])
    }

    func testCoreDataRoundTripsAutomations() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let persistenceController = PersistenceController(inMemory: true)
        let repository = CoreDataFlickRepository(
            context: persistenceController.container.viewContext,
            cloudAvailability: { false }
        )
        let product = makeProduct(now: now)
        let productImageID = UUID()
        let creationModel = makeCreationModel(now: now)
        let nextScheduledAt = Date(timeInterval: 3_600, since: now)
        let automation = ContentAutomation(
            name: "Weekday launches",
            templateIDs: ["template-a", "template-b"],
            productID: product.id,
            productImageAssetIDs: [productImageID],
            creationModel: creationModel.generationReference,
            imageVibe: .flashCandid,
            schedule: AutomationSchedule(
                weekdays: [.monday, .wednesday, .friday],
                fixedTimes: [
                    AutomationTimeOfDay(hour: 9),
                    AutomationTimeOfDay(hour: 13),
                    AutomationTimeOfDay(hour: 17)
                ]
            ),
            tikTokSettings: DraftTikTokSettings(
                title: "Try Flick",
                postAsDraft: false,
                privacyLevel: .publicToEveryone,
                allowComment: true
            ),
            youtubeSettings: DraftYouTubeSettings(
                title: "Try Flick Shorts",
                description: "Scheduled YouTube description",
                tags: ["flick"],
                privacyStatus: .private,
                categoryID: "22",
                selfDeclaredMadeForKids: false,
                containsSyntheticMedia: true,
                notifySubscribers: false
            ),
            targetPlatforms: [.tiktok, .youtubeShorts],
            accountSelections: [
                PlatformAccountSelection(platform: .tiktok, accountID: UUID()),
                PlatformAccountSelection(platform: .youtubeShorts, accountID: UUID())
            ],
            nextScheduledAt: nextScheduledAt,
            createdAt: now,
            updatedAt: now
        )
        var state = FlickEmptyState.make()
        state.products = [product]
        state.creationModels = [creationModel]
        state.automations = [automation]

        try await repository.saveOverview(state)
        let loaded = try await repository.loadOverview()
        let loadedAutomation = try XCTUnwrap(loaded.automations.first)

        XCTAssertEqual(loadedAutomation, automation)
        XCTAssertEqual(loadedAutomation.creationModel?.name, creationModel.name)
        XCTAssertEqual(loadedAutomation.imageVibe, .flashCandid)
        XCTAssertTrue(loadedAutomation.creationModel?.aiMetadataJSONString().contains("\"skin_details\"") == true)
        XCTAssertEqual(loaded.dashboard.activeAutomationCount, 1)
        XCTAssertEqual(loaded.dashboard.nextAutomationPostAt, nextScheduledAt)
    }

    func testContentAutomationDecodesLegacyPayloadWithoutAccountSelections() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let automation = ContentAutomation(
            name: "Weekday launches",
            templateIDs: ["template-a"],
            productID: UUID(),
            productImageAssetIDs: [UUID()],
            schedule: AutomationSchedule(),
            tikTokSettings: DraftTikTokSettings(title: "Try Flick", privacyLevel: .publicToEveryone),
            accountSelections: [PlatformAccountSelection(platform: .tiktok, accountID: UUID())],
            createdAt: now,
            updatedAt: now
        )
        let legacyData = try removingTopLevelJSONKey("accountSelections", from: JSONEncoder().encode(automation))

        let decodedAutomation = try JSONDecoder().decode(ContentAutomation.self, from: legacyData)

        XCTAssertTrue(decodedAutomation.accountSelections.isEmpty)
        XCTAssertEqual(decodedAutomation.name, automation.name)
        XCTAssertEqual(decodedAutomation.targetPlatforms, automation.targetPlatforms)
    }

    func testContentAutomationDecodesLegacyPayloadWithoutImageVibe() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let automation = ContentAutomation(
            name: "Weekday launches",
            templateIDs: ["template-a"],
            productID: UUID(),
            productImageAssetIDs: [UUID()],
            imageVibe: .warmFilm,
            schedule: AutomationSchedule(),
            tikTokSettings: DraftTikTokSettings(title: "Try Flick", privacyLevel: .publicToEveryone),
            createdAt: now,
            updatedAt: now
        )
        let legacyData = try removingTopLevelJSONKey("imageVibe", from: JSONEncoder().encode(automation))

        let decodedAutomation = try JSONDecoder().decode(ContentAutomation.self, from: legacyData)

        XCTAssertEqual(decodedAutomation.imageVibe, .defaultValue)
        XCTAssertEqual(decodedAutomation.name, automation.name)
    }

    func testSlideshowDraftDecodesLegacyPayloadWithoutImageVibe() throws {
        let draft = makeSlideshowDraft(imageVibe: .flashCandid)
        let legacyData = try removingTopLevelJSONKey("imageVibe", from: JSONEncoder().encode(draft))

        let decodedDraft = try JSONDecoder().decode(SlideshowDraft.self, from: legacyData)

        XCTAssertEqual(decodedDraft.imageVibe, .defaultValue)
        XCTAssertEqual(decodedDraft.title, draft.title)
    }

    func testCoreDataRoundTripsAutomationPostProgresses() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let persistenceController = PersistenceController(inMemory: true)
        let repository = CoreDataFlickRepository(
            context: persistenceController.container.viewContext,
            cloudAvailability: { false }
        )
        let automationID = UUID()
        var progress = AutomationPostProgress.make(
            automationID: automationID,
            title: "Launch Carousel",
            productName: "Flick Pro",
            creationModelName: "Cottage Host",
            targetPlatforms: [.tiktok, .youtubeShorts],
            scheduledAt: now,
            now: now
        )
        progress.draftID = UUID()
        progress.templateTitle = "@flickapp"
        progress.steps[0].state = .completed
        progress.steps[0].updatedAt = now
        progress.steps[1].state = .current
        progress.steps[1].detail = "Creating the carousel plan."
        progress.updatedAt = now.addingTimeInterval(60)
        var state = FlickEmptyState.make()
        state.automationPostProgresses = [progress]

        try await repository.saveOverview(state)
        let loaded = try await repository.loadOverview()
        let loadedProgress = try XCTUnwrap(loaded.automationPostProgresses.first)

        XCTAssertEqual(loadedProgress, progress)
        XCTAssertEqual(loadedProgress.currentStep?.id, AutomationPostProgressStepID.planSlideshow)
    }

    func testAutomationPostProgressDecodesLegacyPayloadWithoutTargetPlatforms() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let progress = AutomationPostProgress.make(
            automationID: UUID(),
            title: "Launch Carousel",
            productName: "Flick Pro",
            targetPlatforms: [.tiktok, .youtubeShorts],
            scheduledAt: now,
            now: now
        )
        let legacyData = try removingTopLevelJSONKey("targetPlatforms", from: JSONEncoder().encode(progress))

        let decodedProgress = try JSONDecoder().decode(AutomationPostProgress.self, from: legacyData)

        XCTAssertEqual(decodedProgress.targetPlatforms, [.tiktok])
        XCTAssertEqual(decodedProgress.title, progress.title)
    }

    func testAutomationPostProgressDecodesLegacyStepPayloadWithoutImageProgress() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let progress = AutomationPostProgress.make(
            automationID: UUID(),
            title: "Launch Carousel",
            productName: "Flick Pro",
            scheduledAt: now,
            now: now
        )
        let data = try JSONEncoder().encode(progress)

        let decodedProgress = try JSONDecoder().decode(AutomationPostProgress.self, from: data)
        let generateStep = try XCTUnwrap(decodedProgress.steps.first { $0.id == AutomationPostProgressStepID.generateImages })

        XCTAssertNil(generateStep.completedImageCount)
        XCTAssertNil(generateStep.totalImageCount)
        XCTAssertNil(generateStep.currentImageIndex)
        XCTAssertNil(generateStep.attemptDetail)
    }

    func testAutomationPostProgressFractionIncludesCurrentImageProgress() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var progress = AutomationPostProgress.make(
            automationID: UUID(),
            title: "Launch Carousel",
            productName: "Flick Pro",
            scheduledAt: now,
            now: now
        )
        progress.steps[0].state = .completed
        progress.steps[1].state = .completed
        progress.steps[2].state = .current
        progress.steps[2].completedImageCount = 2
        progress.steps[2].totalImageCount = 8
        progress.steps[2].currentImageIndex = 3

        XCTAssertEqual(progress.progressFraction, 2.25 / 8.0, accuracy: 0.0001)
        XCTAssertEqual(progress.steps[2].imageProgressSummary, "2 of 8 images created")
        XCTAssertEqual(progress.steps[2].compactImageProgressSummary, "2/8 created")
        XCTAssertEqual(progress.steps[2].currentImageSummary, "Image 3 of 8")
    }

    func testCoreDataRoundTripsAutomationPostProgressImageProgress() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let persistenceController = PersistenceController(inMemory: true)
        let repository = CoreDataFlickRepository(
            context: persistenceController.container.viewContext,
            cloudAvailability: { false }
        )
        var progress = AutomationPostProgress.make(
            automationID: UUID(),
            title: "Launch Carousel",
            productName: "Flick Pro",
            scheduledAt: now,
            now: now
        )
        progress.steps[2].state = .current
        progress.steps[2].detail = "Retrying image 3 of 8."
        progress.steps[2].completedImageCount = 2
        progress.steps[2].totalImageCount = 8
        progress.steps[2].currentImageIndex = 3
        progress.steps[2].attemptDetail = "Attempt 2 of 2 after the request timed out."
        var state = FlickEmptyState.make()
        state.automationPostProgresses = [progress]

        try await repository.saveOverview(state)
        let loaded = try await repository.loadOverview()
        let loadedProgress = try XCTUnwrap(loaded.automationPostProgresses.first)
        let loadedStep = try XCTUnwrap(loadedProgress.steps.first { $0.id == AutomationPostProgressStepID.generateImages })

        XCTAssertEqual(loadedStep.completedImageCount, 2)
        XCTAssertEqual(loadedStep.totalImageCount, 8)
        XCTAssertEqual(loadedStep.currentImageIndex, 3)
        XCTAssertEqual(loadedStep.attemptDetail, "Attempt 2 of 2 after the request timed out.")
        XCTAssertEqual(loadedProgress.progressFraction, progress.progressFraction, accuracy: 0.0001)
    }

    func testAutomationDashboardSnapshotGroupsActiveProgresses() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let product = makeProduct(now: now)
        let automation = ContentAutomation(
            name: "Weekday launches",
            templateIDs: ["template-a"],
            productID: product.id,
            productImageAssetIDs: [UUID()],
            schedule: AutomationSchedule(),
            tikTokSettings: DraftTikTokSettings(title: "Try Flick", privacyLevel: .publicToEveryone),
            createdAt: now,
            updatedAt: now
        )
        let activeProgress = AutomationPostProgress.make(
            automationID: automation.id,
            title: "Launch Carousel",
            productName: product.name,
            scheduledAt: now,
            now: now
        )
        var finishedProgress = AutomationPostProgress.make(
            automationID: automation.id,
            title: "Finished Carousel",
            productName: product.name,
            scheduledAt: now,
            now: now
        )
        finishedProgress.finishedAt = now
        var state = FlickEmptyState.make()
        state.products = [product]
        state.automations = [automation]
        state.automationPostProgresses = [finishedProgress, activeProgress]

        let snapshot = AutomationDashboardSnapshot.make(overview: state)
        let item = snapshot.items.first

        XCTAssertEqual(snapshot.activeProgresses.map(\.id), [activeProgress.id])
        XCTAssertEqual(item?.activeProgresses.map(\.id), [activeProgress.id])
    }

    func testAutomationDashboardSnapshotShowsSelectedAccountOnly() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let selectedAccount = makeConnectedAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            platformUserID: "selected-open-id",
            displayName: "@selected",
            now: now
        )
        let otherAccount = makeConnectedAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            platformUserID: "other-open-id",
            displayName: "@other",
            now: now
        )
        let automation = ContentAutomation(
            name: "Weekday launches",
            templateIDs: ["template-a"],
            productID: UUID(),
            productImageAssetIDs: [UUID()],
            schedule: AutomationSchedule(),
            tikTokSettings: DraftTikTokSettings(title: "Try Flick", privacyLevel: .publicToEveryone),
            accountSelections: [PlatformAccountSelection(platform: .tiktok, accountID: selectedAccount.id)],
            createdAt: now,
            updatedAt: now
        )
        var state = FlickEmptyState.make()
        state.accounts = [selectedAccount, otherAccount]
        state.automations = [automation]

        let snapshot = AutomationDashboardSnapshot.make(overview: state)
        let targets = snapshot.items.first?.targets

        XCTAssertEqual(targets?.map(\.accountID), [selectedAccount.id])
        XCTAssertEqual(targets?.map(\.accountName), ["@selected"])
    }

    func testAutomationDashboardSnapshotShowsFailedCreatedPost() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let product = makeProduct(now: now)
        let automation = ContentAutomation(
            name: "Weekday launches",
            templateIDs: ["template-a"],
            productID: product.id,
            productImageAssetIDs: [UUID()],
            schedule: AutomationSchedule(),
            tikTokSettings: DraftTikTokSettings(title: "Try Flick", privacyLevel: .publicToEveryone),
            createdAt: now,
            updatedAt: now
        )
        let draft = makeSlideshowDraft(now: now)
        var job = makePublishingJob(status: .failed)
        job.automationID = automation.id
        job.draftID = draft.id
        job.lastError = PlatformFailure(
            kind: .mediaURLInaccessible,
            message: "TikTok could not access one generated image.",
            suggestedFix: "Retry after upload finishes.",
            rawResponse: nil
        )
        job.updatedAt = now.addingTimeInterval(60)
        var state = FlickEmptyState.make()
        state.products = [product]
        state.drafts = [draft]
        state.automations = [automation]
        state.publishingJobs = [job]

        let snapshot = AutomationDashboardSnapshot.make(overview: state)
        let item = snapshot.items.first
        let preview = item?.postPreviews.first

        XCTAssertEqual(snapshot.postCount, 1)
        XCTAssertEqual(item?.publishedPosts.count, 0)
        XCTAssertEqual(item?.postCount, 1)
        XCTAssertEqual(preview?.status, .failed)
        XCTAssertEqual(preview?.draft?.id, draft.id)
        XCTAssertEqual(preview?.lastError?.message, "TikTok could not access one generated image.")
    }

    func testRefreshBackfillsAutomationPostFromCompletedPublishingJob() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let product = makeProduct(now: now)
        let automation = ContentAutomation(
            name: "Weekday launches",
            templateIDs: ["template-a"],
            productID: product.id,
            productImageAssetIDs: [UUID()],
            schedule: AutomationSchedule(),
            tikTokSettings: DraftTikTokSettings(title: "Try Flick", privacyLevel: .publicToEveryone),
            createdAt: now,
            updatedAt: now
        )
        let draft = makeSlideshowDraft(now: now)
        var job = makePublishingJob(status: .published)
        job.automationID = automation.id
        job.draftID = draft.id
        job.platformPublishID = "7123456789012345678"
        job.updatedAt = now
        var state = FlickEmptyState.make()
        state.products = [product]
        state.drafts = [draft]
        state.automations = [automation]
        state.publishingJobs = [job]
        let repository = InMemoryFlickRepository(state: state)
        let model = FlickAppModel(
            repository: repository,
            configuration: .current
        )

        await model.refresh()

        XCTAssertEqual(model.overview.publishedPosts.count, 1)
        XCTAssertEqual(model.overview.publishedPosts.first?.automationID, automation.id)
        XCTAssertEqual(model.overview.publishedPosts.first?.platformPostID, "7123456789012345678")

        let snapshot = AutomationDashboardSnapshot.make(overview: model.overview)
        XCTAssertEqual(snapshot.items.first?.publishedPosts.count, 1)
        XCTAssertEqual(snapshot.items.first?.postPreviews.count, 1)
    }

    func testCoreDataRoundTripsPublishingJobsAndPublishedPosts() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let persistenceController = PersistenceController(inMemory: true)
        let repository = CoreDataFlickRepository(
            context: persistenceController.container.viewContext,
            cloudAvailability: { false }
        )
        let draft = makeSlideshowDraft(now: now)
        var job = makePublishingJob(status: .awaitingUserCompletion)
        job.draftID = draft.id
        job.publishMode = .photoUploadForCompletion
        job.platformPublishID = "p_inbox_url~v2.123"
        job.updatedAt = now
        let post = PublishedPost(
            id: UUID(),
            platform: .tiktok,
            accountID: job.accountID,
            platformPostID: "7123456789012345678",
            platformURL: nil,
            publishedAt: now,
            draftID: draft.id,
            templateID: nil,
            trendTags: [],
            caption: "Try Flick",
            createdAt: now,
            updatedAt: now
        )
        var state = FlickEmptyState.make()
        state.drafts = [draft]
        state.publishingJobs = [job]
        state.publishedPosts = [post]

        try await repository.saveOverview(state)
        let loaded = try await repository.loadOverview()

        XCTAssertEqual(loaded.publishingJobs.first?.platformPublishID, "p_inbox_url~v2.123")
        XCTAssertEqual(loaded.publishingJobs.first?.status, .awaitingUserCompletion)
        XCTAssertEqual(loaded.publishedPosts.first?.platformPostID, "7123456789012345678")
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
        var state = FlickEmptyState.make()
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

    func testLocalMediaPathResolverFindsProductMediaMovedIntoResourceRoot() throws {
        let resourceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("flick-resource-root-\(UUID().uuidString)", isDirectory: true)
        let productMediaDirectory = resourceRoot.appendingPathComponent("ProductMedia", isDirectory: true)
        try FileManager.default.createDirectory(at: productMediaDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: resourceRoot)
        }

        let imageURL = productMediaDirectory.appendingPathComponent("product.jpg")
        try Data([0xFF, 0xD8, 0xFF]).write(to: imageURL)

        let oldProjectPath = "/Users/example/Desktop/Flick/Flick/ProductMedia/product.jpg"
        let resolvedURL = LocalMediaPathResolver.readableFileURL(
            for: oldProjectPath,
            source: .uploaded,
            additionalResourceRoots: [resourceRoot]
        )

        XCTAssertEqual(resolvedURL?.standardizedFileURL.path, imageURL.standardizedFileURL.path)
    }

    func testUploadedProductImageCountsAsReadyCreateImage() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let product = makeProduct(now: now)
        let asset = makeMediaAsset(
            source: .uploaded,
            publicURL: try XCTUnwrap(URL(string: "https://example.com/product-image.jpg")),
            width: 0,
            height: 0,
            productIDs: [product.id],
            now: now
        )
        let slide = makeSlide(imageAssetID: asset.id, generationStatus: .complete, now: now)
        let draft = makeSlideshowDraft(slides: [slide], now: now)
        let assetsByID = [asset.id: asset]

        XCTAssertEqual(draft.createReadyImageCount(assetsByID: assetsByID), 1)
        XCTAssertEqual(draft.createMissingImageCount(assetsByID: assetsByID), 0)
        XCTAssertTrue(draft.hasCompletedCreateImages(assetsByID: assetsByID))
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
        var state = FlickEmptyState.make()
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

    func testRefreshPreservesCompletedStatusForUploadedProductImage() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let product = makeProduct(now: now)
        let asset = makeMediaAsset(
            source: .uploaded,
            publicURL: try XCTUnwrap(URL(string: "https://example.com/product-image.jpg")),
            width: 0,
            height: 0,
            productIDs: [product.id],
            now: now
        )
        let slide = makeSlide(imageAssetID: asset.id, generationStatus: .complete, now: now)
        let draft = makeSlideshowDraft(slides: [slide], now: now)
        var state = FlickEmptyState.make()
        state.products = [product]
        state.assets = [asset]
        state.drafts = [draft]

        let repository = InMemoryFlickRepository(state: state)
        let model = FlickAppModel(repository: repository, configuration: .current)

        await model.refresh()

        XCTAssertEqual(model.overview.drafts.first?.slides.first?.generationStatus, .complete)
        XCTAssertEqual(repository.state.drafts.first?.slides.first?.generationStatus, .complete)
    }

    func testCredentialVaultStoresOnlySupportedNonEmptyValues() throws {
        let store = MemorySecretStore()
        let vault = CredentialVault(store: store)

        try vault.storeValue("client-id", for: "TIKTOK_CLIENT_ID")
        XCTAssertThrowsError(try vault.storeValue("ignored", for: "UNKNOWN_KEY"))
        XCTAssertThrowsError(try vault.storeValue("postgres", for: "POSTGRES_URL"))
        XCTAssertThrowsError(try vault.storeValue("", for: "OPENAI_API_KEY"))
        XCTAssertEqual(String(data: try XCTUnwrap(store.data(for: "TIKTOK_CLIENT_ID")), encoding: .utf8), "client-id")
    }

    func testCredentialVaultClearsRetiredCredentialKeys() throws {
        let store = MemorySecretStore()
        let vault = CredentialVault(store: store)

        try store.save(Data("client-id".utf8), for: "TIKTOK_CLIENT_ID")
        try store.save(Data("postgres-url".utf8), for: "POSTGRES_URL")

        try vault.clearStoredCredentials()

        XCTAssertNil(try store.data(for: "TIKTOK_CLIENT_ID"))
        XCTAssertNil(try store.data(for: "POSTGRES_URL"))
    }

    func testYouTubeConfigurationReadsOAuthValuesFromCredentialsOnly() {
        let missingConfiguration = YouTubeConfiguration(values: [:])

        XCTAssertNil(missingConfiguration.clientID)
        XCTAssertNil(missingConfiguration.reversedClientID)
        XCTAssertNil(missingConfiguration.redirectURI)

        let credentialConfiguration = YouTubeConfiguration(values: [
            "GOOGLE_CLIENT_ID": " google-client-id ",
            "GOOGLE_REVERSED_CLIENT_ID": " com.googleusercontent.apps.flick ",
            "YOUTUBE_SCOPES": "\(YouTubeConfiguration.uploadScope), \(YouTubeConfiguration.readonlyScope)"
        ])

        XCTAssertEqual(credentialConfiguration.clientID, "google-client-id")
        XCTAssertEqual(credentialConfiguration.reversedClientID, "com.googleusercontent.apps.flick")
        XCTAssertEqual(credentialConfiguration.redirectURI?.absoluteString, "com.googleusercontent.apps.flick:/oauth2redirect")
        XCTAssertEqual(credentialConfiguration.requestedScopes, [
            YouTubeConfiguration.uploadScope,
            YouTubeConfiguration.readonlyScope
        ])
    }

    func testCredentialExportDocumentWritesSortedJSON() throws {
        let document = CredentialExportDocument(values: [
            "TIKTOK_CLIENT_ID": "tiktok-client-id",
            "GOOGLE_CLIENT_ID": "google-client-id"
        ])

        let json = try XCTUnwrap(String(data: document.jsonData(), encoding: .utf8))
        let decodedValues = try XCTUnwrap(
            JSONSerialization.jsonObject(with: document.jsonData()) as? [String: String]
        )
        let googleKeyRange = try XCTUnwrap(json.range(of: "\"GOOGLE_CLIENT_ID\""))
        let tiktokKeyRange = try XCTUnwrap(json.range(of: "\"TIKTOK_CLIENT_ID\""))

        XCTAssertEqual(decodedValues["GOOGLE_CLIENT_ID"], "google-client-id")
        XCTAssertEqual(decodedValues["TIKTOK_CLIENT_ID"], "tiktok-client-id")
        XCTAssertLessThan(googleKeyRange.lowerBound, tiktokKeyRange.lowerBound)
        XCTAssertTrue(json.hasSuffix("\n"))
    }

    func testR2ConfigurationRecognizesBucketAndDerivedEndpoint() {
        let configuration = R2StorageConfiguration(values: [
            "R2_ACCOUNT_ID": "account-id",
            "R2_ACCESS_KEY_ID": "access-key",
            "R2_SECRET_ACCESS_KEY": "secret-key",
            "R2_BUCKET": "flick-media",
            "R2_PUBLIC_BASE_URL": "https://media.example.com"
        ])

        XCTAssertEqual(configuration.endpointURL?.absoluteString, "https://account-id.r2.cloudflarestorage.com")
        XCTAssertEqual(configuration.publicBaseURL?.absoluteString, "https://media.example.com")
        XCTAssertEqual(configuration.bucket, "flick-media")
        XCTAssertTrue(configuration.accessKeyIDPresent)
        XCTAssertTrue(configuration.secretAccessKeyPresent)
        XCTAssertTrue(configuration.isConfigured)
    }

    func testR2StorageServiceBuildsPublicURLFromCustomDomain() throws {
        let service = R2StorageService(credentials: [
            "R2_ACCOUNT_ID": "account-id",
            "R2_ACCESS_KEY_ID": "access-key",
            "R2_SECRET_ACCESS_KEY": "secret-key",
            "R2_BUCKET": "flick-media",
            "R2_PUBLIC_BASE_URL": "https://media.example.com"
        ])

        let url = try service.publicURL(path: "generated-slides/drafts/slide 01.png")

        XCTAssertEqual(
            url.absoluteString,
            "https://media.example.com/generated-slides/drafts/slide%2001.png"
        )
    }

    func testR2StorageServiceBuildsPublicURLForBucketNamedHost() throws {
        let service = R2StorageService(credentials: [
            "R2_ACCOUNT_ID": "account-id",
            "R2_ACCESS_KEY_ID": "access-key",
            "R2_SECRET_ACCESS_KEY": "secret-key",
            "R2_BUCKET": "flick-media",
            "R2_PUBLIC_BASE_URL": "https://flick-media.goingviral.club"
        ])

        let url = try service.publicURL(path: "rendered-image-sequences/draft-id/slide.jpg")

        XCTAssertEqual(
            url.absoluteString,
            "https://flick-media.goingviral.club/flick-media/rendered-image-sequences/draft-id/slide.jpg"
        )
    }

    func testR2StorageServiceDoesNotDoubleBucketPathInPublicURL() throws {
        let service = R2StorageService(credentials: [
            "R2_ACCOUNT_ID": "account-id",
            "R2_ACCESS_KEY_ID": "access-key",
            "R2_SECRET_ACCESS_KEY": "secret-key",
            "R2_BUCKET": "flick-media",
            "R2_PUBLIC_BASE_URL": "https://flick-media.goingviral.club/flick-media"
        ])

        let url = try service.publicURL(path: "rendered-image-sequences/draft-id/slide.jpg")

        XCTAssertEqual(
            url.absoluteString,
            "https://flick-media.goingviral.club/flick-media/rendered-image-sequences/draft-id/slide.jpg"
        )
    }

    func testR2StorageServiceBuildsSignedURLForSingleBucketObject() async throws {
        let service = R2StorageService(credentials: [
            "R2_ACCOUNT_ID": "account-id",
            "R2_ACCESS_KEY_ID": "access-key",
            "R2_SECRET_ACCESS_KEY": "secret-key",
            "R2_BUCKET": "flick-media",
            "R2_PUBLIC_BASE_URL": "https://media.example.com"
        ])

        let url = try await service.signedURL(path: "generated-slides/slide-01.png", expiresIn: 600)

        XCTAssertTrue(url.absoluteString.hasPrefix("https://account-id.r2.cloudflarestorage.com/flick-media/generated-slides/slide-01.png?"))
        XCTAssertTrue(url.absoluteString.contains("X-Amz-Algorithm=AWS4-HMAC-SHA256"))
        XCTAssertTrue(url.absoluteString.contains("X-Amz-Credential=access-key%2F"))
        XCTAssertTrue(url.absoluteString.contains("X-Amz-Signature="))
    }

    func testR2StoragePathsExposeEveryConfiguredPrefix() {
        let paths = R2StoragePaths()

        XCTAssertEqual(
            paths.all,
            [
                paths.productMedia,
                paths.generatedImages,
                paths.renderedImages,
                paths.referenceImages,
                paths.thumbnails
            ]
        )
    }

    func testRemoteTemplateIndexLoadsNicheSummariesWithoutFetchingPages() async throws {
        var requestedPaths: [String] = []
        CapturingURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            requestedPaths.append(path)

            let payload: String
            switch path {
            case "/template-library/current.json":
                payload = """
                {
                    "releaseID": "release-1",
                    "basePath": "template-library/releases/release-1",
                    "indexPath": "template-library/releases/release-1/index.json"
                }
                """
            case "/template-library/releases/release-1/index.json":
                payload = """
                {
                    "releaseID": "release-1",
                    "basePath": "template-library/releases/release-1",
                    "pageSize": 24,
                    "niches": [
                        {
                            "folder": "Fitness",
                            "title": "Fitness",
                            "nicheSlug": "fitness",
                            "sourcePage": "https://example.com/fitness",
                            "slideshowCount": 30,
                            "totalSlideCount": 90,
                            "pageSize": 24,
                            "pageCount": 2
                        },
                        {
                            "folder": "Wellness",
                            "title": "Wellness",
                            "nicheSlug": "wellness",
                            "sourcePage": "https://example.com/wellness",
                            "slideshowCount": 12,
                            "totalSlideCount": 36,
                            "pageSize": 24,
                            "pageCount": 1
                        }
                    ]
                }
                """
            case "/template-library/deleted-templates.json":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!,
                    Data()
                )
            default:
                XCTFail("Unexpected template library request: \(path)")
                payload = "{}"
            }

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(payload.utf8)
            )
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let index = try await ExampleSlideshowLibrary.loadIndex(
            configuration: makeTestAppConfiguration(),
            urlSession: session
        )

        XCTAssertEqual(index.releaseID, "release-1")
        XCTAssertEqual(index.collections.map(\.id), ["Fitness", "Wellness"])
        XCTAssertEqual(index.collections.first?.pageCount, 2)
        XCTAssertFalse(requestedPaths.contains { $0.contains("/pages/") })
    }

    func testRemoteTemplatePageBuildsSlideRemoteURLs() async throws {
        CapturingURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            let payload: String
            switch path {
            case "/template-library/current.json":
                payload = """
                {
                    "releaseID": "release-1",
                    "basePath": "template-library/releases/release-1",
                    "indexPath": "template-library/releases/release-1/index.json"
                }
                """
            case "/template-library/releases/release-1/index.json":
                payload = """
                {
                    "releaseID": "release-1",
                    "basePath": "template-library/releases/release-1",
                    "pageSize": 24,
                    "niches": [
                        {
                            "folder": "Fitness",
                            "title": "Fitness",
                            "nicheSlug": "fitness",
                            "sourcePage": null,
                            "slideshowCount": 1,
                            "totalSlideCount": 1,
                            "pageSize": 24,
                            "pageCount": 1
                        }
                    ]
                }
                """
            case "/template-library/deleted-templates.json":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!,
                    Data()
                )
            case "/template-library/releases/release-1/niches/fitness/pages/1.json":
                payload = """
                {
                    "pageNumber": 1,
                    "pageSize": 24,
                    "pageCount": 1,
                    "slideshows": [
                        {
                            "id": "fitness-template-1",
                            "niche": "Fitness",
                            "nicheSlug": "fitness",
                            "sourceUrl": "https://example.com/source",
                            "postNumber": 1,
                            "profile": "fitcreator",
                            "profileDisplayName": "Fit Creator",
                            "folder": "fitness-template-1",
                            "slideCount": 1,
                            "metrics": {},
                            "product": {},
                            "creator": {},
                            "slides": [
                                {
                                    "index": 1,
                                    "url": "https://example.com/original-slide.jpg",
                                    "filename": "slide 01.jpg",
                                    "relativePath": "fitness-template-1/slide 01.jpg"
                                }
                            ]
                        }
                    ]
                }
                """
            default:
                XCTFail("Unexpected template library request: \(path)")
                payload = "{}"
            }

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(payload.utf8)
            )
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let appConfiguration = makeTestAppConfiguration()
        let index = try await ExampleSlideshowLibrary.loadIndex(
            configuration: appConfiguration,
            urlSession: session
        )
        let page = try await ExampleSlideshowLibrary.loadPage(
            nicheID: "Fitness",
            pageNumber: 1,
            index: index,
            configuration: appConfiguration,
            urlSession: session
        )

        let slide = try XCTUnwrap(page.collection.templates.first?.slides.first)
        XCTAssertEqual(
            slide.remoteURL?.absoluteString,
            "https://media.example.com/template-library/releases/release-1/ExampleSlideshows/Fitness/fitness-template-1/slide%2001.jpg"
        )
    }

    func testTemplateLibraryStoreInitialSelectionUsesPersistedNicheThenFirstFallback() async throws {
        let index = makeTemplateLibraryIndex()
        var requestedPages: [(String, Int)] = []
        let client = TemplateLibraryClient(
            loadIndex: { _ in index },
            loadPage: { nicheID, pageNumber, index, _ in
                requestedPages.append((nicheID, pageNumber))
                return makeTemplatePage(
                    nicheID: nicheID,
                    pageNumber: pageNumber,
                    index: index,
                    templates: [makeExampleSlideshowTemplate(id: "\(nicheID)-page-\(pageNumber)")]
                )
            },
            deleteTemplate: { _, _, _ in
            }
        )
        let suiteName = "TemplateLibraryStore-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set("Wellness", forKey: "lastSelectedTemplateNicheID")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let persistedStore = TemplateLibraryStore(userDefaults: defaults, client: client)
        await persistedStore.loadInitial(configuration: makeTestAppConfiguration())

        XCTAssertEqual(persistedStore.selectedNicheID, "Wellness")
        XCTAssertEqual(requestedPages.map { "\($0.0):\($0.1)" }, ["Wellness:1"])

        defaults.set("Missing", forKey: "lastSelectedTemplateNicheID")
        requestedPages = []
        let fallbackStore = TemplateLibraryStore(userDefaults: defaults, client: client)
        await fallbackStore.loadInitial(configuration: makeTestAppConfiguration())

        XCTAssertEqual(fallbackStore.selectedNicheID, "Fitness")
        XCTAssertEqual(requestedPages.map { "\($0.0):\($0.1)" }, ["Fitness:1"])
    }

    func testTemplateLibraryStoreSelectionAndPaginationFetchSelectedNichePages() async {
        let index = makeTemplateLibraryIndex()
        var requestedPages: [(String, Int)] = []
        let client = TemplateLibraryClient(
            loadIndex: { _ in index },
            loadPage: { nicheID, pageNumber, index, _ in
                requestedPages.append((nicheID, pageNumber))
                return makeTemplatePage(
                    nicheID: nicheID,
                    pageNumber: pageNumber,
                    index: index,
                    templates: [makeExampleSlideshowTemplate(id: "\(nicheID)-template-\(pageNumber)", niche: nicheID)]
                )
            },
            deleteTemplate: { _, _, _ in
            }
        )
        let suiteName = "TemplateLibraryStore-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = TemplateLibraryStore(userDefaults: defaults, client: client)

        await store.loadInitial(configuration: makeTestAppConfiguration())
        await store.selectNiche("Wellness", configuration: makeTestAppConfiguration())
        await store.loadNextPage(configuration: makeTestAppConfiguration())

        XCTAssertEqual(requestedPages.map { "\($0.0):\($0.1)" }, ["Fitness:1", "Wellness:1", "Wellness:2"])
        XCTAssertEqual(store.templates.map(\.id), ["Wellness-template-1", "Wellness-template-2"])
        XCTAssertEqual(store.pageNumber, 2)
        XCTAssertFalse(store.hasNextPage)
    }

    func testRemoteTemplateDeletionRegistryFiltersIndexAndPages() async throws {
        CapturingURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            let payload: String
            switch path {
            case "/template-library/current.json":
                payload = """
                {
                    "releaseID": "release-1",
                    "basePath": "template-library/releases/release-1",
                    "indexPath": "template-library/releases/release-1/index.json"
                }
                """
            case "/template-library/releases/release-1/index.json":
                payload = """
                {
                    "releaseID": "release-1",
                    "basePath": "template-library/releases/release-1",
                    "pageSize": 24,
                    "niches": [
                        {
                            "folder": "Fitness",
                            "title": "Fitness",
                            "nicheSlug": "fitness",
                            "sourcePage": null,
                            "slideshowCount": 2,
                            "totalSlideCount": 4,
                            "pageSize": 24,
                            "pageCount": 1
                        }
                    ]
                }
                """
            case "/template-library/deleted-templates.json":
                payload = """
                {
                    "version": 1,
                    "updatedAt": "2026-01-01T00:00:00Z",
                    "templates": [
                        {
                            "templateID": "deleted-template",
                            "releaseID": "release-1",
                            "nicheID": "Fitness",
                            "fingerprint": "fingerprint",
                            "slideCount": 2,
                            "deletedAt": "2026-01-01T00:00:00Z"
                        }
                    ]
                }
                """
            case "/template-library/releases/release-1/niches/fitness/pages/1.json":
                payload = """
                {
                    "pageNumber": 1,
                    "pageSize": 24,
                    "pageCount": 1,
                    "slideshows": [
                        {
                            "id": "deleted-template",
                            "niche": "Fitness",
                            "nicheSlug": "fitness",
                            "sourceUrl": "https://example.com/deleted",
                            "postNumber": 1,
                            "profile": "deleted",
                            "profileDisplayName": "Deleted",
                            "folder": "deleted-template",
                            "slideCount": 2,
                            "metrics": {},
                            "product": {},
                            "creator": {},
                            "slides": []
                        },
                        {
                            "id": "visible-template",
                            "niche": "Fitness",
                            "nicheSlug": "fitness",
                            "sourceUrl": "https://example.com/visible",
                            "postNumber": 2,
                            "profile": "visible",
                            "profileDisplayName": "Visible",
                            "folder": "visible-template",
                            "slideCount": 2,
                            "metrics": {},
                            "product": {},
                            "creator": {},
                            "slides": []
                        }
                    ]
                }
                """
            default:
                XCTFail("Unexpected template library request: \(path)")
                payload = "{}"
            }

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(payload.utf8)
            )
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let appConfiguration = makeTestAppConfiguration()
        let index = try await ExampleSlideshowLibrary.loadIndex(
            configuration: appConfiguration,
            urlSession: session
        )
        let page = try await ExampleSlideshowLibrary.loadPage(
            nicheID: "Fitness",
            pageNumber: 1,
            index: index,
            configuration: appConfiguration,
            urlSession: session
        )

        XCTAssertEqual(index.collections.first?.slideshowCount, 1)
        XCTAssertEqual(index.collections.first?.totalSlideCount, 2)
        XCTAssertEqual(index.deletedTemplateIDs, ["deleted-template"])
        XCTAssertEqual(page.collection.templates.map(\.id), ["visible-template"])
    }

    func testTemplateLibraryStoreDeleteRemovesTemplateAndMarksIndexDeleted() async throws {
        let firstTemplate = makeExampleSlideshowTemplate(id: "Fitness-template-1", niche: "Fitness")
        let secondTemplate = makeExampleSlideshowTemplate(id: "Fitness-template-2", niche: "Fitness")
        let index = makeTemplateLibraryIndex()
        var deletedTemplateIDs: [String] = []
        let client = TemplateLibraryClient(
            loadIndex: { _ in index },
            loadPage: { nicheID, pageNumber, index, _ in
                makeTemplatePage(
                    nicheID: nicheID,
                    pageNumber: pageNumber,
                    index: index,
                    templates: [firstTemplate, secondTemplate]
                )
            },
            deleteTemplate: { template, _, _ in
                deletedTemplateIDs.append(template.id)
            }
        )
        let store = TemplateLibraryStore(client: client)

        await store.loadInitial(configuration: makeTestAppConfiguration())
        try await store.deleteTemplate(firstTemplate, configuration: makeTestAppConfiguration())

        XCTAssertEqual(deletedTemplateIDs, [firstTemplate.id])
        XCTAssertEqual(store.templates.map(\.id), [secondTemplate.id])
        XCTAssertTrue(store.index?.deletedTemplateIDs.contains(firstTemplate.id) ?? false)
        XCTAssertEqual(store.selectedSummary?.slideshowCount, 23)
    }

    func testCreateDraftUsesRemoteOnlySlideURLs() throws {
        let template = makeExampleSlideshowTemplate(
            id: "remote-template",
            slideCount: 2,
            niche: "Fitness",
            slides: [
                makeExampleSlideshowSlide(index: 1, remoteURL: try XCTUnwrap(URL(string: "https://media.example.com/slide-1.jpg"))),
                makeExampleSlideshowSlide(index: 2, remoteURL: try XCTUnwrap(URL(string: "https://media.example.com/slide-2.jpg")))
            ]
        )
        let model = FlickAppModel(
            repository: InMemoryFlickRepository(state: FlickEmptyState.make()),
            configuration: makeTestAppConfiguration()
        )

        model.createDraft(from: template)

        XCTAssertEqual(model.overview.assets.count, 2)
        XCTAssertEqual(model.overview.assets.map(\.publicURL), template.slides.map(\.remoteURL))
        XCTAssertTrue(model.overview.assets.allSatisfy { $0.localFilePath == nil })
        XCTAssertEqual(model.activeCreateDraft?.slides.count, 2)
    }

    func testDeleteLocalAnalysisRemovesMatchingCreativeTemplate() async throws {
        let sourceTemplate = makeExampleSlideshowTemplate(id: "cached-template")
        let fingerprint = TemplateAnalysisCacheService.fingerprint(for: sourceTemplate)
        let matchingTemplate = makeCreativeTemplate(
            sourceTemplateID: sourceTemplate.id,
            sourceTemplateFingerprint: fingerprint,
            analysisSchemaVersion: TemplateAnalysisCacheService.schemaVersion
        )
        let unrelatedTemplate = makeCreativeTemplate(
            sourceTemplateID: "other-template",
            sourceTemplateFingerprint: "other-fingerprint",
            analysisSchemaVersion: TemplateAnalysisCacheService.schemaVersion
        )
        var state = FlickEmptyState.make()
        state.templates = [matchingTemplate, unrelatedTemplate]
        let repository = InMemoryFlickRepository(state: state)
        let model = FlickAppModel(repository: repository, configuration: makeTestAppConfiguration())

        await model.refresh()
        await model.deleteLocalAnalysis(for: sourceTemplate)

        XCTAssertEqual(model.overview.templates.map(\.id), [unrelatedTemplate.id])
        XCTAssertEqual(repository.state.templates.map(\.id), [unrelatedTemplate.id])
    }

    func testAnalysisCacheHitSkipsOpenAI() async throws {
        let styleGuide = makeTemplateStyleGuide(styleName: "Cached Style")
        let template = makeExampleSlideshowTemplate(id: "cached-template")
        let fingerprint = TemplateAnalysisCacheService.fingerprint(for: template)
        let path = TemplateAnalysisCacheService.cachePath(templateID: template.id, fingerprint: fingerprint)
        let storage = FakeTemplateAnalysisStorage()
        storage.cachedDataByPath[path] = try makeAnalysisCacheRecordData(
            templateID: template.id,
            fingerprint: fingerprint,
            styleGuide: styleGuide
        )
        var openAIRequestCount = 0
        CapturingURLProtocol.requestHandler = { request in
            openAIRequestCount += 1
            return (
                HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }

        let service = TemplateAnalysisCacheService(
            openAIClient: makeOpenAIClientForTests(),
            storage: storage
        )
        let resolved = try await service.resolveStyleGuide(for: template)

        XCTAssertEqual(resolved, styleGuide)
        XCTAssertEqual(openAIRequestCount, 0)
        XCTAssertTrue(storage.uploads.isEmpty)
    }

    func testAnalysisCacheMissCallsOpenAIOnceAndStoresJSON() async throws {
        let styleGuide = makeTemplateStyleGuide(styleName: "Fresh Style")
        let template = makeExampleSlideshowTemplate(id: "fresh-template")
        let fingerprint = TemplateAnalysisCacheService.fingerprint(for: template)
        var openAIRequestCount = 0
        CapturingURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/responses")
            openAIRequestCount += 1

            let outputData = try JSONEncoder.flick.encode(styleGuide)
            let outputText = try XCTUnwrap(String(data: outputData, encoding: .utf8))
            let responseData = try JSONSerialization.data(withJSONObject: ["output_text": outputText])
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                responseData
            )
        }
        let storage = FakeTemplateAnalysisStorage()
        let service = TemplateAnalysisCacheService(
            openAIClient: makeOpenAIClientForTests(),
            storage: storage
        )

        let resolved = try await service.resolveStyleGuide(for: template)

        XCTAssertEqual(resolved, styleGuide)
        XCTAssertEqual(openAIRequestCount, 1)
        XCTAssertEqual(storage.uploads.count, 1)
        XCTAssertEqual(storage.uploads.first?.path, TemplateAnalysisCacheService.cachePath(templateID: template.id, fingerprint: fingerprint))
        XCTAssertNotNil(storage.cachedDataByPath[TemplateAnalysisCacheService.cachePath(templateID: template.id, fingerprint: fingerprint)])
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

    func testLoginKitAccountMetadataRequestsBasicFieldsOnly() async throws {
        LoginKitSuccessMetadataURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoginKitSuccessMetadataURLProtocol.self]
        let store = MemorySecretStore()
        let client = TikTokLoginKitClient(
            urlSession: URLSession(configuration: configuration),
            accountStore: LoginKitAccountStore(store: store),
            tokenStore: LoginKitTokenStore(store: store)
        )

        let account = try await client.refreshAuthorizedAccount(
            accessToken: "access-token",
            scopes: ["user.info.basic", "video.publish"]
        )

        XCTAssertEqual(LoginKitSuccessMetadataURLProtocol.capturedPath, "/v2/user/info")
        XCTAssertEqual(LoginKitSuccessMetadataURLProtocol.capturedFields, "open_id,avatar_url,display_name")
        XCTAssertFalse(LoginKitSuccessMetadataURLProtocol.capturedFields?.contains("username") == true)
        XCTAssertEqual(LoginKitSuccessMetadataURLProtocol.capturedAuthorizationHeader, "Bearer access-token")
        XCTAssertEqual(account.platformUserID, "real-open-id")
        XCTAssertEqual(account.displayName, "Creator Name")
        let storedAccount = try XCTUnwrap(LoginKitAccountStore(store: store).loadAccounts().first)
        XCTAssertEqual(storedAccount.id, account.id)
        XCTAssertEqual(storedAccount.platformUserID, "real-open-id")
        XCTAssertEqual(storedAccount.displayName, "Creator Name")
    }

    func testLoginKitAccountMetadataFailureIncludesTikTokDiagnostics() async throws {
        LoginKitFailureMetadataURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoginKitFailureMetadataURLProtocol.self]
        let store = MemorySecretStore()
        let client = TikTokLoginKitClient(
            urlSession: URLSession(configuration: configuration),
            accountStore: LoginKitAccountStore(store: store),
            tokenStore: LoginKitTokenStore(store: store)
        )

        do {
            _ = try await client.refreshAuthorizedAccount(
                accessToken: "access-token",
                scopes: ["video.publish"]
            )
            XCTFail("Expected Login Kit metadata refresh to fail.")
        } catch let error as LoginKitError {
            XCTAssertTrue(error.localizedDescription.contains("HTTP 403"))
            XCTAssertTrue(error.localizedDescription.contains("scope_not_authorized"))
            XCTAssertTrue(error.localizedDescription.contains("metadata-log-123"))
            XCTAssertTrue(error.diagnosticDescription.contains("rawResponse="))
            XCTAssertEqual(LoginKitFailureMetadataURLProtocol.capturedPath, "/v2/user/info")
        }
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

    func testLoginKitAccountStorePersistsMultipleTikTokAccounts() throws {
        let store = MemorySecretStore()
        let accountStore = LoginKitAccountStore(store: store)
        let firstAccount = LoginKitAccountMapper.connectedAccount(
            from: LoginKitAuthorizedUser(
                platform: .tiktok,
                openID: "first-open-id",
                displayName: "@first",
                avatarURL: nil,
                scopes: ["user.info.basic", "video.publish"]
            )
        )
        let secondAccount = LoginKitAccountMapper.connectedAccount(
            from: LoginKitAuthorizedUser(
                platform: .tiktok,
                openID: "second-open-id",
                displayName: "@second",
                avatarURL: nil,
                scopes: ["user.info.basic", "video.publish"]
            )
        )

        try accountStore.upsert(firstAccount)
        try accountStore.upsert(secondAccount)

        let accounts = accountStore.loadAccounts()
        XCTAssertEqual(Set(accounts.map(\.platformUserID)), ["first-open-id", "second-open-id"])
        XCTAssertEqual(accounts.count, 2)
    }

    func testLoginKitTokenStoreKeysTokensByTikTokPlatformUserID() throws {
        let store = MemorySecretStore()
        let tokenStore = LoginKitTokenStore(store: store)
        let firstAccount = LoginKitAccountMapper.connectedAccount(
            from: LoginKitAuthorizedUser(
                platform: .tiktok,
                openID: "first-open-id",
                displayName: "@first",
                avatarURL: nil,
                scopes: ["user.info.basic", "video.publish"]
            )
        )
        let secondAccount = LoginKitAccountMapper.connectedAccount(
            from: LoginKitAuthorizedUser(
                platform: .tiktok,
                openID: "second-open-id",
                displayName: "@second",
                avatarURL: nil,
                scopes: ["user.info.basic", "video.publish"]
            )
        )
        let now = Date()
        try tokenStore.save(
            LoginKitTokenBundle(
                platform: .tiktok,
                platformUserID: firstAccount.platformUserID,
                accessToken: "first-access",
                refreshToken: "first-refresh",
                tokenType: "Bearer",
                scopes: firstAccount.scopes,
                accessTokenExpiresAt: now.addingTimeInterval(3_600),
                refreshTokenExpiresAt: now.addingTimeInterval(86_400),
                updatedAt: now
            ),
            for: firstAccount
        )
        try tokenStore.save(
            LoginKitTokenBundle(
                platform: .tiktok,
                platformUserID: secondAccount.platformUserID,
                accessToken: "second-access",
                refreshToken: "second-refresh",
                tokenType: "Bearer",
                scopes: secondAccount.scopes,
                accessTokenExpiresAt: now.addingTimeInterval(3_600),
                refreshTokenExpiresAt: now.addingTimeInterval(86_400),
                updatedAt: now
            ),
            for: secondAccount
        )

        XCTAssertEqual(try tokenStore.tokenBundle(for: firstAccount)?.accessToken, "first-access")
        XCTAssertEqual(try tokenStore.tokenBundle(for: secondAccount)?.accessToken, "second-access")
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

    func testLoginKitTokenReconciliationPreservesSyncedTikTokAccountWhenLocalTokenIsMissing() throws {
        let secretStore = MemorySecretStore()
        let account = LoginKitAccountMapper.connectedAccount(
            from: LoginKitAuthorizedUser(
                platform: .tiktok,
                openID: "real-open-id",
                displayName: "@realaccount",
                avatarURL: nil,
                scopes: ["user.info.basic", "video.publish"]
            )
        )
        let client = TikTokLoginKitClient(
            accountStore: LoginKitAccountStore(store: secretStore),
            tokenStore: LoginKitTokenStore(store: secretStore)
        )
        let model = FlickAppModel(
            repository: InMemoryFlickRepository(state: FlickEmptyState.make()),
            configuration: makeTestAppConfiguration(),
            tiktokLoginKitClient: client
        )
        model.overview.accounts = [account]

        XCTAssertFalse(model.reconcileLoginKitAccountTokenStatus())

        let reconciledAccount = try XCTUnwrap(model.overview.accounts.first)
        XCTAssertEqual(reconciledAccount, account)
        XCTAssertFalse(model.canPublish(reconciledAccount, on: .tiktok))
    }

    func testLoginKitTokenReconciliationPreservesRefreshFailureUntilNewTokenBundle() throws {
        let secretStore = MemorySecretStore()
        let failureDate = Date(timeIntervalSince1970: 1_800_000_000)
        var account = LoginKitAccountMapper.connectedAccount(
            from: LoginKitAuthorizedUser(
                platform: .tiktok,
                openID: "real-open-id",
                displayName: "@realaccount",
                avatarURL: nil,
                scopes: ["user.info.basic", "video.publish"]
            ),
            now: failureDate.addingTimeInterval(-120)
        )
        account.status = .needsAuth
        account.tokenStatus = .refreshFailed
        account.isPublishingEnabled = false
        account.updatedAt = failureDate
        let tokenStore = LoginKitTokenStore(store: secretStore)
        let staleBundle = LoginKitTokenBundle(
            platform: .tiktok,
            platformUserID: account.platformUserID,
            accessToken: "expired-access-token",
            refreshToken: "refresh-token",
            tokenType: "Bearer",
            scopes: account.scopes,
            accessTokenExpiresAt: failureDate.addingTimeInterval(-60),
            refreshTokenExpiresAt: failureDate.addingTimeInterval(3_600),
            updatedAt: failureDate.addingTimeInterval(-120)
        )
        try tokenStore.save(staleBundle, for: account)
        let client = TikTokLoginKitClient(
            accountStore: LoginKitAccountStore(store: secretStore),
            tokenStore: tokenStore
        )
        let model = FlickAppModel(
            repository: InMemoryFlickRepository(state: FlickEmptyState.make()),
            configuration: makeTestAppConfiguration(),
            tiktokLoginKitClient: client
        )
        model.overview.accounts = [account]

        XCTAssertFalse(model.reconcileLoginKitAccountTokenStatus(now: failureDate.addingTimeInterval(60)))
        var reconciledAccount = try XCTUnwrap(model.overview.accounts.first)
        XCTAssertEqual(reconciledAccount.status, .needsAuth)
        XCTAssertEqual(reconciledAccount.tokenStatus, .refreshFailed)
        XCTAssertFalse(reconciledAccount.isPublishingEnabled)
        XCTAssertFalse(reconciledAccount.canPublishToTikTok)

        let refreshedBundle = LoginKitTokenBundle(
            platform: .tiktok,
            platformUserID: account.platformUserID,
            accessToken: "new-access-token",
            refreshToken: "new-refresh-token",
            tokenType: "Bearer",
            scopes: account.scopes,
            accessTokenExpiresAt: failureDate.addingTimeInterval(86_400),
            refreshTokenExpiresAt: failureDate.addingTimeInterval(31_536_000),
            updatedAt: failureDate.addingTimeInterval(120)
        )
        try tokenStore.save(refreshedBundle, for: account)

        XCTAssertTrue(model.reconcileLoginKitAccountTokenStatus(now: failureDate.addingTimeInterval(180)))
        reconciledAccount = try XCTUnwrap(model.overview.accounts.first)
        XCTAssertEqual(reconciledAccount.status, .connected)
        XCTAssertEqual(reconciledAccount.tokenStatus, .valid)
        XCTAssertTrue(reconciledAccount.isPublishingEnabled)
        XCTAssertTrue(reconciledAccount.canPublishToTikTok)
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
            case "/rendered-slide.jpg":
                XCTAssertEqual(request.httpMethod, "HEAD")
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: [
                            "Content-Type": "image/jpeg",
                            "Content-Length": "1024"
                        ]
                    )!,
                    Data()
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
                imageURLs: [try XCTUnwrap(URL(string: "https://example.com/rendered-slide.jpg"))],
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

    func testTikTokAdapterUsesMediaUploadForDraftUploads() async throws {
        let secretStore = MemorySecretStore()
        let account = LoginKitAccountMapper.connectedAccount(
            from: LoginKitAuthorizedUser(
                platform: .tiktok,
                openID: "real-open-id",
                displayName: "@realaccount",
                avatarURL: nil,
                scopes: ["user.info.basic", "video.upload"]
            )
        )
        let tokenBundle = LoginKitTokenBundle(
            platform: .tiktok,
            platformUserID: account.platformUserID,
            accessToken: "valid-access-token",
            refreshToken: "refresh-token",
            tokenType: "Bearer",
            scopes: account.scopes,
            accessTokenExpiresAt: Date(timeIntervalSinceNow: 3_600),
            refreshTokenExpiresAt: Date(timeIntervalSinceNow: 86_400),
            updatedAt: Date()
        )
        try LoginKitTokenStore(store: secretStore).save(tokenBundle, for: account)

        let publishBody = CapturingURLProtocol.CapturedValue()
        let statusBody = CapturingURLProtocol.CapturedValue()
        CapturingURLProtocol.requestHandler = { request in
            switch request.url?.path.removingTrailingSlash {
            case "/v2/post/publish/content/init":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer valid-access-token")
                publishBody.value = request.encodedBodyString
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(
                        """
                        {
                            "data": {
                                "publish_id": "p_inbox_url~v2.123"
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
            case "/rendered-slide.jpg":
                XCTAssertEqual(request.httpMethod, "HEAD")
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: [
                            "Content-Type": "image/jpeg",
                            "Content-Length": "1024"
                        ]
                    )!,
                    Data()
                )
            case "/v2/post/publish/status/fetch":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer valid-access-token")
                statusBody.value = request.encodedBodyString
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(
                        """
                        {
                            "data": {
                                "status": "SEND_TO_USER_INBOX"
                            },
                            "error": {
                                "code": "ok",
                                "message": "",
                                "log_id": "status-log-123"
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
        let adapter = TikTokAdapter(
            configuration: TikTokConfiguration(values: [
                "TIKTOK_CLIENT_ID": "client-key",
                "TIKTOK_VERIFIED_BASE_URL": "https://example.com"
            ]),
            tokenStore: secretStore,
            urlSession: URLSession(configuration: configuration),
            statusPollIntervalNanoseconds: 0
        )
        var job = makePublishingJob()
        job.accountID = account.id

        let result = try await adapter.publish(
            job,
            account: account,
            media: PreparedPlatformMedia(
                mode: .photoUploadForCompletion,
                imageURLs: [try XCTUnwrap(URL(string: "https://example.com/rendered-slide.jpg"))],
                videoURL: nil,
                warnings: []
            ),
            settings: TikTokManualPublishSettings(
                title: "Launch",
                description: "Try Flick",
                postAsDraft: true,
                privacyLevel: .publicToEveryone,
                allowComment: true,
                allowDuet: true,
                allowStitch: true,
                disclosesVideoContent: true,
                promotesYourBrand: true,
                promotesBrandedContent: true
            )
        )

        let body = try XCTUnwrap(publishBody.value)
        let fetchedStatusBody = try XCTUnwrap(statusBody.value)
        XCTAssertEqual(result.platformPostID, "p_inbox_url~v2.123")
        XCTAssertEqual(result.platformStatus, "SEND_TO_USER_INBOX")
        XCTAssertTrue(body.contains(#""post_mode":"MEDIA_UPLOAD""#))
        XCTAssertTrue(fetchedStatusBody.contains(#""publish_id":"p_inbox_url~v2.123""#))
        XCTAssertFalse(body.contains("privacy_level"))
        XCTAssertFalse(body.contains("disable_comment"))
        XCTAssertFalse(body.contains("brand_content_toggle"))
        XCTAssertFalse(body.contains("brand_organic_toggle"))
    }

    func testTikTokAdapterSurfacesStatusRateLimitError() async throws {
        let secretStore = MemorySecretStore()
        let account = LoginKitAccountMapper.connectedAccount(
            from: LoginKitAuthorizedUser(
                platform: .tiktok,
                openID: "real-open-id",
                displayName: "@realaccount",
                avatarURL: nil,
                scopes: ["user.info.basic", "video.upload"]
            )
        )
        let tokenBundle = LoginKitTokenBundle(
            platform: .tiktok,
            platformUserID: account.platformUserID,
            accessToken: "valid-access-token",
            refreshToken: "refresh-token",
            tokenType: "Bearer",
            scopes: account.scopes,
            accessTokenExpiresAt: Date(timeIntervalSinceNow: 3_600),
            refreshTokenExpiresAt: Date(timeIntervalSinceNow: 86_400),
            updatedAt: Date()
        )
        try LoginKitTokenStore(store: secretStore).save(tokenBundle, for: account)

        CapturingURLProtocol.requestHandler = { request in
            switch request.url?.path.removingTrailingSlash {
            case "/v2/post/publish/status/fetch":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!,
                    Data(
                        """
                        {
                            "data": {},
                            "error": {
                                "code": "rate_limit_exceeded",
                                "message": "The API rate limit exceeded. Please try again later.",
                                "log_id": "status-rate-limit-log"
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
        let adapter = TikTokAdapter(
            configuration: TikTokConfiguration(values: ["TIKTOK_CLIENT_ID": "client-key"]),
            tokenStore: secretStore,
            urlSession: URLSession(configuration: configuration)
        )

        do {
            _ = try await adapter.fetchPublishStatus(
                publishID: "p_inbox_url~v2.123",
                account: account
            )
            XCTFail("Expected TikTok rate limit error.")
        } catch let error as TikTokPublishAPIError {
            XCTAssertEqual(error.code, "rate_limit_exceeded")
            XCTAssertTrue(error.rawResponse.contains("status-rate-limit-log"))
        }
    }

    func testTikTokAdapterKeepsInitializedDraftUploadWhenStatusFetchRateLimited() async throws {
        let secretStore = MemorySecretStore()
        let account = LoginKitAccountMapper.connectedAccount(
            from: LoginKitAuthorizedUser(
                platform: .tiktok,
                openID: "real-open-id",
                displayName: "@realaccount",
                avatarURL: nil,
                scopes: ["user.info.basic", "video.upload"]
            )
        )
        let tokenBundle = LoginKitTokenBundle(
            platform: .tiktok,
            platformUserID: account.platformUserID,
            accessToken: "valid-access-token",
            refreshToken: "refresh-token",
            tokenType: "Bearer",
            scopes: account.scopes,
            accessTokenExpiresAt: Date(timeIntervalSinceNow: 3_600),
            refreshTokenExpiresAt: Date(timeIntervalSinceNow: 86_400),
            updatedAt: Date()
        )
        try LoginKitTokenStore(store: secretStore).save(tokenBundle, for: account)

        CapturingURLProtocol.requestHandler = { request in
            switch request.url?.path.removingTrailingSlash {
            case "/rendered-slide.jpg":
                XCTAssertEqual(request.httpMethod, "HEAD")
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: [
                            "Content-Type": "image/jpeg",
                            "Content-Length": "1024"
                        ]
                    )!,
                    Data()
                )
            case "/v2/post/publish/content/init":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(
                        """
                        {
                            "data": {
                                "publish_id": "p_inbox_url~v2.123"
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
            case "/v2/post/publish/status/fetch":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!,
                    Data(
                        """
                        {
                            "data": {},
                            "error": {
                                "code": "rate_limit_exceeded",
                                "message": "The API rate limit exceeded. Please try again later.",
                                "log_id": "status-rate-limit-log"
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
        let adapter = TikTokAdapter(
            configuration: TikTokConfiguration(values: [
                "TIKTOK_CLIENT_ID": "client-key",
                "TIKTOK_VERIFIED_BASE_URL": "https://example.com"
            ]),
            tokenStore: secretStore,
            urlSession: URLSession(configuration: configuration),
            statusPollIntervalNanoseconds: 0
        )
        var job = makePublishingJob()
        job.accountID = account.id

        let result = try await adapter.publish(
            job,
            account: account,
            media: PreparedPlatformMedia(
                mode: .photoUploadForCompletion,
                imageURLs: [try XCTUnwrap(URL(string: "https://example.com/rendered-slide.jpg"))],
                videoURL: nil,
                warnings: []
            ),
            settings: TikTokManualPublishSettings(
                title: "Launch",
                description: "Try Flick",
                postAsDraft: true,
                privacyLevel: .selfOnly,
                allowComment: true,
                allowDuet: false,
                allowStitch: false,
                disclosesVideoContent: false,
                promotesYourBrand: false,
                promotesBrandedContent: false
            )
        )

        XCTAssertEqual(result.platformPostID, "p_inbox_url~v2.123")
        XCTAssertNil(result.platformStatus)
        XCTAssertTrue(result.rawResponse.contains("rate_limit_exceeded"))
    }

    func testTikTokAdapterDecodesPublishCompleteStatusWithStringPostIDs() async throws {
        let secretStore = MemorySecretStore()
        let account = LoginKitAccountMapper.connectedAccount(
            from: LoginKitAuthorizedUser(
                platform: .tiktok,
                openID: "real-open-id",
                displayName: "@realaccount",
                avatarURL: nil,
                scopes: ["user.info.basic", "video.upload"]
            )
        )
        let tokenBundle = LoginKitTokenBundle(
            platform: .tiktok,
            platformUserID: account.platformUserID,
            accessToken: "valid-access-token",
            refreshToken: "refresh-token",
            tokenType: "Bearer",
            scopes: account.scopes,
            accessTokenExpiresAt: Date(timeIntervalSinceNow: 3_600),
            refreshTokenExpiresAt: Date(timeIntervalSinceNow: 86_400),
            updatedAt: Date()
        )
        try LoginKitTokenStore(store: secretStore).save(tokenBundle, for: account)

        CapturingURLProtocol.requestHandler = { request in
            switch request.url?.path.removingTrailingSlash {
            case "/v2/post/publish/status/fetch":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer valid-access-token")
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(
                        """
                        {
                            "data": {
                                "status": "PUBLISH_COMPLETE",
                                "publicly_available_post_id": ["7123456789012345678"]
                            },
                            "error": {
                                "code": "ok",
                                "message": "",
                                "log_id": "status-log-123"
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
        let adapter = TikTokAdapter(
            configuration: TikTokConfiguration(values: ["TIKTOK_CLIENT_ID": "client-key"]),
            tokenStore: secretStore,
            urlSession: URLSession(configuration: configuration)
        )

        let status = try await adapter.fetchPublishStatus(
            publishID: "p_inbox_url~v2.123",
            account: account
        )

        XCTAssertEqual(status.status, "PUBLISH_COMPLETE")
        XCTAssertTrue(status.isPublishComplete)
        XCTAssertEqual(status.publiclyAvailablePostIDs, ["7123456789012345678"])
    }

    func testAccountManagementPolicySupportsYouTubeOnEveryDeviceAndTikTokOnIOSOnly() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        XCTAssertTrue(AccountManagementPolicy.canAuthorize(.tiktok))
        #else
        XCTAssertFalse(AccountManagementPolicy.canAuthorize(.tiktok))
        #endif
        XCTAssertTrue(AccountManagementPolicy.canAuthorize(.youtubeShorts))
        XCTAssertTrue(AccountManagementPolicy.canAuthorizeAccountsOnThisDevice)
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
        XCTAssertTrue(SlideshowImageGenerationSettings.draft.isGPTImage2CompatibleCustomSize)

        XCTAssertEqual(SlideshowImageGenerationSettings.finalExport.size, "1024x1536")
        XCTAssertEqual(SlideshowImageGenerationSettings.finalExport.width, 1024)
        XCTAssertEqual(SlideshowImageGenerationSettings.finalExport.height, 1536)
        XCTAssertEqual(SlideshowImageGenerationSettings.finalExport.aspectRatio, 2.0 / 3.0)
        XCTAssertTrue(SlideshowImageGenerationSettings.finalExport.isGPTImage2CompatibleCustomSize)
    }

    func testTikTokPhotoPostRenderOptionsUseSupportedFormat() {
        let options = ImageRenderOptions.tikTokPhotoPost

        XCTAssertEqual(options.width, 720)
        XCTAssertEqual(options.height, 1080)
        XCTAssertEqual(options.jpegQuality, 0.92)
        XCTAssertEqual(options.contentType, "image/jpeg")
        XCTAssertEqual(options.fileExtension, "jpg")
        XCTAssertTrue(options.fitsTikTokPhotoPostImageSize)
    }

    func testTextOverlayRendererWritesTikTokJpegImages() async throws {
        #if canImport(UIKit)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("flick-render-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let sourceURL = directory.appendingPathComponent("source.png")
        let sourceData = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 180)).pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 180))
        }
        try sourceData.write(to: sourceURL)

        let asset = makeMediaAsset(
            source: .generated,
            localFilePath: sourceURL.path,
            width: 120,
            height: 180,
            now: now
        )
        var slide = makeSlide(imageAssetID: asset.id, generationStatus: .complete, now: now)
        slide.text = "Launch"
        let draft = makeSlideshowDraft(slides: [slide], now: now)
        let options = ImageRenderOptions.tikTokPhotoPost
        let renderedImages = try await TextOverlayRenderService(renderDirectory: directory)
            .renderImages(from: draft, assets: [asset], options: options)
        let renderedImage = try XCTUnwrap(renderedImages.first)
        let renderedData = try Data(contentsOf: renderedImage.fileURL)
        let renderedSource = try XCTUnwrap(CGImageSourceCreateWithData(renderedData as CFData, nil))
        let decodedImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(renderedSource, 0, nil))

        XCTAssertEqual(renderedImage.contentType, "image/jpeg")
        XCTAssertEqual(renderedImage.fileURL.pathExtension, "jpg")
        XCTAssertEqual(renderedImage.width, options.width)
        XCTAssertEqual(renderedImage.height, options.height)
        XCTAssertEqual(decodedImage.width, options.width)
        XCTAssertEqual(decodedImage.height, options.height)
        XCTAssertLessThanOrEqual(max(decodedImage.width, decodedImage.height), ImageRenderOptions.tikTokPhotoPostMaximumPixelEdge)
        XCTAssertEqual(Array(renderedData.prefix(3)), [0xFF, 0xD8, 0xFF])
        #endif
    }

    func testProductImageCropRendererWritesGeneratedSlideSizedJPEG() throws {
        #if canImport(UIKit)
        let sourceImage = makeTestImage(width: 300, height: 120)
        var cropState = ProductImageCropState()
        cropState.center = CGPoint(x: 0.42, y: 0.5)
        cropState.zoom = 1.25

        let data = try ProductImageCropRenderer.jpegData(
            image: sourceImage,
            cropState: cropState,
            targetPixelSize: ProductImageCropSheet.generatedSlideTargetPixelSize
        )
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let decodedImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))

        XCTAssertEqual(decodedImage.width, SlideshowImageGenerationSettings.draft.width)
        XCTAssertEqual(decodedImage.height, SlideshowImageGenerationSettings.draft.height)
        XCTAssertEqual(Array(data.prefix(3)), [0xFF, 0xD8, 0xFF])
        #endif
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
        XCTAssertTrue(prompt.contains("Use template/source people only"))
        XCTAssertTrue(prompt.contains("human-taken camera photo"))
        XCTAssertTrue(prompt.contains("Avoid AI gloss"))
        XCTAssertTrue(prompt.contains("waxy or porcelain skin"))
        XCTAssertTrue(prompt.contains("ignore that stale style instruction"))
    }

    func testGeneratedImagePromptIncludesSelectedCreationModelJSON() {
        let creationModel = makeCreationModel()
        let prompt = SlideshowImagePromptFormatter.applyVerticalOutputContract(
            to: "Create a founder in the same pose as the template.",
            settings: .draft,
            creationModel: creationModel.generationReference
        )

        XCTAssertTrue(prompt.contains("Selected creation model"))
        XCTAssertTrue(prompt.contains("\"skin_details\""))
        XCTAssertTrue(prompt.contains("Do not copy a template person's face"))
        XCTAssertTrue(prompt.contains("Cottagecore"))
    }

    func testGeneratedImagePromptIncludesSelectedImageVibe() {
        let prompt = SlideshowImagePromptFormatter.applyVerticalOutputContract(
            to: "Create a candid launch-party slide image.",
            settings: .draft,
            imageVibe: .phoneSnapshot
        )

        XCTAssertTrue(prompt.contains("casual smartphone photo"))
        XCTAssertTrue(prompt.contains("ordinary phone-camera perspective"))
        XCTAssertTrue(prompt.contains("human-taken camera photo"))
        XCTAssertTrue(prompt.contains("not AI-generated artwork"))
    }

    func testPlannerAppendsSelectedProductImageWhenTemplateHasNoProductSlot() async throws {
        let product = makeProduct(name: "Flick Pro")
        let creationModel = makeCreationModel()
        let productImageURL = try XCTUnwrap(URL(string: "https://example.com/product-image.jpg"))
        let productImage = SlideshowProductImage(
            product: product,
            asset: makeMediaAsset(
                source: .uploaded,
                publicURL: productImageURL,
                productIDs: [product.id]
            )
        )
        let responsePlan = PlannedSlideshow(
            title: "Launch Carousel",
            tikTokTitle: "Launch Flick Pro",
            topic: "Product launch",
            audience: "Creators",
            goal: "Increase installs",
            tone: "Direct",
            slideCount: 3,
            narrativeArc: ["Hook", "Product", "Proof"],
            globalVisualMotif: "Clean product frames",
            planSummary: "Two template slides plus one final product image slide.",
            slides: [
                PlannedSlide(index: 0, text: "Start here", textPosition: .center, imagePrompt: "Generated hook", selectedVisualSummary: "Hook visual", usesProductImage: false),
                PlannedSlide(index: 1, text: "Ship faster", textPosition: .center, imagePrompt: "Generated proof", selectedVisualSummary: "Proof visual", usesProductImage: false),
                PlannedSlide(index: 2, text: "See Flick Pro", textPosition: .center, imagePrompt: "Use selected product image", selectedVisualSummary: "Product image", usesProductImage: true)
            ],
            caption: "Try Flick Pro",
            hashtags: ["flick"]
        )

        CapturingURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/responses")
            let bodyData = Data(request.encodedBodyString.utf8)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            let input = try XCTUnwrap(body["input"] as? [[String: Any]])
            let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
            let promptText = try XCTUnwrap(content.first?["text"] as? String)

            XCTAssertTrue(promptText.contains("Template slide count to keep: 2"))
            XCTAssertTrue(promptText.contains("Total planned slide count to return: 3"))
            XCTAssertTrue(promptText.contains("TikTok post title"))
            XCTAssertTrue(promptText.contains("Selected creation model"))
            XCTAssertTrue(promptText.contains("\"skin_details\""))
            XCTAssertTrue(promptText.contains("Do not copy the template person's face"))
            XCTAssertTrue(promptText.contains("Image vibe: Documentary"))
            XCTAssertTrue(promptText.contains("observational documentary photography"))
            XCTAssertTrue(promptText.contains("real camera photograph made by a human"))
            XCTAssertTrue(promptText.contains("Detected template product-image slide numbers: none"))
            XCTAssertTrue(promptText.contains("Append the selected product image as one final actual slide image at the end of the carousel."))
            XCTAssertTrue(promptText.contains("Keep exactly 2 non-product generated/template slides, plus this final product-image slide."))
            XCTAssertEqual(content.last?["image_url"] as? String, productImageURL.absoluteString)

            let responsePlanData = try JSONEncoder.flick.encode(responsePlan)
            let responsePlanText = try XCTUnwrap(String(data: responsePlanData, encoding: .utf8))
            let responseData = try JSONSerialization.data(withJSONObject: ["output_text": responsePlanText])
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                responseData
            )
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = OpenAIClient(
            credentials: ["OPENAI_API_KEY": "test-key"],
            urlSession: session
        )

        let plan = try await SlideshowPlannerService(client: client).createPlan(
            brief: "Launch Flick Pro",
            template: makeExampleSlideshowTemplate(slideCount: 2),
            styleGuide: .empty,
            creationModel: creationModel.generationReference,
            productImage: productImage,
            imageVibe: .documentary
        )

        XCTAssertEqual(plan.slides.count, 3)
        XCTAssertEqual(plan.slides.filter(\.usesProductImage).count, 1)
        XCTAssertTrue(plan.slides.sorted { $0.index < $1.index }.last?.usesProductImage == true)
        XCTAssertEqual(plan.tikTokTitle, "Launch Flick Pro")
    }

    func testPlannerReplacesDetectedTemplateProductSlotWithSelectedProductImage() async throws {
        let product = makeProduct(name: "Flick Pro")
        let productImageURL = try XCTUnwrap(URL(string: "https://example.com/product-image.jpg"))
        let productImage = SlideshowProductImage(
            product: product,
            asset: makeMediaAsset(
                source: .uploaded,
                publicURL: productImageURL,
                productIDs: [product.id]
            )
        )
        let styleGuide = makeTemplateStyleGuide(
            styleName: "Launch Style",
            productImageSlideNumbers: [2]
        )
        let responsePlan = PlannedSlideshow(
            title: "Launch Carousel",
            tikTokTitle: "Launch Flick Pro",
            topic: "Product launch",
            audience: "Creators",
            goal: "Increase installs",
            tone: "Direct",
            slideCount: 3,
            narrativeArc: ["Hook", "Product", "Proof"],
            globalVisualMotif: "Clean product frames",
            planSummary: "A template product slot is replaced by Flick Pro.",
            slides: [
                PlannedSlide(index: 0, text: "Start here", textPosition: .center, imagePrompt: "Generated hook", selectedVisualSummary: "Hook visual", usesProductImage: false),
                PlannedSlide(index: 1, text: "See Flick Pro", textPosition: .center, imagePrompt: "Use selected product image", selectedVisualSummary: "Product image", usesProductImage: true),
                PlannedSlide(index: 2, text: "Ship faster", textPosition: .center, imagePrompt: "Generated proof", selectedVisualSummary: "Proof visual", usesProductImage: false)
            ],
            caption: "Try Flick Pro",
            hashtags: ["flick"]
        )

        CapturingURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/responses")
            let bodyData = Data(request.encodedBodyString.utf8)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            let input = try XCTUnwrap(body["input"] as? [[String: Any]])
            let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
            let promptText = try XCTUnwrap(content.first?["text"] as? String)

            XCTAssertTrue(promptText.contains("Total planned slide count to return: 3"))
            XCTAssertTrue(promptText.contains("Detected template product-image slide numbers: 2"))
            XCTAssertTrue(promptText.contains("Replace those template product-image positions with the attached selected product image. Do not add an extra product-image slide."))
            XCTAssertTrue(promptText.contains("Set usesProductImage to true only for those detected template product-image positions"))
            XCTAssertEqual(content.last?["image_url"] as? String, productImageURL.absoluteString)

            let responsePlanData = try JSONEncoder.flick.encode(responsePlan)
            let responsePlanText = try XCTUnwrap(String(data: responsePlanData, encoding: .utf8))
            let responseData = try JSONSerialization.data(withJSONObject: ["output_text": responsePlanText])
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                responseData
            )
        }

        let plan = try await SlideshowPlannerService(client: makeOpenAIClientForTests()).createPlan(
            brief: "Launch Flick Pro",
            template: makeExampleSlideshowTemplate(slideCount: 3),
            styleGuide: styleGuide,
            productImage: productImage
        )

        XCTAssertEqual(plan.slides.count, 3)
        XCTAssertEqual(
            plan.slides.sorted { $0.index < $1.index }.enumerated().compactMap { offset, slide in
                slide.usesProductImage ? offset + 1 : nil
            },
            [2]
        )
    }

    func testPlannerRemovesTemplateProductImagesWhenNoProductSelected() async throws {
        let styleGuide = makeTemplateStyleGuide(
            styleName: "Launch Style",
            productImageSlideNumbers: [2]
        )
        let responsePlan = PlannedSlideshow(
            title: "Launch Carousel",
            tikTokTitle: "Launch Flick Pro",
            topic: "Product launch",
            audience: "Creators",
            goal: "Increase installs",
            tone: "Direct",
            slideCount: 3,
            narrativeArc: ["Hook", "Middle", "Proof"],
            globalVisualMotif: "Clean motion frames",
            planSummary: "The template product slot becomes a non-product slide.",
            slides: [
                PlannedSlide(index: 0, text: "Start here", textPosition: .center, imagePrompt: "Generated hook", selectedVisualSummary: "Hook visual", usesProductImage: false),
                PlannedSlide(index: 1, text: "Keep going", textPosition: .center, imagePrompt: "Abstract workflow visual with no product imagery", selectedVisualSummary: "Non-product middle visual", usesProductImage: false),
                PlannedSlide(index: 2, text: "Ship faster", textPosition: .center, imagePrompt: "Generated proof", selectedVisualSummary: "Proof visual", usesProductImage: false)
            ],
            caption: "Try Flick Pro",
            hashtags: ["flick"]
        )

        CapturingURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/responses")
            let bodyData = Data(request.encodedBodyString.utf8)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            let input = try XCTUnwrap(body["input"] as? [[String: Any]])
            let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
            let promptText = try XCTUnwrap(content.first?["text"] as? String)

            XCTAssertEqual(content.count, 1)
            XCTAssertTrue(promptText.contains("Total planned slide count to return: 3"))
            XCTAssertTrue(promptText.contains("No selected product image was supplied."))
            XCTAssertTrue(promptText.contains("Detected template product-image slide numbers: 2."))
            XCTAssertTrue(promptText.contains("turn those positions into non-product generated visuals"))
            XCTAssertTrue(promptText.contains("Image prompts must not mention, recreate, imply, or visually describe the template product"))

            let responsePlanData = try JSONEncoder.flick.encode(responsePlan)
            let responsePlanText = try XCTUnwrap(String(data: responsePlanData, encoding: .utf8))
            let responseData = try JSONSerialization.data(withJSONObject: ["output_text": responsePlanText])
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                responseData
            )
        }

        let plan = try await SlideshowPlannerService(client: makeOpenAIClientForTests()).createPlan(
            brief: "Launch Flick Pro",
            template: makeExampleSlideshowTemplate(slideCount: 3),
            styleGuide: styleGuide
        )

        XCTAssertEqual(plan.slides.count, 3)
        XCTAssertTrue(plan.slides.allSatisfy { !$0.usesProductImage })
    }

    func testCreateAIAnalysisPrefillsTikTokSettingsTitle() async throws {
        let styleGuide = TemplateStyleGuide(
            styleName: "Clean Launch",
            visualTraits: ["Polished app visuals"],
            colorPalette: ["Blue", "White"],
            lighting: "Soft studio light",
            recurringMotifs: ["Phone frames"],
            reuseStructurally: ["Hook, product, proof"],
            avoidCopyingDirectly: ["Creator likeness"],
            imageGenerationRules: ["No readable text"]
        )
        let responsePlan = PlannedSlideshow(
            title: "Launch Carousel",
            tikTokTitle: "Launch Flick Pro",
            topic: "Product launch",
            audience: "Creators",
            goal: "Increase installs",
            tone: "Direct",
            slideCount: 2,
            narrativeArc: ["Hook", "Proof"],
            globalVisualMotif: "Clean product frames",
            planSummary: "Two-slide launch story.",
            slides: [
                PlannedSlide(index: 0, text: "Start here", textPosition: .center, imagePrompt: "Generated hook", selectedVisualSummary: "Hook visual", usesProductImage: false),
                PlannedSlide(index: 1, text: "Ship faster", textPosition: .center, imagePrompt: "Generated proof", selectedVisualSummary: "Proof visual", usesProductImage: false)
            ],
            caption: "Try Flick Pro",
            hashtags: ["flick"]
        )
        var requestCount = 0

        CapturingURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/responses")
            requestCount += 1

            let outputData: Data
            switch requestCount {
            case 1:
                outputData = try JSONEncoder.flick.encode(styleGuide)
            case 2:
                outputData = try JSONEncoder.flick.encode(responsePlan)
            default:
                XCTFail("Unexpected OpenAI request \(requestCount)")
                outputData = Data("{}".utf8)
            }

            let outputText = try XCTUnwrap(String(data: outputData, encoding: .utf8))
            let responseData = try JSONSerialization.data(withJSONObject: ["output_text": outputText])
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                responseData
            )
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = OpenAIClient(
            credentials: ["OPENAI_API_KEY": "test-key"],
            urlSession: session
        )
        let repository = InMemoryFlickRepository(state: FlickEmptyState.make())
        let model = FlickAppModel(
            repository: repository,
            configuration: .current,
            openAIClientFactory: { _ in client },
            templateAnalysisStorageFactory: { _ in FakeTemplateAnalysisStorage(missingConfiguration: true) }
        )
        let creationModel = makeCreationModel()

        await model.createAISlideshow(
            brief: "",
            from: makeExampleSlideshowTemplate(slideCount: 2),
            creationModel: creationModel.generationReference
        )

        let draft = try XCTUnwrap(model.activeCreateDraft)
        XCTAssertEqual(draft.tikTokSettings?.title, "Launch Flick Pro")
        XCTAssertEqual(draft.creationModel?.id, creationModel.id)
        XCTAssertEqual(draft.creationModel?.name, creationModel.name)
        XCTAssertEqual(repository.state.drafts.first?.tikTokSettings?.title, "Launch Flick Pro")
        XCTAssertEqual(repository.state.drafts.first?.creationModel?.id, creationModel.id)
    }

    func testOpenAIImageGenerationRequestsJpegOutput() async throws {
        let imageBytes = Data([0xFF, 0xD8, 0xFF])
        defer { CapturingURLProtocol.requestHandler = nil }
        CapturingURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/images/generations")
            XCTAssertEqual(request.timeoutInterval, 10 * 60, accuracy: 0.1)
            let bodyData = Data(request.encodedBodyString.utf8)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            XCTAssertEqual(body["output_format"] as? String, "jpeg")
            XCTAssertEqual(body["output_compression"] as? Int, 92)
            XCTAssertEqual(body["size"] as? String, SlideshowImageGenerationSettings.draft.size)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(
                    """
                    {
                        "data": [
                            {
                                "b64_json": "\(imageBytes.base64EncodedString())"
                            }
                        ]
                    }
                    """.utf8
                )
            )
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = OpenAIClient(
            credentials: ["OPENAI_API_KEY": "test-key"],
            urlSession: session
        )
        let image = try await client.generateImage(prompt: "Create a product image.", settings: .draft)

        XCTAssertEqual(image.data, imageBytes)
        XCTAssertEqual(image.contentType, "image/jpeg")
        XCTAssertEqual(image.fileExtension, "jpg")
    }

    func testOpenAIImageGenerationRetriesTimedOutRequestOnce() async throws {
        let imageBytes = Data([0xFF, 0xD8, 0xFF])
        var requestCount = 0
        defer { CapturingURLProtocol.requestHandler = nil }
        CapturingURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/images/generations")
            requestCount += 1
            if requestCount == 1 {
                throw URLError(.timedOut)
            }

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(
                    """
                    {
                        "data": [
                            {
                                "b64_json": "\(imageBytes.base64EncodedString())"
                            }
                        ]
                    }
                    """.utf8
                )
            )
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = OpenAIClient(
            credentials: ["OPENAI_API_KEY": "test-key"],
            urlSession: session,
            retryDelay: { _ in 0 }
        )

        let image = try await client.generateImage(prompt: "Create a product image.", settings: .draft)

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(image.data, imageBytes)
    }

    func testOpenAIImageGenerationDoesNotRetryNonRetryableError() async throws {
        var requestCount = 0
        defer { CapturingURLProtocol.requestHandler = nil }
        CapturingURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/images/generations")
            requestCount += 1
            return (
                HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!,
                Data(
                    """
                    {
                        "error": {
                            "message": "Invalid image request."
                        }
                    }
                    """.utf8
                )
            )
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = OpenAIClient(
            credentials: ["OPENAI_API_KEY": "test-key"],
            urlSession: session,
            retryDelay: { _ in 0 }
        )

        do {
            _ = try await client.generateImage(prompt: "Create a product image.", settings: .draft)
            XCTFail("Expected image generation to fail.")
        } catch OpenAIClientError.requestFailed(let statusCode, let message) {
            XCTAssertEqual(statusCode, 400)
            XCTAssertEqual(message, "Invalid image request.")
        }

        XCTAssertEqual(requestCount, 1)
    }
}

private func makePublishingJob(status: PublishingJobStatus = .rendering) -> PublishingJob {
    let now = Date()
    return PublishingJob(
        id: UUID(),
        platform: .tiktok,
        accountID: UUID(),
        draftID: UUID(),
        status: status,
        publishMode: .photoDirectPost,
        attemptCount: 0,
        lastAttemptAt: nil,
        lastError: nil,
        platformPublishID: nil,
        createdAt: now,
        updatedAt: now
    )
}

private func removingTopLevelJSONKey(_ key: String, from data: Data) throws -> Data {
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object.removeValue(forKey: key)
    return try JSONSerialization.data(withJSONObject: object)
}

private func makeSlideshowDraft(
    id: UUID = UUID(),
    slides: [Slide]? = nil,
    creationModel: SlideshowCreationModelReference? = nil,
    imageVibe: SlideshowImageVibe = .defaultValue,
    now: Date = Date()
) -> SlideshowDraft {
    SlideshowDraft(
        id: id,
        title: "Launch Carousel",
        templateID: nil,
        creationModel: creationModel,
        imageVibe: imageVibe,
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
    storagePath: String? = nil,
    publicURL: URL? = nil,
    width: Int = 1024,
    height: Int = 1536,
    productIDs: [UUID] = [],
    now: Date = Date()
) -> MediaAsset {
    MediaAsset(
        id: id,
        mediaType: .image,
        source: source,
        localFilePath: localFilePath,
        storageBucket: "flick-media",
        storagePath: storagePath ?? "generated-slides/\(id.uuidString).png",
        publicURL: publicURL,
        signedURLExpiration: nil,
        width: width,
        height: height,
        duration: nil,
        fileSize: 1024,
        checksum: nil,
        trendTags: [],
        productIDs: productIDs,
        createdAt: now,
        updatedAt: now
    )
}

private func makeProduct(
    id: UUID = UUID(),
    name: String = "Flick Pro",
    summary: String = "Launch assets",
    now: Date = Date()
) -> FlickProduct {
    FlickProduct(
        id: id,
        name: name,
        summary: summary,
        createdAt: now,
        updatedAt: now
    )
}

private func makeCreationModel(
    id: UUID = UUID(),
    name: String = "Cottage Host",
    now: Date = Date()
) -> FlickCreationModel {
    var metadata = CreationModelMetadata()
    metadata.identity.gender = "Female"
    metadata.identity.ageRange = "41-50"
    metadata.ethnicity.ethnicity = "Samoan"
    metadata.skinDetails.clarity = "Clear"
    metadata.skinDetails.freckles = "Light Subtle"
    metadata.faceShape.shape = "Oval"
    metadata.faceDetails.jawline = "Sharp"
    metadata.hair.color = "Auburn"
    metadata.hair.style = "Bob"
    metadata.eyesAndBrows.color = "Green"
    metadata.body.build = "Athletic"
    metadata.styleAndAccessories.aesthetic = "Cottagecore"
    metadata.styleAndAccessories.glasses = "Prescription Square"

    return FlickCreationModel(
        id: id,
        name: name,
        metadata: metadata,
        createdAt: now,
        updatedAt: now
    )
}

private func makeConnectedAccount(
    id: UUID = UUID(),
    platformUserID: String = "open-id-123",
    displayName: String = "@flickcreator",
    now: Date = Date()
) -> ConnectedAccount {
    ConnectedAccount(
        id: id,
        platform: .tiktok,
        displayName: displayName,
        platformUserID: platformUserID,
        avatarURL: URL(string: "https://example.com/avatar.jpg"),
        scopes: ["user.info.basic", "video.publish"],
        status: .connected,
        authorizationSource: .loginKit,
        tokenStatus: .valid,
        isPublishingEnabled: true,
        defaultPrivacyLevel: TikTokPrivacyLevel.preferredDefault.rawValue,
        lastValidatedAt: now,
        createdAt: now,
        updatedAt: now
    )
}

private func makeYouTubeAccount(
    id: UUID = UUID(),
    platformUserID: String = "youtube-channel-id",
    displayName: String = "Flick Channel",
    now: Date = Date()
) -> ConnectedAccount {
    ConnectedAccount(
        id: id,
        platform: .youtubeShorts,
        displayName: displayName,
        platformUserID: platformUserID,
        avatarURL: URL(string: "https://example.com/youtube-avatar.jpg"),
        scopes: [YouTubeConfiguration.uploadScope, YouTubeConfiguration.readonlyScope],
        status: .connected,
        authorizationSource: .nativeOAuth,
        tokenStatus: .valid,
        isPublishingEnabled: true,
        defaultPrivacyLevel: YouTubePrivacyStatus.private.rawValue,
        lastValidatedAt: now,
        createdAt: now,
        updatedAt: now
    )
}

private func makeExampleSlideshowTemplate(
    id: String? = nil,
    slideCount: Int = 2,
    niche: String = "Productivity",
    nicheSlug: String? = nil,
    slides: [ExampleSlideshowSlide] = []
) -> ExampleSlideshowTemplate {
    let templateID = id ?? "template-\(slideCount)"
    let resolvedNicheSlug = nicheSlug ?? niche.lowercased().replacingOccurrences(of: " ", with: "-")

    return ExampleSlideshowTemplate(
        id: templateID,
        niche: niche,
        nicheSlug: resolvedNicheSlug,
        sourceURL: nil,
        postNumber: 1,
        profile: "flickapp",
        profileDisplayName: "Flick",
        folder: "\(niche)/\(templateID)",
        slideCount: slideCount,
        metrics: ExampleSlideshowMetrics(
            views: nil,
            likes: nil,
            bookmarks: nil,
            shares: nil
        ),
        product: ExampleSlideshowProduct(
            medium: "App",
            name: "Flick",
            linkInBio: nil
        ),
        creator: ExampleSlideshowCreator(
            followerCount: nil,
            signature: nil,
            avatarURL: nil,
            region: nil
        ),
        slides: slides
    )
}

private func makeExampleSlideshowSlide(index: Int, remoteURL: URL? = nil) -> ExampleSlideshowSlide {
    ExampleSlideshowSlide(
        id: "slide-\(index)",
        index: index,
        filename: "slide-\(index).jpg",
        relativePath: "template/slide-\(index).jpg",
        localURL: URL(fileURLWithPath: "/missing/template/slide-\(index).jpg"),
        sourceURL: URL(string: "https://example.com/source-slide-\(index).jpg"),
        remoteURL: remoteURL
    )
}

private func makeTemplateStyleGuide(
    styleName: String,
    productImageSlideNumbers: [Int] = []
) -> TemplateStyleGuide {
    TemplateStyleGuide(
        styleName: styleName,
        visualTraits: ["Clean layout"],
        colorPalette: ["Blue", "White"],
        lighting: "Soft",
        recurringMotifs: ["Phone frame"],
        reuseStructurally: ["Hook then proof"],
        avoidCopyingDirectly: ["Creator likeness"],
        imageGenerationRules: ["No readable text"],
        productImageSlideNumbers: productImageSlideNumbers
    )
}

private func makeCreativeTemplate(
    sourceTemplateID: String? = nil,
    sourceTemplateFingerprint: String? = nil,
    analysisSchemaVersion: Int? = nil,
    now: Date = Date(timeIntervalSince1970: 1_800_000_000)
) -> CreativeTemplate {
    CreativeTemplate(
        id: UUID(),
        name: "Cached Style",
        description: "Cached analysis",
        platform: .tiktok,
        slideCount: 2,
        styleJSON: makeTemplateStyleGuide(styleName: "Cached Style").encodedJSONString(),
        defaultTextRules: "No readable text.",
        sourceTemplateID: sourceTemplateID,
        sourceTemplateFingerprint: sourceTemplateFingerprint,
        analysisSchemaVersion: analysisSchemaVersion,
        tags: [],
        createdAt: now,
        updatedAt: now
    )
}

private func makeTemplateLibraryIndex() -> ExampleSlideshowLibraryIndex {
    ExampleSlideshowLibraryIndex(
        releaseID: "release-1",
        basePath: "template-library/releases/release-1",
        pageSize: 24,
        collections: [
            ExampleSlideshowCollectionSummary(
                folder: "Fitness",
                title: "Fitness",
                nicheSlug: "fitness",
                sourcePage: nil,
                slideshowCount: 24,
                totalSlideCount: 48,
                pageSize: 24,
                pageCount: 1
            ),
            ExampleSlideshowCollectionSummary(
                folder: "Wellness",
                title: "Wellness",
                nicheSlug: "wellness",
                sourcePage: nil,
                slideshowCount: 48,
                totalSlideCount: 96,
                pageSize: 24,
                pageCount: 2
            )
        ]
    )
}

private func makeTemplatePage(
    nicheID: String,
    pageNumber: Int,
    index: ExampleSlideshowLibraryIndex,
    templates: [ExampleSlideshowTemplate]
) -> ExampleSlideshowPage {
    let summary = index.collections.first { $0.id == nicheID } ?? index.collections[0]
    return ExampleSlideshowPage(
        collection: ExampleSlideshowCollection(
            folder: summary.folder,
            title: summary.title,
            nicheSlug: summary.nicheSlug,
            sourcePage: summary.sourcePage,
            slideshowCount: summary.slideshowCount,
            totalSlideCount: summary.totalSlideCount,
            templates: templates
        ),
        pageNumber: pageNumber,
        pageSize: summary.pageSize,
        pageCount: summary.pageCount
    )
}

private func makeTestAppConfiguration(values: [String: String] = [:]) -> AppConfiguration {
    let mergedValues = [
        "R2_ACCOUNT_ID": "account-id",
        "R2_ACCESS_KEY_ID": "access-key",
        "R2_SECRET_ACCESS_KEY": "secret-key",
        "R2_BUCKET": "flick-media",
        "R2_PUBLIC_BASE_URL": "https://media.example.com",
        "OPENAI_API_KEY": "test-key"
    ].merging(values) { _, new in new }

    return AppConfiguration(
        r2: R2StorageConfiguration(values: mergedValues),
        tiktok: TikTokConfiguration(values: mergedValues),
        youtube: YouTubeConfiguration(values: mergedValues),
        openAI: OpenAIConfiguration(values: mergedValues),
        meta: MetaConfiguration(values: mergedValues),
        storagePaths: R2StoragePaths(),
        renderDirectory: FileManager.default.temporaryDirectory,
        secureStoredCredentialKeys: Set(mergedValues.keys)
    )
}

private func makeOpenAIClientForTests() -> OpenAIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CapturingURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return OpenAIClient(
        credentials: ["OPENAI_API_KEY": "test-key"],
        urlSession: session
    )
}

private func makeAnalysisCacheRecordData(
    templateID: String,
    fingerprint: String,
    styleGuide: TemplateStyleGuide
) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "templateID": templateID,
        "fingerprint": fingerprint,
        "schemaVersion": TemplateAnalysisCacheService.schemaVersion,
        "model": "gpt-test",
        "createdAt": "2026-01-01T00:00:00Z",
        "styleGuide": [
            "styleName": styleGuide.styleName,
            "visualTraits": styleGuide.visualTraits,
            "colorPalette": styleGuide.colorPalette,
            "lighting": styleGuide.lighting,
            "recurringMotifs": styleGuide.recurringMotifs,
            "reuseStructurally": styleGuide.reuseStructurally,
            "avoidCopyingDirectly": styleGuide.avoidCopyingDirectly,
            "imageGenerationRules": styleGuide.imageGenerationRules,
            "productImageSlideNumbers": styleGuide.productImageSlideNumbers
        ]
    ])
}

private func managedObjectCount(entityName: String, in context: NSManagedObjectContext) throws -> Int {
    let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
    return try context.count(for: request)
}

private final class FakeMediaStorage: MediaStorageProviding {
    private(set) var uploadedPaths: [String] = []
    private(set) var uploadedContentTypes: [String] = []

    func uploadAsset(_ asset: LocalMediaAsset, path: String) async throws -> RemoteMediaAsset {
        uploadedPaths.append(path)
        uploadedContentTypes.append(asset.contentType)
        return RemoteMediaAsset(
            storageBucket: "flick-media",
            storagePath: path,
            publicURL: URL(string: "https://media.example.com/\(path)"),
            signedURLExpiration: nil
        )
    }

    func publicURL(path: String) throws -> URL {
        try XCTUnwrap(URL(string: "https://media.example.com/\(path)"))
    }

    func signedURL(path: String, expiresIn: TimeInterval) async throws -> URL {
        try XCTUnwrap(URL(string: "https://signed.example.com/\(path)?expires=\(Int(expiresIn))"))
    }
}

private final class FakeTemplateAnalysisStorage: TemplateAnalysisStorageProviding {
    struct Upload: Hashable {
        var path: String
        var data: Data
        var metadata: [String: String]
    }

    var cachedDataByPath: [String: Data] = [:]
    private(set) var uploads: [Upload] = []
    private let missingConfiguration: Bool

    init(missingConfiguration: Bool = false) {
        self.missingConfiguration = missingConfiguration
    }

    func uploadJSONIfAbsent(_ data: Data, path: String, metadata: [String: String]) async throws -> Bool {
        if missingConfiguration {
            throw MediaStorageError.missingR2Configuration
        }
        uploads.append(Upload(path: path, data: data, metadata: metadata))
        guard cachedDataByPath[path] == nil else { return false }
        cachedDataByPath[path] = data
        return true
    }

    func data(path: String) async throws -> Data {
        if missingConfiguration {
            throw MediaStorageError.missingR2Configuration
        }
        guard let data = cachedDataByPath[path] else {
            throw MediaStorageError.requestFailed(operation: "download", statusCode: 404, response: "")
        }
        return data
    }
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

    func saveMacRunnerHeartbeat(_ heartbeat: MacRunnerHeartbeat) async throws {
        state.macRunnerHeartbeat = heartbeat
    }

    func upsertConnectedAccount(_ account: ConnectedAccount) async throws {
        state.accounts.removeAll { $0.id == account.id }
        state.accounts.insert(account, at: 0)
        state.dashboard.connectedAccounts = state.accounts
    }

    func deleteConnectedAccount(id: UUID) async throws {
        state.accounts.removeAll { $0.id == id }
        state.dashboard.connectedAccounts = state.accounts
    }

    func upsertProduct(_ product: FlickProduct) async throws {
        state.products.removeAll { $0.id == product.id }
        state.products.insert(product, at: 0)
    }

    func upsertAsset(_ asset: MediaAsset) async throws {
        state.assets.removeAll { $0.id == asset.id }
        state.assets.insert(asset, at: 0)
    }

    func deleteAsset(id: UUID) async throws {
        state.assets.removeAll { $0.id == id }
    }
}

#if canImport(UIKit)
private func makeTestImage(width: Int, height: Int) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true

    let size = CGSize(width: CGFloat(width), height: CGFloat(height))
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
        UIColor.systemBlue.setFill()
        context.fill(CGRect(origin: .zero, size: size))
        UIColor.systemOrange.setFill()
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width) / 2, height: CGFloat(height)))
    }
}

private func makeTestJPEGData(width: Int, height: Int) -> Data {
    let image = makeTestImage(width: width, height: height)
    return image.jpegData(compressionQuality: 0.92) ?? Data()
}
#endif

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

private extension URLRequest {
    var httpBodyStringForTests: String? {
        if let httpBody {
            return String(data: httpBody, encoding: .utf8)
        }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            if bytesRead > 0 {
                data.append(buffer, count: bytesRead)
            } else {
                break
            }
        }

        return String(data: data, encoding: .utf8)
    }
}

private final class LoginKitSuccessMetadataURLProtocol: URLProtocol {
    static var capturedPath: String?
    static var capturedFields: String?
    static var capturedAuthorizationHeader: String?

    static func reset() {
        capturedPath = nil
        capturedFields = nil
        capturedAuthorizationHeader = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.capturedPath = request.url?.path.removingTrailingSlash
        Self.capturedFields = request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)?
                .queryItems?
                .value(named: "fields")
        }
        Self.capturedAuthorizationHeader = request.value(forHTTPHeaderField: "Authorization")

        let data = Data(
            """
            {
                "data": {
                    "user": {
                        "open_id": "real-open-id",
                        "avatar_url": "https://example.com/avatar.jpg",
                        "display_name": "Creator Name"
                    }
                },
                "error": {
                    "code": "ok",
                    "message": "",
                    "log_id": "log-123"
                }
            }
            """.utf8
        )
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class LoginKitFailureMetadataURLProtocol: URLProtocol {
    static var capturedPath: String?

    static func reset() {
        capturedPath = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.capturedPath = request.url?.path.removingTrailingSlash
        let data = Data(
            """
            {
                "error": {
                    "code": "scope_not_authorized",
                    "message": "The access token is missing a required user info scope.",
                    "log_id": "metadata-log-123"
                }
            }
            """.utf8
        )
        let response = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
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
