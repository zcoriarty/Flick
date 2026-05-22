//
//  IOSTemplatesView.swift
//  Flick
//

import SwiftUI

#if !os(macOS)
struct IOSTemplatesView: View {
    @Environment(FlickAppModel.self) private var appModel
    @State private var templateStore = TemplateLibraryStore()
    @State private var selectedTemplate: ExampleSlideshowTemplate?
    @State private var searchText = ""

    var body: some View {
        content
            .flickToolbarTitle("Templates")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Reload", systemImage: "arrow.clockwise") {
                        Task {
                            await loadTemplates(forceReload: true)
                        }
                    }
                }
            }
            .sheet(item: $selectedTemplate) { template in
                TemplatePreviewSheet(template: template)
            }
        .task {
            if case .loading = templateStore.status {
                await loadTemplates()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch templateStore.status {
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
                Task {
                    await loadTemplates(forceReload: true)
                }
            }
            .padding(FlickStyle.pagePadding)
        case .loaded:
            loadedContent
        }
    }

    private var loadedContent: some View {
        let templates = filteredTemplates
        let totalTemplates = templateStore.selectedSummary?.slideshowCount ?? templates.count
        let totalSlides = templateStore.selectedSummary?.totalSlideCount ?? templates.reduce(0) { $0 + $1.slideCount }

        return VStack(alignment: .leading, spacing: 14) {
            SectionTitle(
                title: templateStore.selectedSummary?.title ?? "Example library",
                subtitle: "\(totalTemplates) templates, \(totalSlides) slides, \(templateStore.summaries.count) niches",
                systemImage: "rectangle.stack"
            )
            filters
            templateGrid(templates)
        }
        .flickScrollablePage()
        .searchable(text: $searchText, prompt: "Search templates")
    }

    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(templateStore.summaries) { collection in
                    NicheFilterChip(
                        title: collection.title,
                        isSelected: templateStore.selectedNicheID == collection.id
                    ) {
                        Task {
                            await templateStore.selectNiche(collection.id, configuration: appModel.configuration)
                        }
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

                if showLoadMore {
                    Button {
                        Task {
                            await templateStore.loadNextPage(configuration: appModel.configuration)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if templateStore.isLoadingPage {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(templateStore.isLoadingPage ? "Loading templates" : "Load more")
                                .font(.callout.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .disabled(templateStore.isLoadingPage)
                }
            }
        }
    }

    private var showLoadMore: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && templateStore.hasNextPage
    }

    private var templateColumns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: 132, maximum: 190),
                spacing: 12,
                alignment: .top
            )
        ]
    }

    private var filteredTemplates: [ExampleSlideshowTemplate] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let templates = templateStore.templates.filter(\.hasDisplayablePreview)

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

    private func loadTemplates(forceReload: Bool = false) async {
        await templateStore.loadInitial(configuration: appModel.configuration, forceReload: forceReload)
    }
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
                .background(isSelected ? FlickStyle.appTint : Color.secondary.opacity(0.12), in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var appModel = FlickAppModel.live()
    IOSTemplatesView()
        .environment(appModel)
}
#endif
