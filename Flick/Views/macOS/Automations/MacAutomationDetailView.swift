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
                        MacAutomationDetailPosts(item: item)
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
                        .disabled(appModel.isProcessingAutomations)
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
                    MacAutomationHeaderMetric(title: "Posts", value: item.publishedPosts.count.formatted())
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MacSectionHeader(
                title: "Posts",
                subtitle: AutomationDashboardFormatting.postCount(item.publishedPosts.count)
            )

            if item.postPreviews.isEmpty {
                MacAutomationInlineEmptyState(
                    title: "No posts from this automation yet",
                    message: "Published posts will appear here after the runner completes an automation."
                )
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 14, alignment: .top)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(item.postPreviews) { preview in
                        NavigationLink {
                            MacAutomationPostDetailView(postID: preview.post.id)
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
                Text(AutomationDashboardFormatting.absoluteDate(preview.post.publishedAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
                    title: "Awaiting TikTok",
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

    var postID: UUID

    private var post: PublishedPost? {
        appModel.overview.publishedPosts.first { $0.id == postID }
    }

    private var assetsByID: [UUID: MediaAsset] {
        Dictionary(uniqueKeysWithValues: appModel.overview.assets.map { ($0.id, $0) })
    }

    var body: some View {
        Group {
            if let post {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        postHeader(for: post)
                        slidesGrid(for: post)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .flickAppBackground()
                .navigationTitle(postTitle(for: post))
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

    private func postHeader(for post: PublishedPost) -> some View {
        HStack(alignment: .top, spacing: 24) {
            VerticalMediaFrame(
                fileURL: previewAsset(for: post)?.localFileURL,
                remoteURL: previewAsset(for: post)?.publicURL,
                cornerRadius: 18,
                maxPixelSize: 1_080
            )
            .frame(width: 240)

            VStack(alignment: .leading, spacing: 16) {
                Text(postTitle(for: post))
                    .font(.largeTitle.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190), spacing: 12, alignment: .top)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    MacAutomationDetailValue(
                        title: "Platform",
                        value: post.platform.displayName,
                        systemImage: post.platform.systemImage,
                        tint: post.platform.tint
                    )
                    MacAutomationDetailValue(
                        title: "Account",
                        value: accountName(for: post) ?? "Unknown",
                        systemImage: "person.crop.circle",
                        tint: .blue
                    )
                    MacAutomationDetailValue(
                        title: "Published",
                        value: AutomationDashboardFormatting.absoluteDate(post.publishedAt),
                        systemImage: "clock",
                        tint: .green
                    )
                    MacAutomationDetailValue(
                        title: "Post ID",
                        value: post.platformPostID,
                        systemImage: "number",
                        tint: .secondary
                    )
                }

                if let platformURL = post.platformURL {
                    Link(destination: platformURL) {
                        Label(platformURL.host ?? platformURL.absoluteString, systemImage: "arrow.up.forward.app")
                    }
                }
            }
            .layoutPriority(1)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 24))
    }

    private func slidesGrid(for post: PublishedPost) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            MacSectionHeader(title: "Slides", subtitle: "\(slides(for: post).count.formatted()) synced")

            if slides(for: post).isEmpty {
                MacAutomationInlineEmptyState(
                    title: "No local slide detail",
                    message: "The post is synced, but its generated draft slides are not available on this device."
                )
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 14, alignment: .top)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(slides(for: post)) { slide in
                        MacAutomationSlideTile(
                            slide: slide,
                            asset: slide.imageAssetID.flatMap { assetsByID[$0] }
                        )
                    }
                }
            }
        }
    }

    private func postTitle(for post: PublishedPost) -> String {
        let caption = post.caption.trimmingCharacters(in: .whitespacesAndNewlines)
        return caption.isEmpty ? "\(post.platform.displayName) post" : caption
    }

    private func accountName(for post: PublishedPost) -> String? {
        appModel.overview.accounts.first { $0.id == post.accountID }?.displayName
    }

    private func draft(for post: PublishedPost) -> SlideshowDraft? {
        appModel.overview.drafts.first { $0.id == post.draftID }
    }

    private func slides(for post: PublishedPost) -> [Slide] {
        draft(for: post)?.slides.sorted { $0.index < $1.index } ?? []
    }

    private func previewAsset(for post: PublishedPost) -> MediaAsset? {
        guard let draft = draft(for: post) else { return nil }

        if let asset = draft.exportedImageAssetIDs.compactMap({ assetsByID[$0] }).first {
            return asset
        }

        return slides(for: post)
            .compactMap(\.imageAssetID)
            .compactMap { assetsByID[$0] }
            .first
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
