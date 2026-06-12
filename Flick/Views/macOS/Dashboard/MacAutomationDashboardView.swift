//
//  MacAutomationDashboardView.swift
//  Flick
//

#if os(macOS)
import SwiftUI

struct MacAutomationDashboardView: View {
    @Environment(FlickAppModel.self) private var appModel
    @State private var exampleTemplates: [ExampleSlideshowTemplate] = []

    private var snapshot: AutomationDashboardSnapshot {
        AutomationDashboardSnapshot.make(
            overview: appModel.overview,
            exampleTemplates: exampleTemplates
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if !snapshot.activeProgresses.isEmpty {
                    MacAutomationInProgressSection(progresses: snapshot.activeProgresses)
                }

                if snapshot.items.isEmpty {
                    MacAutomationEmptyState()
                } else {
                    automationGrid
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .flickAppBackground()
        .navigationTitle("Automations")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await appModel.refresh() }
                }
            }
        }
        .task {
            await loadExampleTemplates()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Automation Runner")
                    .font(.largeTitle.weight(.semibold))
                Text("Monitor schedules, connected accounts, recent runs, and synced posts from this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 20)

            HStack(spacing: 18) {
                MacAutomationMetric(title: "Active", value: snapshot.activeCount.formatted())
                MacAutomationMetric(title: "Running", value: snapshot.activeProgresses.count.formatted())
                MacAutomationMetric(title: "Posts", value: snapshot.postCount.formatted())
                MacAutomationMetric(
                    title: "Next",
                    value: AutomationDashboardFormatting.relativeDate(snapshot.nextPostAt)
                )
            }
        }
    }

    private var automationGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 320, maximum: 420), spacing: 16, alignment: .top)],
            alignment: .leading,
            spacing: 16
        ) {
            ForEach(snapshot.items) { item in
                NavigationLink {
                    MacAutomationDetailView(
                        automationID: item.id,
                        exampleTemplates: exampleTemplates
                    )
                } label: {
                    MacAutomationCard(item: item)
                }
                .buttonStyle(.plain)
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

struct MacAutomationInProgressSection: View {
    var progresses: [AutomationPostProgress]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("In Progress")
                    .font(.title2.weight(.semibold))
                Text(progresses.count == 1 ? "1 post being made" : "\(progresses.count) posts being made")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 360, maximum: 520), spacing: 16, alignment: .top)],
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(progresses) { progress in
                    MacAutomationInProgressCard(progress: progress)
                }
            }
        }
    }
}

struct MacAutomationInProgressCard: View {
    var progress: AutomationPostProgress

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            AutomationPostSkeletonShimmer()
                .frame(width: 86, height: 148)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        StatusBadge(
                            title: "In Progress",
                            tint: .blue,
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                        Text(progress.title)
                            .font(.headline)
                            .lineLimit(2)
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 8)

                    Text("\(progress.currentStepIndex)/\(max(progress.totalCount, 1))")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if let currentStep = progress.currentStep {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(currentStep.title, systemImage: currentStep.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(currentStep.state.tint)
                        Text(currentStep.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        if currentStep.hasImageProgress {
                            AutomationImageProgressDetailRow(step: currentStep)
                        }
                    }
                }

                ProgressView(value: progress.progressFraction)
                    .progressViewStyle(.linear)

                AutomationProgressStepStrip(steps: progress.steps)

                HStack(spacing: 10) {
                    AutomationProgressPlatformSummary(
                        platforms: progress.normalizedTargetPlatforms,
                        font: .caption2
                    )
                    if let productName = progress.productName, !productName.isEmpty {
                        Label(productName, systemImage: "shippingbox")
                    }
                    if let templateTitle = progress.templateTitle, !templateTitle.isEmpty {
                        Label(templateTitle, systemImage: "rectangle.stack")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
            .layoutPriority(1)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.blue.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MacAutomationMetric: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .lineLimit(1)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MacAutomationEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No automations yet")
                .font(.title3.weight(.semibold))
            Text("Create automations on iOS, then keep this Mac running to publish on schedule and sync results back through CloudKit.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: 460, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 36))
        .overlay {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct MacAutomationCard: View {
    var item: AutomationDashboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.automation.status == .active ? "calendar.badge.clock" : "pause.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(item.automation.status.tint)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.displayName)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(item.accountPlatformSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .layoutPriority(1)

                Spacer(minLength: 8)

                DashboardStatusIcon(
                    title: item.automation.status.displayName,
                    tint: item.automation.status.tint,
                    systemImage: item.automation.status.systemImage
                )
            }

            HStack(spacing: 10) {
                MacAutomationCardStat(
                    title: "Posts",
                    value: item.postCount.formatted(),
                    systemImage: "photo.stack"
                )
                MacAutomationCardStat(
                    title: "Next",
                    value: AutomationDashboardFormatting.relativeDate(item.nextScheduledAt),
                    systemImage: "clock"
                )
                MacAutomationCardStat(
                    title: "Previous",
                    value: AutomationDashboardFormatting.relativeDate(item.previousPostedAt),
                    systemImage: "arrow.counterclockwise"
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(item.scheduleSummary, systemImage: "calendar")
                if let productName = item.productName {
                    Label(productName, systemImage: "shippingbox")
                }
                if item.awaitingDraftUploadCount > 0 {
                    Label("\(item.awaitingDraftUploadCount) awaiting TikTok", systemImage: "bell.badge")
                        .foregroundStyle(.orange)
                }
                if !item.activeProgresses.isEmpty {
                    Label(
                        item.activeProgresses.count == 1 ? "1 post in progress" : "\(item.activeProgresses.count) posts in progress",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .foregroundStyle(.blue)
                }
                if let lastErrorMessage = item.automation.lastErrorMessage, !lastErrorMessage.isEmpty {
                    Label(lastErrorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minHeight: 236, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 36))
        .overlay {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .contentShape(.rect(cornerRadius: 36))
        .accessibilityElement(children: .combine)
    }
}

private struct MacAutomationCardStat: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
