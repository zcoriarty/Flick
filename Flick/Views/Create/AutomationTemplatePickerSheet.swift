//
//  AutomationTemplatePickerSheet.swift
//  Flick
//

import SwiftUI

struct AutomationTemplatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var collections: [ExampleSlideshowCollection]
    @Binding var selectedTemplateIDs: Set<String>
    @State private var searchText = ""

    private var filteredCollections: [ExampleSlideshowCollection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return collections.compactMap { collection in
            let templates = collection.templates
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

            guard !templates.isEmpty else { return nil }

            var copy = collection
            copy.templates = templates
            return copy
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredCollections.isEmpty {
                    CreateMessageRow(
                        title: "No matching templates",
                        message: "Adjust the search text to find templates."
                    )
                } else {
                    ForEach(filteredCollections) { collection in
                        Section(collection.title) {
                            ForEach(collection.templates) { template in
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
