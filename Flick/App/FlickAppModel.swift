//
//  FlickAppModel.swift
//  Flick
//

import Foundation
import Observation

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
        connectingPlatform = platform
        accountConnectionMessage = nil
        lastErrorMessage = nil

        defer {
            connectingPlatform = nil
        }

        do {
            switch platform {
            case .tiktok:
                let result = try await tiktokLoginKitClient.authorize(configuration: configuration.tiktok)
                switch result {
                case let .completed(account):
                    applyAuthorizedAccounts()
                    accountConnectionMessage = "Connected \(account.displayName)."
                case .openedExternalBrowser:
                    accountConnectionMessage = "Opened TikTok authorization in the browser. Finish Login Kit there, then return to Flick."
                }
            case .instagram, .threads, .x:
                throw PlatformAdapterError.futurePlatform(platform)
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func handleOAuthCallback(_ url: URL) async {
        do {
            guard let account = try await tiktokLoginKitClient.handleCallback(url) else { return }
            applyAuthorizedAccounts()
            accountConnectionMessage = "Connected \(account.displayName)."
            lastErrorMessage = nil
        } catch {
            accountConnectionMessage = nil
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

    func storeCredentialEnvironment(_ contents: String) {
        do {
            let result = try credentialVault.storeEnvironment(contents)
            configuration = .current
            applyCredentialHealth()
            credentialMessage = "Stored \(result.storedKeys.count) values securely" + (result.ignoredKeys.isEmpty ? "." : "; ignored \(result.ignoredKeys.count).")
            lastErrorMessage = nil
        } catch {
            credentialMessage = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    func clearStoredCredentials() {
        do {
            try credentialVault.clearStoredCredentials()
            configuration = .current
            applyCredentialHealth()
            credentialMessage = "Cleared stored credentials."
            lastErrorMessage = nil
        } catch {
            credentialMessage = nil
            lastErrorMessage = error.localizedDescription
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
}

private extension Array where Element == CredentialStatus {
    func containsPresent(_ name: String) -> Bool {
        contains { $0.name == name && $0.isPresent }
    }
}
