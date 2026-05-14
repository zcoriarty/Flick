//
//  AnalyticsView.swift
//  Flick
//

import Charts
import SwiftUI

struct AnalyticsView: View {
    @Environment(FlickAppModel.self) private var appModel

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: FlickStyle.sectionSpacing) {
                performanceSummary
                topPostsChart
                learningLoop
            }
            .flickScrollablePage()
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .principal) {
                    Text("Analytics")
                }
                #else
                ToolbarItem(placement: .title) {
                    Text("Analytics")
                }
                #endif
            }
        }
    }

    private var performanceSummary: some View {
        ResponsiveGrid(minimum: 190) {
            MetricTile(title: "Top views", value: topViews.formatted(), systemImage: "eye", tint: .blue)
            MetricTile(title: "Best engagement", value: topEngagement.formatted(.percent.precision(.fractionLength(1))), systemImage: "heart", tint: .red)
            MetricTile(title: "Best saves/view", value: topSavesPerView.formatted(.number.precision(.fractionLength(3))), systemImage: "bookmark", tint: .green)
            MetricTile(title: "Snapshots stored", value: appModel.overview.analyticsSnapshots.count.formatted(), systemImage: "camera.metering.matrix", tint: .purple)
        }
    }

    private var topPostsChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Top posts", subtitle: "Views and engagement by creative", systemImage: "chart.xyaxis.line")
            FlickGlassCard {
                if appModel.overview.analyticsPerformance.isEmpty {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No analytics yet")
                                .font(.headline)
                            Text("Published posts and analytics snapshots will populate this chart after a platform account is authorized and content is published.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "chart.xyaxis.line")
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 160, alignment: .center)
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
    }

    private var learningLoop: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Recommended experiments", subtitle: "Remix winning hooks, templates, tags, timing, and app features", systemImage: "lightbulb")
            if appModel.overview.analyticsPerformance.isEmpty {
                FlickEmptyStateCard(
                    title: "No recommendations yet",
                    message: "Recommendations require real published posts and analytics snapshots.",
                    systemImage: "lightbulb"
                )
            } else {
                ResponsiveGrid(minimum: 270) {
                    ExperimentCard(title: "Remix current winner", detail: "Create variants from the top-performing post in this workspace.", tint: .purple, systemImage: "square.stack.3d.up")
                    ExperimentCard(title: "Compare tags", detail: "Use saved trend tags and snapshots to identify which creative patterns are working.", tint: .green, systemImage: "tag")
                }
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

private struct ExperimentCard: View {
    var title: String
    var detail: String
    var tint: Color
    var systemImage: String

    var body: some View {
        FlickGlassCard(interactive: true) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }
}
