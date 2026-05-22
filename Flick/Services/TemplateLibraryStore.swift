//
//  TemplateLibraryStore.swift
//  Flick
//

import Foundation
import Observation

struct TemplateLibraryClient {
    var loadIndex: (AppConfiguration) async throws -> ExampleSlideshowLibraryIndex
    var loadPage: (String, Int, ExampleSlideshowLibraryIndex, AppConfiguration) async throws -> ExampleSlideshowPage
    var deleteTemplate: (ExampleSlideshowTemplate, ExampleSlideshowLibraryIndex, AppConfiguration) async throws -> Void

    static let remote = TemplateLibraryClient(
        loadIndex: { configuration in
            try await ExampleSlideshowLibrary.loadIndex(configuration: configuration)
        },
        loadPage: { nicheID, pageNumber, index, configuration in
            try await ExampleSlideshowLibrary.loadPage(
                nicheID: nicheID,
                pageNumber: pageNumber,
                index: index,
                configuration: configuration
            )
        },
        deleteTemplate: { template, index, configuration in
            try await ExampleSlideshowLibrary.deleteTemplate(
                template,
                index: index,
                configuration: configuration
            )
        }
    )
}

@MainActor
@Observable
final class TemplateLibraryStore {
    enum Status: Hashable {
        case loading
        case loaded
        case failed(String)
    }

    var status: Status = .loading
    var index: ExampleSlideshowLibraryIndex?
    var selectedNicheID: String?
    var templates: [ExampleSlideshowTemplate] = []
    var pageNumber = 0
    var pageCount = 0
    var isLoadingPage = false
    var pageErrorMessage: String?
    var deleteErrorMessage: String?
    var deletingTemplateIDs: Set<String> = []

    @ObservationIgnored private let persistedNicheKey: String
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let client: TemplateLibraryClient

    init(
        persistedNicheKey: String = "lastSelectedTemplateNicheID",
        userDefaults: UserDefaults = .standard,
        client: TemplateLibraryClient? = nil
    ) {
        self.persistedNicheKey = persistedNicheKey
        self.userDefaults = userDefaults
        self.client = client ?? .remote
    }

    var summaries: [ExampleSlideshowCollectionSummary] {
        index?.collections ?? []
    }

    var selectedSummary: ExampleSlideshowCollectionSummary? {
        guard let selectedNicheID else { return nil }
        return summaries.first { $0.id == selectedNicheID }
    }

    var currentCollection: ExampleSlideshowCollection? {
        guard let selectedSummary else { return nil }
        return ExampleSlideshowCollection(
            folder: selectedSummary.folder,
            title: selectedSummary.title,
            nicheSlug: selectedSummary.nicheSlug,
            sourcePage: selectedSummary.sourcePage,
            slideshowCount: selectedSummary.slideshowCount,
            totalSlideCount: selectedSummary.totalSlideCount,
            templates: templates
        )
    }

    var collections: [ExampleSlideshowCollection] {
        currentCollection.map { [$0] } ?? []
    }

    var hasNextPage: Bool {
        pageNumber < pageCount
    }

    var loadedTemplateCountText: String {
        guard let selectedSummary else { return "\(templates.count) loaded" }
        if selectedSummary.slideshowCount <= templates.count {
            return "\(templates.count) available"
        }
        return "\(templates.count) of \(selectedSummary.slideshowCount) loaded"
    }

