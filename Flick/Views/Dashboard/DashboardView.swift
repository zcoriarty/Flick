//
//  DashboardView.swift
//  Flick
//

import SwiftUI

struct DashboardView: View {
    @Environment(FlickAppModel.self) private var appModel

    var body: some View {
        dashboardContent
            .flickScrollablePage()
            .refreshable {
                await appModel.refresh()
            }
            .flickToolbarTitle("Dashboard")
    }

    private var dashboardContent: some View {
        VStack(alignment: .leading, spacing: FlickStyle.sectionSpacing) {
            metricGrid
            tiktokPublishing
            syncStatus
            apiHealth
            accountHealth
        }
    }

    private var metricGrid: some View {
        ResponsiveGrid(minimum: 170) {
            MetricTile(
                title: "Draft uploads",
                value: awaitingTikTokJobs.count.formatted(),
                systemImage: "bell.badge",
                tint: .orange
            )
            MetricTile(
                title: "Published posts",
                value: publishedTikTokPostCount.formatted(),
                systemImage: "checkmark.seal",
                tint: .green
            )
            MetricTile(
                title: "Failed publishes",
                value: appModel.overview.dashboard.failedJobCount.formatted(),
                systemImage: "exclamationmark.triangle",
                tint: .red
            )
            MetricTile(
                title: "Connected accounts",
                value: appModel.overview.accounts.filter(\.isPublishingEnabled).count.formatted(),
                systemImage: "person.2",
                tint: .green
            )
        }
    }

    private var tiktokPublishing: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "TikTok publishing", subtitle: "Draft uploads and completed posts", systemImage: "paperplane")
            if awaitingTikTokJobs.isEmpty && recentPublishedPosts.isEmpty {
                FlickEmptyStateCard(
                    title: "No TikTok publish activity yet",
                    message: "Draft uploads and direct posts will appear here after publishing from Create.",
                    systemImage: "paperplane"
                )
            } else {
                FlickGlassCard {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(awaitingTikTokJobs.enumerated()), id: \.element.id) { index, job in
                            TikTokPublishingJobRow(job: job)
                            if index < awaitingTikTokJobs.count - 1 || !recentPublishedPosts.isEmpty {
                                Divider()
                                    .padding(.vertical, 10)
                            }
                        }

                        ForEach(Array(recentPublishedPosts.enumerated()), id: \.element.id) { index, post in
                            TikTokPublishedPostRow(post: post)
                            if index < recentPublishedPosts.count - 1 {
                                Divider()
                                    .padding(.vertical, 10)
                            }
                        }
                    }
                }
            }
        }
    }

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

    private var syncStatus: some View {
        SyncStatusPanel(syncHealth: appModel.overview.dashboard.syncHealth)
    }

    private var apiHealth: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Platform health", subtitle: "Configuration and API readiness", systemImage: "antenna.radiowaves.left.and.right")
            ResponsiveGrid(minimum: 260) {
                ForEach(appModel.overview.dashboard.apiHealth) { status in
                    FlickGlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(status.serviceName)
                                    .font(.headline)
                                Spacer()
                                StatusBadge(
                                    title: status.isConfigured ? "Ready" : "Needs setup",
                                    tint: status.isConfigured ? .green : .orange,
                                    systemImage: status.isConfigured ? "checkmark.circle" : "exclamationmark.circle"
                                )
                            }
                            Text(status.statusText)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var accountHealth: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Accounts", subtitle: "Publishing and token status", systemImage: "person.crop.circle.badge.checkmark")
            if appModel.overview.dashboard.connectedAccounts.isEmpty {
                FlickEmptyStateCard(
                    title: "No authorized accounts",
                    message: "Connect a platform account with Login Kit before scheduling posts.",
                    systemImage: "person.crop.circle.badge.plus",
                    actionTitle: "Open Accounts",
                    actionSystemImage: "person.2"
                ) {
                    appModel.selectedSection = .accounts
                }
            } else {
                ResponsiveGrid(minimum: 260) {
                    ForEach(appModel.overview.dashboard.connectedAccounts) { account in
                        FlickGlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Label(account.displayName, systemImage: account.platform.systemImage)
                                        .font(.headline)
                                    Spacer()
                                    StatusBadge(title: account.status.displayName, tint: account.status.tint, systemImage: "circle.fill")
                                }
                                Text(account.scopes.isEmpty ? "No scopes connected yet" : account.scopes.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
    }

}

private struct TikTokPublishingJobRow: View {
    var job: PublishingJob

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.badge")
                .foregroundStyle(.orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text("Waiting for TikTok")
                    .font(.subheadline.weight(.semibold))
                Text("Open the TikTok inbox notification to finish posting.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let publishID = job.platformPublishID {
                    Text(publishID)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 12)

            StatusBadge(title: "Draft sent", tint: .orange, systemImage: "clock")
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TikTokPublishedPostRow: View {
    var post: PublishedPost

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(post.dashboardTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text("Published \(RelativeDateTimeFormatter.short.localizedString(for: post.publishedAt, relativeTo: Date()))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(post.platformPostID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            StatusBadge(title: "Published", tint: .green, systemImage: "checkmark.circle")
        }
        .accessibilityElement(children: .combine)
    }
}

private extension PublishedPost {
    var dashboardTitle: String {
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCaption.isEmpty else { return "\(platform.displayName) post" }
        return trimmedCaption
    }
}

private struct SyncStatusPanel: View {
    var syncHealth: SyncHealth

    var body: some View {
        FlickGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("iCloud account", systemImage: "icloud")
                        .font(.headline)
                    Spacer()
                    StatusBadge(
                        title: syncHealth.iCloudAvailable ? "Available" : "Unavailable",
                        tint: syncHealth.iCloudAvailable ? .blue : .orange,
                        systemImage: "circle.fill"
                    )
                }

                Text(syncHealth.iCloudAvailable ? "CloudKit access is available for this iCloud account." : "Sign into iCloud and enable iCloud Drive to sync app data.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private extension RelativeDateTimeFormatter {
    static var short: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }
}
