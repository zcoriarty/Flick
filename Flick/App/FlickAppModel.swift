//
//  FlickAppModel.swift
//  Flick
//

import Foundation
import Observation
import UniformTypeIdentifiers

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

    @ObservationIgnored private let repository: FlickRepository
    @ObservationIgnored private let scheduler = PublishingScheduler()
    @ObservationIgnored private let credentialVault = CredentialVault()
    @ObservationIgnored private let loginKitAccountStore = LoginKitAccountStore()
    @ObservationIgnored private let tiktokLoginKitClient = TikTokLoginKitClient()
    @ObservationIgnored private let localMediaLibrary = LocalMediaLibrary(directoryName: "ProductMedia")

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

    func refresh() async {
        do {
            overview = try await repository.loadOverview()
            configuration = .current
            applyAuthorizedAccounts()
            applyCredentialHealth()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func toggleAutomationPaused() {
        overview.workspace.automationPaused.toggle()
        overview.dashboard.workerStatus.automationPaused = overview.workspace.automationPaused
    }

    func approve(job: PublishingJob) {
        update(job: job, to: .approved)
    }

    func pause(job: PublishingJob) {
        update(job: job, to: .paused)
    }

    func resume(job: PublishingJob) {
        update(job: job, to: .queued)
    }

    func retry(job: PublishingJob) {
        update(job: job, to: .queued)
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
                role: SlideRole.templateRole(at: offset, total: template.slides.count),
                imageAssetID: asset.id,
                prompt: "Use slide \(sourceSlide.index) from @\(template.profile) as the visual reference.",
                overlayText: SlideRole.templateRole(at: offset, total: template.slides.count).templateOverlayText(index: offset),
                textPosition: .center,
                textStyle: SlideTextStyle(
                    fontName: "System Rounded",
                    weight: "Black",
                    foregroundHex: "#FFFFFF",
                    backgroundHex: "#111111",
                    alignment: "center"
                ),
                duration: 1.5,
                transition: offset == 0 ? .none : .push,
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
            sourceTrendID: nil,
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
        selectedSection = .create
    }

    func addProductMedia(data: Data, contentType: UTType) throws {
        let storedMedia = try localMediaLibrary.store(data: data, contentType: contentType)
        addProductMedia(storedMedia)
    }

    func addProductMedia(fileURL: URL, contentType: UTType) throws {
        let storedMedia = try localMediaLibrary.store(fileURL: fileURL, contentType: contentType)
        addProductMedia(storedMedia)
    }

    private func addProductMedia(_ storedMedia: StoredLocalMedia) {
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
        lastErrorMessage = nil
    }

    func removeProductMedia(_ asset: MediaAsset) {
        overview.assets.removeAll { $0.id == asset.id }
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

    private func update(job: PublishingJob, to status: PublishingJobStatus) {
        guard let index = overview.publishingJobs.firstIndex(where: { $0.id == job.id }) else {
            lastErrorMessage = FlickRepositoryError.missingJob(job.id).localizedDescription
            return
        }

        do {
            let updated = try scheduler.transition(overview.publishingJobs[index], to: status)
            overview.publishingJobs[index] = updated
            refreshDashboardCounts()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func refreshDashboardCounts() {
        overview.dashboard.awaitingApprovalCount = overview.publishingJobs.filter { $0.status == .awaitingApproval }.count
        overview.dashboard.failedJobCount = overview.publishingJobs.filter { $0.status == .failed }.count
        overview.dashboard.scheduledTodayCount = overview.publishingJobs.filter { Calendar.current.isDateInToday($0.scheduledAt) }.count
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
                isConfigured: statuses.containsPresent("Supabase URL") && statuses.containsPresent("Supabase anon key"),
                statusText: statuses.containsPresent("Supabase service role key") ? "Anon key found; service role stays local only" : "Anon project credentials expected",
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
}

private extension Array where Element == CredentialStatus {
    func containsPresent(_ name: String) -> Bool {
        contains { $0.name == name && $0.isPresent }
    }
}

private extension FlickAppModel {
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
}

private extension SlideRole {
    static func templateRole(at index: Int, total: Int) -> SlideRole {
        if index == 0 { return .hook }
        if index == total - 1 { return .cta }

        switch index % 4 {
        case 1: return .problem
        case 2: return .proof
        case 3: return .demo
        default: return .benefit
        }
    }

    func templateOverlayText(index: Int) -> String {
        switch self {
        case .hook: "Hook"
        case .problem: "Problem"
        case .proof: "Proof"
        case .demo: "Demo"
        case .benefit: "Benefit"
        case .cta: "CTA"
        }
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
