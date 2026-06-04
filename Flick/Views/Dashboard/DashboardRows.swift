//
//  DashboardRows.swift
//  Flick
//

import SwiftUI

struct DashboardMessageRow: View {
    var title: String
    var message: String
    var systemImage: String
    var iconColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct DashboardStatusRow: View {
    var title: String
    var message: String
    var messageLineLimit: Int? = nil
    var systemImage: String
    var iconColor: Color
    var badgeTitle: String
    var badgeTint: Color
    var badgeSystemImage: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(messageLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            DashboardStatusIcon(
                title: badgeTitle,
                tint: badgeTint,
                systemImage: badgeSystemImage
            )
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct PublishingJobRow: View {
    var job: PublishingJob

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: job.platform == .tiktok ? "bell.badge" : job.platform.systemImage)
                .foregroundStyle(job.platform == .tiktok ? .orange : job.platform.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(job.awaitingCompletionTitle)
                    .font(.subheadline.weight(.semibold))
                Text(job.awaitingCompletionMessage)
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

            DashboardStatusIcon(title: job.awaitingCompletionBadgeTitle, tint: .orange, systemImage: "clock")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct PublishedPostRow: View {
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

            DashboardStatusIcon(title: "Published", tint: .green, systemImage: "checkmark.circle")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct DashboardStatusIcon: View {
    var title: String
    var tint: Color
    var systemImage: String?

    var body: some View {
        Image(systemName: systemImage ?? "circle.fill")
            .font(.body.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 24, height: 24)
            .accessibilityLabel(title)
    }
}

private extension PublishedPost {
    var dashboardTitle: String {
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCaption.isEmpty else { return "\(platform.displayName) post" }
        return trimmedCaption
    }
}

private extension PublishingJob {
    var awaitingCompletionTitle: String {
        platform == .tiktok ? "Waiting for TikTok" : "Waiting for \(platform.displayName)"
    }

    var awaitingCompletionMessage: String {
        if platform == .tiktok {
            return "Open the TikTok inbox notification to finish posting."
        }
        return "The platform needs a final account-side action before this post can complete."
    }

    var awaitingCompletionBadgeTitle: String {
        platform == .tiktok ? "Draft sent" : "Needs action"
    }
}

private extension RelativeDateTimeFormatter {
    static var short: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }
}
