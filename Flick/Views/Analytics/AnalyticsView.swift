//
//  AnalyticsView.swift
//  Flick
//

import Charts
import SwiftUI

struct AnalyticsView: View {
    @Environment(FlickAppModel.self) private var appModel

    var body: some View {
        List {
            performanceSection
            topPostsSection
            experimentsSection
        }
        .flickSettingsListStyle()
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Analytics")
                    .font(.system(.body, weight: .semibold))
            }
        }
    }

    private var performanceSection: some View {
        Section("Performance") {
            FlickSettingsValueRow(title: "Top views", systemImage: "eye", iconColor: .blue, value: topViews.formatted())
            FlickSettingsValueRow(
                title: "Best engagement",
                systemImage: "heart",
                iconColor: .red,
                value: topEngagement.formatted(.percent.precision(.fractionLength(1)))
            )
            FlickSettingsValueRow(
                title: "Best saves/view",
                systemImage: "bookmark",
                iconColor: .green,
                value: topSavesPerView.formatted(.number.precision(.fractionLength(3)))
            )
            FlickSettingsValueRow(
                title: "Snapshots stored",
                systemImage: "camera.metering.matrix",
                iconColor: .purple,
                value: appModel.overview.analyticsSnapshots.count.formatted()
            )
        }
    }

    private var topPostsSection: some View {
        Section("Top posts") {
            if appModel.overview.analyticsPerformance.isEmpty {
                AnalyticsMessageRow(
                    title: "No analytics yet",
                    message: "Published posts and analytics snapshots will populate this chart after a platform account is authorized and content is published."
                )
            } else {
                Chart(appModel.overview.analyticsPerformance) { post in
                    BarMark(
                        x: .value("Views", post.views),
                        y: .value("Post", post.title)
                    )
                    .foregroundStyle(by: .value("Platform", post.platform.displayName))

                    PointMark(
                        x: .value("Engagement", Int(post.engagementRate * Double(max(topViews, 1)))),
                        y: .value("Post", post.title)
                    )
                    .foregroundStyle(.orange)
                    .symbolSize(80)
                }
                .chartXAxisLabel("Views; orange dots scale engagement rate")
                .frame(minHeight: 240)
                .accessibilityLabel("Top posts by views with engagement overlay")
            }
        }
    }

    private var experimentsSection: some View {
        Section("Recommended experiments") {
            if appModel.overview.analyticsPerformance.isEmpty {
                AnalyticsMessageRow(
                    title: "No recommendations yet",
                    message: "Recommendations require real published posts and analytics snapshots."
                )
            } else {
                ExperimentRow(
                    title: "Remix current winner",
                    detail: "Create variants from the top-performing post in this workspace.",
                    systemImage: "square.stack.3d.up",
                    tint: .purple
                )
                ExperimentRow(
                    title: "Compare tags",
                    detail: "Use saved trend tags and snapshots to identify which creative patterns are working.",
                    systemImage: "tag",
                    tint: .green
                )
            }
        }
    }

    private var topViews: Int {
        appModel.overview.analyticsPerformance.map(\.views).max() ?? 0
    }

    private var topEngagement: Double {
        appModel.overview.analyticsPerformance.map(\.engagementRate).max() ?? 0
    }

    private var topSavesPerView: Double {
        appModel.overview.analyticsPerformance.map(\.savesPerView).max() ?? 0
    }
}

private struct ExperimentRow: View {
    var title: String
    var detail: String
    var systemImage: String
    var tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AnalyticsMessageRow: View {
    var title: String
    var message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .foregroundStyle(.primary)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
