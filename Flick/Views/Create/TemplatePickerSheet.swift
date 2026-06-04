//
//  TemplatePickerSheet.swift
//  Flick
//

import SwiftUI

struct TemplatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var templateStore: TemplateLibraryStore
    var configuration: AppConfiguration
    @Binding var selectedTemplate: ExampleSlideshowTemplate?
    @State private var searchText = ""

    private var filteredTemplates: [ExampleSlideshowTemplate] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return templateStore.templates
            .filter(\.hasDisplayablePreview)
            .filter { template in
                guard !query.isEmpty else { return true }
                return [
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

    private var selectedNicheTitle: String {
        templateStore.selectedSummary?.title ?? "Templates"
    }

    private var showLoadMore: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && templateStore.hasNextPage
    }

    private var loadMoreRow: some View {
        Button {
            Task {
                await templateStore.loadNextPage(configuration: configuration)
            }
        } label: {
            HStack {
                if templateStore.isLoadingPage {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(templateStore.isLoadingPage ? "Loading templates" : "Load more templates")
                Spacer()
                Text(templateStore.loadedTemplateCountText)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(templateStore.isLoadingPage)
    }

    var body: some View {
        NavigationStack {
            List {
                TemplateNicheSelectionSection(
                    summaries: templateStore.summaries,
                    selectedNicheID: templateStore.selectedNicheID,
                    configuration: configuration,
                    templateStore: templateStore
                )

                if filteredTemplates.isEmpty {
                    CreateMessageRow(
                        title: "No matching templates",
                        message: "Adjust the search text to find a template."
                    )
                } else {
                    Section(selectedNicheTitle) {
                        ForEach(filteredTemplates) { template in
                            Button {
                                selectedTemplate = template
                                dismiss()
                            } label: {
                                TemplatePickerRow(
                                    template: template,
                                    isSelected: selectedTemplate?.id == template.id
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if showLoadMore {
                            loadMoreRow
                        }
                    }
                }
            }
            .flickSettingsListStyle()
            .searchable(text: $searchText, prompt: "Search templates")
            .flickToolbarTitle("Select Template")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

struct TemplatePickerRow: View {
    var template: ExampleSlideshowTemplate
    var isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VerticalMediaFrame(
                fileURL: template.displayablePreviewSlide?.localURL,
                remoteURL: template.displayablePreviewSlide?.remoteURL,
                cornerRadius: 8
            )
                .frame(width: 48, height: 86)

            VStack(alignment: .leading, spacing: 5) {
                Text(template.subtitle)
                    .foregroundStyle(.primary)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text("@\(template.profile)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(template.niche) - \(template.slideCount) slides")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? FlickStyle.appTint : Color.secondary.opacity(0.6))
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

struct TemplateNicheSelectionSection: View {
    var summaries: [ExampleSlideshowCollectionSummary]
    var selectedNicheID: String?
    var configuration: AppConfiguration
    var templateStore: TemplateLibraryStore
    @Namespace private var selectionNamespace

    var body: some View {
        if !summaries.isEmpty {
            Section("Niche") {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(summaries) { summary in
                            let isSelected = selectedNicheID == summary.id
                            Button {
                                Task {
                                    await templateStore.selectNiche(summary.id, configuration: configuration)
                                }
                            } label: {
                                Text(summary.title)
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(isSelected ? .primary : .secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        ZStack {
                                            if isSelected {
                                                Capsule()
                                                    .fill(Color.gray.opacity(0.12))
                                                    .matchedGeometryEffect(id: "selectedNiche", in: selectionNamespace)
                                            }
                                        }
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                    .animation(.snappy(duration: 0.24), value: selectedNicheID)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}
