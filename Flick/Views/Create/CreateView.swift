//
//  CreateView.swift
//  Flick
//

import Foundation
import SwiftUI

private enum CreateSheet: String, Identifiable {
    case templatePicker
    case drafts
    case slideEditor
    case tikTokSettings
    case songPicker
    case publishProgress

    var id: String { rawValue }
}

struct CreateView: View {
    @Environment(FlickAppModel.self) private var appModel

    @State private var templateLoadState: CreateTemplateLoadState = .loading
    @State private var isAutomated = false
    @State private var selectedTemplate: ExampleSlideshowTemplate?
    @State private var selectedAutomationTemplateIDs: Set<String> = []
    @State private var selectedCreationModel: SlideshowCreationModelReference?
    @State private var selectedProductID: UUID?
    @State private var selectedProductImageAssetID: UUID?
    @State private var selectedAutomationProductImageAssetIDs: Set<UUID> = []
    @State private var automationSchedule = AutomationSchedule.default
    @State private var automationTikTokSettings = DraftTikTokSettings()
    @State private var automationName = ""
    @State private var editingAutomationID: UUID?
    @State private var isStartingAutomation = false
    @State private var showsAutomationStartSuccess = false
    @State private var automationSuccessDismissTask: Task<Void, Never>?
    @State private var createFormResetID = UUID()
    @State private var presentedSheet: CreateSheet?
    @State private var selectedSlideID: UUID?
    @State private var slideEditorDetent: PresentationDetent = .large

    private var tiktokAccountName: String? {
        publishingTikTokAccount(in: appModel)?.displayName
    }

