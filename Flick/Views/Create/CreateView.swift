//
//  CreateView.swift
//  Flick
//

import Foundation
import SwiftUI

struct CreateView: View {
    @Environment(FlickAppModel.self) private var appModel

    @State private var templateLoadState: CreateTemplateLoadState = .loading
    @State private var selectedTemplate: ExampleSlideshowTemplate?
    @State private var isTemplatePickerPresented = false
    @State private var isDraftsPresented = false
    @State private var selectedSlideID: UUID?
    @State private var postTime = Date()
    @State private var selectedWeekdays: Set<CreateWeekday> = [CreateWeekday.current]
    @State private var selectedSongs: [SelectedSong] = []
    @State private var isSongPickerPresented = false
    @State private var isTikTokSettingsPresented = false
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
        appModel.overview.accounts
            .first { $0.platform == .tiktok && $0.authorizationSource == .loginKit }?
            .displayName
    }

    var body: some View {
        let currentDraftID = activeDraftID(in: appModel)

        List {
            CreateTemplateSection(
                loadState: templateLoadState,
                selectedTemplate: selectedTemplate,
                selectAction: { isTemplatePickerPresented = true },
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
                    selectedSlideID: $selectedSlideID
                )
            } else {
                Section("Slideshow") {
                    CreateMessageRow(
                        title: "No slideshow plan yet",
                        message: "Select a template and analyze it to start editing slides, or open Drafts to resume an unposted draft."
                    )
                }
            }

            CreateCadenceSection(
                postTime: $postTime,
                selectedWeekdays: $selectedWeekdays
            )

            CreateSongSection(
                selectedSongs: $selectedSongs,
                selectAction: { isSongPickerPresented = true }
            )

            CreateTikTokSettingsSection(
                accountName: tiktokAccountName,
                postAsDraft: postAsDraft,
                selectedVisibility: selectedVisibility,
                disclosesVideoContent: disclosesVideoContent,
                promotesYourBrand: promotesYourBrand,
                promotesBrandedContent: promotesBrandedContent,
                action: { isTikTokSettingsPresented = true }
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
        .sheet(isPresented: $isTemplatePickerPresented) {
            TemplatePickerSheet(
                collections: templateLoadState.collections,
                selectedTemplate: $selectedTemplate
            )
        }
        .sheet(isPresented: $isDraftsPresented) {
            CreateDraftsSheet(
                drafts: appModel.createDrafts,
                assetsByID: Dictionary(uniqueKeysWithValues: appModel.overview.assets.map { ($0.id, $0) }),
                selectedDraftID: appModel.activeCreateDraftID,
                selectAction: { draftID in
                    appModel.selectCreateDraft(id: draftID)
                    updateSelectedSlide(using: appModel)
                }
            )
        }
        .sheet(isPresented: $isTikTokSettingsPresented) {
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
        }
        #if os(iOS) && canImport(MediaPlayer)
        .sheet(isPresented: $isSongPickerPresented) {
            MediaLibraryPicker(selectedSongs: $selectedSongs)
        }
        #endif
    }

    private var draftsButton: some View {
        Button("Drafts", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") {
            isDraftsPresented = true
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
    @State private var isSlideEditorPresented = false

    var body: some View {
        if let draftIndex = appModel.overview.drafts.firstIndex(where: { $0.id == draftID }) {
            let draftBinding = $appModel.overview.drafts[draftIndex]
            let draft = appModel.overview.drafts[draftIndex]
            let assetsByID = Dictionary(uniqueKeysWithValues: appModel.overview.assets.map { ($0.id, $0) })
            let selectedAsset = selectedSlide(in: draft)?.imageAssetID.flatMap { assetsByID[$0] }

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

            CreateSlideRail(
                slides: draft.slides,
                assetsByID: assetsByID,
                selectedSlideID: $selectedSlideID,
                openAction: { slideID in
                    selectedSlideID = slideID
                    isSlideEditorPresented = true
                }
            )

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

            CreateExportSection(
                draft: draft,
                assetsByID: assetsByID,
                isExporting: appModel.isExportingSlideshow,
                exportAction: {
                    Task {
                        await appModel.exportImageSequence(for: draft.id)
                    }
                }
            )
            .sheet(isPresented: $isSlideEditorPresented) {
                CreateSlideEditor(
                    draft: draftBinding,
                    selectedSlideID: selectedSlideID,
                    asset: selectedAsset,
                    isGenerating: appModel.isGeneratingSlideshowImages,
                    moveAction: { slideID, direction in
                        appModel.moveSlide(slideID, in: draft.id, direction: direction)
                    },
                    duplicateAction: { slideID in
                        appModel.duplicateSlide(slideID, in: draft.id)
                    },
                    deleteAction: { slideID in
                        appModel.deleteSlide(slideID, in: draft.id)
                        selectedSlideID = appModel.overview.drafts
                            .first(where: { $0.id == draft.id })?
                            .slides
                            .sorted { $0.index < $1.index }
                            .first?
                            .id
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
            }
        }
    }

    private func activeTemplateIndex(for draft: SlideshowDraft) -> Int? {
        guard let templateID = draft.templateID else { return nil }
        return appModel.overview.templates.firstIndex { $0.id == templateID }
    }

    private func selectedSlide(in draft: SlideshowDraft) -> Slide? {
        if let selectedSlideID, let slide = draft.slides.first(where: { $0.id == selectedSlideID }) {
            return slide
        }
        return draft.slides.sorted { $0.index < $1.index }.first
    }
}

#Preview {
    @Previewable @State var appModel = FlickAppModel.live()
    CreateView()
        .environment(appModel)
}
