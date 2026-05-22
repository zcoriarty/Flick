//
//  MacModelsView.swift
//  Flick
//

#if os(macOS) || targetEnvironment(macCatalyst)
import SwiftUI

struct MacModelsView: View {
    @Environment(FlickAppModel.self) private var appModel

    @State private var selectedModelID: UUID?
    @State private var isNewModelSheetPresented = false
    @State private var activeSheet: MacModelDetailSheet?
    @State private var isDeleteConfirmationPresented = false

    private var selectedModel: FlickCreationModel? {
        selectedModelID.flatMap { selectedID in
            appModel.overview.creationModels.first { $0.id == selectedID }
        } ?? appModel.overview.creationModels.first
    }

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            modelSidebar
                .frame(width: 300)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .macWorkspacePage()
        .navigationTitle("Models")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Model", systemImage: "plus") {
                    isNewModelSheetPresented = true
                }
            }
        }
        .sheet(isPresented: $isNewModelSheetPresented) {
            MacModelCreateSheet(
                saveAction: { name, metadata in
                    let model = try await appModel.createCreationModel(name: name, metadata: metadata)
                    selectedModelID = model.id
                }
            )
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .name:
                if let selectedModel {
                    MacModelNameSheet(
                        title: "Model Name",
                        initialName: selectedModel.name,
                        confirmTitle: "Save",
                        saveAction: { name in
                            var updatedModel = selectedModel
                            updatedModel.name = name
                            try await appModel.updateCreationModel(updatedModel)
                        }
                    )
                }
            case let .section(section):
                if let selectedModel {
                    MacModelCustomizationSheet(
                        model: selectedModel,
                        section: section,
                        saveAction: appModel.updateCreationModel
                    )
                }
            }
        }
        .confirmationDialog(
            "Delete Model",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Model", role: .destructive) {
                deleteSelectedModel()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear(perform: reconcileSelection)
        .onChange(of: appModel.overview.creationModels) { _, _ in
            reconcileSelection()
        }
    }

    private var modelSidebar: some View {
        MacWorkspacePanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Models")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Text(appModel.overview.creationModels.count.formatted())
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if appModel.overview.creationModels.isEmpty {
                    MacInlineEmptyState(
                        title: "No models",
                        message: "Create a reusable character model before using it in a generation flow.",
                        systemImage: "person.crop.square"
                    )
                } else {
                    VStack(spacing: 8) {
                        ForEach(appModel.overview.creationModels) { model in
                            MacModelSidebarRow(
                                model: model,
                                isSelected: selectedModel?.id == model.id
                            ) {
                                selectedModelID = model.id
                            }
                        }
                    }
                }

                Button("New Model", systemImage: "plus", action: { isNewModelSheetPresented = true })
                    .buttonStyle(.glassProminent)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedModel {
            MacModelDetail(
                model: selectedModel,
                editNameAction: { activeSheet = .name },
                editSectionAction: { activeSheet = .section($0) },
                randomizeAction: { randomizeModel(selectedModel) },
                deleteAction: { isDeleteConfirmationPresented = true }
            )
        } else {
            MacInlineEmptyState(
                title: "No model selected",
                message: "Create a model to define reusable character details for generated slideshows.",
                systemImage: "person.crop.square"
            )
        }
    }

    private func reconcileSelection() {
        guard let selectedModelID else {
            self.selectedModelID = appModel.overview.creationModels.first?.id
            return
        }

        guard appModel.overview.creationModels.contains(where: { $0.id == selectedModelID }) else {
            self.selectedModelID = appModel.overview.creationModels.first?.id
            return
        }
    }

    private func deleteSelectedModel() {
        guard let model = selectedModel else { return }
        Task {
            do {
                try await appModel.deleteCreationModel(id: model.id)
                selectedModelID = appModel.overview.creationModels.first?.id
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

private struct MacModelSidebarRow: View {
    var model: FlickCreationModel
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.crop.square")
                    .foregroundStyle(isSelected ? FlickStyle.appTint : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(model.macListSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(isSelected ? FlickStyle.appTint.opacity(0.12) : Color.clear, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private struct MacModelDetail: View {
    var model: FlickCreationModel
    var editNameAction: () -> Void
    var editSectionAction: (CreationModelSection) -> Void
    var randomizeAction: () -> Void
    var deleteAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            MacWorkspaceHeader(
                title: model.name,
                subtitle: model.macListSummary,
                metrics: [
                    MacWorkspaceMetric(title: "Sections", value: CreationModelSection.allCases.count.formatted()),
                    MacWorkspaceMetric(title: "Updated", value: model.updatedAt.formatted(date: .abbreviated, time: .omitted))
                ]
            )

            HStack(spacing: 10) {
                Button("Rename", systemImage: "textformat", action: editNameAction)
                Button("Randomize", systemImage: "shuffle", action: randomizeAction)
                Button("Delete", systemImage: "trash", role: .destructive, action: deleteAction)
            }

            MacWorkspaceSection(title: "Model Profile", systemImage: "person.text.rectangle") {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 14, alignment: .top)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(CreationModelSection.allCases) { section in
                        MacModelSectionCard(
                            section: section,
                            metadata: model.metadata
                        ) {
                            editSectionAction(section)
                        }
                    }
                }
            }
        }
    }
}

private struct MacModelSectionCard: View {
    var section: CreationModelSection
    var metadata: CreationModelMetadata
    var editAction: () -> Void

    var body: some View {
        MacWorkspacePanel(minHeight: 158) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: section.macSystemImage)
                        .font(.title3)
                        .foregroundStyle(section.macTint)
                        .frame(width: 26)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.title)
                            .font(.headline)
                        Text(section.summary(for: metadata))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .layoutPriority(1)
                }

                Spacer(minLength: 0)

                Button("Edit", systemImage: "slider.horizontal.3", action: editAction)
                    .buttonStyle(.borderless)
            }
        }
    }
}

