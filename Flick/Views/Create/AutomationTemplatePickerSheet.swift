//
//  AutomationTemplatePickerSheet.swift
//  Flick
//

import SwiftUI

struct AutomationTemplatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var templateStore: TemplateLibraryStore
    var configuration: AppConfiguration
    @Binding var selectedTemplateIDs: Set<String>
    @Binding var selectedTemplateNicheIDs: Set<String>
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

    private var isSelectedNicheIncluded: Bool {
        guard let selectedNicheID = templateStore.selectedNicheID else { return false }
        return selectedTemplateNicheIDs.contains(selectedNicheID)
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
                        message: "Adjust the search text to find templates."
                    )
                } else {
                    Section(selectedNicheTitle) {
                        if let summary = templateStore.selectedSummary {
                            Button {
                                toggleNiche(summary)
                            } label: {
                                TemplateNichePickerRow(
                                    summary: summary,
                                    isSelected: selectedTemplateNicheIDs.contains(summary.id)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(filteredTemplates) { template in
                            Button {
                                toggle(template)
                            } label: {
                                TemplatePickerRow(
                                    template: template,
                                    isSelected: isSelectedNicheIncluded || selectedTemplateIDs.contains(template.id)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isSelectedNicheIncluded)
                        }

                        if showLoadMore {
                            loadMoreRow
                        }
                    }
                }
            }
            .flickSettingsListStyle()
            .searchable(text: $searchText, prompt: "Search templates")
            .flickToolbarTitle("Select Templates")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func toggleNiche(_ summary: ExampleSlideshowCollectionSummary) {
        if selectedTemplateNicheIDs.contains(summary.id) {
            selectedTemplateNicheIDs.remove(summary.id)
        } else {
            selectedTemplateNicheIDs.insert(summary.id)
            let loadedNicheTemplateIDs = templateStore.templates
                .filter { $0.nicheSlug == summary.nicheSlug || $0.niche == summary.title }
                .map(\.id)
            selectedTemplateIDs.subtract(loadedNicheTemplateIDs)
        }
    }

    private func toggle(_ template: ExampleSlideshowTemplate) {
        if selectedTemplateIDs.contains(template.id) {
            selectedTemplateIDs.remove(template.id)
        } else {
            selectedTemplateIDs.insert(template.id)
        }
    }
}

private struct TemplateNichePickerRow: View {
    var summary: ExampleSlideshowCollectionSummary
    var isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.title3)
                .foregroundStyle(FlickStyle.appTint)
                .frame(width: 48, height: 48)
                .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                Text("All \(summary.title)")
                    .foregroundStyle(.primary)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text("\(summary.slideshowCount) templates")
                    .font(.callout)
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
