//
//  IOSDashboardView.swift
//  Flick
//

#if !os(macOS)
import SwiftUI

struct IOSDashboardView: View {
    @Environment(FlickAppModel.self) private var appModel
    @State private var exampleTemplates: [ExampleSlideshowTemplate] = []

    private var automationSnapshot: AutomationDashboardSnapshot {
        AutomationDashboardSnapshot.make(
            overview: appModel.overview,
            exampleTemplates: exampleTemplates
        )
    }

    private var awaitingPublishingJobs: [PublishingJob] {
        appModel.overview.publishingJobs
            .filter { $0.status == .awaitingUserCompletion }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var authorizedAccountCount: Int {
        appModel.overview.accounts
            .filter { $0.authorizationSource == .loginKit || $0.authorizationSource == .nativeOAuth }
            .count
    }

    var body: some View {
        List {
            overviewSections
            if !automationSnapshot.activeProgresses.isEmpty {
                inProgressSection
            }
        }
        .flickSettingsListStyle()
        .refreshable {
            await appModel.refresh()
        }
        .task {
            await loadExampleTemplates()
        }
        .flickToolbarTitle("Dashboard")
    }

    @ViewBuilder
    private var overviewSections: some View {
        Section("Overview") {
            DashboardPostsNavigationRow(
                draftCount: awaitingPublishingJobs.count
            ) {
                IOSPublishingActivityView()
            }

            if let nextAutomationPostAt = appModel.overview.dashboard.nextAutomationPostAt {
                FlickSettingsNavigationRow(
                    title: "Next automated post",
                    systemImage: "clock",
                    iconColor: .orange,
                    value: AutomationDashboardFormatting.relativeDate(nextAutomationPostAt)
                ) {
                    IOSAutomationDashboardListView(exampleTemplates: exampleTemplates)
                }
            }

            FlickSettingsNavigationRow(
                title: "Accounts",
                systemImage: "person.2",
                iconColor: .green,
                value: accountCountValue
            ) {
                IOSAccountsView()
            }
        }
    }

    private var accountCountValue: String {
        authorizedAccountCount == 1 ? "1 account" : "\(authorizedAccountCount.formatted()) accounts"
    }

    private var inProgressSection: some View {
        Section("In Progress") {
            ForEach(automationSnapshot.activeProgresses) { progress in
                AutomationProgressSummaryRow(progress: progress)
            }
        }
    }

    private func loadExampleTemplates() async {
        do {
            let index = try await ExampleSlideshowLibrary.loadIndex(configuration: appModel.configuration)
            guard let firstNicheID = index.collections.first?.id else {
                exampleTemplates = []
                return
            }
            let page = try await ExampleSlideshowLibrary.loadPage(
                nicheID: firstNicheID,
                pageNumber: 1,
                index: index,
                configuration: appModel.configuration
            )
            exampleTemplates = page.collection.templates
        } catch {
            exampleTemplates = []
        }
    }
}

private struct DashboardPostsNavigationRow<Destination: View>: View {
    var draftCount: Int
    let destination: Destination

    init(
        draftCount: Int,
        @ViewBuilder destination: () -> Destination
    ) {
        self.draftCount = draftCount
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            FlickSettingsRow(
                title: "Posts",
                systemImage: "photo.stack",
                iconColor: FlickStyle.appTint
            ) {
                HStack(spacing: 10) {
                    DashboardPostCount(systemImage: "bell.badge", tint: .orange, count: draftCount)
                }
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        "\(draftCount.formatted()) draft posts"
    }
}

private struct DashboardPostCount: View {
    var systemImage: String
    var tint: Color
    var count: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(count.formatted())
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.subheadline.weight(.semibold))
        .accessibilityHidden(true)
    }
}

private struct IOSAutomationDashboardListView: View {
    @Environment(FlickAppModel.self) private var appModel

    var exampleTemplates: [ExampleSlideshowTemplate]

    private var snapshot: AutomationDashboardSnapshot {
        AutomationDashboardSnapshot.make(
            overview: appModel.overview,
            exampleTemplates: exampleTemplates
        )
    }

    private var activeItems: [AutomationDashboardItem] {
        snapshot.items.filter { $0.automation.status == .active }
    }

    var body: some View {
        List {
            if !snapshot.activeProgresses.isEmpty {
                Section("In Progress") {
                    ForEach(snapshot.activeProgresses) { progress in
                        AutomationProgressSummaryRow(progress: progress)
                    }
                }
            }

            Section("Active automations") {
                if activeItems.isEmpty {
                    DashboardMessageRow(
                        title: "No active automations",
                        message: "Create or resume automations from the Create tab to schedule recurring posts.",
                        systemImage: "calendar.badge.plus",
                        iconColor: .secondary
                    )
                } else {
                    ForEach(activeItems) { item in
                        NavigationLink {
                            IOSAutomationDetailView(
                                automationID: item.id,
                                exampleTemplates: exampleTemplates
                            )
                        } label: {
                            IOSAutomationDashboardRow(item: item)
                        }
                    }
                }
            }
        }
        .flickSettingsListStyle()
        .refreshable {
            await appModel.refresh()
        }
        .flickToolbarTitle("Active Automations")
    }
}

private struct IOSAutomationDashboardRow: View {
    var item: AutomationDashboardItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.automation.status == .active ? "calendar.badge.clock" : "pause.circle")
                .foregroundStyle(item.automation.status.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(item.accountPlatformSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Label(AutomationDashboardFormatting.postCount(item.postCount), systemImage: "photo.stack")
                    Label(item.scheduleSummary, systemImage: "calendar")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

                HStack(spacing: 8) {
                    Label("Next \(AutomationDashboardFormatting.relativeDate(item.nextScheduledAt))", systemImage: "clock")
                    Label("Previous \(AutomationDashboardFormatting.relativeDate(item.previousPostedAt))", systemImage: "arrow.counterclockwise")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

                if let lastErrorMessage = item.automation.lastErrorMessage, !lastErrorMessage.isEmpty {
                    Text(lastErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }

                if !item.activeProgresses.isEmpty {
                    Text(item.activeProgresses.count == 1 ? "1 post in progress" : "\(item.activeProgresses.count) posts in progress")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            DashboardStatusIcon(
                title: item.automation.status.displayName,
                tint: item.automation.status.tint,
                systemImage: item.automation.status.systemImage
            )
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
#endif
