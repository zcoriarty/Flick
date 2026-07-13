//
//  IOSAutomationFailuresView.swift
//  Flick
//

#if !os(macOS)
import SwiftUI

struct IOSAutomationFailuresView: View {
    @Environment(FlickAppModel.self) private var appModel
    @State private var isRetryConfirmationPresented = false
    @State private var isRetrying = false
    @State private var retryResult: PublishingRetrySummary?

    var automationID: UUID
    var exampleTemplates: [ExampleSlideshowTemplate]

    private var item: AutomationDashboardItem? {
        AutomationDashboardSnapshot
            .make(overview: appModel.overview, exampleTemplates: exampleTemplates)
            .items
            .first { $0.id == automationID }
    }

    private var assetsByID: [UUID: MediaAsset] {
        Dictionary(uniqueKeysWithValues: appModel.overview.assets.map { ($0.id, $0) })
    }

    var body: some View {
        Group {
            if let item {
                List {
                    summarySection(for: item)
                    productImagesSection(for: item)
                    failedJobsSection(for: item)
                }
                .flickSettingsListStyle()
                .flickToolbarTitle("Failures")
                .confirmationDialog(
                    "Retry all failed posts?",
                    isPresented: $isRetryConfirmationPresented,
                    titleVisibility: .visible
                ) {
                    Button("Retry \(failedJobs(for: item).count) Failed Post\(failedJobs(for: item).count == 1 ? "" : "s")") {
                        retryAllFailures()
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("Flick will inspect each saved post, reuse existing rendered files, repair only missing Cloudflare uploads, check any prior platform submission, and resume from the first incomplete step. It will not regenerate AI images.")
                }
                .alert("Retry finished", isPresented: retryResultBinding) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(retryResult?.message ?? "")
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

    private func summarySection(for item: AutomationDashboardItem) -> some View {
        Section("Summary") {
            Button {
                isRetryConfirmationPresented = true
            } label: {
                FlickSettingsRowLabel(
                    title: isRetrying ? "Retrying Failed Posts" : "Retry All Failed Posts",
                    systemImage: isRetrying ? "arrow.clockwise" : "arrow.clockwise.circle.fill",
                    iconColor: .blue,
                    value: isRetrying ? "Checking media and publishing…" : "Repair media and publish again",
                    valueLineLimit: 2
                )
            }
            .buttonStyle(.plain)
            .disabled(failedJobs(for: item).isEmpty || isRetrying || appModel.isPublishingSlideshow)

            FlickSettingsValueRow(
                title: "Consecutive failures",
                systemImage: "exclamationmark.triangle",
                iconColor: .orange,
                value: item.automation.consecutiveFailureCount.formatted()
            )
            FlickSettingsValueRow(
                title: "Failed jobs",
                systemImage: "xmark.octagon",
                iconColor: .red,
                value: item.failedJobCount.formatted()
            )
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

    private func productImagesSection(for item: AutomationDashboardItem) -> some View {
        let productImageAssets = productImageAssets(for: item)
        let missingImageIDs = missingProductImageIDs(for: item)

        return Section("Selected Product Images") {
            if productImageAssets.isEmpty && missingImageIDs.isEmpty {
                DashboardMessageRow(
                    title: "No selected product images",
                    message: "This automation does not have product image records attached.",
                    systemImage: "photo.badge.exclamationmark",
                    iconColor: .secondary
                )
            } else {
                if !productImageAssets.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(Array(productImageAssets.enumerated()), id: \.element.id) { offset, asset in
                                IOSAutomationFailureImageTile(
                                    title: "Image \(offset + 1)",
                                    subtitle: imageAvailabilityText(for: asset),
                                    asset: asset
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 0))
                }

                ForEach(missingImageIDs, id: \.self) { imageID in
                    DashboardMessageRow(
                        title: "Missing image record",
                        message: imageID.uuidString,
                        systemImage: "photo.badge.exclamationmark",
                        iconColor: .orange
                    )
                }
            }
        }
    }

    private func failedJobsSection(for item: AutomationDashboardItem) -> some View {
        let failedJobs = failedJobs(for: item)

        return Section("Failed Publish Jobs") {
            if failedJobs.isEmpty {
                DashboardMessageRow(
                    title: "No failed publish jobs",
                    message: "The latest failure happened before Flick created a TikTok publish job.",
                    systemImage: "xmark.octagon",
                    iconColor: .secondary
                )
            } else {
                ForEach(failedJobs) { job in
                    IOSAutomationFailureJobRow(
                        job: job,
                        slides: slides(for: job),
                        assetsByID: assetsByID
                    )
                }
            }
        }
    }

    private func productImageAssets(for item: AutomationDashboardItem) -> [MediaAsset] {
        item.automation.productImageAssetIDs.compactMap { assetsByID[$0] }
    }

    private func missingProductImageIDs(for item: AutomationDashboardItem) -> [UUID] {
        item.automation.productImageAssetIDs.filter { assetsByID[$0] == nil }
    }

    private func failedJobs(for item: AutomationDashboardItem) -> [PublishingJob] {
        item.publishingJobs
            .filter { $0.status == .failed }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func draft(for job: PublishingJob) -> SlideshowDraft? {
        appModel.overview.drafts.first { $0.id == job.draftID }
    }

    private func slides(for job: PublishingJob) -> [Slide] {
        draft(for: job)?.slides.sorted { $0.index < $1.index } ?? []
    }

    private func imageAvailabilityText(for asset: MediaAsset) -> String {
        if asset.localFileURL != nil {
            return "Local file"
        }
        if asset.publicURL != nil {
            return "Public URL"
        }
        return "Unreadable"
    }
}

private struct IOSAutomationFailureJobRow: View {
    var job: PublishingJob
    var slides: [Slide]
    var assetsByID: [UUID: MediaAsset]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("\(job.platform.displayName) publish", systemImage: "xmark.octagon")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Text(AutomationDashboardFormatting.relativeDate(job.updatedAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if let failure = job.lastError {
                PublishingFailureDetailsView(failure: failure, job: job)
            }

            if slides.isEmpty {
                Text("No local draft images are available for this failed job.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(slides) { slide in
                            IOSAutomationFailureImageTile(
                                title: "Slide \(slide.index + 1)",
                                subtitle: slide.text.isEmpty ? slide.prompt : slide.text,
                                asset: slide.imageAssetID.flatMap { assetsByID[$0] }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private extension IOSAutomationFailuresView {
    var retryResultBinding: Binding<Bool> {
        Binding(
            get: { retryResult != nil },
            set: { isPresented in
                if !isPresented {
                    retryResult = nil
                }
            }
        )
    }

    func retryAllFailures() {
        guard !isRetrying else { return }
        isRetrying = true
        Task {
            let result = await appModel.retryFailedPublishingJobs(automationID: automationID)
            isRetrying = false
            retryResult = result
        }
    }
}

private struct IOSAutomationFailureImageTile: View {
    var title: String
    var subtitle: String
    var asset: MediaAsset?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VerticalMediaFrame(
                fileURL: asset?.localFileURL,
                remoteURL: asset?.publicURL,
                cornerRadius: 8,
                maxPixelSize: 720
            )
            .frame(width: 86)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 86, alignment: .leading)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(width: 86, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
