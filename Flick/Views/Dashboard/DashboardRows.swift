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

            StatusBadge(
                title: badgeTitle,
                tint: badgeTint,
                systemImage: badgeSystemImage
            )
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct TikTokPublishingJobRow: View {
    var job: PublishingJob

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.badge")
                .foregroundStyle(.orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text("Waiting for TikTok")
                    .font(.subheadline.weight(.semibold))
                Text("Open the TikTok inbox notification to finish posting.")
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

            StatusBadge(title: "Draft sent", tint: .orange, systemImage: "clock")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct TikTokPublishedPostRow: View {
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

            StatusBadge(title: "Published", tint: .green, systemImage: "checkmark.circle")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private extension PublishedPost {
    var dashboardTitle: String {
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCaption.isEmpty else { return "\(platform.displayName) post" }
        return trimmedCaption
    }
}

private extension RelativeDateTimeFormatter {
    static var short: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }
}