private enum MacModelDetailSheet: Identifiable {
    case name
    case section(CreationModelSection)

    var id: String {
        switch self {
        case .name: "name"
        case let .section(section): "section-\(section.id)"
        }
    }
}

private struct MacModelCreateSheet: View {
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
                    TextField("Name", text: $name)
                }

                Section("Preset") {
                    ForEach(CreationModelPreset.allCases) { preset in
                        Button {
                            selectedPreset = preset
                        } label: {
                            MacModelPresetRow(
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
        .frame(minWidth: 420, minHeight: 560)
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

private struct MacModelPresetRow: View {
    var preset: CreationModelPreset
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: preset.macSystemImage)
                .foregroundStyle(preset.macTint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(preset.title)
                    .foregroundStyle(.primary)
                Text(preset.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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

private struct MacModelNameSheet: View {
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
                    TextField("Name", text: $name)
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
        .frame(minWidth: 420, minHeight: 260)
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

private struct MacModelCustomizationSheet: View {
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
                        MacCreationModelPickerRow(
                            field: field,
                            systemImage: section.macSystemImage,
                            iconColor: section.macTint,
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
        .frame(minWidth: 500, minHeight: 620)
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

private struct MacCreationModelPickerRow: View {
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
    var macListSummary: String {
        let values = [
            CreationModelSection.identity.summary(for: metadata),
            CreationModelSection.ethnicity.summary(for: metadata),
            CreationModelSection.hair.summary(for: metadata),
            CreationModelSection.styleAndAccessories.summary(for: metadata)
        ]
        .filter { $0 != "Not set" }

        guard !values.isEmpty else { return "Not set" }
        return values.joined(separator: " / ")
    }
}

private extension CreationModelPreset {
    var macSystemImage: String {
        switch self {
        case .fromScratch: "square.dashed"
        case .cottageHost: "leaf"
        case .studioFounder: "briefcase"
        case .wellnessCreator: "sun.max"
        case .streetwearEditor: "camera"
        case .fitnessCoach: "figure.strengthtraining.traditional"
        }
    }

    var macTint: Color {
        switch self {
        case .fromScratch: .secondary
        case .cottageHost: .green
        case .studioFounder: .blue
        case .wellnessCreator: .orange
        case .streetwearEditor: .purple
        case .fitnessCoach: .teal
        }
    }
}

private extension CreationModelSection {
    var macSystemImage: String {
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

    var macTint: Color {
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
#endif
