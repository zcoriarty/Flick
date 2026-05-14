//
//  TrendsView.swift
//  Flick
//

import SwiftUI

struct TrendsView: View {
    @Environment(FlickAppModel.self) private var appModel
    @State private var selectedStatus: TrendStatus?

    var body: some View {
        List {
            filtersSection
            trendLibrarySection
            tagTaxonomySection
        }
        .flickSettingsListStyle()
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Trends")
                    .font(.system(.body, weight: .semibold))
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Add trend", systemImage: "plus") { }
            }
        }
    }

    private var filtersSection: some View {
        Section("Filter") {
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

    private var trendLibrarySection: some View {
        Section("Trend library") {
            if filteredTrends.isEmpty {
                TrendsMessageRow(
                    title: selectedStatus == nil ? "No trends yet" : "No \(selectedStatus?.displayName.lowercased() ?? "") trends",
                    message: "Add trends from Creative Center, manual notes, uploaded references, or winning posts once real content exists."
                )
            } else {
                ForEach(filteredTrends) { trend in
                    TrendRow(trend: trend)
                }
            }
        }
    }

    private var tagTaxonomySection: some View {
        Section("Tag taxonomy") {
            if appModel.overview.trendTags.isEmpty {
                TrendsMessageRow(
                    title: "No tags yet",
                    message: "Tags will appear after you create trend patterns or classify imported references."
                )
            } else {
                ForEach(appModel.overview.trendTags) { tag in
                    TrendTagRow(tag: tag)
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
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.semibold))
        }
        .modifier(BorderedSelectionButtonStyle(isSelected: isSelected))
    }
}

private struct BorderedSelectionButtonStyle: ViewModifier {
    var isSelected: Bool

    func body(content: Content) -> some View {
        if isSelected {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private struct TrendRow: View {
    var trend: Trend

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(trend.name)
                        .font(.body.weight(.semibold))
                    Text(trend.source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                StatusBadge(title: trend.status.displayName, tint: trend.status.tint, systemImage: "circle.fill")
            }

            Text(trend.notes)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            if !trend.tags.isEmpty {
                Text(trend.tags.map(\.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !trend.performanceSummary.isEmpty {
                Text(trend.performanceSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct TrendTagRow: View {
    var tag: TrendTag

    var body: some View {
        FlickSettingsRow(title: tag.name) {
            Text(tag.category.displayName)
                .font(.callout)
                .foregroundStyle(Color(hex: tag.colorHex))
                .multilineTextAlignment(.trailing)
        }
        .accessibilityLabel("\(tag.name), \(tag.category.displayName)")
    }
}

private struct TrendsMessageRow: View {
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
