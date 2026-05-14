//
//  TrendsView.swift
//  Flick
//

import SwiftUI

struct TrendsView: View {
    @Environment(FlickAppModel.self) private var appModel
    @State private var selectedStatus: TrendStatus?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: FlickStyle.sectionSpacing) {
                statusFilter
                trendLibrary
                tagLibrary
            }
            .flickScrollablePage()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Trends")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add trend", systemImage: "plus") { }
                        .buttonStyle(.glassProminent)
                }
            }
        }
    }

    private var statusFilter: some View {
        GlassEffectContainer(spacing: 10) {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    TrendFilterButton(title: "All", isSelected: selectedStatus == nil) {
                        selectedStatus = nil
                    }

                    ForEach(TrendStatus.allCases) { status in
                        TrendFilterButton(title: status.displayName, isSelected: selectedStatus == status) {
                            selectedStatus = status
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var trendLibrary: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Trend library", subtitle: "Manual references, Creative Center notes, and winning Flick patterns", systemImage: "sparkles.rectangle.stack")
            if filteredTrends.isEmpty {
                FlickEmptyStateCard(
                    title: selectedStatus == nil ? "No trends yet" : "No \(selectedStatus?.displayName.lowercased() ?? "") trends",
                    message: "Add trends from Creative Center, manual notes, uploaded references, or winning posts once real content exists.",
                    systemImage: "sparkles.rectangle.stack"
                )
            } else {
                ResponsiveGrid(minimum: 300) {
                    ForEach(filteredTrends) { trend in
                        TrendCard(trend: trend)
                    }
                }
            }
        }
    }

    private var tagLibrary: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Tag taxonomy", subtitle: "Hook, template, visual style, niche, CTA, pacing, and platform tags", systemImage: "tag")
            FlickGlassCard {
                if appModel.overview.trendTags.isEmpty {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No tags yet")
                                .font(.headline)
                            Text("Tags will appear after you create trend patterns or classify imported references.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "tag")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(appModel.overview.trendTags) { tag in
                            TagChip(tag: tag)
                                .accessibilityLabel("\(tag.name), \(tag.category.displayName)")
                        }
                    }
                }
            }
        }
    }

    private var filteredTrends: [Trend] {
        guard let selectedStatus else {
            return appModel.overview.trends
        }
        return appModel.overview.trends.filter { $0.status == selectedStatus }
    }
}

private struct TrendFilterButton: View {
    var title: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(title, action: action)
            .modifier(GlassSelectionButtonStyle(isSelected: isSelected))
    }
}

private struct GlassSelectionButtonStyle: ViewModifier {
    var isSelected: Bool

    func body(content: Content) -> some View {
        if isSelected {
            content.buttonStyle(.glassProminent)
        } else {
            content
        }
    }
}

private struct TrendCard: View {
    var trend: Trend

    var body: some View {
        FlickGlassCard(interactive: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(trend.name)
                            .font(.headline)
                        Text(trend.source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(title: trend.status.displayName, tint: trend.status.tint, systemImage: "circle.fill")
                }

                Text(trend.notes)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(trend.tags) { tag in
                        TagChip(tag: tag)
                    }
                }

                Text(trend.performanceSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }
}
