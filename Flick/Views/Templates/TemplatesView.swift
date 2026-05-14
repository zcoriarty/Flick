//
//  TemplatesView.swift
//  Flick
//

import SwiftUI

struct TemplatesView: View {
    @Environment(FlickAppModel.self) private var appModel
    @State private var loadState: TemplatesLoadState = .loading
    @State private var selectedTemplate: ExampleSlideshowTemplate?
    @State private var selectedNicheID = TemplatesFilter.allID
    @State private var searchText = ""

    var body: some View {
        content
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Templates")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Reload", systemImage: "arrow.clockwise") {
                        loadTemplates()
                    }
                }
            }
            .sheet(item: $selectedTemplate) { template in
                TemplatePreviewSheet(template: template)
            }
        .task {
            if case .loading = loadState {
                loadTemplates()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            FlickEmptyStateCard(
                title: "Templates unavailable",
                message: message,
                systemImage: "exclamationmark.triangle",
                actionTitle: "Reload",
                actionSystemImage: "arrow.clockwise"
            ) {
                loadTemplates()
            }
            .padding(FlickStyle.pagePadding)
        case let .loaded(collections):
            loadedContent(collections)
        }
    }

    private func loadedContent(_ collections: [ExampleSlideshowCollection]) -> some View {
        let templates = filteredTemplates(in: collections)
        let displayableTemplates = collections.flatMap(\.templates).filter(\.hasDisplayablePreview)
        let totalTemplates = displayableTemplates.count
        let totalSlides = displayableTemplates.reduce(0) { $0 + $1.slideCount }

        return VStack(alignment: .leading, spacing: 14) {
            SectionTitle(
                title: "Example library",
                subtitle: "\(totalTemplates) templates, \(totalSlides) slides, \(collections.count) niches",
                systemImage: "rectangle.stack"
            )
            filters(collections)
            templateGrid(templates)
        }
        .flickScrollablePage()
        .searchable(text: $searchText, prompt: "Search templates")
    }

    private func filters(_ collections: [ExampleSlideshowCollection]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                NicheFilterChip(
                    title: "All",
                    isSelected: selectedNicheID == TemplatesFilter.allID
                ) {
                    selectedNicheID = TemplatesFilter.allID
                }
                ForEach(collections) { collection in
                    NicheFilterChip(
                        title: collection.title,
                        isSelected: selectedNicheID == collection.id
                    ) {
                        selectedNicheID = collection.id
                    }
                }
            }
            .padding(.horizontal, FlickStyle.pagePadding)
            .padding(.vertical, 2)
        }
        .contentMargins(.horizontal, -FlickStyle.pagePadding, for: .scrollContent)
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func templateGrid(_ templates: [ExampleSlideshowTemplate]) -> some View {
        if templates.isEmpty {
            FlickEmptyStateCard(
                title: "No matching templates",
                message: "Adjust the search text or niche filter.",
                systemImage: "magnifyingglass"
            )
        } else {
            LazyVGrid(columns: templateColumns, alignment: .leading, spacing: 22) {
                ForEach(templates) { template in
                    Button {
                        selectedTemplate = template
                    } label: {
                        TemplateCard(template: template)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Use Template", systemImage: "wand.and.sparkles") {
                            appModel.createDraft(from: template)
                        }
                    }
                }
            }
        }
    }

    private var templateColumns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: 108, maximum: 190),
                spacing: 10,
                alignment: .top
            )
        ]
    }

    private func filteredTemplates(in collections: [ExampleSlideshowCollection]) -> [ExampleSlideshowTemplate] {
        let sourceCollections = selectedNicheID == TemplatesFilter.allID
            ? collections
            : collections.filter { $0.id == selectedNicheID }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let templates = sourceCollections
            .flatMap(\.templates)
            .filter(\.hasDisplayablePreview)

        guard !query.isEmpty else { return templates }

        return templates.filter { template in
            [
                template.niche,
                template.profile,
                template.profileDisplayName,
                template.subtitle,
                template.product.medium,
                template.product.name
            ]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(query) }
        }
    }

    private func loadTemplates() {
        loadState = .loading
        do {
            loadState = .loaded(try ExampleSlideshowLibrary.load())
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}

private enum TemplatesLoadState {
    case loading
    case loaded([ExampleSlideshowCollection])
    case failed(String)
}

private enum TemplatesFilter {
    static let allID = "all"
}

private struct NicheFilterChip: View {
    var title: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? .white : .primary)
                .background(isSelected ? Color.indigo : Color.secondary.opacity(0.12), in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var appModel = FlickAppModel.live()
    TemplatesView()
        .environment(appModel)
}
