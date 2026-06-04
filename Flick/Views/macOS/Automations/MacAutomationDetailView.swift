//
//  MacAutomationDetailView.swift
//  Flick
//

#if os(macOS)
import SwiftUI

struct MacAutomationDetailView: View {
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        MacAutomationDetailHeader(item: item)
                        if !item.activeProgresses.isEmpty {
                            MacAutomationInProgressSection(progresses: item.activeProgresses)
                        }
                        MacAutomationDetailPosts(item: item, exampleTemplates: exampleTemplates)
                        MacAutomationDetailRuns(item: item)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .flickAppBackground()
                .navigationTitle(item.displayName)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("Refresh", systemImage: "arrow.clockwise") {
                            Task { await appModel.refresh() }
                        }
                        Button("Run", systemImage: "play.fill") {
                            runNow()
                        }
                        .disabled(appModel.isProcessingAutomations || !item.activeProgresses.isEmpty)
                        Button(
                            item.automation.status == .active ? "Pause" : "Resume",
                            systemImage: item.automation.status == .active ? "pause.circle" : "play.circle"
                        ) {
                            updateStatus(to: item.automation.status == .active ? .paused : .active)
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            isDeleteConfirmationPresented = true
                        }
                    }
                }
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

    private func updateStatus(to status: ContentAutomationStatus) {
        Task {
            await appModel.updateAutomationStatus(id: automationID, status: status)
        }
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

private struct MacAutomationDetailHeader: View {
    var item: AutomationDashboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    StatusBadge(
                        title: item.automation.status.displayName,
                        tint: item.automation.status.tint,
                        systemImage: item.automation.status.systemImage
                    )
                    Text(item.displayName)
                        .font(.largeTitle.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.accountPlatformSummary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)

                Spacer(minLength: 20)

                VStack(alignment: .trailing, spacing: 10) {
                    MacAutomationHeaderMetric(title: "Posts", value: item.postCount.formatted())
                    MacAutomationHeaderMetric(title: "Failures", value: item.automation.consecutiveFailureCount.formatted())
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), spacing: 12, alignment: .top)],
                alignment: .leading,
                spacing: 12
            ) {
                MacAutomationDetailValue(
                    title: "Schedule",
                    value: item.scheduleSummary,
                    systemImage: "calendar",
                    tint: .teal
                )
                MacAutomationDetailValue(
                    title: "Next post",
                    value: AutomationDashboardFormatting.absoluteDate(item.nextScheduledAt),
                    systemImage: "clock",
                    tint: .orange
                )
                MacAutomationDetailValue(
                    title: "Previous post",
                    value: AutomationDashboardFormatting.absoluteDate(item.previousPostedAt),
                    systemImage: "arrow.counterclockwise",
                    tint: .secondary
                )
                MacAutomationDetailValue(
                    title: "Platforms",
                    value: item.targetPlatformSummary,
                    systemImage: "paperplane",
                    tint: .blue
                )
                if let productName = item.productName {
                    MacAutomationDetailValue(
                        title: "Product",
                        value: productName,
                        systemImage: "shippingbox",
                        tint: .orange
                    )
                }
                if let creationModelName = item.creationModelName {
                    MacAutomationDetailValue(
                        title: "Model",
                        value: creationModelName,
                        systemImage: "person.crop.square",
                        tint: .purple
                    )
                }
            }

            if let lastErrorMessage = item.automation.lastErrorMessage, !lastErrorMessage.isEmpty {
                Label(lastErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.1), in: .rect(cornerRadius: 12))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
    }
}

private struct MacAutomationHeaderMetric: View {
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

private struct MacAutomationDetailValue: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct MacAutomationDetailPosts: View {
    var item: AutomationDashboardItem
    var exampleTemplates: [ExampleSlideshowTemplate]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MacSectionHeader(
                title: "Posts",
                subtitle: AutomationDashboardFormatting.postCount(item.postCount)
            )

            if item.postPreviews.isEmpty {
                MacAutomationInlineEmptyState(
                    title: "No posts from this automation yet",
                    message: "Created posts will appear here with their current TikTok status."
                )
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 14, alignment: .top)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(item.postPreviews) { preview in
                        NavigationLink {
                            MacAutomationPostDetailView(
                                automationID: item.id,
                                previewID: preview.id,
                                exampleTemplates: exampleTemplates
                            )
                        } label: {
                            MacAutomationPostCard(preview: preview)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct MacAutomationPostCard: View {
    var preview: AutomationPostPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VerticalMediaFrame(
                fileURL: preview.thumbnailAsset?.localFileURL,
                remoteURL: preview.thumbnailAsset?.publicURL,
                cornerRadius: 12,
                maxPixelSize: 720
            )
            .frame(height: 190)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text(preview.displayTitle)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                Text(preview.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Label(preview.status.displayName, systemImage: preview.status.systemImage)
                        .foregroundStyle(preview.status.tint)
                    Text(AutomationDashboardFormatting.absoluteDate(preview.timelineDate))
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
                .lineLimit(1)
            }
        }
        .padding(14)
        .background(.thinMaterial, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
        .contentShape(.rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

private struct MacAutomationDetailRuns: View {
    var item: AutomationDashboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MacSectionHeader(title: "Runner", subtitle: "Current automation state")

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), spacing: 12, alignment: .top)],
                alignment: .leading,
                spacing: 12
            ) {
                MacAutomationDetailValue(
                    title: "Awaiting action",
                    value: item.awaitingDraftUploadCount.formatted(),
                    systemImage: "bell.badge",
                    tint: .orange
                )
                MacAutomationDetailValue(
                    title: "Failed jobs",
                    value: item.failedJobCount.formatted(),
                    systemImage: "xmark.octagon",
                    tint: .red
                )
                MacAutomationDetailValue(
                    title: "Updated",
                    value: AutomationDashboardFormatting.absoluteDate(item.automation.updatedAt),
                    systemImage: "arrow.triangle.2.circlepath",
                    tint: .secondary
                )
                MacAutomationDetailValue(
                    title: "Created",
                    value: AutomationDashboardFormatting.absoluteDate(item.automation.createdAt),
                    systemImage: "plus.circle",
                    tint: .secondary
                )
            }
            .padding(18)
            .background(.thinMaterial, in: .rect(cornerRadius: 18))
        }
    }
}

