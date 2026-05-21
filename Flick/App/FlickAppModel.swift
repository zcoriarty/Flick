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
    var isR2SmokeTestRunning = false
    var r2SmokeTestResult: R2StorageSmokeTestResult?
    var r2SmokeTestErrorMessage: String?
    var activeCreateDraftID: UUID?
    var createWorkflowMessage: String?
    var isPlanningSlideshow = false
    var isGeneratingSlideshowImages = false
    var isPublishingSlideshow = false
    var isProcessingAutomations = false
    var manualPublishProgress: ManualPublishProgress?

    @ObservationIgnored private let repository: FlickRepository
    @ObservationIgnored private let credentialVault = CredentialVault()
    @ObservationIgnored private let loginKitAccountStore = LoginKitAccountStore()
    @ObservationIgnored private let tiktokLoginKitClient = TikTokLoginKitClient()
    @ObservationIgnored private let localMediaLibrary = LocalMediaLibrary(directoryName: "ProductMedia")
    @ObservationIgnored private let generatedImageLibrary = LocalMediaLibrary(directoryName: "GeneratedImages")
    @ObservationIgnored private let openAIClientFactory: @MainActor ([String: String]) -> OpenAIClient
    @ObservationIgnored private let mediaStorageFactory: @MainActor ([String: String]) -> any MediaStorageProviding
    @ObservationIgnored private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.orion.Flick", category: "Publishing")
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var isRefreshPending = false

    init(
        repository: FlickRepository,
        configuration: AppConfiguration,
        openAIClientFactory: @escaping @MainActor ([String: String]) -> OpenAIClient = { OpenAIClient(credentials: $0) },
        mediaStorageFactory: @escaping @MainActor ([String: String]) -> any MediaStorageProviding = { R2StorageService(credentials: $0) }
    ) {
        self.repository = repository
        self.configuration = configuration
        self.openAIClientFactory = openAIClientFactory
        self.mediaStorageFactory = mediaStorageFactory
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
            applyConnectedAccounts()
            applyCredentialHealth()
            overview.refreshDerivedState()
            let didUpdateTikTokStatuses = await refreshTikTokPublishStatuses()
            let didReconcilePublishedPosts = reconcilePublishedPostsFromCompletedJobs()
            clearActiveCreateDraftIfUnavailable()
            let didPruneProgresses = pruneAutomationPostProgresses()
            if reconcileCompletedSlideImages() || didUpdateTikTokStatuses || didReconcilePublishedPosts || didPruneProgresses {
                overview.refreshDerivedState()
                try await repository.saveOverview(overview)
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
            case .instagram, .threads, .x:
                throw PlatformAdapterError.futurePlatform(platform)
            }
        } catch {
            lastErrorMessage = error.localizedDescription
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
                localFilePath: slide.localURL.path,
                storageBucket: nil,
                storagePath: nil,
                publicURL: nil,
                signedURLExpiration: nil,
                width: 0,
                height: 0,
                duration: nil,
                fileSize: fileSize(at: slide.localURL),
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
            targetPlatforms: [.tiktok],
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
        overview.products.removeAll { $0.id == productID }
        overview.assets = overview.assets.compactMap { asset in
            guard asset.productIDs.contains(productID) else { return asset }

            let retainedProductIDs = asset.productIDs.filter { $0 != productID }
            guard !retainedProductIDs.isEmpty else { return nil }

            var updatedAsset = asset
            updatedAsset.productIDs = retainedProductIDs
            updatedAsset.updatedAt = Date()
            return updatedAsset
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

        let previousAsset = overview.assets[assetIndex]
        overview.assets[assetIndex].productIDs = resolvedProductIDs
        overview.assets[assetIndex].updatedAt = Date()

        do {
            try await repository.upsertAsset(overview.assets[assetIndex])
            lastErrorMessage = nil
        } catch {
            overview.assets[assetIndex] = previousAsset
            throw error
        }
    }

    func removeProductMedia(_ asset: MediaAsset) async throws {
        guard let index = overview.assets.firstIndex(where: { $0.id == asset.id }) else { return }
        let removedAsset = overview.assets.remove(at: index)

        do {
            try await repository.deleteAsset(id: asset.id)
            lastErrorMessage = nil
        } catch {
            overview.assets.insert(removedAsset, at: min(index, overview.assets.count))
            throw error
        }
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
        if let existingIndex = overview.automations.firstIndex(where: { $0.id == automation.id }) {
            automation.createdAt = overview.automations[existingIndex].createdAt
            overview.automations[existingIndex] = automation
        } else {
            overview.automations.insert(automation, at: 0)
        }
        overview.refreshDerivedState()

        do {
            try await repository.saveOverview(overview)
            createWorkflowMessage = "Automation started."
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
        productImage: SlideshowProductImage? = nil
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
                productImage: productImage
            )
            overview.templates.insert(result.creativeTemplate, at: 0)
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
                instruction: normalizedInstruction
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

    func generateMissingSlideImages(for draftID: UUID) async {
        await generateSlideImages(for: draftID, replacingExisting: false)
    }

    func regenerateSlideImages(for draftID: UUID) async {
        await generateSlideImages(for: draftID, replacingExisting: true)
    }

    private func generateSlideImages(for draftID: UUID, replacingExisting: Bool) async {
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

            for slideID in slideIDs {
                try await generateImage(for: slideID, in: draftID, instruction: nil, settings: .draft)
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
            guard let account = publishingTikTokAccount() else {
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
            if settings.postAsDraft {
                completeDraftUploadJob(job.id, result: result)
            } else {
                completePublishingJob(job.id, result: result, draft: refreshedDraft)
            }
            overview.refreshDerivedState()
            try await repository.saveOverview(overview)
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

    private func sortedConnectedAccounts(_ accounts: [ConnectedAccount]) -> [ConnectedAccount] {
        accounts.sorted {
            if $0.platform.rawValue == $1.platform.rawValue {
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            return $0.platform.displayName < $1.platform.displayName
        }
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
    var draft: SlideshowDraft
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
            "The slideshow plan must place the selected product image on exactly one slide."
        }
    }
}

enum ManualPublishError: LocalizedError {
    case missingTikTokAccount
    case missingPublishableImageURLs

    var errorDescription: String? {
        switch self {
        case .missingTikTokAccount:
            "Connect a TikTok account with publishing access before publishing."
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
            return "Complete the automation templates, product images, cadence, and TikTok settings before it can publish."
        case .missingTemplate:
            return "One of the automation templates is no longer available."
        case let .missingProductImage(message):
            return message.isEmpty ? "One of the automation product images is no longer available." : message
        case let .generationFailed(message):
            return message.isEmpty ? "Automated slide image generation failed." : message
        case let .publishFailed(message):
            return message.isEmpty ? "Automated publishing failed." : message
        }
    }
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
            scheduledAt: scheduledAt
        )
        overview.automationPostProgresses.insert(progress, at: 0)
        await persistAutomationPostProgresses()
        return progress.id
    }

    func startAutomationPostProgressStep(
        _ progressID: UUID?,
        _ stepID: String,
        detail: String
    ) async {
        await updateAutomationPostProgressStep(progressID, stepID, state: .current, detail: detail)
    }

    func completeAutomationPostProgressStep(
        _ progressID: UUID?,
        _ stepID: String,
        detail: String
    ) async {
        await updateAutomationPostProgressStep(progressID, stepID, state: .completed, detail: detail)
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
        detail: String
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
        productImage: SlideshowProductImage?
    ) async throws -> AISlideshowCreationResult {
        let openAIClient = makeOpenAIClient()
        let styleGuide = try await TemplateAnalysisService(client: openAIClient).createStyleGuide(from: template)
        createWorkflowMessage = "Planning slideshow..."
        let plan = try await SlideshowPlannerService(client: openAIClient).createPlan(
            brief: brief,
            template: template,
            styleGuide: styleGuide,
            creationModel: creationModel,
            productImage: productImage
        )

        let expectedSlideCount = expectedPlanSlideCount(template: template, productImage: productImage)
        guard plan.slides.count == expectedSlideCount else {
            throw SlideshowCreationError.planSlideCountMismatch(expected: expectedSlideCount, actual: plan.slides.count)
        }
        try validateProductImagePlacement(in: plan, productImage: productImage)

        let now = Date()
        let creativeTemplate = CreativeTemplate(
            id: UUID(),
            name: "\(styleGuide.styleName.isEmpty ? template.niche : styleGuide.styleName) - @\(template.profile)",
            description: "AI style guide from @\(template.profile)'s \(template.niche.lowercased()) template.",
            platform: .tiktok,
            slideCount: template.slideCount,
            styleJSON: styleGuide.encodedJSONString(),
            defaultTextRules: "Generated backgrounds must contain no readable text. Flick renders all text overlays.",
            tags: [],
            createdAt: now,
            updatedAt: now
        )

        let draft = makeDraft(
            from: plan,
            brief: brief,
            templateID: creativeTemplate.id,
            creationModel: creationModel,
            productImage: productImage,
            now: now
        )

        return AISlideshowCreationResult(creativeTemplate: creativeTemplate, draft: draft)
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

            guard publishingTikTokAccount() != nil else {
                throw ManualPublishError.missingTikTokAccount
            }

            await startAutomationPostProgressStep(
                progressID,
                AutomationPostProgressStepID.selectTemplate,
                detail: "Choosing a template and product image for this run."
            )
            let template = try automationTemplate(for: automation, scheduledAt: scheduledAt)
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
                    productImage: productImage
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

            overview.templates.insert(result.creativeTemplate, at: 0)
            overview.drafts.insert(result.draft, at: 0)
            await updateAutomationPostProgress(
                progressID,
                draftID: result.draft.id,
                title: result.draft.title
            )
            try await repository.saveOverview(overview)

            await startAutomationPostProgressStep(
                progressID,
                AutomationPostProgressStepID.generateImages,
                detail: "Generating \(result.draft.slides.count) slide visuals."
            )
            await generateMissingSlideImages(for: result.draft.id)
            guard let generatedDraft = overview.drafts.first(where: { $0.id == result.draft.id }) else {
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

            let tikTokSettings = automation.tikTokSettings.fillingTitle(from: generatedDraft.tikTokSettings)
            guard let settings = tikTokSettings.automatedPublishSettings(description: generatedDraft.publishDescription) else {
                throw AutomationRunError.notReady
            }

            let didPublish = await publishManualSlideshow(
                draftID: generatedDraft.id,
                settings: settings,
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
    ) throws -> ExampleSlideshowTemplate {
        let templates = try ExampleSlideshowLibrary.load()
            .flatMap(\.templates)
            .filter(\.hasDisplayablePreview)
        let templatesByID = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0) })
        let selectedTemplates = automation.templateIDs.compactMap { templatesByID[$0] }
        guard !selectedTemplates.isEmpty else {
            throw AutomationRunError.missingTemplate
        }

        let index = deterministicIndex(
            seed: "\(automation.id.uuidString)-template-\(scheduledAt.timeIntervalSince1970)",
            count: selectedTemplates.count
        )
        return selectedTemplates[index]
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
        productImage: SlideshowProductImage?
    ) -> Int {
        template.slideCount + (productImage == nil ? 0 : 1)
    }

    func makeDraft(
        from plan: PlannedSlideshow,
        brief: String,
        templateID: UUID,
        creationModel: SlideshowCreationModelReference?,
        productImage: SlideshowProductImage?,
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
            targetPlatforms: [.tiktok, .instagram],
            tikTokSettings: defaultTikTokSettings(from: plan),
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
        productImage: SlideshowProductImage?
    ) throws {
        guard productImage != nil else { return }
        let placementCount = plan.slides.filter(\.usesProductImage).count
        guard placementCount == 1 else {
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
        settings: SlideshowImageGenerationSettings
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
            let openAIClient = makeOpenAIClient()
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
                    instruction: instruction
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
                    previousVisualSummary: previousSummary
                )
            }

            let generatedImage = try await ImageGenerationService(client: openAIClient).generateSlideImage(
                prompt: slide.prompt,
                settings: settings,
                creationModel: draft.creationModel
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
            let remote = try await R2StorageService(credentials: credentialVault.loadValues())
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
            let remote = try await R2StorageService(credentials: credentialVault.loadValues())
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

    func publishingTikTokAccount() -> ConnectedAccount? {
        overview.accounts.first { account in
            account.platform == .tiktok
                && account.authorizationSource == .loginKit
                && account.status == .connected
                && account.isPublishingEnabled
        }
    }

    func refreshTikTokPublishStatuses() async -> Bool {
        let awaitingJobs = overview.publishingJobs.filter { job in
            job.platform == .tiktok
                && job.status == .awaitingUserCompletion
                && job.platformPublishID != nil
        }
        guard !awaitingJobs.isEmpty else { return false }

        let accountsByID = Dictionary(uniqueKeysWithValues: overview.accounts.map { ($0.id, $0) })
        let adapter = TikTokAdapter(configuration: configuration.tiktok)
        var didChange = false

        for job in awaitingJobs {
            guard
                let publishID = job.platformPublishID,
                let account = accountsByID[job.accountID]
            else {
                continue
            }

            do {
                let status = try await adapter.fetchPublishStatus(
                    publishID: publishID,
                    account: account
                )
                didChange = applyTikTokPublishStatus(status, to: job.id) || didChange
            } catch {
                logger.error("TikTok publish status refresh failed jobID=\(job.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            }
        }

        return didChange
    }

    func refreshAndPersistTikTokPublishStatuses() async {
        let didUpdateTikTokStatuses = await refreshTikTokPublishStatuses()
        let didReconcilePublishedPosts = reconcilePublishedPostsFromCompletedJobs()
        guard didUpdateTikTokStatuses || didReconcilePublishedPosts else { return }

        do {
            overview.refreshDerivedState()
            try await repository.saveOverview(overview)
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
        overview.publishedPosts.contains { post in
            post.platform == .tiktok
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
        switch kind {
        case .authExpired:
            "Reconnect the TikTok account and try again."
        case .missingScope:
            "Reconnect TikTok with the required publishing scope."
        case .rateLimit:
            "Wait for the TikTok rate limit window to reset."
        case .mediaURLInaccessible:
            "Verify the rendered image URLs are publicly reachable."
        case .urlOwnershipUnverified:
            "Verify the Cloudflare R2 custom domain or TikTok media URL prefix."
        case .invalidPrivacySetting:
            "Refresh TikTok creator info and choose a supported visibility option."
        case .unauditedClient:
            "Use private visibility while the TikTok client is unaudited, or complete app audit."
        case .platformProcessingFailed:
            "Check the TikTok account and app status, then retry."
        case .unknownServerError:
            "Check the platform response and retry after the service recovers."
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
