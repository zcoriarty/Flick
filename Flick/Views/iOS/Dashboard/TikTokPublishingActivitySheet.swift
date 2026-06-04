//
//  PublishingActivitySheet.swift
//  Flick
//

#if !os(macOS)
import SwiftUI

struct PublishingActivitySummaryRow: View {
    var awaitingJobCount: Int
    var publishedPostCount: Int
    var latestActivityDate: Date?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "paperplane")
                .foregroundStyle(FlickStyle.appTint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                Text("Publishing activity")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(summaryText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let latestActivityDate {
                    Text("Latest \(AutomationDashboardFormatting.relativeDate(latestActivityDate))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var summaryText: String {
        switch (awaitingJobCount, publishedPostCount) {
        case (0, 0):
            "No publish activity"
        case (0, _):
            publishedPostSummary
        case (_, 0):
            awaitingJobSummary
        default:
            "\(awaitingJobSummary), \(publishedPostSummary)"
        }
    }

    private var awaitingJobSummary: String {
        awaitingJobCount == 1 ? "1 draft waiting" : "\(awaitingJobCount.formatted()) drafts waiting"
    }

    private var publishedPostSummary: String {
        publishedPostCount == 1 ? "1 published post" : "\(publishedPostCount.formatted()) published posts"
    }
}

struct PublishingActivitySheet: View {
    @Environment(\.dismiss) private var dismiss

    var awaitingJobs: [PublishingJob]
    var publishedPosts: [PublishedPost]

    var body: some View {
        NavigationStack {
            List {
                if !awaitingJobs.isEmpty {
                    Section(awaitingJobsSectionTitle) {
                        ForEach(awaitingJobs) { job in
                            PublishingJobRow(job: job)
                        }
                    }
                }

                if !publishedPosts.isEmpty {
                    Section(publishedPostsSectionTitle) {
                        ForEach(publishedPosts) { post in
                            PublishedPostRow(post: post)
                        }
                    }
                }
            }
            .flickSettingsListStyle()
            .flickToolbarTitle("Publishing")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var awaitingJobsSectionTitle: String {
        awaitingJobs.count == 1 ? "Draft upload" : "Draft uploads"
    }

    private var publishedPostsSectionTitle: String {
        publishedPosts.count == 1 ? "Published post" : "Published posts"
    }
}
#endif
