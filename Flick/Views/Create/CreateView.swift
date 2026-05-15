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
    @State private var hookPrompt = ""
    @State private var contentPrompt = ""
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
        List {
            CreateTemplateSection(
                loadState: templateLoadState,
                selectedTemplate: selectedTemplate,
                selectAction: { isTemplatePickerPresented = true },
                clearAction: { selectedTemplate = nil },
                retryAction: loadTemplates
            )

            CreatePromptSection(
                hookPrompt: $hookPrompt,
                contentPrompt: $contentPrompt
            )

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
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Create")
                    .font(.system(.body, weight: .semibold))
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .task {
            if case .loading = templateLoadState {
                loadTemplates()
            }
        }
        .sheet(isPresented: $isTemplatePickerPresented) {
            TemplatePickerSheet(
                collections: templateLoadState.collections,
                selectedTemplate: $selectedTemplate
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

    private func loadTemplates() {
        templateLoadState = .loading
        do {
            templateLoadState = .loaded(try ExampleSlideshowLibrary.load())
        } catch {
            templateLoadState = .failed(error.localizedDescription)
        }
    }
}

#Preview {
    @Previewable @State var appModel = FlickAppModel.live()
    CreateView()
        .environment(appModel)
}
