//
//  IOSModelsView.swift
//  Flick
//

import SwiftUI

#if !os(macOS)
struct IOSModelsView: View {
    @Environment(FlickAppModel.self) private var appModel

    @State private var isNewModelSheetPresented = false

    var body: some View {
        List {
            if appModel.overview.creationModels.isEmpty {
                Section {
                    ModelsEmptyRow(createAction: { isNewModelSheetPresented = true })
                }
            } else {
                modelsSection
            }

            Section {
                FlickSettingsActionRow(
                    title: "New Model",
                    systemImage: "plus.circle",
                    iconColor: .green,
                    action: { isNewModelSheetPresented = true }
                )
            }
        }
        .flickSettingsListStyle()
        .flickToolbarTitle("Models")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Model", systemImage: "plus") {
                    isNewModelSheetPresented = true
                }
            }
        }
        .sheet(isPresented: $isNewModelSheetPresented) {
            ModelCreateSheet(
                saveAction: { name, metadata in
                    _ = try await appModel.createCreationModel(name: name, metadata: metadata)
                }
            )
        }
    }

    private var modelsSection: some View {
        Section("Models") {
            ForEach(appModel.overview.creationModels) { model in
                NavigationLink {
                    ModelDetailView(modelID: model.id)
                } label: {
                    FlickSettingsRowLabel(
                        title: model.name,
                        systemImage: "person.crop.square",
                        iconColor: FlickStyle.appTint,
                        value: model.listSummary,
                        valueLineLimit: 2
                    )
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        deleteModel(model)
                    }
                }
            }
        }
    }

    private func deleteModel(_ model: FlickCreationModel) {
        Task {
            do {
                try await appModel.deleteCreationModel(id: model.id)
            } catch {
                appModel.lastErrorMessage = error.localizedDescription
            }
        }
    }
}

