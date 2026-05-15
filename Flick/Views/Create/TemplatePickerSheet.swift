//
//  TemplatePickerSheet.swift
//  Flick
//

import SwiftUI

struct TemplatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var collections: [ExampleSlideshowCollection]
    @Binding var selectedTemplate: ExampleSlideshowTemplate?
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
                        message: "Adjust the search text to find a template."
                    )
                } else {
                    ForEach(filteredCollections) { collection in
                        Section(collection.title) {
                            ForEach(collection.templates) { template in
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
                        }
                    }
                }
            }
            .flickSettingsListStyle()
            .searchable(text: $searchText, prompt: "Search templates")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Select Template")
                        .font(.system(.body, weight: .semibold))
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct TemplatePickerRow: View {
    var template: ExampleSlideshowTemplate
    var isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VerticalMediaFrame(fileURL: template.displayablePreviewSlide?.localURL, cornerRadius: 8)
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
                .foregroundStyle(isSelected ? Color.indigo : Color.secondary.opacity(0.6))
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
