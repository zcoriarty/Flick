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
                        message: "Adjust the search text to find templates."
                    )
                } else {
                    Section(selectedNicheTitle) {
                        ForEach(filteredTemplates) { template in
                            Button {
                                toggle(template)
                            } label: {
                                TemplatePickerRow(
                                    template: template,
                                    isSelected: selectedTemplateIDs.contains(template.id)
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

    private func toggle(_ template: ExampleSlideshowTemplate) {
        if selectedTemplateIDs.contains(template.id) {
            selectedTemplateIDs.remove(template.id)
        } else {
            selectedTemplateIDs.insert(template.id)
        }
    }
}