private struct ModelsEmptyRow: View {
    var createAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "person.crop.square")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("No models yet")
                    .font(.headline)
                Text("Create a reusable character model before using it in a generation flow.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("New Model", systemImage: "plus", action: createAction)
                .padding(.top, 2)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

private struct ModelDetailView: View {
    @Environment(FlickAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var activeSheet: ModelDetailSheet?
    @State private var isDeleteConfirmationPresented = false

    var modelID: UUID

    private var model: FlickCreationModel? {
        appModel.overview.creationModels.first { $0.id == modelID }
    }

    var body: some View {
        List {
            if let model {
                modelSection(model)
                overviewSection(model)
                randomizeSection(model)
            } else {
                Section {
                    SettingsMessageRow(
                        title: "Model unavailable",
                        message: "This model may have been removed on another device."
                    )
                }
            }
        }
        .flickSettingsListStyle()
        .flickToolbarTitle(model?.name ?? "Model")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    isDeleteConfirmationPresented = true
                }
                .disabled(model == nil)
            }
        }
        .confirmationDialog(
            "Delete Model",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Model", role: .destructive) {
                deleteModel()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .name:
                if let model {
                    ModelNameSheet(
                        title: "Model Name",
                        initialName: model.name,
                        confirmTitle: "Save",
                        saveAction: { name in
                            var updatedModel = model
                            updatedModel.name = name
                            try await appModel.updateCreationModel(updatedModel)
                        }
                    )
                }
            case let .section(section):
                if let model {
                    ModelCustomizationSheet(
                        model: model,
                        section: section,
                        saveAction: appModel.updateCreationModel
                    )
                }
            }
        }
    }

    private func modelSection(_ model: FlickCreationModel) -> some View {
        Section("Model") {
            FlickSettingsActionRow(
                title: "Name",
                systemImage: "textformat",
                iconColor: .blue,
                value: model.name,
                action: { activeSheet = .name }
            )
        }
    }

    private func overviewSection(_ model: FlickCreationModel) -> some View {
        Section("Overview") {
            ForEach(CreationModelSection.allCases) { section in
                FlickSettingsActionRow(
                    title: section.title,
                    systemImage: section.systemImage,
                    iconColor: section.tint,
                    value: section.summary(for: model.metadata),
                    valueLineLimit: 2,
                    action: { activeSheet = .section(section) }
                )
            }
        }
    }

    private func randomizeSection(_ model: FlickCreationModel) -> some View {
        Section {
            FlickSettingsActionRow(
                title: "Randomize",
                systemImage: "shuffle",
                iconColor: .orange,
                showsChevron: false,
                action: { randomizeModel(model) }
            )
        }
    }

    private func deleteModel() {
        Task {
            do {
                try await appModel.deleteCreationModel(id: modelID)
                dismiss()
            } catch {
                appModel.lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func randomizeModel(_ model: FlickCreationModel) {
        Task {
            do {
                var updatedModel = model
                updatedModel.metadata = CreationModelMetadata.randomized()
                try await appModel.updateCreationModel(updatedModel)
            } catch {
                appModel.lastErrorMessage = error.localizedDescription
            }
        }
    }
}

private enum ModelDetailSheet: Identifiable {
    case name
    case section(CreationModelSection)

    var id: String {
        switch self {
        case .name: "name"
        case let .section(section): "section-\(section.id)"
        }
    }
}

private struct ModelCreateSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedPreset: CreationModelPreset = .fromScratch
    @State private var isSaving = false
    @State private var errorMessage: String?

    var saveAction: (String, CreationModelMetadata) async throws -> Void

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Name") {
                    #if os(iOS)
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    #else
                    TextField("Name", text: $name)
                    #endif
                }

                Section("Preset") {
                    ForEach(CreationModelPreset.allCases) { preset in
                        Button {
                            selectedPreset = preset
                        } label: {
                            ModelPresetRow(
                                preset: preset,
                                isSelected: selectedPreset == preset
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let errorMessage {
                    Section("Error") {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .flickSettingsListStyle()
            .flickToolbarTitle("New Model")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", systemImage: "checkmark") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        guard canSave else { return }

        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await saveAction(name, selectedPreset.metadata)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

private struct ModelPresetRow: View {
    var preset: CreationModelPreset
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: preset.systemImage)
                .foregroundStyle(preset.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(preset.title)
                    .foregroundStyle(.primary)

                Text(preset.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(FlickStyle.appTint)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct ModelNameSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    var title: String
    var confirmTitle: String
    var saveAction: (String) async throws -> Void

    init(
        title: String,
        initialName: String,
        confirmTitle: String,
        saveAction: @escaping (String) async throws -> Void
    ) {
        self.title = title
        self.confirmTitle = confirmTitle
        self.saveAction = saveAction
        _name = State(initialValue: initialName)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Name") {
                    #if os(iOS)
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    #else
                    TextField("Name", text: $name)
                    #endif
                }

                if let errorMessage {
                    Section("Error") {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .flickSettingsListStyle()
            .flickToolbarTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle, systemImage: "checkmark") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        guard canSave else { return }

        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await saveAction(name)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

private struct ModelCustomizationSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draftMetadata: CreationModelMetadata
    @State private var isSaving = false
    @State private var errorMessage: String?

    var model: FlickCreationModel
    var section: CreationModelSection
    var saveAction: (FlickCreationModel) async throws -> Void

    init(
        model: FlickCreationModel,
        section: CreationModelSection,
        saveAction: @escaping (FlickCreationModel) async throws -> Void
    ) {
        self.model = model
        self.section = section
        self.saveAction = saveAction
        _draftMetadata = State(initialValue: model.metadata)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(section.fields) { field in
                    Section(field.title) {
                        CreationModelPickerRow(
                            field: field,
                            systemImage: section.systemImage,
                            iconColor: section.tint,
                            value: Binding(
                                get: { draftMetadata[keyPath: field.keyPath] },
                                set: { draftMetadata[keyPath: field.keyPath] = $0 }
                            )
                        )
                    }
                }

                if let errorMessage {
                    Section("Error") {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .flickSettingsListStyle()
            .flickToolbarTitle(section.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        save()
                    }
                    .disabled(isSaving)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        guard !isSaving else { return }

        isSaving = true
        errorMessage = nil

        Task {
            do {
                var updatedModel = model
                updatedModel.metadata = draftMetadata
                try await saveAction(updatedModel)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

private struct CreationModelPickerRow: View {
    var field: CreationModelField
    var systemImage: String
    var iconColor: Color
    @Binding var value: String

    var body: some View {
        FlickSettingsRow(
            title: "Selection",
            systemImage: systemImage,
            iconColor: iconColor
        ) {
            Menu {
                Button {
                    value = ""
                } label: {
                    if value.isEmpty {
                        Label("Not set", systemImage: "checkmark")
                    } else {
                        Text("Not set")
                    }
                }

                ForEach(field.options, id: \.self) { option in
                    Button {
                        value = option
                    } label: {
                        if value == option {
                            Label(option, systemImage: "checkmark")
                        } else {
                            Text(option)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(value.isEmpty ? "Not set" : value)
                        .foregroundStyle(value.isEmpty ? .orange : .secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

private extension FlickCreationModel {
    var listSummary: String {
        let values = [
            CreationModelSection.identity.summary(for: metadata),
            CreationModelSection.ethnicity.summary(for: metadata),
            CreationModelSection.styleAndAccessories.summary(for: metadata)
        ]
        .filter { $0 != "Not set" }

        guard !values.isEmpty else { return "Not set" }
        return values.joined(separator: " / ")
    }
}

private extension CreationModelPreset {
    var systemImage: String {
        switch self {
        case .fromScratch: "square.dashed"
        case .hotBlondeFitnessInfluencer: "iphone"
        case .fitBlackGuy: "figure.strengthtraining.traditional"
        case .attractiveBrunette: "sparkles"
        case .fitWhiteBrunetteMale: "figure.run"
        }
    }

    var tint: Color {
        switch self {
        case .fromScratch: .secondary
        case .hotBlondeFitnessInfluencer: .pink
        case .fitBlackGuy: .teal
        case .attractiveBrunette: .purple
        case .fitWhiteBrunetteMale: .blue
        }
    }
}

private extension CreationModelSection {
    var systemImage: String {
        switch self {
        case .identity: "person.crop.circle"
        case .ethnicity: "globe.americas"
        case .skinDetails: "sparkles"
        case .faceShape: "face.smiling"
        case .faceDetails: "person.crop.circle.badge"
        case .hair: "comb"
        case .eyesAndBrows: "eye"
        case .noseAndEars: "ear"
        case .body: "figure.stand"
        case .styleAndAccessories: "eyeglasses"
        }
    }

    var tint: Color {
        switch self {
        case .identity: .blue
        case .ethnicity: .green
        case .skinDetails: .pink
        case .faceShape: .orange
        case .faceDetails: .purple
        case .hair: .brown
        case .eyesAndBrows: .teal
        case .noseAndEars: .indigo
        case .body: .cyan
        case .styleAndAccessories: FlickStyle.appTint
        }
    }
}

#Preview {
    @Previewable @State var appModel = FlickAppModel.live()
    IOSModelsView()
        .environment(appModel)
}
#endif
