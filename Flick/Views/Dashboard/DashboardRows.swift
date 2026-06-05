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
            PlatformIcon(platform: job.platform, size: 22, frameSize: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(job.dashboardTitle)
                    .font(.subheadline.weight(.semibold))
                Text(job.dashboardMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let suggestedFix = job.dashboardSuggestedFix {
                    Text(suggestedFix)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let publishID = job.platformPublishID {
                    Text(publishID)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 12)

            DashboardStatusIcon(
                title: job.status.displayName,
                tint: job.status.tint,
                systemImage: job.status.dashboardSystemImage
            )
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
    var dashboardTitle: String {
        switch status {
        case .awaitingUserCompletion:
            platform == .tiktok ? "Waiting for TikTok" : "Waiting for \(platform.displayName)"
        case .failed:
            "\(platform.displayName) upload failed"
        case .published:
            "\(platform.displayName) upload published"
        case .rendering:
            "Rendering \(platform.displayName) upload"
        case .publishing:
            "Publishing to \(platform.displayName)"
        }
    }

    var dashboardMessage: String {
        switch status {
        case .awaitingUserCompletion:
            if platform == .tiktok {
                return "Open the TikTok inbox notification to finish posting."
            }
            return "The platform needs a final account-side action before this post can complete."
        case .failed:
            return lastError?.message ?? "The platform failed this upload before it could be published."
        case .published:
            return "Flick recorded this upload as published."
        case .rendering:
            return "Flick is preparing the media for upload."
        case .publishing:
            return "Flick is uploading this post to the platform."
        }
    }

    var dashboardSuggestedFix: String? {
        guard status == .failed else { return nil }
        let trimmedFix = lastError?.suggestedFix.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedFix.isEmpty ? nil : trimmedFix
    }
}

private extension PublishingJobStatus {
    var dashboardSystemImage: String {
        switch self {
        case .rendering:
            "photo.on.rectangle"
        case .publishing:
            "paperplane"
        case .awaitingUserCompletion:
            "bell.badge"
        case .published:
            "checkmark.circle"
        case .failed:
            "xmark.octagon"
        }
    }
}

private extension RelativeDateTimeFormatter {
    static var short: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }
}