    var body: some View {
        @Bindable var appModel = appModel
        let currentDraftID = activeDraftID(in: appModel)
        let currentDraftIndex = currentDraftID.flatMap { draftID in
            appModel.overview.drafts.firstIndex { $0.id == draftID }
        }

        ZStack {
            createFormList(
                in: appModel,
                currentDraftID: currentDraftID,
                currentDraftIndex: currentDraftIndex
            )

            if showsAutomationStartSuccess {
                CreateAutomationStartSuccessView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.snappy, value: showsAutomationStartSuccess)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                createToolbarTitle(in: appModel)
            }
            .sharedBackgroundVisibility(.hidden)
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                draftsButton
            }
            #else
            ToolbarItem(placement: .navigation) {
                draftsButton
            }
            #endif
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    if isAutomated {
                        publishAutomation(using: appModel)
                    } else {
                        publishManualPost(using: appModel)
                    }
                } label: {
                    if isPrimaryActionBusy(in: appModel) {
                        ProgressView()
                    } else {
                        Text(isAutomated ? "Start" : "Publish")
                    }
                }
                .disabled(!canPublish(in: appModel) || isPrimaryActionBusy(in: appModel) || showsAutomationStartSuccess)
            }
        }
        .task {
            if case .loading = templateLoadState {
                loadTemplates()
            }
            syncCreationModelSelectionFromActiveDraft(in: appModel)
            updateSelectedSlide(using: appModel)
        }
        .onChange(of: appModel.activeCreateDraftID) { _, _ in
            syncCreationModelSelectionFromActiveDraft(in: appModel)
            updateSelectedSlide(using: appModel)
        }
        .onChange(of: appModel.overview.drafts) { _, _ in
            updateSelectedSlide(using: appModel)
            Task {
                await appModel.persistCreateState()
            }
        }
        .onChange(of: appModel.overview.templates) { _, _ in
            Task {
                await appModel.persistCreateState()
            }
        }
        .onChange(of: appModel.overview.products) { _, _ in
            reconcileProductSelection(in: appModel)
            reconcileAutomationProductSelection(in: appModel)
        }
        .onChange(of: appModel.overview.assets) { _, _ in
            reconcileProductSelection(in: appModel)
            reconcileAutomationProductSelection(in: appModel)
        }
        .onChange(of: appModel.overview.creationModels) { _, _ in
            refreshSelectedCreationModel(in: appModel)
        }
        .onChange(of: selectedCreationModel) { _, _ in
            updateActiveDraftCreationModel(in: appModel)
        }
        .onChange(of: isAutomated) { _, newValue in
            if !newValue {
                syncCreationModelSelectionFromActiveDraft(in: appModel)
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .templatePicker:
                if isAutomated {
                    AutomationTemplatePickerSheet(
                        collections: templateLoadState.collections,
                        selectedTemplateIDs: $selectedAutomationTemplateIDs
                    )
                } else {
                    TemplatePickerSheet(
                        collections: templateLoadState.collections,
                        selectedTemplate: $selectedTemplate
                    )
                }
            case .drafts:
                CreateDraftsSheet(
                    drafts: appModel.createDrafts,
                    assetsByID: Dictionary(uniqueKeysWithValues: appModel.overview.assets.map { ($0.id, $0) }),
                    selectedDraftID: appModel.activeCreateDraftID,
                    selectAction: { draftID in
                        appModel.selectCreateDraft(id: draftID)
                        syncCreationModelSelectionFromActiveDraft(in: appModel)
                        updateSelectedSlide(using: appModel)
                    },
                    deleteAction: { draftID in
                        Task { @MainActor in
                            await appModel.deleteCreateDraft(id: draftID)
                            updateSelectedSlide(using: appModel)
                        }
                    }
                )
            case .slideEditor:
                if
                    let currentDraftID = activeDraftID(in: appModel),
                    let draftIndex = appModel.overview.drafts.firstIndex(where: { $0.id == currentDraftID })
                {
                    let draft = appModel.overview.drafts[draftIndex]
                    let assetsByID = Dictionary(uniqueKeysWithValues: appModel.overview.assets.map { ($0.id, $0) })

                    CreateSlideEditor(
                        draft: $appModel.overview.drafts[draftIndex],
                        selectedSlideID: $selectedSlideID,
                        assetsByID: assetsByID,
                        isGenerating: appModel.isGeneratingSlideshowImages,
                        moveAction: { slideID, direction in
                            appModel.moveSlide(slideID, in: draft.id, direction: direction)
                        },
                        duplicateAction: { slideID in
                            appModel.duplicateSlide(slideID, in: draft.id)
                        },
                        deleteAction: { slideID in
                            appModel.deleteSlide(slideID, in: draft.id)
                        },
                        rewritePromptAction: { slideID, instruction in
                            Task {
                                await appModel.rewritePrompt(for: slideID, in: draft.id, instruction: instruction)
                            }
                        },
                        regenerateAction: { slideID, instruction in
                            Task {
                                await appModel.regenerateSlideImage(slideID: slideID, in: draft.id, instruction: instruction)
                            }
                        }
                    )
                    .presentationDetents([.medium, .large], selection: $slideEditorDetent)
                    .presentationDragIndicator(.visible)
                } else {
                    CreateMessageRow(
                        title: "No slide selected",
                        message: "Select a slide from the rail to edit it."
                    )
                }
            case .tikTokSettings:
                if isAutomated {
                    TikTokSettingsSheet(
                        accountName: tiktokAccountName,
                        postTitle: $automationTikTokSettings.title,
                        postAsDraft: $automationTikTokSettings.postAsDraft,
                        selectedVisibility: automationSelectedVisibilityBinding,
                        allowComment: $automationTikTokSettings.allowComment,
                        allowDuet: $automationTikTokSettings.allowDuet,
                        allowStitch: $automationTikTokSettings.allowStitch,
                        disclosesVideoContent: $automationTikTokSettings.disclosesVideoContent,
                        promotesYourBrand: $automationTikTokSettings.promotesYourBrand,
                        promotesBrandedContent: $automationTikTokSettings.promotesBrandedContent
                    )
                } else if let currentDraftID = activeDraftID(in: appModel) {
                    TikTokSettingsSheet(
                        accountName: tiktokAccountName,
                        postTitle: tikTokSettingBinding(in: appModel, draftID: currentDraftID, keyPath: \.title),
                        postAsDraft: tikTokSettingBinding(in: appModel, draftID: currentDraftID, keyPath: \.postAsDraft),
                        selectedVisibility: selectedVisibilityBinding(in: appModel, draftID: currentDraftID),
                        allowComment: tikTokSettingBinding(in: appModel, draftID: currentDraftID, keyPath: \.allowComment),
                        allowDuet: tikTokSettingBinding(in: appModel, draftID: currentDraftID, keyPath: \.allowDuet),
                        allowStitch: tikTokSettingBinding(in: appModel, draftID: currentDraftID, keyPath: \.allowStitch),
                        disclosesVideoContent: tikTokSettingBinding(in: appModel, draftID: currentDraftID, keyPath: \.disclosesVideoContent),
                        promotesYourBrand: tikTokSettingBinding(in: appModel, draftID: currentDraftID, keyPath: \.promotesYourBrand),
                        promotesBrandedContent: tikTokSettingBinding(in: appModel, draftID: currentDraftID, keyPath: \.promotesBrandedContent)
                    )
                } else {
                    CreateMessageRow(
                        title: "No draft selected",
                        message: "Create or resume a slideshow draft before editing TikTok settings."
                    )
                }
            case .songPicker:
                #if os(iOS) && canImport(MediaPlayer)
                if let currentDraftID = activeDraftID(in: appModel) {
                    MediaLibraryPicker(selectedSongs: selectedSongsBinding(in: appModel, draftID: currentDraftID))
                } else {
                    EmptyView()
                }
                #else
                EmptyView()
                #endif
            case .publishProgress:
                CreatePublishProgressSheet(progress: appModel.manualPublishProgress)
            }
        }
        .onDisappear {
            automationSuccessDismissTask?.cancel()
        }
    }

    private func createFormList(
        in appModel: FlickAppModel,
        currentDraftID: UUID?,
        currentDraftIndex: Int?
    ) -> some View {
        List {
            CreateAutomationSection(
                isAutomated: $isAutomated,
                schedule: $automationSchedule
            )

            if isAutomated {
                automatedSetupSections(in: appModel)
            } else {
                manualSetupSections(
                    in: appModel,
                    currentDraftID: currentDraftID,
                    currentDraftIndex: currentDraftIndex
                )
            }
        }
        .id(createFormResetID)
        .flickSettingsListStyle()
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
        .disabled(showsAutomationStartSuccess)
        .opacity(showsAutomationStartSuccess ? 0 : 1)
    }

    private var draftsButton: some View {
        Button("Drafts", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") {
            presentedSheet = .drafts
        }
    }

    @ViewBuilder
    private func createToolbarTitle(in appModel: FlickAppModel) -> some View {
        if isAutomated {
            TextField(
                automationDefaultName(in: appModel),
                text: $automationName,
                prompt: Text(automationDefaultName(in: appModel))
            )
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.system(.body, weight: .semibold))
            .frame(minWidth: 160, maxWidth: 280)
            .submitLabel(.done)
            .accessibilityLabel("Automation name")
        } else {
            Text("Create")
                .font(.system(.body, weight: .semibold))
        }
    }

    private var automationSelectedVisibilityBinding: Binding<TikTokAudience?> {
        Binding(
            get: { automationTikTokSettings.selectedAudience },
            set: { newValue in
                automationTikTokSettings.privacyLevel = newValue?.privacyLevel
            }
        )
    }

    @ViewBuilder
    private func automatedSetupSections(in appModel: FlickAppModel) -> some View {
        CreateAutomationTemplateSection(
            loadState: templateLoadState,
            selectedTemplateIDs: $selectedAutomationTemplateIDs,
            selectAction: { presentedSheet = .templatePicker },
            retryAction: loadTemplates
        )

        CreateModelSection(
            models: appModel.overview.creationModels,
            selectedModel: $selectedCreationModel
        )

        CreateAutomationProductImageSection(
            products: appModel.overview.products,
            productImageAssets: selectableProductImageAssets(in: appModel),
            selectedProductID: $selectedProductID,
            selectedProductImageAssetIDs: $selectedAutomationProductImageAssetIDs
        )

        CreateTikTokSettingsSection(
            accountName: tiktokAccountName,
            hasConfiguredSettings: automationTikTokSettings.automatedPublishSettings(description: "") != nil,
            postAsDraft: automationTikTokSettings.postAsDraft,
            selectedVisibility: automationTikTokSettings.selectedAudience,
            disclosesVideoContent: automationTikTokSettings.disclosesVideoContent,
            promotesYourBrand: automationTikTokSettings.promotesYourBrand,
            promotesBrandedContent: automationTikTokSettings.promotesBrandedContent,
            action: { presentedSheet = .tikTokSettings }
        )

        CreateAutomationsSection(
            automations: appModel.overview.automations,
            templates: allTemplates(in: templateLoadState),
            products: appModel.overview.products,
            editAction: loadAutomation,
            deleteAction: { deleteAutomation($0, using: appModel) }
        )
    }

    @ViewBuilder
    private func manualSetupSections(
        in appModel: FlickAppModel,
        currentDraftID: UUID?,
        currentDraftIndex: Int?
    ) -> some View {
        CreateTemplateSection(
            loadState: templateLoadState,
            selectedTemplate: selectedTemplate,
            selectAction: { presentedSheet = .templatePicker },
            clearAction: { selectedTemplate = nil },
            retryAction: loadTemplates
        )

        CreateModelSection(
            models: appModel.overview.creationModels,
            selectedModel: $selectedCreationModel
        )

        CreateProductImageSection(
            products: appModel.overview.products,
            productImageAssets: selectableProductImageAssets(in: appModel),
            selectedProductID: $selectedProductID,
            selectedProductImageAssetID: $selectedProductImageAssetID
        )

        AnalyzeTemplateSection(
            selectedTemplate: selectedTemplate,
            isPlanning: appModel.isPlanningSlideshow,
            hasAnalyzedTemplate: currentDraftID != nil,
            canAnalyze: canAnalyzeTemplate(in: appModel),
            action: analyzeTemplate
        )

        if let currentDraftID {
            CreateDraftWorkflowSections(
                appModel: appModel,
                draftID: currentDraftID,
                selectedSlideID: $selectedSlideID,
                openEditorAction: openSlideEditor
            )
        } else {
            Section("Slideshow") {
                CreateMessageRow(
                    title: "No slideshow plan yet",
                    message: "Select a template and analyze it to start editing slides, or open Drafts to resume an unposted draft."
                )
            }
        }

        manualPublishingSettingsSections(
            in: appModel,
            currentDraftID: currentDraftID,
            currentDraftIndex: currentDraftIndex
        )
    }

    @ViewBuilder
    private func manualPublishingSettingsSections(
        in appModel: FlickAppModel,
        currentDraftID: UUID?,
        currentDraftIndex: Int?
    ) -> some View {
        if let currentDraftID, let currentDraftIndex {
            let tikTokSettings = appModel.overview.drafts[currentDraftIndex].tikTokSettings

            CreateSongSection(
                selectedSongs: selectedSongsBinding(in: appModel, draftID: currentDraftID),
                selectAction: { presentedSheet = .songPicker }
            )

            CreateTikTokSettingsSection(
                accountName: tiktokAccountName,
                hasConfiguredSettings: tikTokSettings != nil,
                postAsDraft: tikTokSettings?.postAsDraft ?? false,
                selectedVisibility: tikTokSettings?.selectedAudience,
                disclosesVideoContent: tikTokSettings?.disclosesVideoContent ?? false,
                promotesYourBrand: tikTokSettings?.promotesYourBrand ?? false,
                promotesBrandedContent: tikTokSettings?.promotesBrandedContent ?? false,
                action: { presentedSheet = .tikTokSettings }
            )
        } else {
            CreateSongSection(
                selectedSongs: .constant([]),
                selectAction: {}
            )
            .disabled(true)

            CreateTikTokSettingsSection(
                accountName: tiktokAccountName,
                hasConfiguredSettings: false,
                postAsDraft: false,
                selectedVisibility: nil,
                disclosesVideoContent: false,
                promotesYourBrand: false,
                promotesBrandedContent: false,
                action: {}
            )
            .disabled(true)
        }
    }

    private func selectedSongsBinding(in appModel: FlickAppModel, draftID: UUID) -> Binding<[SelectedSong]> {
        Binding(
            get: {
                appModel.overview.drafts.first { $0.id == draftID }?.selectedSongs ?? []
            },
            set: { newValue in
                updateDraft(in: appModel, draftID: draftID) { draft in
                    draft.selectedSongs = newValue
                }
            }
        )
    }

    private func tikTokSettingBinding<Value>(
        in appModel: FlickAppModel,
        draftID: UUID,
        keyPath: WritableKeyPath<DraftTikTokSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                draftTikTokSettings(in: appModel, draftID: draftID)[keyPath: keyPath]
            },
            set: { newValue in
                updateTikTokSettings(in: appModel, draftID: draftID) { settings in
                    settings[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func selectedVisibilityBinding(in appModel: FlickAppModel, draftID: UUID) -> Binding<TikTokAudience?> {
        Binding(
            get: {
                draftTikTokSettings(in: appModel, draftID: draftID).selectedAudience
            },
            set: { newValue in
                updateTikTokSettings(in: appModel, draftID: draftID) { settings in
                    settings.privacyLevel = newValue?.privacyLevel
                }
            }
        )
    }

    private func draftTikTokSettings(in appModel: FlickAppModel, draftID: UUID) -> DraftTikTokSettings {
        appModel.overview.drafts.first { $0.id == draftID }?.tikTokSettings ?? DraftTikTokSettings()
    }

    private func updateTikTokSettings(
        in appModel: FlickAppModel,
        draftID: UUID,
        _ update: (inout DraftTikTokSettings) -> Void
    ) {
        updateDraft(in: appModel, draftID: draftID) { draft in
            var settings = draft.tikTokSettings ?? DraftTikTokSettings()
            update(&settings)
            draft.tikTokSettings = settings
        }
    }

    private func updateDraft(
        in appModel: FlickAppModel,
        draftID: UUID,
        _ update: (inout SlideshowDraft) -> Void
    ) {
        guard let draftIndex = appModel.overview.drafts.firstIndex(where: { $0.id == draftID }) else {
            return
        }

        update(&appModel.overview.drafts[draftIndex])
        appModel.overview.drafts[draftIndex].updatedAt = Date()
    }

    private func openSlideEditor() {
        slideEditorDetent = .large
        presentedSheet = .slideEditor
    }

    private func resetCreateFlowAfterSuccessfulManualPublish(draftID: UUID, using appModel: FlickAppModel) {
        if appModel.activeCreateDraftID == draftID {
            appModel.clearActiveCreateDraft()
        }
        selectedTemplate = nil
        selectedProductID = nil
        selectedProductImageAssetID = nil
        selectedCreationModel = nil
        selectedSlideID = nil
    }

    private func clearAutomationForm() {
        editingAutomationID = nil
        automationName = ""
        selectedAutomationTemplateIDs = []
        selectedCreationModel = nil
        selectedProductID = nil
        selectedAutomationProductImageAssetIDs = []
        automationSchedule = .default
        automationTikTokSettings = DraftTikTokSettings()
    }

    private func loadTemplates() {
        templateLoadState = .loading
        do {
            templateLoadState = .loaded(try ExampleSlideshowLibrary.load())
        } catch {
            templateLoadState = .failed(error.localizedDescription)
        }
    }

    private func loadAutomation(_ automation: ContentAutomation) {
        isAutomated = true
        editingAutomationID = automation.id
        automationName = automation.name
        selectedAutomationTemplateIDs = Set(automation.templateIDs)
        selectedCreationModel = automation.creationModel
        selectedProductID = automation.productID
        selectedAutomationProductImageAssetIDs = Set(automation.productImageAssetIDs)
        automationSchedule = automation.schedule
        automationSchedule.reconcileFixedTimes()
        automationTikTokSettings = automation.tikTokSettings
    }

    private func deleteAutomation(_ automation: ContentAutomation, using appModel: FlickAppModel) {
        Task {
            await appModel.deleteAutomation(id: automation.id)
            if editingAutomationID == automation.id {
                clearAutomationForm()
            }
        }
    }

    private func allTemplates(in loadState: CreateTemplateLoadState) -> [ExampleSlideshowTemplate] {
        loadState.collections
            .flatMap(\.templates)
            .filter(\.hasDisplayablePreview)
    }

    private func automationDefaultName(in appModel: FlickAppModel) -> String {
        automationDraft(using: appModel, now: Date())
            .defaultName(templates: allTemplates(in: templateLoadState), products: appModel.overview.products)
    }

    private func canPublish(in appModel: FlickAppModel) -> Bool {
        if isAutomated {
            return canPublishAutomation(in: appModel)
        }
        return canPublishManualPost(in: appModel)
    }

    private func isPrimaryActionBusy(in appModel: FlickAppModel) -> Bool {
        isAutomated ? isStartingAutomation : appModel.isPublishingSlideshow
    }

    private func canPublishAutomation(in appModel: FlickAppModel) -> Bool {
        let automation = automationDraft(using: appModel, now: Date())
        return automation.isReadyToSchedule
            && selectedAutomationSelectionsAreAvailable(in: appModel)
            && publishingTikTokAccount(in: appModel) != nil
    }

    private func publishAutomation(using appModel: FlickAppModel) {
        guard canPublishAutomation(in: appModel), !isStartingAutomation else { return }
        let automation = automationDraft(using: appModel, now: Date())
        isStartingAutomation = true
        Task { @MainActor in
            let didStart = await appModel.upsertAutomation(automation)
            isStartingAutomation = false
            guard didStart else { return }
            showAutomationStartSuccess()
        }
    }

    private func showAutomationStartSuccess() {
        automationSuccessDismissTask?.cancel()
        withAnimation(.snappy) {
            showsAutomationStartSuccess = true
        }
        automationSuccessDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1350))
            guard !Task.isCancelled else { return }
            clearAutomationForm()
            createFormResetID = UUID()
            withAnimation(.snappy) {
                showsAutomationStartSuccess = false
            }
        }
    }

    private func automationDraft(using appModel: FlickAppModel, now: Date) -> ContentAutomation {
        let automationID = editingAutomationID ?? UUID()
        var schedule = automationSchedule
        schedule.reconcileFixedTimes()

        let nextScheduledAt = schedule.nextOccurrence(after: now, automationID: automationID)
        return ContentAutomation(
            id: automationID,
            name: automationName.trimmingCharacters(in: .whitespacesAndNewlines),
            templateIDs: Array(selectedAutomationTemplateIDs).sorted(),
            productID: selectedProductID,
            productImageAssetIDs: Array(selectedAutomationProductImageAssetIDs).sorted { $0.uuidString < $1.uuidString },
            creationModel: selectedCreationModel,
            schedule: schedule,
            tikTokSettings: automationTikTokSettings,
            targetPlatforms: [.tiktok],
            status: .active,
            nextScheduledAt: nextScheduledAt,
            createdAt: appModel.overview.automations.first(where: { $0.id == automationID })?.createdAt ?? now,
            updatedAt: now
        )
    }

    private func analyzeTemplate() {
        guard let selectedTemplate else { return }
        let productImage = selectedProductImageContext(in: appModel)
        Task {
            await appModel.createAISlideshow(
                brief: "",
                from: selectedTemplate,
                creationModel: selectedCreationModel,
                productImage: productImage
            )
            updateSelectedSlide(using: appModel)
        }
    }

    private func canAnalyzeTemplate(in appModel: FlickAppModel) -> Bool {
        guard selectedTemplate != nil else { return false }
        guard let selectedProductID else { return true }
        let imageAssets = selectableProductImageAssets(in: appModel).filter { asset in
            asset.productIDs.contains(selectedProductID)
        }
        guard !imageAssets.isEmpty else { return false }
        return selectedProductImageAssetID.map { selectedAssetID in
            imageAssets.contains { $0.id == selectedAssetID }
        } == true
    }

    private func selectedAutomationSelectionsAreAvailable(in appModel: FlickAppModel) -> Bool {
        let templateIDs = Set(allTemplates(in: templateLoadState).map(\.id))
        guard !selectedAutomationTemplateIDs.isEmpty else { return false }
        guard selectedAutomationTemplateIDs.isSubset(of: templateIDs) else { return false }
        guard let selectedProductID, appModel.overview.products.contains(where: { $0.id == selectedProductID }) else {
            return false
        }

        let availableImageIDs = Set(
            selectableProductImageAssets(in: appModel)
                .filter { $0.productIDs.contains(selectedProductID) }
                .map(\.id)
        )
        return !selectedAutomationProductImageAssetIDs.isEmpty
            && selectedAutomationProductImageAssetIDs.isSubset(of: availableImageIDs)
    }

    private func selectableProductImageAssets(in appModel: FlickAppModel) -> [MediaAsset] {
        appModel.productMediaAssets.filter { asset in
            asset.mediaType == .image && asset.hasAvailableMediaLocation
        }
    }

    private func selectedProductImageContext(in appModel: FlickAppModel) -> SlideshowProductImage? {
        guard
            let selectedProductID,
            let product = appModel.overview.products.first(where: { $0.id == selectedProductID })
        else {
            return nil
        }

        let productImages = selectableProductImageAssets(in: appModel).filter { asset in
            asset.productIDs.contains(selectedProductID)
        }
        let asset = selectedProductImageAssetID.flatMap { selectedAssetID in
            productImages.first { $0.id == selectedAssetID }
        }

        guard let asset else { return nil }
        return SlideshowProductImage(product: product, asset: asset)
    }

    private func reconcileProductSelection(in appModel: FlickAppModel) {
        if let selectedProductID, !appModel.overview.products.contains(where: { $0.id == selectedProductID }) {
            self.selectedProductID = nil
            selectedProductImageAssetID = nil
            return
        }

        guard let selectedProductImageAssetID else { return }
        let imageAssets = selectableProductImageAssets(in: appModel)
        guard imageAssets.contains(where: { $0.id == selectedProductImageAssetID }) else {
            self.selectedProductImageAssetID = nil
            return
        }
    }

    private func reconcileAutomationProductSelection(in appModel: FlickAppModel) {
        guard let selectedProductID else {
            selectedAutomationProductImageAssetIDs.removeAll()
            return
        }
        guard appModel.overview.products.contains(where: { $0.id == selectedProductID }) else {
            self.selectedProductID = nil
            selectedAutomationProductImageAssetIDs.removeAll()
            return
        }

        let availableIDs = Set(
            selectableProductImageAssets(in: appModel)
                .filter { $0.productIDs.contains(selectedProductID) }
                .map(\.id)
        )
        selectedAutomationProductImageAssetIDs = selectedAutomationProductImageAssetIDs.intersection(availableIDs)
    }

    private func canPublishManualPost(in appModel: FlickAppModel) -> Bool {
        guard let draft = appModel.activeCreateDraft else { return false }
        let assetsByID = Dictionary(uniqueKeysWithValues: appModel.overview.assets.map { ($0.id, $0) })
        return draft.hasCompletedCreateImages(assetsByID: assetsByID)
            && publishingTikTokAccount(in: appModel) != nil
            && publishSettings(for: draft) != nil
    }

    private func publishManualPost(using appModel: FlickAppModel) {
        guard let draft = appModel.activeCreateDraft, let settings = publishSettings(for: draft) else { return }
        appModel.beginManualPublishProgress(for: draft)
        presentedSheet = .publishProgress
        Task { @MainActor in
            let didPublish = await appModel.publishManualSlideshow(draftID: draft.id, settings: settings)
            if didPublish, !settings.postAsDraft {
                resetCreateFlowAfterSuccessfulManualPublish(draftID: draft.id, using: appModel)
            }
        }
    }

    private func publishSettings(for draft: SlideshowDraft) -> TikTokManualPublishSettings? {
        guard let settings = draft.tikTokSettings else { return nil }
        return settings.manualPublishSettings(description: draft.publishDescription)
    }

    private func publishingTikTokAccount(in appModel: FlickAppModel) -> ConnectedAccount? {
        appModel.overview.accounts.first { account in
            account.platform == .tiktok
                && account.authorizationSource == .loginKit
                && account.status == .connected
                && account.isPublishingEnabled
        }
    }

    private func activeDraftID(in appModel: FlickAppModel) -> UUID? {
        appModel.activeCreateDraft?.id
    }

    private func updateSelectedSlide(using appModel: FlickAppModel) {
        guard
            let activeDraftID = activeDraftID(in: appModel),
            let draftIndex = appModel.overview.drafts.firstIndex(where: { $0.id == activeDraftID }),
            !appModel.overview.drafts[draftIndex].slides.isEmpty
        else {
            selectedSlideID = nil
            return
        }

        let draft = appModel.overview.drafts[draftIndex]
        if let selectedSlideID, draft.slides.contains(where: { $0.id == selectedSlideID }) {
            return
        }
        selectedSlideID = draft.slides.sorted { $0.index < $1.index }.first?.id
    }

    private func syncCreationModelSelectionFromActiveDraft(in appModel: FlickAppModel) {
        guard !isAutomated, let draft = appModel.activeCreateDraft else { return }
        selectedCreationModel = draft.creationModel
    }

    private func refreshSelectedCreationModel(in appModel: FlickAppModel) {
        guard let selectedCreationModel else { return }
        guard let model = appModel.overview.creationModels.first(where: { $0.id == selectedCreationModel.id }) else {
            return
        }
        self.selectedCreationModel = model.generationReference
    }

    private func updateActiveDraftCreationModel(in appModel: FlickAppModel) {
        guard !isAutomated, let draftID = activeDraftID(in: appModel) else { return }
        guard appModel.overview.drafts.first(where: { $0.id == draftID })?.creationModel != selectedCreationModel else {
            return
        }
        updateDraft(in: appModel, draftID: draftID) { draft in
            draft.creationModel = selectedCreationModel
        }
    }
}

