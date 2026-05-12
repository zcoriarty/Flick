//
//  DashboardView.swift
//  Flick
//

import SwiftUI

struct DashboardView: View {
    @Environment(FlickAppModel.self) private var appModel

    var body: some View {
        NavigationStack {
            dashboardContent
                .flickScrollablePage()
                .navigationTitle("Dashboard")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Generate batch", systemImage: "wand.and.sparkles") {
                            appModel.selectedSection = .create
                        }
                        .buttonStyle(.glassProminent)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Refresh", systemImage: "arrow.clockwise") {
                            Task { await appModel.refresh() }
                        }
                        .buttonStyle(.glass)
                    }
                }
        }
    }

    private var dashboardContent: some View {
        VStack(alignment: .leading, spacing: FlickStyle.sectionSpacing) {
            metricGrid
            workerAndSync
            apiHealth
            accountHealth
            bestPost
        }
    }

    private var metricGrid: some View {
        ResponsiveGrid(minimum: 170) {
            MetricTile(
                title: "Scheduled today",
                value: appModel.overview.dashboard.scheduledTodayCount.formatted(),
                systemImage: "calendar",
                tint: .blue
            )
            MetricTile(
                title: "Awaiting approval",
                value: appModel.overview.dashboard.awaitingApprovalCount.formatted(),
                systemImage: "checkmark.seal",
                tint: .orange
            )
            MetricTile(
                title: "Failed jobs",
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

    private var workerAndSync: some View {
        ResponsiveGrid(minimum: 280) {
            WorkerStatusPanel(status: appModel.overview.dashboard.workerStatus) {
                appModel.toggleAutomationPaused()
            }
            SyncStatusPanel(syncHealth: appModel.overview.dashboard.syncHealth)
        }
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

    @ViewBuilder
    private var bestPost: some View {
        if let post = appModel.overview.dashboard.bestRecentPost {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Best recent post", subtitle: "Current winner for remixing", systemImage: "trophy")
                FlickGlassCard(interactive: true) {
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.purple)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(post.title)
                                .font(.title3.weight(.semibold))
                            HStack(spacing: 12) {
                                Text("\(post.views.formatted()) views")
                                Text(post.engagementRate, format: .percent.precision(.fractionLength(1)))
                                Text("\(post.savesPerView.formatted(.number.precision(.fractionLength(3)))) saves/view")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            HStack {
                                ForEach(post.tags) { tag in
                                    TagChip(tag: tag)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                        Button("Remix", systemImage: "arrow.triangle.2.circlepath") {
                            if let draft = appModel.overview.drafts.first {
                                appModel.duplicateDraft(draft)
                            }
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Best recent post", subtitle: "Current winner for remixing", systemImage: "trophy")
                FlickEmptyStateCard(
                    title: "No published posts yet",
                    message: "After real posts are published and analytics snapshots are collected, the current winner will appear here.",
                    systemImage: "trophy"
                )
            }
        }
    }
}

private struct WorkerStatusPanel: View {
    var status: WorkerStatus
    var toggleAutomation: () -> Void

    var body: some View {
        FlickGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Mac worker", systemImage: "desktopcomputer")
                        .font(.headline)
                    Spacer()
                    StatusBadge(title: status.isOnline ? "Online" : "Offline", tint: status.isOnline ? .green : .red, systemImage: "circle.fill")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(status.deviceName)
                        .font(.subheadline.weight(.semibold))
                    Text(status.isPrimary ? "Primary automation worker" : "No primary worker configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if status.isOnline {
                        Text("Last seen \(status.lastSeenAt, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if status.isPrimary {
                    Button(status.automationPaused ? "Resume automation" : "Pause automation", systemImage: status.automationPaused ? "play.fill" : "pause.fill") {
                        toggleAutomation()
                    }
                    .modifier(WorkerAutomationButtonStyle(isPaused: status.automationPaused))
                }
            }
        }
    }
}

private struct WorkerAutomationButtonStyle: ViewModifier {
    var isPaused: Bool

    func body(content: Content) -> some View {
        if isPaused {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.glass)
        }
    }
}

private struct SyncStatusPanel: View {
    var syncHealth: SyncHealth

    var body: some View {
        FlickGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("CloudKit sync", systemImage: "icloud")
                        .font(.headline)
                    Spacer()
                    StatusBadge(
                        title: syncHealth.iCloudAvailable ? "Available" : "Unavailable",
                        tint: syncHealth.iCloudAvailable ? .blue : .orange,
                        systemImage: "circle.fill"
                    )
                }

                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    GridRow {
                        Text("Import")
                            .foregroundStyle(.secondary)
                        Text(syncHealth.lastCloudKitImport.map { RelativeDateTimeFormatter.short.localizedString(for: $0, relativeTo: Date()) } ?? "Never")
                    }
                    GridRow {
                        Text("Export")
                            .foregroundStyle(.secondary)
                        Text(syncHealth.lastCloudKitExport.map { RelativeDateTimeFormatter.short.localizedString(for: $0, relativeTo: Date()) } ?? "Never")
                    }
                    GridRow {
                        Text("Pending")
                            .foregroundStyle(.secondary)
                        Text(syncHealth.pendingChanges.formatted())
                    }
                }
                .font(.caption)
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
