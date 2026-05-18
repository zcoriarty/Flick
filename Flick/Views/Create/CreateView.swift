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
    @State private var selectedTemplate: ExampleSlideshowTemplate?
    @State private var presentedSheet: CreateSheet?
    @State private var selectedSlideID: UUID?
    @State private var isAutonomous = false
    @State private var postTime = Date()
    @State private var selectedWeekdays: Set<CreateWeekday> = [CreateWeekday.current]
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

        List {
            CreateAutomationModeSection(isAutonomous: $isAutonomous)

            CreateTemplateSection(
                loadState: templateLoadState,
                selectedTemplate: selectedTemplate,
                selectAction: { presentedSheet = .templatePicker },
                clearAction: { selectedTemplate = nil },
                retryAction: loadTemplates
            )

            AnalyzeTemplateSection(
                selectedTemplate: selectedTemplate,
                isPlanning: appModel.isPlanningSlideshow,
                hasAnalyzedTemplate: currentDraftID != nil,
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

            if isAutonomous {
                CreateCadenceSection(
                    postTime: $postTime,
                    selectedWeekdays: $selectedWeekdays
                )
            }

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
        .flickSettingsListStyle()
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
        .navigationTitle("Create")
        .toolbarTitleDisplayMode(.inline)
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
                    publishManualPost(using: appModel)
                } label: {
                    if appModel.isPublishingSlideshow {
                        ProgressView()
                    } else {
                        Text("Publish")
                    }
                }
                .disabled(!canPublishManualPost(in: appModel) || appModel.isPublishingSlideshow)
            }
        }
        .task {
            if case .loading = templateLoadState {
                loadTemplates()
            }
            updateSelectedSlide(using: appModel)
        }
        .onChange(of: appModel.activeCreateDraftID) { _, _ in
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
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .templatePicker:
                TemplatePickerSheet(
                    collections: templateLoadState.collections,
                    selectedTemplate: $selectedTemplate
                )
            case .drafts:
                CreateDraftsSheet(
                    drafts: appModel.createDrafts,
                    assetsByID: Dictionary(uniqueKeysWithValues: appModel.overview.assets.map { ($0.id, $0) }),
                    selectedDraftID: appModel.activeCreateDraftID,
                    selectAction: { draftID in
                        appModel.selectCreateDraft(id: draftID)
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
                if let currentDraftID = activeDraftID(in: appModel) {
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
    }

    private var draftsButton: some View {
        Button("Drafts", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") {
            presentedSheet = .drafts
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
        selectedSlideID = nil
    }

    private func loadTemplates() {
        templateLoadState = .loading
        do {
            templateLoadState = .loaded(try ExampleSlideshowLibrary.load())
        } catch {
            templateLoadState = .failed(error.localizedDescription)
        }
    }

    private func analyzeTemplate() {
        guard let selectedTemplate else { return }
        Task {
            await appModel.createAISlideshow(brief: "", from: selectedTemplate)
            updateSelectedSlide(using: appModel)
        }
    }

    private func canPublishManualPost(in appModel: FlickAppModel) -> Bool {
        guard !isAutonomous else { return false }
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
        let title = settings.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        guard settings.postAsDraft || settings.privacyLevel != nil else { return nil }
        guard settings.postAsDraft || !settings.disclosesVideoContent || settings.promotesYourBrand || settings.promotesBrandedContent else { return nil }

        return TikTokManualPublishSettings(
            title: title,
            description: publishDescription(for: draft),
            postAsDraft: settings.postAsDraft,
            privacyLevel: settings.privacyLevel ?? .selfOnly,
            allowComment: settings.allowComment,
            allowDuet: settings.allowDuet,
            allowStitch: settings.allowStitch,
            disclosesVideoContent: settings.disclosesVideoContent,
            promotesYourBrand: settings.promotesYourBrand,
            promotesBrandedContent: settings.promotesBrandedContent
        )
    }

    private func publishDescription(for draft: SlideshowDraft) -> String {
        let caption = draft.caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let hashtags = draft.hashtags
            .map { hashtag in
                let cleanValue = hashtag.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                return cleanValue.isEmpty ? "" : "#\(cleanValue)"
            }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return [caption, hashtags]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
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