    func loadInitial(configuration: AppConfiguration, forceReload: Bool = false) async {
        if !forceReload, case .loaded = status, index != nil {
            return
        }

        status = .loading
        pageErrorMessage = nil
        deleteErrorMessage = nil

        do {
            let loadedIndex = try await client.loadIndex(configuration)
            index = loadedIndex
            let persistedNicheID = userDefaults.string(forKey: persistedNicheKey)
            let selectedID = loadedIndex.collections.first { $0.id == persistedNicheID }?.id
                ?? loadedIndex.collections.first?.id
            selectedNicheID = selectedID
            templates = []
            pageNumber = 0
            pageCount = selectedID.flatMap { id in loadedIndex.collections.first { $0.id == id }?.pageCount } ?? 0
            status = .loaded

            if let selectedID {
                await loadPage(1, nicheID: selectedID, configuration: configuration, replacing: true)
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func selectNiche(_ nicheID: String, configuration: AppConfiguration) async {
        guard selectedNicheID != nicheID else { return }
        selectedNicheID = nicheID
        userDefaults.set(nicheID, forKey: persistedNicheKey)
        templates = []
        pageNumber = 0
        pageCount = summaries.first { $0.id == nicheID }?.pageCount ?? 0
        pageErrorMessage = nil
        deleteErrorMessage = nil
        await loadPage(1, nicheID: nicheID, configuration: configuration, replacing: true)
    }

    func loadNextPage(configuration: AppConfiguration) async {
        guard hasNextPage, let selectedNicheID, !isLoadingPage else { return }
        await loadPage(pageNumber + 1, nicheID: selectedNicheID, configuration: configuration, replacing: false)
    }

    func deleteTemplate(_ template: ExampleSlideshowTemplate, configuration: AppConfiguration) async throws {
        guard let index, !deletingTemplateIDs.contains(template.id) else { return }
        deletingTemplateIDs.insert(template.id)
        deleteErrorMessage = nil
        defer {
            deletingTemplateIDs.remove(template.id)
        }

        do {
            try await client.deleteTemplate(template, index, configuration)
            templates.removeAll { $0.id == template.id }
            let deletion = ExampleSlideshowDeletedTemplate(
                templateID: template.id,
                releaseID: index.releaseID,
                nicheID: selectedNicheID ?? template.niche,
                fingerprint: TemplateAnalysisCacheService.fingerprint(for: template),
                slideCount: template.slideCount,
                deletedAt: Date()
            )
            if var loadedIndex = self.index {
                loadedIndex.deletedTemplates.removeAll {
                    $0.releaseID == deletion.releaseID && $0.templateID == deletion.templateID
                }
                loadedIndex.deletedTemplates.append(deletion)
                self.index = loadedIndex
            }
            decrementSelectedSummaryCounts(for: template)
        } catch {
            deleteErrorMessage = error.localizedDescription
            throw error
        }
    }

    private func loadPage(
        _ page: Int,
        nicheID: String,
        configuration: AppConfiguration,
        replacing: Bool
    ) async {
        guard let index else { return }
        isLoadingPage = true
        pageErrorMessage = nil
        do {
            let loadedPage = try await client.loadPage(nicheID, page, index, configuration)
            if replacing {
                templates = loadedPage.collection.templates
            } else {
                let existingIDs = Set(templates.map(\.id))
                templates.append(contentsOf: loadedPage.collection.templates.filter { !existingIDs.contains($0.id) })
            }
            pageNumber = loadedPage.pageNumber
            pageCount = loadedPage.pageCount
            status = .loaded
        } catch {
            pageErrorMessage = error.localizedDescription
            if replacing {
                status = .failed(error.localizedDescription)
            }
        }
        isLoadingPage = false
    }

    private func decrementSelectedSummaryCounts(for template: ExampleSlideshowTemplate) {
        guard
            let selectedNicheID,
            var loadedIndex = index,
            let collectionIndex = loadedIndex.collections.firstIndex(where: { $0.id == selectedNicheID })
        else {
            return
        }

        loadedIndex.collections[collectionIndex].slideshowCount = max(
            loadedIndex.collections[collectionIndex].slideshowCount - 1,
            0
        )
        loadedIndex.collections[collectionIndex].totalSlideCount = max(
            loadedIndex.collections[collectionIndex].totalSlideCount - template.slideCount,
            0
        )
        index = loadedIndex
    }
}
