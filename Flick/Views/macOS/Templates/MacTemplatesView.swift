//
//  MacTemplatesView.swift
//  Flick
//

#if os(macOS) || targetEnvironment(macCatalyst)
import SwiftUI

struct MacTemplatesView: View {
    @Environment(FlickAppModel.self) private var appModel
    @State private var templateStore = TemplateLibraryStore()
    @State private var selectedTemplate: ExampleSlideshowTemplate?
    @State private var previewedTemplate: ExampleSlideshowTemplate?
    @State private var searchText = ""

    var body: some View {
        content
            .navigationTitle("Templates")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Reload", systemImage: "arrow.clockwise") {
                        Task {
                            await loadTemplates(forceReload: true)
                        }
                    }
                }
            }
            .sheet(item: $previewedTemplate) { template in
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
                .flickAppBackground()
        case let .failed(message):
            MacInlineEmptyState(
                title: "Templates unavailable",
                message: message,
                systemImage: "exclamationmark.triangle"
            )
            .padding(28)
            .flickAppBackground()
        case .loaded:
            loadedContent
        }
    }

    private var loadedContent: some View {
        let templates = filteredTemplates
        let totalTemplates = templateStore.selectedSummary?.slideshowCount ?? templates.count
        let totalSlides = templateStore.selectedSummary?.totalSlideCount ?? templates.reduce(0) { $0 + $1.slideCount }

        return HStack(alignment: .top, spacing: 22) {
            MacTemplateSidebar(
                summaries: templateStore.summaries,
                selectedNicheID: templateStore.selectedNicheID,
                selectAction: { summary in
                    Task {
                        await templateStore.selectNiche(summary.id, configuration: appModel.configuration)
                    }
                }
            )
            .frame(width: 260)

            VStack(alignment: .leading, spacing: 22) {
                MacWorkspaceHeader(
                    title: "Template Library",
                        subtitle: "Browse examples by niche, inspect source details, and start drafts from proven slideshow structures.",
                        metrics: [
                        MacWorkspaceMetric(title: "Templates", value: totalTemplates.formatted()),
                        MacWorkspaceMetric(title: "Slides", value: totalSlides.formatted()),
                        MacWorkspaceMetric(title: "Niches", value: templateStore.summaries.count.formatted())
                    ]
                )

                TextField("Search templates", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 420)

                HStack(alignment: .top, spacing: 18) {
                    MacTemplateGrid(
                        templates: templates,
                        showsLoadMore: showLoadMore,
                        isLoadingMore: templateStore.isLoadingPage,
                        selectedTemplate: selectedTemplate,
                        selectAction: { selectedTemplate = $0 },
                        useAction: useTemplate,
                        loadMoreAction: {
                            Task {
                                await templateStore.loadNextPage(configuration: appModel.configuration)
                            }
                        }
                    )

                    MacTemplateInspector(
                        template: selectedTemplate ?? templates.first,
                        previewAction: { previewedTemplate = $0 },
                        useAction: useTemplate
                    )
                    .frame(width: 320)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .macWorkspacePage()
        .onChange(of: templates) { _, newTemplates in
            reconcileSelection(with: newTemplates)
        }
        .task(id: templateStore.selectedNicheID) {
            reconcileSelection(with: templates)
        }
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

    private func reconcileSelection(with templates: [ExampleSlideshowTemplate]) {
        guard let selectedTemplate else {
            self.selectedTemplate = templates.first
            return
        }
        guard templates.contains(selectedTemplate) else {
            self.selectedTemplate = templates.first
            return
        }
    }

    private func useTemplate(_ template: ExampleSlideshowTemplate) {
        appModel.createDraft(from: template)
    }

    private var showLoadMore: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && templateStore.hasNextPage
    }

    private func loadTemplates(forceReload: Bool = false) async {
        await templateStore.loadInitial(configuration: appModel.configuration, forceReload: forceReload)
        selectedTemplate = templateStore.templates.first(where: \.hasDisplayablePreview)
    }
}

private struct MacTemplateSidebar: View {
    var summaries: [ExampleSlideshowCollectionSummary]
    var selectedNicheID: String?
    var selectAction: (ExampleSlideshowCollectionSummary) -> Void

    var body: some View {
        MacWorkspacePanel {
            VStack(alignment: .leading, spacing: 16) {
                Text("Niches")
                    .font(.title2.weight(.semibold))

                VStack(spacing: 8) {
                    ForEach(summaries) { collection in
                        MacTemplateFilterButton(
                            title: collection.title,
                            subtitle: "\(collection.slideshowCount.formatted()) templates",
                            isSelected: selectedNicheID == collection.id
                        ) {
                            selectAction(collection)
                        }
                    }
                }
            }
        }
    }
}

private struct MacTemplateFilterButton: View {
    var title: String
    var subtitle: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? FlickStyle.appTint : .secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? FlickStyle.appTint.opacity(0.12) : Color.clear, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private struct MacTemplateGrid: View {
    var templates: [ExampleSlideshowTemplate]
    var showsLoadMore: Bool
    var isLoadingMore: Bool
    var selectedTemplate: ExampleSlideshowTemplate?
    var selectAction: (ExampleSlideshowTemplate) -> Void
    var useAction: (ExampleSlideshowTemplate) -> Void
    var loadMoreAction: () -> Void

    var body: some View {
        MacWorkspaceSection(title: "Templates", systemImage: "rectangle.stack") {
            if templates.isEmpty {
                MacInlineEmptyState(
                    title: "No matching templates",
                    message: "Adjust the search text or niche filter.",
                    systemImage: "magnifyingglass"
                )
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 170, maximum: 230), spacing: 14, alignment: .top)],
                    alignment: .leading,
                    spacing: 20
                ) {
                    ForEach(templates) { template in
                        Button {
                            selectAction(template)
                        } label: {
                            TemplateCard(template: template)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(selectedTemplate == template ? FlickStyle.appTint : Color.clear, lineWidth: 3)
                                }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Use Template", systemImage: "wand.and.sparkles") {
                                useAction(template)
                            }
                        }
                    }
                }

                if showsLoadMore {
                    Button(action: loadMoreAction) {
                        HStack(spacing: 8) {
                            if isLoadingMore {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(isLoadingMore ? "Loading templates" : "Load more")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoadingMore)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct MacTemplateInspector: View {
    var template: ExampleSlideshowTemplate?
    var previewAction: (ExampleSlideshowTemplate) -> Void
    var useAction: (ExampleSlideshowTemplate) -> Void

    var body: some View {
        MacWorkspaceSection(title: "Details", systemImage: "sidebar.right") {
            if let template {
                MacWorkspacePanel {
                    VStack(alignment: .leading, spacing: 16) {
                        VerticalMediaFrame(
                            fileURL: template.displayablePreviewSlide?.localURL,
                            remoteURL: template.displayablePreviewSlide?.remoteURL,
                            cornerRadius: 14,
                            maxPixelSize: 1_080
                        )
                            .frame(maxWidth: 210)
                            .frame(maxWidth: .infinity)

                        VStack(alignment: .leading, spacing: 8) {
                            StatusBadge(title: template.niche, tint: FlickStyle.appTint, systemImage: "tag")
                            Text(template.subtitle)
                                .font(.title3.weight(.semibold))
                                .lineLimit(3)
                            Text("@\(template.profile)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                            MacDetailRow(title: "Slides", value: template.slideCount.formatted())
                            MacDetailRow(title: "Medium", value: template.product.medium ?? "None", valueLineLimit: 2)
                            MacDetailRow(title: "Product", value: template.product.name ?? "None", valueLineLimit: 2)
                            MacDetailRow(title: "Followers", value: template.creator.followerCount ?? "Unknown")
                            if let views = template.metrics.views {
                                MacDetailRow(title: "Views", value: views)
                            }
                            if let likes = template.metrics.likes {
                                MacDetailRow(title: "Likes", value: likes)
                            }
                        }

                        HStack {
                            Button("Preview", systemImage: "rectangle.stack") {
                                previewAction(template)
                            }
                            Button("Use Template", systemImage: "wand.and.sparkles") {
                                useAction(template)
                            }
                            .buttonStyle(.glassProminent)
                        }
                    }
                }
            } else {
                MacInlineEmptyState(
                    title: "No template selected",
                    message: "Select a template to inspect slides, source metrics, and product context.",
                    systemImage: "rectangle.stack.badge.play"
                )
            }
        }
    }
}
#endif
