//
//  FlickRepository.swift
//  Flick
//

import Foundation

nonisolated enum OverviewRecordKind: String, Codable, CaseIterable, Hashable, Sendable {
    case connectedAccount = "connected-account"
    case product
    case creationModel = "creation-model"
    case asset
    case template
    case draft
    case slide
    case automation
    case automationPostProgress = "automation-post-progress"
    case publishingJob = "publishing-job"
    case publishedPost = "published-post"
}

nonisolated struct OverviewDeletion: Codable, Hashable, Sendable {
    var kind: OverviewRecordKind
    var id: UUID
    var deletedAt: Date
}

@MainActor
protocol FlickRepository {
    func loadOverview() async throws -> FlickOverviewState
    func saveOverview(
        _ state: FlickOverviewState,
        deletions: [OverviewDeletion]
    ) async throws
    func saveCreateState(
        drafts: [SlideshowDraft],
        templates: [CreativeTemplate],
        assets: [MediaAsset],
        deletions: [OverviewDeletion]
    ) async throws
    func saveMacRunnerHeartbeat(_ heartbeat: MacRunnerHeartbeat) async throws
    func saveAutomationPostProgresses(_ progresses: [AutomationPostProgress]) async throws
    func upsertConnectedAccount(_ account: ConnectedAccount) async throws
    func deleteConnectedAccount(id: UUID) async throws
    func upsertProduct(_ product: FlickProduct) async throws
    func upsertAsset(_ asset: MediaAsset) async throws
    func deleteAsset(id: UUID) async throws
}

extension FlickRepository {
    func saveOverview(_ state: FlickOverviewState) async throws {
        try await saveOverview(state, deletions: [])
    }

    func saveCreateState(
        drafts: [SlideshowDraft],
        templates: [CreativeTemplate],
        assets: [MediaAsset],
        deletions: [OverviewDeletion]
    ) async throws {
        var state = try await loadOverview()
        state.drafts = state.drafts.mergingLatestRecords(drafts)
        state.templates = state.templates.mergingLatestRecords(templates)
        state.assets = state.assets.mergingLatestRecords(assets)

        let deletedDrafts = deletions.latestDeletionDates(for: .draft)
        let deletedTemplates = deletions.latestDeletionDates(for: .template)
        let deletedAssets = deletions.latestDeletionDates(for: .asset)
        let deletedSlides = deletions.latestDeletionDates(for: .slide)
        state.drafts.removeAll { ($0.updatedAt <= (deletedDrafts[$0.id] ?? .distantPast)) }
        state.templates.removeAll { ($0.updatedAt <= (deletedTemplates[$0.id] ?? .distantPast)) }
        state.assets.removeAll { ($0.updatedAt <= (deletedAssets[$0.id] ?? .distantPast)) }
        for draftIndex in state.drafts.indices {
            state.drafts[draftIndex].slides.removeAll {
                $0.updatedAt <= (deletedSlides[$0.id] ?? .distantPast)
            }
        }
        try await saveOverview(state, deletions: deletions)
    }
}

nonisolated private extension Array where Element == OverviewDeletion {
    func latestDeletionDates(for kind: OverviewRecordKind) -> [UUID: Date] {
        lazy.filter { $0.kind == kind }.reduce(into: [UUID: Date]()) { result, deletion in
            result[deletion.id] = Swift.max(result[deletion.id] ?? .distantPast, deletion.deletedAt)
        }
    }
}

nonisolated private protocol OverviewVersionedRecord: Identifiable where ID == UUID {
    var updatedAt: Date { get }
}

nonisolated extension SlideshowDraft: OverviewVersionedRecord {}
nonisolated extension CreativeTemplate: OverviewVersionedRecord {}
nonisolated extension MediaAsset: OverviewVersionedRecord {}

nonisolated private extension Array where Element: OverviewVersionedRecord {
    func mergingLatestRecords(_ records: [Element]) -> [Element] {
        var merged = self
        var indicesByID = Dictionary(uniqueKeysWithValues: merged.indices.map { (merged[$0].id, $0) })

        for record in records {
            if let index = indicesByID[record.id] {
                if record.updatedAt > merged[index].updatedAt {
                    merged[index] = record
                }
            } else {
                indicesByID[record.id] = merged.count
                merged.append(record)
            }
        }

        return merged
    }
}

struct EmptyFlickRepository: FlickRepository {
    func loadOverview() async throws -> FlickOverviewState {
        FlickEmptyState.make()
    }

    func saveOverview(
        _ state: FlickOverviewState,
        deletions: [OverviewDeletion]
    ) async throws {
        _ = state
        _ = deletions
    }

    func saveMacRunnerHeartbeat(_ heartbeat: MacRunnerHeartbeat) async throws {
        _ = heartbeat
    }

    func saveAutomationPostProgresses(_ progresses: [AutomationPostProgress]) async throws {
        _ = progresses
    }

    func upsertConnectedAccount(_ account: ConnectedAccount) async throws {
        _ = account
    }

    func deleteConnectedAccount(id: UUID) async throws {
        _ = id
    }

    func upsertProduct(_ product: FlickProduct) async throws {
        _ = product
    }

    func upsertAsset(_ asset: MediaAsset) async throws {
        _ = asset
    }

    func deleteAsset(id: UUID) async throws {
        _ = id
    }
}
