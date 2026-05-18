//
//  FlickEmptyState.swift
//  Flick
//

import Foundation

enum FlickEmptyState {
    static func make(now: Date = Date()) -> FlickOverviewState {
        let defaultCadence = CadenceRule(
            id: UUID(),
            accountID: nil,
            postsPerDay: 0,
            allowedTimeWindows: [],
            minimumGapMinutes: 0,
            requireApproval: true,
            maxRetries: 0,
            pauseOnErrorCount: 0
        )

        let workspace = FlickWorkspace(
            id: UUID(),
            name: "Flick Workspace",
            defaultCadence: defaultCadence,
            automationPaused: false,
            primaryWorkerDeviceID: nil,
            createdAt: now,
            updatedAt: now
        )

        let dashboard = DashboardSnapshot(
            scheduledTodayCount: 0,
            awaitingApprovalCount: 0,
            failedJobCount: 0,
            bestRecentPost: nil,
            workerStatus: WorkerStatus(
                deviceName: "No primary worker",
                isPrimary: false,
                isOnline: false,
                automationPaused: false,
                lastSeenAt: now,
                activeJobID: nil
            ),
            connectedAccounts: [],
            syncHealth: SyncHealth(
                lastCloudKitImport: nil,
                lastCloudKitExport: nil,
                pendingChanges: 0,
                iCloudAvailable: true,
                primaryWorkerOnline: false,
                errors: []
            ),
            apiHealth: []
        )

        return FlickOverviewState(
            workspace: workspace,
            devices: [],
            accounts: [],
            campaigns: [],
            products: [],
            assets: [],
            drafts: [],
            templates: [],
            publishingJobs: [],
            publishedPosts: [],
            analyticsSnapshots: [],
            analyticsPerformance: [],
            cadenceRules: [],
            dashboard: dashboard
        )
    }
}
