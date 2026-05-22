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
    @State private var templatePendingDeletion: ExampleSlideshowTemplate?
    @State private var deleteErrorMessage: String?
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
            #if DEBUG
            .confirmationDialog(
                "Delete this template?",
                isPresented: Binding(
                    get: { templatePendingDeletion != nil },
                    set: { if !$0 { templatePendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let template = templatePendingDeletion {
                    Button("Delete Template", role: .destructive) {
                        Task {
                            await deleteTemplate(template)
                        }
                    }
                }
            } message: {
                if let template = templatePendingDeletion {
                    Text("This removes @\(template.profile)'s template from the shared library and deletes its cached analysis.")
                }
            }
            .alert(
                "Template deletion failed",
                isPresented: Binding(
                    get: { deleteErrorMessage != nil },
                    set: { if !$0 { deleteErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteErrorMessage ?? "")
            }
            #endif
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
                        #if DEBUG
                        Button("Delete Template", systemImage: "trash", role: .destructive) {
                            templatePendingDeletion = template
                        }
                        #endif
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

    private func deleteTemplate(_ template: ExampleSlideshowTemplate) async {
        do {
            try await templateStore.deleteTemplate(template, configuration: appModel.configuration)
            await appModel.deleteLocalAnalysis(for: template)
            if selectedTemplate?.id == template.id {
                selectedTemplate = nil
            }
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
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
