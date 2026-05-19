//
//  DashboardView.swift
//  Flick
//

import SwiftUI

struct DashboardView: View {
    @Environment(FlickAppModel.self) private var appModel

    private var awaitingTikTokJobs: [PublishingJob] {
        appModel.overview.publishingJobs
            .filter { $0.platform == .tiktok && $0.status == .awaitingUserCompletion }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var recentPublishedPosts: [PublishedPost] {
        Array(
            appModel.overview.publishedPosts
                .filter { $0.platform == .tiktok }
                .sorted { $0.publishedAt > $1.publishedAt }
                .prefix(5)
        )
    }

    private var publishedTikTokPostCount: Int {
        appModel.overview.publishedPosts.filter { $0.platform == .tiktok }.count
    }

    var body: some View {
        List {
            overviewSection
            tiktokPublishingSection
            syncStatusSection
            apiHealthSection
            accountHealthSection
        }
        .flickSettingsListStyle()
        .refreshable {
            await appModel.refresh()
        }
        .flickToolbarTitle("Dashboard")
    }

    private var overviewSection: some View {
        Section("Overview") {
            FlickSettingsValueRow(
                title: "Draft uploads",
                systemImage: "bell.badge",
                iconColor: .orange,
                value: awaitingTikTokJobs.count.formatted()
            )
            FlickSettingsValueRow(
                title: "Published posts",
                systemImage: "checkmark.seal",
                iconColor: .green,
                value: publishedTikTokPostCount.formatted()
            )
            FlickSettingsValueRow(
                title: "Active automations",
                systemImage: "calendar.badge.clock",
                iconColor: .teal,
                value: appModel.overview.dashboard.activeAutomationCount.formatted()
            )
            if let nextAutomationPostAt = appModel.overview.dashboard.nextAutomationPostAt {
                FlickSettingsValueRow(
                    title: "Next automated post",
                    systemImage: "clock",
                    iconColor: .orange,
                    value: RelativeDateTimeFormatter.dashboardShort.localizedString(for: nextAutomationPostAt, relativeTo: Date())
                )
            }
            FlickSettingsValueRow(
                title: "Failed publishes",
                systemImage: "exclamationmark.triangle",
                iconColor: .red,
                value: appModel.overview.dashboard.failedJobCount.formatted()
            )
            FlickSettingsValueRow(
                title: "Connected accounts",
                systemImage: "person.2",
                iconColor: .green,
                value: appModel.overview.accounts.filter(\.isPublishingEnabled).count.formatted()
            )
        }
    }

    private var tiktokPublishingSection: some View {
        Section("TikTok publishing") {
            if awaitingTikTokJobs.isEmpty && recentPublishedPosts.isEmpty {
                DashboardMessageRow(
                    title: "No TikTok publish activity yet",
                    message: "Draft uploads and direct posts will appear here after publishing from Create.",
                    systemImage: "paperplane",
                    iconColor: .secondary
                )
            } else {
                ForEach(awaitingTikTokJobs) { job in
                    TikTokPublishingJobRow(job: job)
                }

                ForEach(recentPublishedPosts) { post in
                    TikTokPublishedPostRow(post: post)
                }
            }
        }
    }

    private var syncStatusSection: some View {
        Section("Sync") {
            DashboardStatusRow(
                title: "iCloud account",
                message: appModel.overview.dashboard.syncHealth.iCloudAvailable ? "CloudKit access is available for this iCloud account." : "Sign into iCloud and enable iCloud Drive to sync app data.",
                systemImage: "icloud",
                iconColor: appModel.overview.dashboard.syncHealth.iCloudAvailable ? .blue : .orange,
                badgeTitle: appModel.overview.dashboard.syncHealth.iCloudAvailable ? "Available" : "Unavailable",
                badgeTint: appModel.overview.dashboard.syncHealth.iCloudAvailable ? .blue : .orange,
                badgeSystemImage: "circle.fill"
            )
        }
    }

    private var apiHealthSection: some View {
        Section("Platform health") {
            ForEach(appModel.overview.dashboard.apiHealth) { status in
                DashboardStatusRow(
                    title: status.serviceName,
                    message: status.statusText,
                    systemImage: "antenna.radiowaves.left.and.right",
                    iconColor: status.isConfigured ? .green : .orange,
                    badgeTitle: status.isConfigured ? "Ready" : "Needs setup",
                    badgeTint: status.isConfigured ? .green : .orange,
                    badgeSystemImage: status.isConfigured ? "checkmark.circle" : "exclamationmark.circle"
                )
            }
        }
    }

    private var accountHealthSection: some View {
        Section("Accounts") {
            if appModel.overview.dashboard.connectedAccounts.isEmpty {
                Button(action: openAccounts) {
                    DashboardStatusRow(
                        title: "No authorized accounts",
                        message: "Connect a platform account with Login Kit before scheduling posts.",
                        systemImage: "person.crop.circle.badge.plus",
                        iconColor: .secondary,
                        badgeTitle: "Open Accounts",
                        badgeTint: FlickStyle.appTint,
                        badgeSystemImage: "person.2"
                    )
                }
                .buttonStyle(.plain)
            } else {
                ForEach(appModel.overview.dashboard.connectedAccounts) { account in
                    DashboardStatusRow(
                        title: account.displayName,
                        message: account.scopes.isEmpty ? "No scopes connected yet" : account.scopes.joined(separator: ", "),
                        messageLineLimit: 2,
                        systemImage: account.platform.systemImage,
                        iconColor: account.platform.tint,
                        badgeTitle: account.status.displayName,
                        badgeTint: account.status.tint,
                        badgeSystemImage: "circle.fill"
                    )
                }
            }
        }
    }

    private func openAccounts() {
        appModel.selectedSection = .accounts
    }
}

private extension RelativeDateTimeFormatter {
    static var dashboardShort: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }
}
