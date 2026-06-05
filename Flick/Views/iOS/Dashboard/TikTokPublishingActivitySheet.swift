//
//  PublishingActivityView.swift
//  Flick
//

#if !os(macOS)
import SwiftUI

struct IOSPublishingActivityView: View {
    @Environment(FlickAppModel.self) private var appModel

    private var awaitingJobs: [PublishingJob] {
        appModel.overview.publishingJobs
            .filter { $0.status == .awaitingUserCompletion }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var publishedPosts: [PublishedPost] {
        appModel.overview.publishedPosts
            .sorted { $0.publishedAt > $1.publishedAt }
    }

    private var failedJobs: [PublishingJob] {
        appModel.overview.publishingJobs
            .filter { $0.status == .failed }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        List {
            previewSection(for: .draftUploads)
            previewSection(for: .publishedPosts)
            previewSection(for: .failedUploads)
        }
        .flickSettingsListStyle()
        .refreshable {
            await appModel.refresh()
        }
        .flickToolbarTitle("Publishing")
    }

    private func previewSection(for category: PublishingActivityCategory) -> some View {
        Section(category.title) {
            if count(for: category) == 0 {
                DashboardMessageRow(
                    title: category.emptyTitle,
                    message: category.emptyMessage,
                    systemImage: category.systemImage,
                    iconColor: .secondary
                )
            } else {
                previewRows(for: category)
                NavigationLink {
                    IOSPublishingActivityListView(category: category)
                } label: {
                    FlickSettingsRowLabel(
                        title: "View all",
                        systemImage: "list.bullet",
                        iconColor: category.tint,
                        value: category.viewAllValue(count: count(for: category))
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func previewRows(for category: PublishingActivityCategory) -> some View {
        switch category {
        case .draftUploads:
            ForEach(Array(awaitingJobs.prefix(3))) { job in
                PublishingJobRow(job: job)
            }
        case .publishedPosts:
            ForEach(Array(publishedPosts.prefix(3))) { post in
                PublishedPostRow(post: post)
            }
        case .failedUploads:
            ForEach(Array(failedJobs.prefix(3))) { job in
                PublishingJobRow(job: job)
            }
        }
    }

    private func count(for category: PublishingActivityCategory) -> Int {
        switch category {
        case .draftUploads:
            awaitingJobs.count
        case .publishedPosts:
            publishedPosts.count
        case .failedUploads:
            failedJobs.count
        }
    }
}

private struct IOSPublishingActivityListView: View {
    @Environment(FlickAppModel.self) private var appModel

    var category: PublishingActivityCategory

    private var awaitingJobs: [PublishingJob] {
        appModel.overview.publishingJobs
            .filter { $0.status == .awaitingUserCompletion }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var publishedPosts: [PublishedPost] {
        appModel.overview.publishedPosts
            .sorted { $0.publishedAt > $1.publishedAt }
    }

    private var failedJobs: [PublishingJob] {
        appModel.overview.publishingJobs
            .filter { $0.status == .failed }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        List {
            Section(category.title) {
                if count == 0 {
                    DashboardMessageRow(
                        title: category.emptyTitle,
                        message: category.emptyMessage,
                        systemImage: category.systemImage,
                        iconColor: .secondary
                    )
                } else {
                    allRows
                }
            }
        }
        .flickSettingsListStyle()
        .refreshable {
            await appModel.refresh()
        }
        .flickToolbarTitle(category.title)
    }

    @ViewBuilder
    private var allRows: some View {
        switch category {
        case .draftUploads:
            ForEach(awaitingJobs) { job in
                PublishingJobRow(job: job)
            }
        case .publishedPosts:
            ForEach(publishedPosts) { post in
                PublishedPostRow(post: post)
            }
        case .failedUploads:
            ForEach(failedJobs) { job in
                PublishingJobRow(job: job)
            }
        }
    }

    private var count: Int {
        switch category {
        case .draftUploads:
            awaitingJobs.count
        case .publishedPosts:
            publishedPosts.count
        case .failedUploads:
            failedJobs.count
        }
    }
}

private enum PublishingActivityCategory: CaseIterable, Identifiable, Hashable {
    case draftUploads
    case publishedPosts
    case failedUploads

    var id: Self { self }

    var title: String {
        switch self {
        case .draftUploads:
            "Draft uploads"
        case .publishedPosts:
            "Published posts"
        case .failedUploads:
            "Failed uploads"
        }
    }

    var systemImage: String {
        switch self {
        case .draftUploads:
            "bell.badge"
        case .publishedPosts:
            "checkmark.seal"
        case .failedUploads:
            "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .draftUploads:
            .orange
        case .publishedPosts:
            .green
        case .failedUploads:
            .red
        }
    }

    var emptyTitle: String {
        switch self {
        case .draftUploads:
            "No draft uploads"
        case .publishedPosts:
            "No published posts"
        case .failedUploads:
            "No failed uploads"
        }
    }

    var emptyMessage: String {
        switch self {
        case .draftUploads:
            "Uploads waiting for account-side completion will appear here."
        case .publishedPosts:
            "Published posts will appear here after Flick records successful publishes."
        case .failedUploads:
            "Failed publish jobs will appear here with their platform error details."
        }
    }

    func viewAllValue(count: Int) -> String {
        switch self {
        case .draftUploads:
            count == 1 ? "1 upload" : "\(count.formatted()) uploads"
        case .publishedPosts:
            count == 1 ? "1 post" : "\(count.formatted()) posts"
        case .failedUploads:
            count == 1 ? "1 upload" : "\(count.formatted()) uploads"
        }
    }
}
#endif
