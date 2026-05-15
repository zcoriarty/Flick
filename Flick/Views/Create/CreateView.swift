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
    @State private var selectedSongs: [SelectedSong] = []
    @State private var postTitle = ""
    @State private var postAsDraft = true
    @State private var selectedVisibility: TikTokAudience?
    @State private var allowComment = false
    @State private var allowDuet = false
    @State private var allowStitch = false
    @State private var disclosesVideoContent = false
    @State private var promotesYourBrand = false
    @State private var promotesBrandedContent = false

    private var tiktokAccountName: String? {
        publishingTikTokAccount(in: appModel)?.displayName
    }

    var body: some View {
        @Bindable var appModel = appModel
        let currentDraftID = activeDraftID(in: appModel)

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
                action: analyzeTemplate
            )

            if let currentDraftID {
                CreateDraftWorkflowSections(
                    appModel: appModel,
                    draftID: currentDraftID,
                    selectedSlideID: $selectedSlideID,
                    openEditorAction: { presentedSheet = .slideEditor }
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

            CreateSongSection(
                selectedSongs: $selectedSongs,
                selectAction: { presentedSheet = .songPicker }
            )

            CreateTikTokSettingsSection(
                accountName: tiktokAccountName,
                postAsDraft: postAsDraft,
                selectedVisibility: selectedVisibility,
                disclosesVideoContent: disclosesVideoContent,
                promotesYourBrand: promotesYourBrand,
                promotesBrandedContent: promotesBrandedContent,
                action: { presentedSheet = .tikTokSettings }
            )
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
                if shouldShowPublishButton(in: appModel) {
                    Button {
                        publishManualPost(using: appModel)
                    } label: {
                        if appModel.isPublishingSlideshow {
                            ProgressView()
                        } else {
                            Text("Publish")
                        }
                    }
                    .disabled(appModel.isPublishingSlideshow)
                }
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
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                } else {
                    CreateMessageRow(
                        title: "No slide selected",
                        message: "Select a slide from the rail to edit it."
                    )
                }
            case .tikTokSettings:
                TikTokSettingsSheet(
                    accountName: tiktokAccountName,
                    postTitle: $postTitle,
                    postAsDraft: $postAsDraft,
                    selectedVisibility: $selectedVisibility,
                    allowComment: $allowComment,
                    allowDuet: $allowDuet,
                    allowStitch: $allowStitch,
                    disclosesVideoContent: $disclosesVideoContent,
                    promotesYourBrand: $promotesYourBrand,
                    promotesBrandedContent: $promotesBrandedContent
                )
            case .songPicker:
                #if os(iOS) && canImport(MediaPlayer)
                MediaLibraryPicker(selectedSongs: $selectedSongs)
                #else
                EmptyView()
                #endif
            }
        }
    }

    private var draftsButton: some View {
        Button("Drafts", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") {
            presentedSheet = .drafts
        }
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

    private func shouldShowPublishButton(in appModel: FlickAppModel) -> Bool {
        guard !isAutonomous else { return false }
        guard let draft = appModel.activeCreateDraft else { return false }
        let assetsByID = Dictionary(uniqueKeysWithValues: appModel.overview.assets.map { ($0.id, $0) })
        return draft.hasCompletedCreateImages(assetsByID: assetsByID)
            && publishingTikTokAccount(in: appModel) != nil
            && publishSettings(for: draft) != nil
    }

    private func publishManualPost(using appModel: FlickAppModel) {
        guard let draft = appModel.activeCreateDraft, let settings = publishSettings(for: draft) else { return }
        Task {
            await appModel.publishManualSlideshow(draftID: draft.id, settings: settings)
        }
    }

    private func publishSettings(for draft: SlideshowDraft) -> TikTokManualPublishSettings? {
        let title = postTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        guard postAsDraft || selectedVisibility != nil else { return nil }
        guard !disclosesVideoContent || promotesYourBrand || promotesBrandedContent else { return nil }

        return TikTokManualPublishSettings(
            title: title,
            description: publishDescription(for: draft),
            postAsDraft: postAsDraft,
            privacyLevel: selectedVisibility?.privacyLevel ?? .selfOnly,
            allowComment: allowComment,
            allowDuet: allowDuet,
            allowStitch: allowStitch,
            disclosesVideoContent: disclosesVideoContent,
            promotesYourBrand: promotesYourBrand,
            promotesBrandedContent: promotesBrandedContent
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
                generateMissingAction: {
                    Task {
                        await appModel.generateMissingSlideImages(for: draft.id)
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

#Preview {
    @Previewable @State var appModel = FlickAppModel.live()
    CreateView()
        .environment(appModel)
}
