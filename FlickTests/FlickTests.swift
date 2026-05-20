//
//  FlickTests.swift
//  FlickTests
//

import CoreData
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
        let slide = makeSlide(imageAssetID: asset.id, generationStatus: .complete, now: now)
        let draft = makeSlideshowDraft(slides: [slide], now: now)
        var state = FlickEmptyState.make()
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

    func testAddingProductMediaRequiresAndStoresProductSelection() async throws {
        let repository = InMemoryFlickRepository(state: FlickEmptyState.make())
        let mediaStorage = FakeMediaStorage()
        let model = FlickAppModel(
            repository: repository,
            configuration: .current,
            mediaStorageFactory: { _ in mediaStorage }
        )
        let product = try await model.createProduct(name: "Flick Pro", summary: "Launch assets")

        try await model.addProductMedia(
            data: Data([0xFF, 0xD8, 0xFF]),
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
        XCTAssertEqual(repository.state.assets.first?.productIDs, [product.id])
        XCTAssertEqual(repository.state.assets.first?.publicURL, asset.publicURL)
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
        draft.tikTokSettings = tikTokSettings
        draft.selectedSongs = selectedSongs
        var state = FlickEmptyState.make()
        state.drafts = [draft]

        try await repository.saveOverview(state)
        let loaded = try await repository.loadOverview()
        let loadedDraft = try XCTUnwrap(loaded.drafts.first)

        XCTAssertEqual(loadedDraft.tikTokSettings, tikTokSettings)
        XCTAssertEqual(loadedDraft.selectedSongs, selectedSongs)
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

    func testCoreDataRoundTripsAutomations() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let persistenceController = PersistenceController(inMemory: true)
        let repository = CoreDataFlickRepository(
            context: persistenceController.container.viewContext,
            cloudAvailability: { false }
        )
        let product = makeProduct(now: now)
        let productImageID = UUID()
        let nextScheduledAt = Date(timeInterval: 3_600, since: now)
        let automation = ContentAutomation(
            name: "Weekday launches",
            templateIDs: ["template-a", "template-b"],
            productID: product.id,
            productImageAssetIDs: [productImageID],
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
            nextScheduledAt: nextScheduledAt,
            createdAt: now,
            updatedAt: now
        )
        var state = FlickEmptyState.make()
        state.products = [product]
        state.automations = [automation]

        try await repository.saveOverview(state)
        let loaded = try await repository.loadOverview()
        let loadedAutomation = try XCTUnwrap(loaded.automations.first)

        XCTAssertEqual(loadedAutomation, automation)
        XCTAssertEqual(loaded.dashboard.activeAutomationCount, 1)
        XCTAssertEqual(loaded.dashboard.nextAutomationPostAt, nextScheduledAt)
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
        XCTAssertThrowsError(try vault.storeValue("", for: "OPENAI_API_KEY"))
        XCTAssertEqual(String(data: try XCTUnwrap(store.data(for: "TIKTOK_CLIENT_ID")), encoding: .utf8), "client-id")
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

    func testTikTokPhotoPostRenderOptionsUseSupportedFormat() {
        let options = ImageRenderOptions.tikTokPhotoPost

        XCTAssertEqual(options.width, 720)
        XCTAssertEqual(options.height, 1080)
        XCTAssertEqual(options.jpegQuality, 0.92)
        XCTAssertEqual(options.contentType, "image/jpeg")
        XCTAssertEqual(options.fileExtension, "jpg")
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
        let renderedImages = try await TextOverlayRenderService(renderDirectory: directory)
            .renderImages(from: draft, assets: [asset], options: .tikTokPhotoPost)
        let renderedImage = try XCTUnwrap(renderedImages.first)
        let renderedData = try Data(contentsOf: renderedImage.fileURL)

        XCTAssertEqual(renderedImage.contentType, "image/jpeg")
        XCTAssertEqual(renderedImage.fileURL.pathExtension, "jpg")
        XCTAssertEqual(Array(renderedData.prefix(3)), [0xFF, 0xD8, 0xFF])
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
    }

    func testPlannerRequestsExtraSlideForSelectedProductImage() async throws {
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
            planSummary: "Two template slides plus one product image slide.",
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

            XCTAssertTrue(promptText.contains("Template slide count to keep: 2"))
            XCTAssertTrue(promptText.contains("Total planned slide count to return: 3"))
            XCTAssertTrue(promptText.contains("TikTok post title"))
            XCTAssertTrue(promptText.contains("Keep exactly 2 non-product generated/template slides, plus this one product-image slide."))
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
            productImage: productImage
        )

        XCTAssertEqual(plan.slides.count, 3)
        XCTAssertEqual(plan.slides.filter(\.usesProductImage).count, 1)
        XCTAssertEqual(plan.tikTokTitle, "Launch Flick Pro")
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
            openAIClientFactory: { _ in client }
        )

        await model.createAISlideshow(
            brief: "",
            from: makeExampleSlideshowTemplate(slideCount: 2)
        )

        let draft = try XCTUnwrap(model.activeCreateDraft)
        XCTAssertEqual(draft.tikTokSettings?.title, "Launch Flick Pro")
        XCTAssertEqual(repository.state.drafts.first?.tikTokSettings?.title, "Launch Flick Pro")
    }

    func testOpenAIImageGenerationRequestsJpegOutput() async throws {
        let imageBytes = Data([0xFF, 0xD8, 0xFF])
        CapturingURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/images/generations")
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

private func makeSlideshowDraft(
    id: UUID = UUID(),
    slides: [Slide]? = nil,
    now: Date = Date()
) -> SlideshowDraft {
    SlideshowDraft(
        id: id,
        title: "Launch Carousel",
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
    productIDs: [UUID] = [],
    now: Date = Date()
) -> MediaAsset {
    MediaAsset(
        id: id,
        mediaType: .image,
        source: source,
        localFilePath: localFilePath,
        storageBucket: "flick-media",
        storagePath: "generated-slides/\(id.uuidString).png",
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

private func makeExampleSlideshowTemplate(slideCount: Int = 2) -> ExampleSlideshowTemplate {
    ExampleSlideshowTemplate(
        id: "template-\(slideCount)",
        niche: "Productivity",
        nicheSlug: "productivity",
        sourceURL: nil,
        postNumber: 1,
        profile: "flickapp",
        profileDisplayName: "Flick",
        folder: "Productivity/template-\(slideCount)",
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
        slides: []
    )
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
