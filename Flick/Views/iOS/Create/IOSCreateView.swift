//
//  IOSCreateView.swift
//  Flick
//

import Foundation
import SwiftUI

#if !os(macOS)
private enum CreateSheet: Identifiable {
    case templatePicker
    case drafts
    case slideEditor
    case plan(CreatePlanSheet)
    case tikTokSettings
    case youtubeSettings
    case songPicker
    case publishProgress

    var id: String {
        switch self {
        case .templatePicker: "templatePicker"
        case .drafts: "drafts"
        case .slideEditor: "slideEditor"
        case let .plan(sheet): "plan-\(sheet.id)"
        case .tikTokSettings: "tikTokSettings"
        case .youtubeSettings: "youtubeSettings"
        case .songPicker: "songPicker"
        case .publishProgress: "publishProgress"
        }
    }
}

struct IOSCreateView: View {
    @Environment(FlickAppModel.self) private var appModel

    @State private var templateStore = TemplateLibraryStore()
    @State private var isAutomated = false
    @State private var selectedTemplate: ExampleSlideshowTemplate?
    @State private var selectedAutomationTemplateIDs: Set<String> = []
    @State private var selectedAutomationTemplateNicheIDs: Set<String> = []
    @State private var selectedCreationModel: SlideshowCreationModelReference?
    @State private var selectedImageVibe: SlideshowImageVibe = .defaultValue
    @State private var automationImageVibe: SlideshowImageVibe = .defaultValue
    @State private var selectedProductID: UUID?
    @State private var selectedProductImageAssetID: UUID?
    @State private var selectedAutomationProductImageAssetIDs: Set<UUID> = []
    @State private var automationSchedule = AutomationSchedule.default
    @State private var automationTikTokSettings = DraftTikTokSettings()
    @State private var automationYouTubeSettings = DraftYouTubeSettings()
    @State private var automationAccountSelections: [PlatformAccountSelection] = []
    @State private var automationName = ""
    @State private var editingAutomationID: UUID?
    @State private var isStartingAutomation = false
    @State private var showsAutomationStartSuccess = false
    @State private var automationSuccessTitle = "Automation started"
    @State private var automationSuccessMessage = "Your cadence is active."
    @State private var automationSuccessDismissTask: Task<Void, Never>?
    @State private var createFormResetID = UUID()
    @State private var presentedSheet: CreateSheet?
    @State private var selectedSlideID: UUID?
    @State private var slideEditorDetent: PresentationDetent = .large
    @State private var isCreatingShareImport = false
    @State private var showsShareImportAlert = false
    @State private var shareImportAlertMessage = ""

    private var tikTokAccountSelections: [PlatformAccountSelection] {
        if isAutomated {
            return automationAccountSelections
        }
        return appModel.activeCreateDraft?.accountSelections ?? []
    }

    private var youtubeAccountSelections: [PlatformAccountSelection] {
        if isAutomated {
            return automationAccountSelections
        }
        return appModel.activeCreateDraft?.accountSelections ?? []
    }

    private var tiktokAccountSummary: String {
        accountSummary(for: .tiktok, selections: tikTokAccountSelections, in: appModel)
    }

    private var isTikTokAccountReady: Bool {
        !appModel.publishingAccounts(for: .tiktok, in: tikTokAccountSelections).isEmpty
    }

    private var youtubeAccountSummary: String {
        accountSummary(for: .youtubeShorts, selections: youtubeAccountSelections, in: appModel)
    }

    private var isYouTubeAccountReady: Bool {
        !appModel.publishingAccounts(for: .youtubeShorts, in: youtubeAccountSelections).isEmpty
    }

