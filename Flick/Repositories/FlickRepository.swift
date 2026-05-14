//
//  FlickRepository.swift
//  Flick
//

import Foundation

@MainActor
protocol FlickRepository {
    func loadOverview() async throws -> FlickOverviewState
    func saveOverview(_ state: FlickOverviewState) async throws
    func upsertAsset(_ asset: MediaAsset) async throws
    func deleteAsset(id: UUID) async throws
}

enum FlickRepositoryError: LocalizedError {
    case transitionNotAllowed(from: PublishingJobStatus, to: PublishingJobStatus)
    case missingJob(UUID)

    var errorDescription: String? {
        switch self {
        case let .transitionNotAllowed(from, to):
            "Cannot move a publishing job from \(from.rawValue) to \(to.rawValue)."
        case let .missingJob(id):
            "No publishing job exists for \(id.uuidString)."
        }
    }
}

struct EmptyFlickRepository: FlickRepository {
    func loadOverview() async throws -> FlickOverviewState {
        FlickEmptyState.make()
    }

    func saveOverview(_ state: FlickOverviewState) async throws {
        _ = state
    }

    func upsertAsset(_ asset: MediaAsset) async throws {
        _ = asset
    }

    func deleteAsset(id: UUID) async throws {
        _ = id
    }
}
