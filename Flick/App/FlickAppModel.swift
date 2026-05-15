//
//  FlickAppModel.swift
//  Flick
//

import Foundation
import CoreData
import Observation
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
    var isSupabaseSmokeTestRunning = false
    var supabaseSmokeTestResult: SupabaseStorageSmokeTestResult?
    var supabaseSmokeTestErrorMessage: String?
    var activeCreateDraftID: UUID?
    var createWorkflowMessage: String?
    var isPlanningSlideshow = false
    var isGeneratingSlideshowImages = false
    var isExportingSlideshow = false

    @ObservationIgnored private let repository: FlickRepository
    @ObservationIgnored private let credentialVault = CredentialVault()
    @ObservationIgnored private let loginKitAccountStore = LoginKitAccountStore()
    @ObservationIgnored private let tiktokLoginKitClient = TikTokLoginKitClient()
    @ObservationIgnored private let localMediaLibrary = LocalMediaLibrary(directoryName: "ProductMedia")
    @ObservationIgnored private let generatedImageLibrary = LocalMediaLibrary(directoryName: "GeneratedImages")

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

    private func clearActiveCreateDraftIfUnavailable() {
        guard activeCreateDraftID != nil, activeCreateDraft == nil else { return }
        activeCreateDraftID = nil
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
                    guard let imageAssetID = slide.imageAssetID else { return true }
                    return assetsByID[imageAssetID]?.hasAvailableMediaLocation != true
                }
                .map(\.id)

            for slideID in slideIDs {
                try await generateImage(for: slideID, in: draftID, instruction: nil, settings: .draft)
            }

            createWorkflowMessage = slideIDs.isEmpty ? "All slides already have generated images." : "Generated \(slideIDs.count) slide images."
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

    func exportImageSequence(for draftID: UUID) async {
        guard !isExportingSlideshow else { return }
        isExportingSlideshow = true
        createWorkflowMessage = "Preparing high-resolution slide images..."
        lastErrorMessage = nil

        defer {
            isExportingSlideshow = false
        }

        do {
            try await ensureFinalGeneratedImages(for: draftID)

            guard let draftIndex = overview.drafts.firstIndex(where: { $0.id == draftID }) else {
                throw SlideshowCreationError.missingDraft
            }

            createWorkflowMessage = "Rendering Flick text overlays..."
            let draft = overview.drafts[draftIndex]
            let renderedImages = try await TextOverlayRenderService(renderDirectory: configuration.renderDirectory)
                .renderImages(
                    from: draft,
                    assets: overview.assets,
                    options: ImageRenderOptions(width: SlideshowImageGenerationSettings.finalExport.width, height: SlideshowImageGenerationSettings.finalExport.height)
                )

            var renderedAssetIDs: [UUID] = []
            for renderedImage in renderedImages {
                let data = try Data(contentsOf: renderedImage.fileURL)
                let assetID = UUID()
                let path = renderedStoragePath(draftID: draftID, slideID: renderedImage.slideID, assetID: assetID)
                let remote = try await SupabaseStorageService(credentials: credentialVault.loadValues())
                    .uploadAsset(
                        LocalMediaAsset(id: assetID, data: data, contentType: "image/png", fileExtension: "png"),
                        bucket: configuration.storageBuckets.renderedVideos,
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
            }

            if let refreshedDraftIndex = overview.drafts.firstIndex(where: { $0.id == draftID }) {
                overview.drafts[refreshedDraftIndex].exportedImageAssetIDs = renderedAssetIDs
                overview.drafts[refreshedDraftIndex].updatedAt = Date()
            }

            try await repository.saveOverview(overview)
            createWorkflowMessage = "Exported \(renderedAssetIDs.count) rendered images."
            lastErrorMessage = nil
        } catch {
            createWorkflowMessage = nil
            lastErrorMessage = error.localizedDescription
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

    func runSupabaseSmokeTest() async {
        guard !isSupabaseSmokeTestRunning else { return }
        reloadCredentialConfiguration()
        isSupabaseSmokeTestRunning = true
        supabaseSmokeTestResult = nil
        supabaseSmokeTestErrorMessage = nil
        credentialMessage = "Testing Supabase Storage..."
        lastErrorMessage = nil

        defer {
            isSupabaseSmokeTestRunning = false
        }

        do {
            let result = try await SupabaseStorageService().runSmokeTest(
                bucket: configuration.storageBuckets.generatedImages,
                requiredBuckets: configuration.storageBuckets.all
            )
            supabaseSmokeTestResult = result
            supabaseSmokeTestErrorMessage = nil
            credentialMessage = result.summary
            lastErrorMessage = nil
        } catch {
            let message = error.localizedDescription
            supabaseSmokeTestErrorMessage = message
            credentialMessage = "Supabase smoke test failed."
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
                serviceName: "Supabase Storage",
                isConfigured: configuration.supabase.url != nil && configuration.supabase.apiKeyPresent,
                statusText: supabaseStatusText(),
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

    private func supabaseStatusText() -> String {
        if configuration.supabase.serviceRoleKeyPresent {
            return "Service role key found locally"
        }
        if configuration.supabase.publishableKeyPresent {
            return "Publishable key found locally"
        }
        if configuration.supabase.anonKeyPresent {
            return "Anon key found locally"
        }
        return "Supabase project credentials expected"
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
            let remote = try await SupabaseStorageService(credentials: credentialVault.loadValues())
                .uploadAsset(
                    LocalMediaAsset(
                        id: assetID,
                        data: generatedImage.data,
                        contentType: generatedImage.contentType,
                        fileExtension: generatedImage.fileExtension
                    ),
                    bucket: configuration.storageBuckets.generatedImages,
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

    func ensureFinalGeneratedImages(for draftID: UUID) async throws {
        guard let draftIndex = overview.drafts.firstIndex(where: { $0.id == draftID }) else {
            throw SlideshowCreationError.missingDraft
        }

        let assetsByID = Dictionary(uniqueKeysWithValues: overview.assets.map { ($0.id, $0) })
        let slideIDsNeedingFinal = overview.drafts[draftIndex].slides
            .filter { slide in
                guard let assetID = slide.imageAssetID, let asset = assetsByID[assetID] else {
                    return true
                }
                guard asset.hasAvailableMediaLocation else {
                    return true
                }
                return asset.width < SlideshowImageGenerationSettings.finalExport.width || asset.height < SlideshowImageGenerationSettings.finalExport.height
            }
            .map(\.id)

        for slideID in slideIDsNeedingFinal {
            try await generateImage(for: slideID, in: draftID, instruction: nil, settings: .finalExport)
        }
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
        "generated-slides/\(draftID.uuidString)/slide-\(String(format: "%02d", slide.index + 1))-v\(slide.promptVersion)-\(settings.width)x\(settings.height)-\(assetID.uuidString).png"
    }

    func renderedStoragePath(draftID: UUID, slideID: UUID, assetID: UUID) -> String {
        "rendered-image-sequences/\(draftID.uuidString)/\(slideID.uuidString)-\(assetID.uuidString).png"
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
        Preserve the template's pacing, composition rhythm, safe-area behavior, and style guide. Create a plan that can generate one clean 16:9 background image per slide with Flick-rendered editable text.
        """
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