private struct MacSectionHeader: View {
    var title: String
    var subtitle: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MacAutomationInlineEmptyState: View {
    var title: String
    var message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 18))
    }
}

private struct MacAutomationPostDetailView: View {
    @Environment(FlickAppModel.self) private var appModel

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
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        postHeader(for: preview)
                        slidesGrid(for: preview)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .flickAppBackground()
                .navigationTitle(preview.displayTitle)
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

    private func postHeader(for preview: AutomationPostPreview) -> some View {
        HStack(alignment: .top, spacing: 24) {
            VerticalMediaFrame(
                fileURL: preview.thumbnailAsset?.localFileURL,
                remoteURL: preview.thumbnailAsset?.publicURL,
                cornerRadius: 18,
                maxPixelSize: 1_080
            )
            .frame(width: 240)

            VStack(alignment: .leading, spacing: 16) {
                Text(preview.displayTitle)
                    .font(.largeTitle.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190), spacing: 12, alignment: .top)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    MacAutomationDetailValue(
                        title: "Platform",
                        value: preview.platform.displayName,
                        systemImage: preview.platform.systemImage,
                        tint: preview.platform.tint
                    )
                    MacAutomationDetailValue(
                        title: "Account",
                        value: preview.accountName ?? "Unknown",
                        systemImage: "person.crop.circle",
                        tint: .blue
                    )
                    MacAutomationDetailValue(
                        title: "Status",
                        value: preview.status.displayName,
                        systemImage: preview.status.systemImage,
                        tint: preview.status.tint
                    )
                    MacAutomationDetailValue(
                        title: "Created",
                        value: AutomationDashboardFormatting.absoluteDate(preview.createdAt),
                        systemImage: "plus.circle",
                        tint: .secondary
                    )
                    MacAutomationDetailValue(
                        title: "Updated",
                        value: AutomationDashboardFormatting.absoluteDate(preview.updatedAt),
                        systemImage: "arrow.triangle.2.circlepath",
                        tint: .secondary
                    )
                    if let publishedAt = preview.publishedAt {
                        MacAutomationDetailValue(
                            title: "Published",
                            value: AutomationDashboardFormatting.absoluteDate(publishedAt),
                            systemImage: "clock",
                            tint: .green
                        )
                    }
                    if let platformPostID = preview.platformPostID?.trimmingCharacters(in: .whitespacesAndNewlines), !platformPostID.isEmpty {
                        MacAutomationDetailValue(
                            title: "Platform ID",
                            value: platformPostID,
                            systemImage: "number",
                            tint: .secondary
                        )
                    }
                }

                if let failure = preview.lastError {
                    Label(failure.message, systemImage: "xmark.octagon")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    if let platformURL = preview.platformURL {
                        Link(destination: platformURL) {
                            Label(platformURL.host ?? platformURL.absoluteString, systemImage: "arrow.up.forward.app")
                        }
                    }

                    if let draft = preview.draft {
                        Button(
                            draft.isAvailableInCreateDrafts ? "Open Draft" : "Duplicate to Repost",
                            systemImage: draft.isAvailableInCreateDrafts ? "square.and.pencil" : "plus.square.on.square"
                        ) {
                            openDraftForRepost(draft)
                        }
                    }
                }
            }
            .layoutPriority(1)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 24))
    }

    private func slidesGrid(for preview: AutomationPostPreview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            MacSectionHeader(title: "Slides", subtitle: "\(slides(for: preview).count.formatted()) synced")

            if slides(for: preview).isEmpty {
                MacAutomationInlineEmptyState(
                    title: "No local slide detail",
                    message: "This post is synced, but its generated draft slides are not available on this device."
                )
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 14, alignment: .top)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(slides(for: preview)) { slide in
                        MacAutomationSlideTile(
                            slide: slide,
                            asset: slide.imageAssetID.flatMap { previewAssetByID($0) }
                        )
                    }
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
    }
}

private struct MacAutomationSlideTile: View {
    var slide: Slide
    var asset: MediaAsset?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VerticalMediaFrame(
                fileURL: asset?.localFileURL,
                remoteURL: asset?.publicURL,
                cornerRadius: 12,
                maxPixelSize: 720
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("Slide \(slide.index + 1)")
                    .font(.caption.weight(.semibold))
                Text(slide.text.isEmpty ? slide.prompt : slide.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
#endif
