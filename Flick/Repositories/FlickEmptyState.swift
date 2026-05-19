//
//  FlickEmptyState.swift
//  Flick
//

import Foundation

enum FlickEmptyState {
    static func make(now: Date = Date()) -> FlickOverviewState {
        _ = now

        let dashboard = DashboardSnapshot(
            failedJobCount: 0,
            connectedAccounts: [],
            syncHealth: SyncHealth(
                iCloudAvailable: true
            ),
            apiHealth: []
        )

        return FlickOverviewState(
            accounts: [],
            products: [],
            assets: [],
            drafts: [],
            templates: [],
            publishingJobs: [],
            publishedPosts: [],
            dashboard: dashboard
        )
    }
}
