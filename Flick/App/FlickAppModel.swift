//
//  FlickAppModel.swift
//  Flick
//

import Foundation
import CoreData
import Observation
import OSLog
import UniformTypeIdentifiers

enum MoveDirection {
    case earlier
    case later
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
    var manualPublishProgress: ManualPublishProgress?

    @ObservationIgnored private let repository: FlickRepository
    @ObservationIgnored private let credentialVault = CredentialVault()
    @ObservationIgnored private let loginKitAccountStore = LoginKitAccountStore()
    @ObservationIgnored private let tiktokLoginKitClient = TikTokLoginKitClient()
    @ObservationIgnored private let localMediaLibrary = LocalMediaLibrary(directoryName: "ProductMedia")
    @ObservationIgnored private let generatedImageLibrary = LocalMediaLibrary(directoryName: "GeneratedImages")
    @ObservationIgnored private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.orion.Flick", category: "Publishing")

    init(repository: FlickRepository, configuration: AppConfiguration) {
        self.repository = repository
        self.configuration = configuration
        self.overview = FlickEmptyState.make()
        applyAuthorizedAccounts()
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

    var createDrafts: [SlideshowDraft] {
        overview.drafts.filter(\.isAvailableInCreateDrafts)
    }

    var activeCreateDraft: SlideshowDraft? {
        guard let activeCreateDraftID else { return nil }
        return createDrafts.first { $0.id == activeCreateDraftID }
    }

    func refresh() async {
        do {
            overview = try await repository.loadOverview()
            configuration = .current
            applyAuthorizedAccounts()
            applyCredentialHealth()
            clearActiveCreateDraftIfUnavailable()
            if reconcileCompletedSlideImages() {
                try await repository.saveOverview(overview)
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
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

    func toggleAutomationPaused() {
        overview.workspace.automationPaused.toggle()
        overview.dashboard.workerStatus.automationPaused = overview.workspace.automationPaused
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
                applyAuthorizedAccounts()
                accountConnectionMessage = "Connected \(account.displayName)."
            case .instagram, .threads, .x:
                throw PlatformAdapterError.futurePlatform(platform)
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func duplicateDraft(_ draft: SlideshowDraft) {
        var copy = draft
        copy.id = UUID()
        copy.title = "\(draft.title) remix"
        copy.status = .draft
        copy.createdAt = Date()
        copy.updatedAt = Date()
        overview.drafts.insert(copy, at: 0)
        activeCreateDraftID = copy.id
        selectedSection = .create
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
            campaignID: overview.campaigns.first?.id,
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

    func addProductMedia(data: Data, contentType: UTType) async throws {
        let storedMedia = try localMediaLibrary.store(data: data, contentType: contentType)
        try await addProductMedia(storedMedia)
    }

    func addProductMedia(fileURL: URL, contentType: UTType) async throws {
        let storedMedia = try localMediaLibrary.store(fileURL: fileURL, contentType: contentType)
        try await addProductMedia(storedMedia)
    }

    private func addProductMedia(_ storedMedia: StoredLocalMedia) async throws {
        let now = Date()
        let asset = MediaAsset(
            id: UUID(),
            mediaType: AssetMediaType(contentType: storedMedia.contentType),
            source: .uploaded,
            localFilePath: storedMedia.fileURL.path,
            storageBucket: nil,
            storagePath: nil,
            publicURL: nil,
            signedURLExpiration: nil,
            width: 0,
            height: 0,
            duration: nil,
            fileSize: storedMedia.fileSize,
            checksum: nil,
            trendTags: [],
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

    func persistCreateState() async {
        do {
            try await repository.saveOverview(overview)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func createAISlideshow(brief: String, from template: ExampleSlideshowTemplate) async {
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
            let openAIClient = OpenAIClient(credentials: credentialVault.loadValues())
            let styleGuide = try await TemplateAnalysisService(client: openAIClient).createStyleGuide(from: template)
            createWorkflowMessage = "Planning slideshow..."
            let plan = try await SlideshowPlannerService(client: openAIClient).createPlan(
                brief: planningBrief,
                template: template,
                styleGuide: styleGuide
            )

            guard plan.slides.count == template.slideCount else {
                throw SlideshowCreationError.planSlideCountMismatch(expected: template.slideCount, actual: plan.slides.count)
            }

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
                brief: planningBrief,
                templateID: creativeTemplate.id,
                now: now
            )

            overview.templates.insert(creativeTemplate, at: 0)
            overview.drafts.insert(draft, at: 0)
            activeCreateDraftID = draft.id
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
            let openAIClient = OpenAIClient(credentials: credentialVault.loadValues())
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

    func publishManualSlideshow(draftID: UUID, settings: TikTokManualPublishSettings) async {
        guard !isPublishingSlideshow else { return }
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
                draftID: draftID,
                scheduledAt: now,
                status: .rendering,
                publishMode: settings.publishMode,
                requiresApproval: false,
                approvedAt: now,
                approvedByDeviceID: overview.devices.first?.id,
                workerDeviceID: overview.devices.first?.id,
                workerLeaseExpiresAt: nil,
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
            let renderedAssetIDs = try await renderImageSequenceForPublish(for: draftID)

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

            let recordStepDetail = settings.postAsDraft
                ? "Saving the TikTok inbox upload status."
                : "Saving the final publish status."
            startPublishStep(ManualPublishProgressStepID.recordResult, detail: recordStepDetail)
            if settings.postAsDraft {
                completeDraftUploadJob(job.id, result: result)
            } else {
                completePublishingJob(job.id, result: result, draft: refreshedDraft)
            }
            try await repository.saveOverview(overview)
            let recordCompletionDetail = settings.postAsDraft
                ? "TikTok draft saved. Open TikTok's inbox notification to edit, save, or post."
                : "Publish status saved."
            completePublishStep(ManualPublishProgressStepID.recordResult, detail: recordCompletionDetail)
            finishManualPublishProgress()
            createWorkflowMessage = settings.postAsDraft ? "TikTok draft sent. Open TikTok's inbox notification to finish." : "Published to TikTok."
            lastErrorMessage = nil
            logPublish("Manual TikTok publish completed jobID=\(job.id.uuidString) publishID=\(result.platformPostID)")
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

    private func applyAuthorizedAccounts() {
        let authorizedAccounts = loginKitAccountStore.loadAccounts()
        overview.accounts = authorizedAccounts
        overview.dashboard.connectedAccounts = authorizedAccounts
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

enum SlideshowCreationError: LocalizedError {
    case missingDraft
    case missingStyleGuide
    case planSlideCountMismatch(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .missingDraft:
            "The slideshow draft could not be found."
        case .missingStyleGuide:
            "Create or repair the template style guide before generating images."
        case let .planSlideCountMismatch(expected, actual):
            "The slideshow plan returned \(actual) slides, but the selected template requires \(expected)."
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

private extension FlickAppModel {
    func makeDraft(
        from plan: PlannedSlideshow,
        brief: String,
        templateID: UUID,
        now: Date
    ) -> SlideshowDraft {
        let slides = plan.slides
            .sorted { $0.index < $1.index }
            .enumerated()
            .map { offset, plannedSlide in
                Slide(
                    id: UUID(),
                    index: offset,
                    imageAssetID: nil,
                    prompt: plannedSlide.imagePrompt,
                    text: plannedSlide.text,
                    textPosition: .center,
                    textStyle: SlideTextStyle(),
                    selectedVisualSummary: plannedSlide.selectedVisualSummary,
                    generationStatus: .notStarted,
                    generationErrorMessage: nil,
                    promptVersion: 1,
                    createdAt: now,
                    updatedAt: now
                )
            }

        return SlideshowDraft(
            id: UUID(),
            title: plan.title,
            campaignID: overview.campaigns.first?.id,
            templateID: templateID,
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
            status: .draft,
            exportedImageAssetIDs: [],
            createdAt: now,
            updatedAt: now
        )
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
            let openAIClient = OpenAIClient(credentials: credentialVault.loadValues())
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
                settings: settings
            )
            let storedMedia = try generatedImageLibrary.store(data: generatedImage.data, contentType: .png)
            let assetID = UUID()
            let path = generatedStoragePath(draftID: draftID, slide: slide, assetID: assetID, settings: settings)
            let remote = try await R2StorageService(credentials: credentialVault.loadValues())
                .uploadAsset(
                    LocalMediaAsset(
                        id: assetID,
                        data: generatedImage.data,
                        contentType: generatedImage.contentType,
                        fileExtension: generatedImage.fileExtension
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

    func renderImageSequenceForPublish(for draftID: UUID) async throws -> [UUID] {
        guard let draftIndex = overview.drafts.firstIndex(where: { $0.id == draftID }) else {
            throw SlideshowCreationError.missingDraft
        }

        startPublishStep(ManualPublishProgressStepID.renderImages, detail: "Rendering the current edited slides.")
        createWorkflowMessage = "Snapshotting edited slides..."
        let draft = overview.drafts[draftIndex]
        logPublish("Rendering publish image sequence draftID=\(draftID.uuidString) slideCount=\(draft.slides.count)")
        let renderedImages = try await TextOverlayRenderService(renderDirectory: configuration.renderDirectory)
            .renderImages(
                from: draft,
                assets: overview.assets,
                options: ImageRenderOptions(
                    width: SlideshowImageGenerationSettings.finalExport.width,
                    height: SlideshowImageGenerationSettings.finalExport.height
                )
            )
        completePublishStep(ManualPublishProgressStepID.renderImages, detail: "Snapshot \(renderedImages.count) edited slides.")

        createWorkflowMessage = "Uploading rendered images..."
        var renderedAssetIDs: [UUID] = []
        for renderedImage in renderedImages {
            let uploadStepID = ManualPublishProgressStepID.uploadSlide(renderedImage.slideID)
            startPublishStep(uploadStepID, detail: "Uploading rendered image to Cloudflare R2.")
            let data = try Data(contentsOf: renderedImage.fileURL)
            let assetID = UUID()
            let path = renderedStoragePath(draftID: draftID, slideID: renderedImage.slideID, assetID: assetID)
            let remote = try await R2StorageService(credentials: credentialVault.loadValues())
                .uploadAsset(
                    LocalMediaAsset(id: assetID, data: data, contentType: "image/png", fileExtension: "png"),
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
                platformPostID: result.platformPostID,
                platformURL: result.platformURL,
                publishedAt: result.publishedAt,
                draftID: draft.id,
                campaignID: draft.campaignID,
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
        overview.publishingJobs[jobIndex].status = .awaitingUserCompletion
        overview.publishingJobs[jobIndex].platformPublishID = result.platformPostID
        overview.publishingJobs[jobIndex].lastError = nil
        overview.publishingJobs[jobIndex].updatedAt = Date()
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

        if slideHasAvailableGeneratedImage(slide, assetsByID: assetsByID) {
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
                let hasGeneratedImage = slideHasAvailableGeneratedImage(slide, assetsByID: assetsByID)

                if hasGeneratedImage {
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

    func slideHasAvailableGeneratedImage(_ slide: Slide, assetsByID: [UUID: MediaAsset]) -> Bool {
        guard
            let assetID = slide.imageAssetID,
            let asset = assetsByID[assetID],
            asset.source == .generated
        else {
            return false
        }

        return asset.hasAvailableMediaLocation
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
        settings: SlideshowImageGenerationSettings
    ) -> String {
        "\(configuration.storagePaths.generatedImages)/\(draftID.uuidString)/slide-\(String(format: "%02d", slide.index + 1))-v\(slide.promptVersion)-\(settings.width)x\(settings.height)-\(assetID.uuidString).png"
    }

    func renderedStoragePath(draftID: UUID, slideID: UUID, assetID: UUID) -> String {
        "\(configuration.storagePaths.renderedImages)/\(draftID.uuidString)/\(slideID.uuidString)-\(assetID.uuidString).png"
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