    var body: some View {
        @Bindable var appModel = appModel
        let currentDraftID = activeDraftID(in: appModel)
        let currentDraftIndex = currentDraftID.flatMap { draftID in
            appModel.overview.drafts.firstIndex { $0.id == draftID }
        }

        mainContent(
            in: appModel,
            currentDraftID: currentDraftID,
            currentDraftIndex: currentDraftIndex
        )
        .animation(.snappy, value: showsAutomationStartSuccess)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            createToolbar(in: appModel)
        }
        .task {
            if case .loading = templateStore.status {
                await loadTemplates()
            }
            syncCreationModelSelectionFromActiveDraft(in: appModel)
            syncImageVibeSelectionFromActiveDraft(in: appModel)
            updateSelectedSlide(using: appModel)
            loadRequestedAutomationIfNeeded(in: appModel)
        }
        .onChange(of: appModel.automationEditRequestID) { _, _ in
            loadRequestedAutomationIfNeeded(in: appModel)
        }
        .onChange(of: appModel.activeCreateDraftID) { _, _ in
            syncCreationModelSelectionFromActiveDraft(in: appModel)
            syncImageVibeSelectionFromActiveDraft(in: appModel)
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
                syncImageVibeSelectionFromActiveDraft(in: appModel)
            }
        }
        .onChange(of: appModel.shareImportErrorMessage) { _, message in
            presentShareImportError(message)
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .templatePicker:
                if isAutomated {
                    AutomationTemplatePickerSheet(
                        templateStore: templateStore,
                        configuration: appModel.configuration,
                        localTemplates: appModel.localAutomationTemplates(),
                        selectedTemplateIDs: $selectedAutomationTemplateIDs,
                        selectedTemplateNicheIDs: $selectedAutomationTemplateNicheIDs
                    )
                } else {
                    TemplatePickerSheet(
                        templateStore: templateStore,
                        configuration: appModel.configuration,
                        localTemplates: appModel.localAutomationTemplates(),
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
                        syncImageVibeSelectionFromActiveDraft(in: appModel)
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
                slideEditorSheet
            case let .plan(planSheet):
                planSheetContent(for: planSheet)
            case .tikTokSettings:
                if isAutomated {
                    TikTokSettingsSheet(
                        accounts: tikTokAccounts(in: appModel),
                        selectedAccountIDs: automationSelectedTikTokAccountIDsBinding,
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
                        accounts: tikTokAccounts(in: appModel),
                        selectedAccountIDs: selectedTikTokAccountIDsBinding(in: appModel, draftID: currentDraftID),
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
            case .youtubeSettings:
                if isAutomated {
                    YouTubeSettingsSheet(
                        accounts: youtubeAccounts(in: appModel),
                        selectedAccountIDs: automationSelectedYouTubeAccountIDsBinding,
                        title: $automationYouTubeSettings.title,
                        description: $automationYouTubeSettings.description,
                        tags: $automationYouTubeSettings.tags,
                        privacyStatus: $automationYouTubeSettings.privacyStatus,
                        categoryID: $automationYouTubeSettings.categoryID,
                        selfDeclaredMadeForKids: $automationYouTubeSettings.selfDeclaredMadeForKids,
                        containsSyntheticMedia: $automationYouTubeSettings.containsSyntheticMedia,
                        notifySubscribers: $automationYouTubeSettings.notifySubscribers
                    )
                } else if let currentDraftID = activeDraftID(in: appModel) {
                    YouTubeSettingsSheet(
                        accounts: youtubeAccounts(in: appModel),
                        selectedAccountIDs: selectedYouTubeAccountIDsBinding(in: appModel, draftID: currentDraftID),
                        title: youtubeSettingBinding(in: appModel, draftID: currentDraftID, keyPath: \.title),
                        description: youtubeSettingBinding(in: appModel, draftID: currentDraftID, keyPath: \.description),
                        tags: youtubeSettingBinding(in: appModel, draftID: currentDraftID, keyPath: \.tags),
                        privacyStatus: youtubeSettingBinding(in: appModel, draftID: currentDraftID, keyPath: \.privacyStatus),
                        categoryID: youtubeSettingBinding(in: appModel, draftID: currentDraftID, keyPath: \.categoryID),
                        selfDeclaredMadeForKids: youtubeSettingBinding(in: appModel, draftID: currentDraftID, keyPath: \.selfDeclaredMadeForKids),
                        containsSyntheticMedia: youtubeSettingBinding(in: appModel, draftID: currentDraftID, keyPath: \.containsSyntheticMedia),
                        notifySubscribers: youtubeSettingBinding(in: appModel, draftID: currentDraftID, keyPath: \.notifySubscribers)
                    )
                } else {
                    CreateMessageRow(
                        title: "No draft selected",
                        message: "Create or resume a slideshow draft before editing YouTube Shorts settings."
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
        .sheet(item: $appModel.pendingShareImport) { session in
            shareImportSheet(session, appModel: appModel)
        }
        .alert(
            "Import failed",
            isPresented: $showsShareImportAlert
        ) {
            Button("OK", role: .cancel) {
                appModel.shareImportErrorMessage = nil
            }
        } message: {
            Text(shareImportAlertMessage)
        }
        .onDisappear {
            automationSuccessDismissTask?.cancel()
        }
    }

    private func mainContent(
        in appModel: FlickAppModel,
        currentDraftID: UUID?,
        currentDraftIndex: Int?
    ) -> some View {
        ZStack {
            createFormList(
                in: appModel,
                currentDraftID: currentDraftID,
                currentDraftIndex: currentDraftIndex
            )

            automationSuccessOverlay
        }
    }

    private func primaryToolbarButton(in appModel: FlickAppModel) -> some View {
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
                Text(isAutomated ? automationPrimaryActionTitle : "Publish")
            }
        }
        .disabled(!canPublish(in: appModel) || isPrimaryActionBusy(in: appModel) || showsAutomationStartSuccess)
    }

    @ToolbarContentBuilder
    private func createToolbar(in appModel: FlickAppModel) -> some ToolbarContent {
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
            primaryToolbarButton(in: appModel)
        }
    }

    private func shareImportSheet(_ session: ShareImportSession, appModel: FlickAppModel) -> some View {
        ShareTemplateImportSheet(
            session: session,
            nicheSummaries: templateStore.summaries,
            isCreating: isCreatingShareImport,
            createAction: { title, niche in
                createShareImportedTemplate(
                    title: title,
                    niche: niche,
                    using: appModel
                )
            },
            discardAction: {
                appModel.discardPendingShareImport()
            }
        )
    }

    @ViewBuilder
    private var slideEditorSheet: some View {
        if
            let currentDraftID = activeDraftID(in: appModel),
            let draftIndex = appModel.overview.drafts.firstIndex(where: { $0.id == currentDraftID })
        {
            let assetsByID = Dictionary(uniqueKeysWithValues: appModel.overview.assets.map { ($0.id, $0) })

            CreateSlideEditor(
                draft: draftBinding(forDraftAt: draftIndex),
                selectedSlideID: $selectedSlideID,
                assetsByID: assetsByID,
                isGenerating: appModel.isGeneratingSlideshowImages,
                moveAction: { slideID, direction in
                    appModel.moveSlide(slideID, in: currentDraftID, direction: direction)
                },
                duplicateAction: { slideID in
                    appModel.duplicateSlide(slideID, in: currentDraftID)
                },
                deleteAction: { slideID in
                    appModel.deleteSlide(slideID, in: currentDraftID)
                },
                rewritePromptAction: { slideID, instruction in
                    Task {
                        await appModel.rewritePrompt(for: slideID, in: currentDraftID, instruction: instruction)
                    }
                },
                regenerateAction: { slideID, instruction in
                    Task {
                        await appModel.regenerateSlideImage(slideID: slideID, in: currentDraftID, instruction: instruction)
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
    }

    @ViewBuilder
    private func planSheetContent(for planSheet: CreatePlanSheet) -> some View {
        if
            let currentDraftID = activeDraftID(in: appModel),
            let draftIndex = appModel.overview.drafts.firstIndex(where: { $0.id == currentDraftID })
        {
            CreatePlanSheetContent(
                sheet: planSheet,
                draft: draftBinding(forDraftAt: draftIndex),
                styleGuideJSON: styleGuideJSONBinding(forDraftAt: draftIndex)
            )
        } else {
            CreateMessageRow(
                title: "No draft selected",
                message: "Create or resume a slideshow draft before editing the plan."
            )
        }
    }

    private func draftBinding(forDraftAt draftIndex: Int) -> Binding<SlideshowDraft> {
        Binding(
            get: {
                appModel.overview.drafts[draftIndex]
            },
            set: { newValue in
                appModel.overview.drafts[draftIndex] = newValue
            }
        )
    }

    private func styleGuideJSONBinding(forDraftAt draftIndex: Int) -> Binding<String> {
        let draft = appModel.overview.drafts[draftIndex]
        guard
            let templateID = draft.templateID,
            let templateIndex = appModel.overview.templates.firstIndex(where: { $0.id == templateID })
        else {
            return .constant("")
        }

        return Binding(
            get: {
                appModel.overview.templates[templateIndex].styleJSON
            },
            set: { newValue in
                appModel.overview.templates[templateIndex].styleJSON = newValue
            }
        )
    }

    private func presentShareImportError(_ message: String?) {
        guard let message, !message.isEmpty else { return }
        shareImportAlertMessage = message
        showsShareImportAlert = true
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

    private var automationPrimaryActionTitle: String {
        editingAutomationID == nil ? "Start" : "Save"
    }

    @ViewBuilder
    private var automationSuccessOverlay: some View {
        if showsAutomationStartSuccess {
            CreateAutomationStartSuccessView(
                title: automationSuccessTitle,
                message: automationSuccessMessage
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
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

    private var automationSelectedTikTokAccountIDsBinding: Binding<[UUID]> {
        Binding(
            get: { automationAccountSelections.accountIDs(for: .tiktok) },
            set: { newValue in
                automationAccountSelections.setAccountIDs(newValue, for: .tiktok)
            }
        )
    }

    private var automationSelectedYouTubeAccountIDsBinding: Binding<[UUID]> {
        Binding(
            get: { automationAccountSelections.accountIDs(for: .youtubeShorts) },
            set: { newValue in
                automationAccountSelections.setAccountIDs(newValue, for: .youtubeShorts)
            }
        )
    }

    @ViewBuilder
    private func automatedSetupSections(in appModel: FlickAppModel) -> some View {
        CreateAutomationTemplateSection(
            templateStore: templateStore,
            localTemplates: appModel.localAutomationTemplates(),
            selectedTemplateIDs: $selectedAutomationTemplateIDs,
            selectedTemplateNicheIDs: $selectedAutomationTemplateNicheIDs,
            selectAction: { presentedSheet = .templatePicker },
            retryAction: {
                Task { await loadTemplates(forceReload: true) }
            }
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

        CreateImageVibeSection(imageVibe: $automationImageVibe)

        CreateTikTokSettingsSection(
            accountSummary: tiktokAccountSummary,
            isAccountReady: isTikTokAccountReady,
            hasConfiguredSettings: automationTikTokSettings.automatedPublishSettings(description: "") != nil,
            postAsDraft: automationTikTokSettings.postAsDraft,
            selectedVisibility: automationTikTokSettings.selectedAudience,
            disclosesVideoContent: automationTikTokSettings.disclosesVideoContent,
            promotesYourBrand: automationTikTokSettings.promotesYourBrand,
            promotesBrandedContent: automationTikTokSettings.promotesBrandedContent,
            action: { presentedSheet = .tikTokSettings }
        )

        CreateYouTubeSettingsSection(
            accountSummary: youtubeAccountSummary,
            isAccountReady: isYouTubeAccountReady,
            hasConfiguredSettings: true,
            privacyStatus: automationYouTubeSettings.privacyStatus,
            containsSyntheticMedia: automationYouTubeSettings.containsSyntheticMedia,
            notifySubscribers: automationYouTubeSettings.notifySubscribers,
            action: { presentedSheet = .youtubeSettings }
        )

        CreateAutomationsSection(
            automations: appModel.overview.automations,
            templates: allTemplates(),
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
            templateStore: templateStore,
            selectedTemplate: selectedTemplate,
            selectAction: { presentedSheet = .templatePicker },
            clearAction: { selectedTemplate = nil },
            retryAction: {
                Task { await loadTemplates(forceReload: true) }
            }
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

        CreateImageVibeSection(
            imageVibe: manualImageVibeBinding(in: appModel, draftID: currentDraftID)
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
                openEditorAction: openSlideEditor,
                openPlanSheetAction: { presentedSheet = .plan($0) }
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
            let youtubeSettings = appModel.overview.drafts[currentDraftIndex].youtubeSettings

            CreateSongSection(
                selectedSongs: selectedSongsBinding(in: appModel, draftID: currentDraftID),
                selectAction: { presentedSheet = .songPicker }
            )

            CreateTikTokSettingsSection(
                accountSummary: tiktokAccountSummary,
                isAccountReady: isTikTokAccountReady,
                hasConfiguredSettings: tikTokSettings != nil,
                postAsDraft: tikTokSettings?.postAsDraft ?? false,
                selectedVisibility: tikTokSettings?.selectedAudience,
                disclosesVideoContent: tikTokSettings?.disclosesVideoContent ?? false,
                promotesYourBrand: tikTokSettings?.promotesYourBrand ?? false,
                promotesBrandedContent: tikTokSettings?.promotesBrandedContent ?? false,
                action: { presentedSheet = .tikTokSettings }
            )

            CreateYouTubeSettingsSection(
                accountSummary: youtubeAccountSummary,
                isAccountReady: isYouTubeAccountReady,
                hasConfiguredSettings: youtubeSettings != nil,
                privacyStatus: youtubeSettings?.privacyStatus ?? .private,
                containsSyntheticMedia: youtubeSettings?.containsSyntheticMedia ?? false,
                notifySubscribers: youtubeSettings?.notifySubscribers ?? false,
                action: { presentedSheet = .youtubeSettings }
            )
        } else {
            CreateSongSection(
                selectedSongs: .constant([]),
                selectAction: {}
            )
            .disabled(true)

            CreateTikTokSettingsSection(
                accountSummary: tiktokAccountSummary,
                isAccountReady: false,
                hasConfiguredSettings: false,
                postAsDraft: false,
                selectedVisibility: nil,
                disclosesVideoContent: false,
                promotesYourBrand: false,
                promotesBrandedContent: false,
                action: {}
            )
            .disabled(true)

            CreateYouTubeSettingsSection(
                accountSummary: youtubeAccountSummary,
                isAccountReady: false,
                hasConfiguredSettings: false,
                privacyStatus: .private,
                containsSyntheticMedia: false,
                notifySubscribers: false,
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

    private func selectedTikTokAccountIDsBinding(in appModel: FlickAppModel, draftID: UUID) -> Binding<[UUID]> {
        Binding(
            get: {
                draftAccountSelections(in: appModel, draftID: draftID).accountIDs(for: .tiktok)
            },
            set: { newValue in
                updateDraft(in: appModel, draftID: draftID) { draft in
                    draft.accountSelections.setAccountIDs(newValue, for: .tiktok)
                }
            }
        )
    }

    private func selectedYouTubeAccountIDsBinding(in appModel: FlickAppModel, draftID: UUID) -> Binding<[UUID]> {
        Binding(
            get: {
                draftAccountSelections(in: appModel, draftID: draftID).accountIDs(for: .youtubeShorts)
            },
            set: { newValue in
                updateDraft(in: appModel, draftID: draftID) { draft in
                    draft.accountSelections.setAccountIDs(newValue, for: .youtubeShorts)
                }
            }
        )
    }

    private func draftTikTokSettings(in appModel: FlickAppModel, draftID: UUID) -> DraftTikTokSettings {
        appModel.overview.drafts.first { $0.id == draftID }?.tikTokSettings ?? DraftTikTokSettings()
    }

    private func draftYouTubeSettings(in appModel: FlickAppModel, draftID: UUID) -> DraftYouTubeSettings {
        appModel.overview.drafts.first { $0.id == draftID }?.youtubeSettings ?? DraftYouTubeSettings()
    }

    private func draftAccountSelections(in appModel: FlickAppModel, draftID: UUID) -> [PlatformAccountSelection] {
        appModel.overview.drafts.first { $0.id == draftID }?.accountSelections ?? []
    }

    private func manualImageVibeBinding(in appModel: FlickAppModel, draftID: UUID?) -> Binding<SlideshowImageVibe> {
        Binding(
            get: {
                guard
                    let draftID,
                    let draft = appModel.overview.drafts.first(where: { $0.id == draftID })
                else {
                    return selectedImageVibe
                }
                return draft.imageVibe
            },
            set: { newValue in
                selectedImageVibe = newValue
                guard let draftID else { return }
                updateDraft(in: appModel, draftID: draftID) { draft in
                    draft.imageVibe = newValue
                }
            }
        )
    }

    private func selectedManualImageVibe(in appModel: FlickAppModel) -> SlideshowImageVibe {
        appModel.activeCreateDraft?.imageVibe ?? selectedImageVibe
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

    private func youtubeSettingBinding<Value>(
        in appModel: FlickAppModel,
        draftID: UUID,
        keyPath: WritableKeyPath<DraftYouTubeSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                draftYouTubeSettings(in: appModel, draftID: draftID)[keyPath: keyPath]
            },
            set: { newValue in
                updateYouTubeSettings(in: appModel, draftID: draftID) { settings in
                    settings[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func updateYouTubeSettings(
        in appModel: FlickAppModel,
        draftID: UUID,
        _ update: (inout DraftYouTubeSettings) -> Void
    ) {
        updateDraft(in: appModel, draftID: draftID) { draft in
            var settings = draft.youtubeSettings ?? DraftYouTubeSettings()
            update(&settings)
            draft.youtubeSettings = settings
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
        selectedImageVibe = .defaultValue
        selectedSlideID = nil
    }

    private func clearAutomationForm() {
        editingAutomationID = nil
        automationName = ""
        selectedAutomationTemplateIDs = []
        selectedAutomationTemplateNicheIDs = []
        selectedCreationModel = nil
        automationImageVibe = .defaultValue
        selectedProductID = nil
        selectedAutomationProductImageAssetIDs = []
        automationSchedule = .default
        automationTikTokSettings = DraftTikTokSettings()
        automationYouTubeSettings = DraftYouTubeSettings()
        automationAccountSelections = []
    }

    private func loadTemplates(forceReload: Bool = false) async {
        await templateStore.loadInitial(configuration: appModel.configuration, forceReload: forceReload)
    }

    private func loadAutomation(_ automation: ContentAutomation) {
        isAutomated = true
        editingAutomationID = automation.id
        automationName = automation.name
        selectedAutomationTemplateIDs = Set(automation.templateIDs)
        selectedAutomationTemplateNicheIDs = Set(automation.templateNicheIDs)
        selectedCreationModel = automation.creationModel
        automationImageVibe = automation.imageVibe
        selectedProductID = automation.productID
        selectedAutomationProductImageAssetIDs = Set(automation.productImageAssetIDs)
        automationSchedule = automation.schedule
        automationSchedule.reconcileFixedTimes()
        automationTikTokSettings = automation.tikTokSettings
        automationYouTubeSettings = automation.youtubeSettings
        automationAccountSelections = automation.accountSelections
    }

    private func loadRequestedAutomationIfNeeded(in appModel: FlickAppModel) {
        guard let automationID = appModel.automationEditRequestID else { return }
        guard let automation = appModel.overview.automations.first(where: { $0.id == automationID }) else { return }

        loadAutomation(automation)
        appModel.clearAutomationEditRequest(id: automationID)
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
        (appModel.localAutomationTemplates() + templateStore.templates)
            .filter(\.hasDisplayablePreview)
    }

    private func createShareImportedTemplate(
        title: String,
        niche: String,
        using appModel: FlickAppModel
    ) {
        guard !isCreatingShareImport else { return }
        isCreatingShareImport = true

        Task { @MainActor in
            let result = await appModel.createTemplateFromPendingShareImport(
                title: title,
                niche: niche
            )
            isCreatingShareImport = false
            guard let result else { return }
            applyShareImportResult(result, using: appModel)
        }
    }

    private func applyShareImportResult(
        _ result: ShareTemplateImportResult,
        using appModel: FlickAppModel
    ) {
        appModel.clearActiveCreateDraft()
        selectedTemplate = appModel.localAutomationTemplates()
            .first { $0.id == result.selectedTemplateID }
        selectedProductID = nil
        selectedProductImageAssetID = nil
        selectedSlideID = nil
        syncCreationModelSelectionFromActiveDraft(in: appModel)
        syncImageVibeSelectionFromActiveDraft(in: appModel)
        updateSelectedSlide(using: appModel)

        withAnimation(.snappy) {
            isAutomated = false
        }
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
    }

    private func publishAutomation(using appModel: FlickAppModel) {
        guard canPublishAutomation(in: appModel), !isStartingAutomation else { return }
        let isEditing = editingAutomationID != nil
        let automation = automationDraft(using: appModel, now: Date())
        isStartingAutomation = true
        Task { @MainActor in
            let didStart = await appModel.upsertAutomation(automation)
            isStartingAutomation = false
            guard didStart else { return }
            showAutomationStartSuccess(isEditing: isEditing)
        }
    }

    private func showAutomationStartSuccess(isEditing: Bool) {
        automationSuccessDismissTask?.cancel()
        automationSuccessTitle = isEditing ? "Automation updated" : "Automation started"
        automationSuccessMessage = isEditing ? "Your changes are saved." : "Your cadence is active."
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

        let existingAutomation = appModel.overview.automations.first { $0.id == automationID }
        let status = existingAutomation?.status ?? .active
        let nextScheduledAt = status == .active ? schedule.nextOccurrence(after: now, automationID: automationID) : nil
        return ContentAutomation(
            id: automationID,
            name: automationName.trimmingCharacters(in: .whitespacesAndNewlines),
            templateIDs: Array(selectedAutomationTemplateIDs).sorted(),
            templateNicheIDs: Array(selectedAutomationTemplateNicheIDs).sorted(),
            productID: selectedProductID,
            productImageAssetIDs: Array(selectedAutomationProductImageAssetIDs).sorted { $0.uuidString < $1.uuidString },
            creationModel: selectedCreationModel,
            imageVibe: automationImageVibe,
            schedule: schedule,
            tikTokSettings: automationTikTokSettings,
            youtubeSettings: automationYouTubeSettings,
            targetPlatforms: automationTargetPlatforms(),
            accountSelections: automationAccountSelections,
            status: status,
            nextScheduledAt: nextScheduledAt,
            lastRunAt: existingAutomation?.lastRunAt,
            lastErrorMessage: existingAutomation?.lastErrorMessage,
            consecutiveFailureCount: existingAutomation?.consecutiveFailureCount ?? 0,
            createdAt: existingAutomation?.createdAt ?? now,
            updatedAt: now
        )
    }

    private func automationTargetPlatforms() -> [SocialPlatform] {
        var platforms: [SocialPlatform] = []
        if !automationAccountSelections.accountIDs(for: .tiktok).isEmpty {
            platforms.append(.tiktok)
        }
        if !automationAccountSelections.accountIDs(for: .youtubeShorts).isEmpty {
            platforms.append(.youtubeShorts)
        }
        return platforms.isEmpty ? [.tiktok] : platforms
    }

    private func analyzeTemplate() {
        guard let selectedTemplate else { return }
        let productImage = selectedProductImageContext(in: appModel)
        Task {
            await appModel.createAISlideshow(
                brief: "",
                from: selectedTemplate,
                creationModel: selectedCreationModel,
                productImage: productImage,
                imageVibe: selectedManualImageVibe(in: appModel)
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
        let nicheIDs = Set(templateStore.summaries.map(\.id))
        let localTemplateIDs = Set(appModel.localAutomationTemplates().map(\.id))
        let missingLocalTemplateIDs = selectedAutomationTemplateIDs.filter { templateID in
            LocalAutomationTemplateIdentifier.templateID(from: templateID) != nil
                && !localTemplateIDs.contains(templateID)
        }
        guard !selectedAutomationTemplateIDs.isEmpty || !selectedAutomationTemplateNicheIDs.isEmpty else { return false }
        guard missingLocalTemplateIDs.isEmpty else { return false }
        guard selectedAutomationTemplateNicheIDs.isSubset(of: nicheIDs) else { return false }
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
            && (publishSettings(for: draft) != nil || youtubePublishSettings(for: draft) != nil)
            && (!appModel.publishingAccounts(for: .tiktok, in: draft.accountSelections).isEmpty
                || !appModel.publishingAccounts(for: .youtubeShorts, in: draft.accountSelections).isEmpty)
    }

    private func publishManualPost(using appModel: FlickAppModel) {
        guard let draft = appModel.activeCreateDraft else { return }
        let tikTokSettings = publishSettings(for: draft)
        let youtubeSettings = youtubePublishSettings(for: draft)
        guard tikTokSettings != nil || youtubeSettings != nil else { return }
        appModel.beginManualPublishProgress(for: draft)
        presentedSheet = .publishProgress
        Task { @MainActor in
            let didPublish = await appModel.publishManualSlideshow(
                draftID: draft.id,
                tikTokSettings: tikTokSettings,
                youtubeSettings: youtubeSettings
            )
            if didPublish, tikTokSettings?.postAsDraft != true {
                resetCreateFlowAfterSuccessfulManualPublish(draftID: draft.id, using: appModel)
            }
        }
    }

    private func publishSettings(for draft: SlideshowDraft) -> TikTokManualPublishSettings? {
        guard let settings = draft.tikTokSettings else { return nil }
        return settings.manualPublishSettings(description: draft.publishDescription)
    }

    private func youtubePublishSettings(for draft: SlideshowDraft) -> YouTubeManualPublishSettings? {
        guard let settings = draft.youtubeSettings else { return nil }
        return settings.manualPublishSettings(
            fallbackTitle: draft.title,
            fallbackDescription: draft.publishDescription,
            fallbackHashtags: draft.hashtags
        )
    }

    private func tikTokAccounts(in appModel: FlickAppModel) -> [ConnectedAccount] {
        appModel.overview.accounts
            .filter { $0.platform == .tiktok }
            .sortedForAccountsView
    }

    private func youtubeAccounts(in appModel: FlickAppModel) -> [ConnectedAccount] {
        appModel.overview.accounts
            .filter { $0.platform == .youtubeShorts }
            .sortedForAccountsView
    }

    private func accountSummary(
        for platform: SocialPlatform = .tiktok,
        selections: [PlatformAccountSelection],
        in appModel: FlickAppModel
    ) -> String {
        let accounts = appModel.selectedAccounts(for: platform, in: selections)
        if accounts.count == 1, let account = accounts.first {
            return account.displayName
        }
        if accounts.count > 1 {
            return "\(accounts.count) \(platform == .youtubeShorts ? "channels" : "accounts")"
        }
        if !selections.accountIDs(for: platform).isEmpty {
            return platform == .youtubeShorts ? "Unavailable channel" : "Unavailable account"
        }
        return platform == .youtubeShorts ? "Select channels" : "Select accounts"
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

    private func syncImageVibeSelectionFromActiveDraft(in appModel: FlickAppModel) {
        guard !isAutomated, let draft = appModel.activeCreateDraft else { return }
        selectedImageVibe = draft.imageVibe
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
    var openPlanSheetAction: (CreatePlanSheet) -> Void

    var body: some View {
        if let draftIndex = appModel.overview.drafts.firstIndex(where: { $0.id == draftID }) {
            let draftBinding = $appModel.overview.drafts[draftIndex]
            let draft = appModel.overview.drafts[draftIndex]
            let assetsByID = Dictionary(uniqueKeysWithValues: appModel.overview.assets.map { ($0.id, $0) })

            if let templateIndex = activeTemplateIndex(for: draft) {
                CreatePlanSection(
                    draft: draftBinding,
                    styleGuideJSON: $appModel.overview.templates[templateIndex].styleJSON,
                    openSheet: openPlanSheetAction
                )
            } else {
                CreatePlanSection(
                    draft: draftBinding,
                    styleGuideJSON: .constant(""),
                    openSheet: openPlanSheetAction
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
    IOSCreateView()
        .environment(appModel)
}
#endif