private struct CreateDraftWorkflowSections: View {
    @Bindable var appModel: FlickAppModel
    var draftID: UUID
    @Binding var selectedSlideID: UUID?
    var openEditorAction: () -> Void

    var body: some View {
        if let draftIndex = appModel.overview.drafts.firstIndex(where: { $0.id == draftID }) {
            let draftBinding = $appModel.overview.drafts[draftIndex]
            let draft = appModel.overview.drafts[draftIndex]
            let assetsByID = Dictionary(uniqueKeysWithValues: appModel.overview.assets.map { ($0.id, $0) })

            if let templateIndex = activeTemplateIndex(for: draft) {
                CreatePlanSection(
                    draft: draftBinding,
                    styleGuideJSON: $appModel.overview.templates[templateIndex].styleJSON
                )
            } else {
                CreatePlanSection(
                    draft: draftBinding,
                    styleGuideJSON: .constant("")
                )
            }

            CreateGenerationControls(
                draft: draft,
                assetsByID: assetsByID,
                isGenerating: appModel.isGeneratingSlideshowImages,
                message: appModel.createWorkflowMessage,
                generateAction: {
                    Task {
                        if draft.createMissingImageCount(assetsByID: assetsByID) == 0 {
                            await appModel.regenerateSlideImages(for: draft.id)
                        } else {
                            await appModel.generateMissingSlideImages(for: draft.id)
                        }
                    }
                }
            )

            if draft.hasCompletedCreateImages(assetsByID: assetsByID) {
                CreateSlideRail(
                    slides: draft.slides,
                    assetsByID: assetsByID,
                    openAction: { slideID in
                        selectedSlideID = slideID
                        openEditorAction()
                    }
                )
            }
        }
    }

    private func activeTemplateIndex(for draft: SlideshowDraft) -> Int? {
        guard let templateID = draft.templateID else { return nil }
        return appModel.overview.templates.firstIndex { $0.id == templateID }
    }

}

private extension DraftTikTokSettings {
    var selectedAudience: TikTokAudience? {
        privacyLevel.flatMap(TikTokAudience.init(privacyLevel:))
    }
}

#Preview {
    @Previewable @State var appModel = FlickAppModel.live()
    CreateView()
        .environment(appModel)
}
