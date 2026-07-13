//
//  FlickRepository.swift
//  Flick
//

import Foundation

@MainActor
protocol FlickRepository {
    func loadOverview() async throws -> FlickOverviewState
    func saveOverview(_ state: FlickOverviewState) async throws
    func saveOverview(
        _ state: FlickOverviewState,
        deletingAutomationIDs: Set<UUID>
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
    func saveOverview(
        _ state: FlickOverviewState,
        deletingAutomationIDs: Set<UUID>
    ) async throws {
        _ = deletingAutomationIDs
        try await saveOverview(state)
    }
}

struct EmptyFlickRepository: FlickRepository {
    func loadOverview() async throws -> FlickOverviewState {
        FlickEmptyState.make()
    }

    func saveOverview(_ state: FlickOverviewState) async throws {
        _ = state
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
