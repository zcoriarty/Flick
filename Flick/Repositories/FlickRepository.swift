//
//  FlickRepository.swift
//  Flick
//

import Foundation

protocol FlickRepository {
    func loadOverview() async throws -> FlickOverviewState
    func saveOverview(_ state: FlickOverviewState) async throws
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
}
