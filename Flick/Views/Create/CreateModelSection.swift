//
//  CreateModelSection.swift
//  Flick
//

import SwiftUI

struct CreateModelSection: View {
    var models: [FlickCreationModel]
    @Binding var selectedModel: SlideshowCreationModelReference?

    var body: some View {
        Section("Model") {
            if models.isEmpty, selectedModel == nil {
                CreateMessageRow(
                    title: "No models",
                    message: "Create a model before using one for generated people."
                )
            } else {
                modelMenu

                if let selectedModel {
                    FlickSettingsValueRow(
                        title: "Appearance",
                        systemImage: "person.text.rectangle",
                        iconColor: .purple,
                        value: selectedModel.metadataSummary,
                        valueLineLimit: 2
                    )
                }
            }
        }
        .onChange(of: models) { _, _ in
            refreshSelectedModelFromCurrentModels()
        }
    }

    private var modelMenu: some View {
        Menu {
            Button {
                selectedModel = nil
            } label: {
                CreateProductMenuOptionLabel(title: "None", isSelected: selectedModel == nil)
            }

            if let selectedModel, !models.contains(where: { $0.id == selectedModel.id }) {
                CreateProductMenuOptionLabel(title: "\(selectedModel.name) Snapshot", isSelected: true)
            }

            ForEach(models) { model in
                Button {
                    selectedModel = model.generationReference
                } label: {
                    CreateProductMenuOptionLabel(title: model.name, isSelected: selectedModel?.id == model.id)
                }
            }
        } label: {
            FlickSettingsRow(
                title: "Model",
                systemImage: "person.crop.square",
                iconColor: FlickStyle.appTint
            ) {
                HStack(spacing: 6) {
                    Text(selectedModel?.name ?? "None")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func refreshSelectedModelFromCurrentModels() {
        guard let selectedModel else { return }
        guard let currentModel = models.first(where: { $0.id == selectedModel.id }) else { return }
        self.selectedModel = currentModel.generationReference
    }
}
