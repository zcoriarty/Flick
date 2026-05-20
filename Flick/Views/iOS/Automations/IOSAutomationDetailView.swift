//
//  IOSAutomationDetailView.swift
//  Flick
//

#if !os(macOS)
import SwiftUI

struct IOSAutomationDetailView: View {
    @Environment(FlickAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var isDeleteConfirmationPresented = false

    var automationID: UUID
    var exampleTemplates: [ExampleSlideshowTemplate]

    private var item: AutomationDashboardItem? {
        AutomationDashboardSnapshot
            .make(overview: appModel.overview, exampleTemplates: exampleTemplates)
            .items
            .first { $0.id == automationID }
    }

    var body: some View {
        Group {
            if let item {
                List {
                    overviewSection(for: item)
                    if !item.activeProgresses.isEmpty {
                        inProgressSection(for: item)
                    }
                    manageSection(for: item)
                    scheduleSection(for: item)
                    postsSection(for: item)
                    runsSection(for: item)
                }
                .flickSettingsListStyle()
                .refreshable {
                    await appModel.refresh()
                }
                .flickToolbarTitle(item.displayName)
                .confirmationDialog("Delete automation?", isPresented: $isDeleteConfirmationPresented) {
                    Button("Delete Automation", role: .destructive) {
                        deleteAutomation()
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This removes the automation schedule. Existing drafts and published post records are kept.")
                }
            } else {
                ContentUnavailableView(
                    "Automation unavailable",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("This automation may have been deleted on another device.")
                )
                .flickAppBackground()
            }
        }
    }

    private func manageSection(for item: AutomationDashboardItem) -> some View {
        Section("Manage") {
            Button {
                runNow()
            } label: {
                FlickSettingsRowLabel(
                    title: "Run Now",
                    systemImage: "play.fill",
                    iconColor: .blue,
                    value: runNowValue(for: item),
                    valueLineLimit: 1
                )
            }
            .buttonStyle(.plain)
            .disabled(appModel.isProcessingAutomations || !item.activeProgresses.isEmpty)

            Button {
                updateStatus(to: item.automation.status == .active ? .paused : .active)
            } label: {
                FlickSettingsRowLabel(
                    title: item.automation.status == .active ? "Pause Automation" : "Resume Automation",
                    systemImage: item.automation.status == .active ? "pause.circle" : "play.circle",
                    iconColor: item.automation.status == .active ? .orange : .green,
                    value: item.automation.status == .active ? "Stop scheduled runs" : "Schedule next run",
                    valueLineLimit: 1
                )
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                isDeleteConfirmationPresented = true
            } label: {
                FlickSettingsRowLabel(
                    title: "Delete Automation",
                    systemImage: "trash",
                    iconColor: .red,
                    value: "Remove schedule",
                    valueLineLimit: 1
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func inProgressSection(for item: AutomationDashboardItem) -> some View {
        Section("In Progress") {
            ForEach(item.activeProgresses) { progress in
                AutomationProgressSummaryRow(progress: progress)
            }
        }
    }

    private func overviewSection(for item: AutomationDashboardItem) -> some View {
        Section("Automation") {
            FlickSettingsValueRow(
                title: "Status",
                systemImage: item.automation.status == .active ? "calendar.badge.clock" : "pause.circle",
                iconColor: item.automation.status.tint,
                value: item.automation.status.displayName
            )
            FlickSettingsValueRow(
                title: "Posts",
                systemImage: "photo.stack",
                iconColor: .green,
                value: item.postCount.formatted()
            )
            FlickSettingsValueRow(
                title: "Accounts",
                systemImage: "person.2",
                iconColor: .blue,
                value: item.accountPlatformSummary,
                valueLineLimit: 3
            )
            FlickSettingsValueRow(
                title: "Platforms",
                systemImage: "paperplane",
                iconColor: .teal,
                value: item.targetPlatformSummary,
                valueLineLimit: 2
            )
            if let productName = item.productName {
                FlickSettingsValueRow(
                    title: "Product",
                    systemImage: "shippingbox",
                    iconColor: .orange,
                    value: productName,
                    valueLineLimit: 2
                )
            }
            if let creationModelName = item.creationModelName {
                FlickSettingsValueRow(
                    title: "Model",
                    systemImage: "person.crop.square",
                    iconColor: .purple,
                    value: creationModelName,
                    valueLineLimit: 2
                )
            }
        }
    }

    private func scheduleSection(for item: AutomationDashboardItem) -> some View {
        Section("Schedule") {
            FlickSettingsValueRow(
                title: "Cadence",
                systemImage: "calendar",
                iconColor: .teal,
                value: item.scheduleSummary,
                valueLineLimit: 2
            )
            FlickSettingsValueRow(
                title: "Next post",
                systemImage: "clock",
                iconColor: .orange,
                value: AutomationDashboardFormatting.absoluteDate(item.nextScheduledAt),
                valueLineLimit: 2
            )
            FlickSettingsValueRow(
                title: "Previous post",
                systemImage: "arrow.counterclockwise",
                iconColor: .secondary,
                value: AutomationDashboardFormatting.absoluteDate(item.previousPostedAt),
                valueLineLimit: 2
            )
            if item.automation.consecutiveFailureCount > 0 {
                FlickSettingsNavigationRow(
                    title: "Failures",
                    systemImage: "exclamationmark.triangle",
                    iconColor: .orange,
                    value: item.automation.consecutiveFailureCount.formatted()
                ) {
                    IOSAutomationFailuresView(
                        automationID: item.id,
                        exampleTemplates: exampleTemplates
                    )
                }
            }
            if let lastErrorMessage = item.automation.lastErrorMessage, !lastErrorMessage.isEmpty {
                DashboardMessageRow(
                    title: "Last error",
                    message: lastErrorMessage,
                    systemImage: "exclamationmark.triangle",
                    iconColor: .orange
                )
            }
        }
    }

    private func postsSection(for item: AutomationDashboardItem) -> some View {
        Section("Posts") {
            if item.postPreviews.isEmpty {
                DashboardMessageRow(
                    title: "No posts from this automation yet",
                    message: "Created posts will appear here with their current TikTok status.",
                    systemImage: "photo.stack",
                    iconColor: .secondary
                )
            } else {
                ForEach(item.postPreviews) { preview in
                    NavigationLink {
                        IOSAutomationPostDetailView(
                            automationID: item.id,
                            previewID: preview.id,
                            exampleTemplates: exampleTemplates
                        )
                    } label: {
                        IOSAutomationPostRow(preview: preview)
                    }
                }
            }
        }
    }

    private func runsSection(for item: AutomationDashboardItem) -> some View {
        Section("Runs") {
            FlickSettingsValueRow(
                title: "Awaiting TikTok",
                systemImage: "bell.badge",
                iconColor: .orange,
                value: item.awaitingDraftUploadCount.formatted()
            )
            if item.failedJobCount > 0 {
                FlickSettingsNavigationRow(
                    title: "Failed jobs",
                    systemImage: "xmark.octagon",
                    iconColor: .red,
                    value: item.failedJobCount.formatted()
                ) {
                    IOSAutomationFailuresView(
                        automationID: item.id,
                        exampleTemplates: exampleTemplates
                    )
                }
            } else {
                FlickSettingsValueRow(
                    title: "Failed jobs",
                    systemImage: "xmark.octagon",
                    iconColor: .red,
                    value: item.failedJobCount.formatted()
                )
            }
            FlickSettingsValueRow(
                title: "Updated",
                systemImage: "arrow.triangle.2.circlepath",
                iconColor: .secondary,
                value: AutomationDashboardFormatting.absoluteDate(item.automation.updatedAt),
                valueLineLimit: 2
            )
        }
    }

    private func updateStatus(to status: ContentAutomationStatus) {
        Task {
            await appModel.updateAutomationStatus(id: automationID, status: status)
        }
    }

    private func runNowValue(for item: AutomationDashboardItem) -> String {
        if !item.activeProgresses.isEmpty {
            return "Running on Mac..."
        }
        if appModel.isProcessingAutomations {
            return "Running..."
        }
        return "Bypass schedule once"
    }

    private func runNow() {
        Task {
            await appModel.runAutomationNow(id: automationID)
        }
    }

    private func deleteAutomation() {
        Task {
            await appModel.deleteAutomation(id: automationID)
            dismiss()
        }
    }
}

private struct IOSAutomationPostRow: View {
    var preview: AutomationPostPreview

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VerticalMediaFrame(
                fileURL: preview.thumbnailAsset?.localFileURL,
                remoteURL: preview.thumbnailAsset?.publicURL,
                cornerRadius: 8,
                maxPixelSize: 360
            )
            .frame(width: 52)

            VStack(alignment: .leading, spacing: 5) {
                Text(preview.displayTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(preview.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(AutomationDashboardFormatting.relativeDate(preview.timelineDate))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            StatusBadge(
                title: preview.status.displayName,
                tint: preview.status.tint,
                systemImage: preview.status.systemImage
            )
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct IOSAutomationPostDetailView: View {
    @Environment(FlickAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    var automationID: UUID
    var previewID: UUID
    var exampleTemplates: [ExampleSlideshowTemplate]

    private var preview: AutomationPostPreview? {
        AutomationDashboardSnapshot
            .make(overview: appModel.overview, exampleTemplates: exampleTemplates)
            .items
            .first { $0.id == automationID }?
            .postPreviews
            .first { $0.id == previewID }
    }

    var body: some View {
        Group {
            if let preview {
                List {
                    previewSection(for: preview)
                    detailsSection(for: preview)
                    actionsSection(for: preview)
                    slidesSection(for: preview)
                }
                .flickSettingsListStyle()
                .flickToolbarTitle(preview.displayTitle)
            } else {
                ContentUnavailableView(
                    "Post unavailable",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("This post may have been deleted on another device.")
                )
                .flickAppBackground()
            }
        }
    }

    private func previewSection(for preview: AutomationPostPreview) -> some View {
        Section {
            HStack {
                Spacer(minLength: 0)
                VerticalMediaFrame(
                    fileURL: preview.thumbnailAsset?.localFileURL,
                    remoteURL: preview.thumbnailAsset?.publicURL,
                    cornerRadius: 14,
                    maxPixelSize: 720
                )
                .frame(maxWidth: 180)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
        }
    }

    private func detailsSection(for preview: AutomationPostPreview) -> some View {
        Section("Details") {
            FlickSettingsValueRow(
                title: "Platform",
                systemImage: preview.platform.systemImage,
                iconColor: preview.platform.tint,
                value: preview.platform.displayName
            )
            FlickSettingsValueRow(
                title: "Account",
                systemImage: "person.crop.circle",
                iconColor: .blue,
                value: preview.accountName ?? "Unknown"
            )
            FlickSettingsValueRow(
                title: "Status",
                systemImage: preview.status.systemImage,
                iconColor: preview.status.tint,
                value: preview.status.displayName
            )
            FlickSettingsValueRow(
                title: "Created",
                systemImage: "plus.circle",
                iconColor: .secondary,
                value: AutomationDashboardFormatting.absoluteDate(preview.createdAt),
                valueLineLimit: 2
            )
            FlickSettingsValueRow(
                title: "Updated",
                systemImage: "arrow.triangle.2.circlepath",
                iconColor: .secondary,
                value: AutomationDashboardFormatting.absoluteDate(preview.updatedAt),
                valueLineLimit: 2
            )
            if let publishedAt = preview.publishedAt {
                FlickSettingsValueRow(
                    title: "Published",
                    systemImage: "clock",
                    iconColor: .green,
                    value: AutomationDashboardFormatting.absoluteDate(publishedAt),
                    valueLineLimit: 2
                )
            }
            if let platformPostID = preview.platformPostID?.trimmingCharacters(in: .whitespacesAndNewlines), !platformPostID.isEmpty {
                FlickSettingsValueRow(
                    title: "Platform ID",
                    systemImage: "number",
                    iconColor: .secondary,
                    value: platformPostID,
                    valueLineLimit: 2
                )
            }
            if let failure = preview.lastError {
                DashboardMessageRow(
                    title: "Failure",
                    message: failure.message,
                    systemImage: "xmark.octagon",
                    iconColor: .red
                )
            }
            if let platformURL = preview.platformURL {
                Link(destination: platformURL) {
                    FlickSettingsRowLabel(
                        title: "Open post",
                        systemImage: "arrow.up.forward.app",
                        iconColor: .blue,
                        value: platformURL.host ?? platformURL.absoluteString,
                        valueLineLimit: 1,
                        showsChevron: true
                    )
                }
            }
        }
    }

    private func actionsSection(for preview: AutomationPostPreview) -> some View {
        Section("Actions") {
            if let draft = preview.draft {
                Button {
                    openDraftForRepost(draft)
                } label: {
                    FlickSettingsRowLabel(
                        title: draft.isAvailableInCreateDrafts ? "Open Draft" : "Duplicate to Repost",
                        systemImage: draft.isAvailableInCreateDrafts ? "square.and.pencil" : "plus.square.on.square",
                        iconColor: .blue,
                        value: draft.isAvailableInCreateDrafts ? "Use this generated post" : "Reuse generated images",
                        valueLineLimit: 1
                    )
                }
                .buttonStyle(.plain)
            } else {
                DashboardMessageRow(
                    title: "Draft unavailable",
                    message: "The generated draft for this post is not available on this device.",
                    systemImage: "photo.badge.exclamationmark",
                    iconColor: .secondary
                )
            }
        }
    }

    private func slidesSection(for preview: AutomationPostPreview) -> some View {
        Section("Slides") {
            if slides(for: preview).isEmpty {
                DashboardMessageRow(
                    title: "No local slide detail",
                    message: "This post is synced, but its generated draft slides are not available on this device.",
                    systemImage: "photo.stack",
                    iconColor: .secondary
                )
            } else {
                ForEach(slides(for: preview)) { slide in
                    IOSAutomationPostSlideRow(
                        slide: slide,
                        asset: slide.imageAssetID.flatMap { previewAssetByID($0) }
                    )
                }
            }
        }
    }

    private func slides(for preview: AutomationPostPreview) -> [Slide] {
        preview.draft?.slides.sorted { $0.index < $1.index } ?? []
    }

    private func previewAssetByID(_ id: UUID) -> MediaAsset? {
        appModel.overview.assets.first { $0.id == id }
    }

    private func openDraftForRepost(_ draft: SlideshowDraft) {
        if draft.isAvailableInCreateDrafts {
            appModel.selectCreateDraft(id: draft.id)
        } else {
            appModel.duplicateDraft(draft)
        }
        dismiss()
    }
}

private struct IOSAutomationPostSlideRow: View {
    var slide: Slide
    var asset: MediaAsset?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VerticalMediaFrame(
                fileURL: asset?.localFileURL,
                remoteURL: asset?.publicURL,
                cornerRadius: 8,
                maxPixelSize: 360
            )
            .frame(width: 52)

            VStack(alignment: .leading, spacing: 5) {
                Text("Slide \(slide.index + 1)")
                    .font(.body.weight(.semibold))
                Text(slide.text.isEmpty ? slide.prompt : slide.text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .layoutPriority(1)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
#endif
