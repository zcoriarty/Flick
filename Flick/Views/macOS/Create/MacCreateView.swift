//
//  MacCreateView.swift
//  Flick
//

import Foundation
import SwiftUI

#if os(macOS) || targetEnvironment(macCatalyst)
private enum CreateSheet: String, Identifiable {
    case templatePicker
    case drafts
    case slideEditor
    case tikTokSettings
    case songPicker
    case publishProgress

    var id: String { rawValue }
}

struct MacCreateView: View {
    @Environment(FlickAppModel.self) private var appModel

    @State private var templateStore = TemplateLibraryStore()
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

    private var createColumnSubtitle: String {
        if isAutomated {
            return "Choose the reusable ingredients and publishing defaults for scheduled runs."
        }
        return "Choose the template, model, and product media that seed this post."
    }

    private var workflowColumnSubtitle: String {
        if isAutomated {
            return "Review existing schedules and jump back into any automation that needs tuning."
        }
        return "Edit the plan, generate slide images, and prepare TikTok publishing details."
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
        .navigationTitle(createTitle(in: appModel))
        .toolbar {
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
            if case .loading = templateStore.status {
                await loadTemplates()
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
                        templateStore: templateStore,
                        configuration: appModel.configuration,
                        selectedTemplateIDs: $selectedAutomationTemplateIDs
                    )
                } else {
                    TemplatePickerSheet(
                        templateStore: templateStore,
                        configuration: appModel.configuration,
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
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    MacWorkspaceHeader(
                        title: createTitle(in: appModel),
                        subtitle: createSubtitle(in: appModel),
                        metrics: createMetrics(in: appModel)
                    )

                    HStack(alignment: .top, spacing: 18) {
                        setupList(
                            in: appModel,
                            currentDraftID: currentDraftID
                        )
                        .frame(minWidth: 420, idealWidth: 460, maxWidth: 520)

                        workflowList(
                            in: appModel,
                            currentDraftID: currentDraftID,
                            currentDraftIndex: currentDraftIndex
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .frame(minHeight: createColumnHeight(for: proxy.size.height))
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.visible)
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .id(createFormResetID)
        .flickAppBackground()
        .dismissKeyboardOnTap()
        .disabled(showsAutomationStartSuccess)
        .opacity(showsAutomationStartSuccess ? 0 : 1)
    }

    private func createColumnHeight(for availableHeight: CGFloat) -> CGFloat {
        max(520, availableHeight - 160)
    }

    private func setupList(
        in appModel: FlickAppModel,
        currentDraftID: UUID?
    ) -> some View {
        MacCreateColumn(
            title: "Setup",
            subtitle: createColumnSubtitle,
            systemImage: isAutomated ? "calendar.badge.clock" : "slider.horizontal.3"
        ) {
            CreateAutomationSection(
                isAutomated: $isAutomated,
                schedule: $automationSchedule
            )
            .macCreateListRows()

            if isAutomated {
                CreateAutomationNameSection(
                    name: $automationName,
                    placeholder: automationDefaultName(in: appModel)
                )
                .macCreateListRows()

                automatedSetupSections(in: appModel)
            } else {
                manualSetupSections(
                    in: appModel,
                    currentDraftID: currentDraftID
                )
            }
        }
    }

    private func workflowList(
        in appModel: FlickAppModel,
        currentDraftID: UUID?,
        currentDraftIndex: Int?
    ) -> some View {
        MacCreateColumn(
            title: isAutomated ? "Automations" : "Workflow",
            subtitle: workflowColumnSubtitle,
            systemImage: isAutomated ? "bolt.badge.automatic" : "rectangle.stack.badge.play"
        ) {
            if isAutomated {
                automatedWorkflowSections(in: appModel)
            } else {
                manualWorkflowSections(
                    in: appModel,
                    currentDraftID: currentDraftID,
                    currentDraftIndex: currentDraftIndex
                )
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func createTitle(in appModel: FlickAppModel) -> String {
        if isAutomated {
            return editingAutomationID == nil ? "Automation Builder" : "Edit Automation"
        }
        return "Create Post"
    }

    private func createSubtitle(in appModel: FlickAppModel) -> String {
        if isAutomated {
            return "Configure recurring template, product, model, and TikTok settings, then monitor scheduled runs."
        }
        return "Build a slideshow draft, generate images, review slides, and prepare TikTok publishing from one workspace."
    }

    private func createMetrics(in appModel: FlickAppModel) -> [MacWorkspaceMetric] {
        if isAutomated {
            return [
                MacWorkspaceMetric(title: "Automations", value: "\(appModel.overview.automations.count)"),
                MacWorkspaceMetric(title: "Templates", value: "\(selectedAutomationTemplateIDs.count)"),
                MacWorkspaceMetric(title: "Images", value: "\(selectedAutomationProductImageAssetIDs.count)")
            ]
        }

        return [
            MacWorkspaceMetric(title: "Drafts", value: "\(appModel.createDrafts.count)"),
            MacWorkspaceMetric(title: "Slides", value: "\(appModel.activeCreateDraft?.slides.count ?? 0)"),
            MacWorkspaceMetric(title: "Templates", value: "\(templateStore.templates.count)")
        ]
    }

    private var draftsButton: some View {
        Button("Drafts", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") {
            presentedSheet = .drafts
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
            templateStore: templateStore,
            selectedTemplateIDs: $selectedAutomationTemplateIDs,
            selectAction: { presentedSheet = .templatePicker },
            retryAction: {
                Task { await loadTemplates(forceReload: true) }
            }
        )
        .macCreateListRows()

        CreateModelSection(
            models: appModel.overview.creationModels,
            selectedModel: $selectedCreationModel
        )
        .macCreateListRows()

        CreateAutomationProductImageSection(
            products: appModel.overview.products,
            productImageAssets: selectableProductImageAssets(in: appModel),
            selectedProductID: $selectedProductID,
            selectedProductImageAssetIDs: $selectedAutomationProductImageAssetIDs
        )
        .macCreateListRows()

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
        .macCreateListRows()
    }

    @ViewBuilder
    private func automatedWorkflowSections(in appModel: FlickAppModel) -> some View {
        CreateAutomationsSection(
            automations: appModel.overview.automations,
            templates: allTemplates(),
            products: appModel.overview.products,
            editAction: loadAutomation,
            deleteAction: { deleteAutomation($0, using: appModel) }
        )
        .macCreateListRows()
    }

    @ViewBuilder
    private func manualSetupSections(
        in appModel: FlickAppModel,
        currentDraftID: UUID?
    ) -> some View {
        CreateTemplateSection(
            templateStore: templateStore,
            selectedTemplate: selectedTemplate,
            selectAction: { presentedSheet = .templatePicker },
            clearAction: { selectedTemplate = nil },
            retryAction: {
                Task { await loadTemplates(forceReload: true) }
            }
        )
        .macCreateListRows()

        CreateModelSection(
            models: appModel.overview.creationModels,
            selectedModel: $selectedCreationModel
        )
        .macCreateListRows()

        CreateProductImageSection(
            products: appModel.overview.products,
            productImageAssets: selectableProductImageAssets(in: appModel),
            selectedProductID: $selectedProductID,
            selectedProductImageAssetID: $selectedProductImageAssetID
        )
        .macCreateListRows()

        AnalyzeTemplateSection(
            selectedTemplate: selectedTemplate,
            isPlanning: appModel.isPlanningSlideshow,
            hasAnalyzedTemplate: currentDraftID != nil,
            canAnalyze: canAnalyzeTemplate(in: appModel),
            action: analyzeTemplate
        )
        .macCreateListRows()
    }

    @ViewBuilder
    private func manualWorkflowSections(
        in appModel: FlickAppModel,
        currentDraftID: UUID?,
        currentDraftIndex: Int?
    ) -> some View {
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
            .macCreateListRows()
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
            .macCreateListRows()

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
            .macCreateListRows()
        } else {
            CreateSongSection(
                selectedSongs: .constant([]),
                selectAction: {}
            )
            .disabled(true)
            .macCreateListRows()

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
            .macCreateListRows()
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

    private func loadTemplates(forceReload: Bool = false) async {
        await templateStore.loadInitial(configuration: appModel.configuration, forceReload: forceReload)
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

    private func allTemplates() -> [ExampleSlideshowTemplate] {
        templateStore.templates
            .filter(\.hasDisplayablePreview)
    }

    private func automationDefaultName(in appModel: FlickAppModel) -> String {
        automationDraft(using: appModel, now: Date())
            .defaultName(templates: allTemplates(), products: appModel.overview.products)
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
        let templateIDs = Set(allTemplates().map(\.id))
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
        appModel.overview.accounts.first { $0.canPublishToTikTok }
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
                .macCreateListRows()
            } else {
                CreatePlanSection(
                    draft: draftBinding,
                    styleGuideJSON: .constant("")
                )
                .macCreateListRows()
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
            .macCreateListRows()

            if draft.hasCompletedCreateImages(assetsByID: assetsByID) {
                CreateSlideRail(
                    slides: draft.slides,
                    assetsByID: assetsByID,
                    openAction: { slideID in
                        selectedSlideID = slideID
                        openEditorAction()
                    }
                )
                .macCreateListRows()
            }
        }
    }

    private func activeTemplateIndex(for draft: SlideshowDraft) -> Int? {
        guard let templateID = draft.templateID else { return nil }
        return appModel.overview.templates.firstIndex { $0.id == templateID }
    }

}

private struct CreateAutomationNameSection: View {
    @Binding var name: String
    var placeholder: String

    var body: some View {
        Section("Name") {
            FlickSettingsRow(
                title: "Automation name",
                systemImage: "text.cursor",
                iconColor: FlickStyle.appTint
            ) {
                TextField(placeholder, text: $name, prompt: Text(placeholder))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .submitLabel(.done)
                    .accessibilityLabel("Automation name")
            }
        }
    }
}

private struct MacCreateColumn<Content: View>: View {
    var title: String
    var subtitle: String
    var systemImage: String
    let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        MacWorkspaceSection(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage
        ) {
            MacWorkspacePanel {
                List {
                    content
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.visible)
                .contentMargins(.top, 0, for: .scrollContent)
                .contentMargins(.horizontal, 0, for: .scrollContent)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct MacCreateRowBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            }
            .padding(.vertical, 3)
    }
}

private extension View {
    func macCreateListRows() -> some View {
        listRowInsets(EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8))
            .listRowBackground(MacCreateRowBackground())
            .listRowSeparator(.hidden)
    }
}

private extension DraftTikTokSettings {
    var selectedAudience: TikTokAudience? {
        privacyLevel.flatMap(TikTokAudience.init(privacyLevel:))
    }
}

#Preview {
    @Previewable @State var appModel = FlickAppModel.live()
    MacCreateView()
        .environment(appModel)
}
#endif
