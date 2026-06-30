//
//  ExampleSlideshowLibrary.swift
//  Flick
//

import Foundation

enum ExampleSlideshowLibraryError: LocalizedError {
    case missingPublicBaseURL
    case invalidRemoteURL(String)
    case missingCollection(String)
    case invalidPage(Int)

    var errorDescription: String? {
        switch self {
        case .missingPublicBaseURL:
            "Cloudflare R2 public base URL is required to load templates."
        case let .invalidRemoteURL(path):
            "Could not build a template library URL for \(path)."
        case let .missingCollection(id):
            "Template niche \(id) is not available."
        case let .invalidPage(page):
            "Template page \(page) is not available."
        }
    }
}

enum ExampleSlideshowLibrary {
    static let defaultPageSize = 24
    static let currentPointerPath = "template-library/current.json"
    static let deletionRegistryPath = "template-library/deleted-templates.json"

    static func loadIndex(
        configuration: AppConfiguration,
        urlSession: URLSession = .shared
    ) async throws -> ExampleSlideshowLibraryIndex {
        let release = try await fetch(
            RemoteTemplateRelease.self,
            path: currentPointerPath,
            configuration: configuration,
            urlSession: urlSession
        )
        let indexPath = release.indexPath ?? "\(release.basePath.trimmingTrailingSlashes())/index.json"
        let index = try await fetch(
            RemoteTemplateIndexDTO.self,
            path: indexPath,
            configuration: configuration,
            urlSession: urlSession
        )
        let deletionRegistry = try await fetchOptional(
            RemoteTemplateDeletionRegistry.self,
            path: deletionRegistryPath,
            configuration: configuration,
            urlSession: urlSession
        ) ?? .empty
        let deletedTemplates = deletionRegistry.templates.filter { $0.releaseID == release.releaseID }
        let deletedTemplatesByNicheID = Dictionary(grouping: deletedTemplates, by: \.nicheID)

        return ExampleSlideshowLibraryIndex(
            releaseID: release.releaseID,
            basePath: release.basePath,
            pageSize: index.pageSize,
            collections: index.niches.map { niche in
                let deletedTemplates = deletedTemplatesByNicheID[niche.folder] ?? []
                return ExampleSlideshowCollectionSummary(
                    folder: niche.folder,
                    title: niche.title,
                    nicheSlug: niche.nicheSlug,
                    sourcePage: URL(string: niche.sourcePage ?? ""),
                    slideshowCount: max(niche.slideshowCount - deletedTemplates.count, 0),
                    totalSlideCount: max(niche.totalSlideCount - deletedTemplates.reduce(0) { $0 + $1.slideCount }, 0),
                    pageSize: niche.pageSize,
                    pageCount: niche.pageCount
                )
            },
            deletedTemplates: deletedTemplates
        )
    }

    static func loadPage(
        nicheID: String,
        pageNumber: Int,
        index: ExampleSlideshowLibraryIndex,
        configuration: AppConfiguration,
        urlSession: URLSession = .shared
    ) async throws -> ExampleSlideshowPage {
        guard let summary = index.collections.first(where: { $0.id == nicheID }) else {
            throw ExampleSlideshowLibraryError.missingCollection(nicheID)
        }
        guard pageNumber > 0, pageNumber <= max(summary.pageCount, 1) else {
            throw ExampleSlideshowLibraryError.invalidPage(pageNumber)
        }

        let pagePath = "\(index.basePath.trimmingTrailingSlashes())/niches/\(summary.nicheSlug)/pages/\(pageNumber).json"
        let page = try await fetch(
            RemoteTemplatePageDTO.self,
            path: pagePath,
            configuration: configuration,
            urlSession: urlSession
        )
        let layout = RemoteTemplateResourceLayout(
            publicBaseURL: try publicBaseURL(configuration: configuration),
            releaseBasePath: index.basePath,
            collectionFolder: summary.folder
        )
        let collection = ExampleSlideshowCollection(
            folder: summary.folder,
            title: summary.title,
            nicheSlug: summary.nicheSlug,
            sourcePage: summary.sourcePage,
            slideshowCount: summary.slideshowCount,
            totalSlideCount: summary.totalSlideCount,
            templates: page.slideshows
                .filter { !index.deletedTemplateIDs.contains($0.id) }
                .map { makeTemplate(from: $0, summary: summary, layout: layout) }
        )

        return ExampleSlideshowPage(
            collection: collection,
            pageNumber: page.pageNumber,
            pageSize: page.pageSize,
            pageCount: page.pageCount
        )
    }

    static func loadTemplates(
        matching templateIDs: Set<String>,
        configuration: AppConfiguration,
        urlSession: URLSession = .shared
    ) async throws -> [ExampleSlideshowTemplate] {
        guard !templateIDs.isEmpty else { return [] }
        let index = try await loadIndex(configuration: configuration, urlSession: urlSession)
        return try await loadTemplates(
            matching: templateIDs,
            index: index,
            configuration: configuration,
            urlSession: urlSession
        )
    }

    static func loadTemplates(
        matching templateIDs: Set<String>,
        index: ExampleSlideshowLibraryIndex,
        configuration: AppConfiguration,
        urlSession: URLSession = .shared
    ) async throws -> [ExampleSlideshowTemplate] {
        guard !templateIDs.isEmpty else { return [] }
        var templatesByID: [String: ExampleSlideshowTemplate] = [:]

        for summary in index.collections {
            guard templatesByID.count < templateIDs.count else { break }
            for pageNumber in 1...max(summary.pageCount, 1) {
                let page = try await loadPage(
                    nicheID: summary.id,
                    pageNumber: pageNumber,
                    index: index,
                    configuration: configuration,
                    urlSession: urlSession
                )
                for template in page.collection.templates where templateIDs.contains(template.id) {
                    templatesByID[template.id] = template
                }
                if templatesByID.count == templateIDs.count {
                    break
                }
            }
        }

        return templateIDs.compactMap { templatesByID[$0] }
    }

    @MainActor
    static func deleteTemplate(
        _ template: ExampleSlideshowTemplate,
        index: ExampleSlideshowLibraryIndex,
        configuration: AppConfiguration
    ) async throws {
        try await deleteTemplate(
            template,
            index: index,
            configuration: configuration,
            storage: R2StorageService()
        )
    }

    static func deleteTemplate(
        _ template: ExampleSlideshowTemplate,
        index: ExampleSlideshowLibraryIndex,
        configuration: AppConfiguration,
        storage: R2StorageService
    ) async throws {
        let fingerprint = TemplateAnalysisCacheService.fingerprint(for: template)
        let nicheID = index.collections.first { $0.nicheSlug == template.nicheSlug }?.id
            ?? index.collections.first { $0.title == template.niche }?.id
            ?? template.niche
        let deletion = ExampleSlideshowDeletedTemplate(
            templateID: template.id,
            releaseID: index.releaseID,
            nicheID: nicheID,
            fingerprint: fingerprint,
            slideCount: template.slideCount,
            deletedAt: Date()
        )

        var registry = try await loadDeletionRegistry(storage: storage)
        registry.templates.removeAll {
            $0.releaseID == deletion.releaseID && $0.templateID == deletion.templateID
        }
        registry.templates.append(deletion)
        registry.updatedAt = Date()

        try await storage.putJSON(
            JSONEncoder.flick.encode(registry),
            path: deletionRegistryPath,
            metadata: [
                "release-id": index.releaseID,
                "template-id": template.id
            ]
        )

        let analysisPath = TemplateAnalysisCacheService.cachePath(templateID: template.id, fingerprint: fingerprint)
        try await storage.deleteObject(path: analysisPath)

        for path in sourceObjectPaths(for: template, index: index, configuration: configuration) {
            try await storage.deleteObject(path: path)
        }
    }

    private static func fetch<T: Decodable>(
        _ type: T.Type,
        path: String,
        configuration: AppConfiguration,
        urlSession: URLSession
    ) async throws -> T {
        let url = try remoteURL(path: path, configuration: configuration)
        let (data, response) = try await urlSession.data(from: url)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw ExampleSlideshowLibraryError.invalidRemoteURL("\(path) returned HTTP \(httpResponse.statusCode)")
        }
        return try JSONDecoder.flick.decode(type, from: data)
    }

    private static func fetchOptional<T: Decodable>(
        _ type: T.Type,
        path: String,
        configuration: AppConfiguration,
        urlSession: URLSession
    ) async throws -> T? {
        let url = try remoteURL(path: path, configuration: configuration)
        let (data, response) = try await urlSession.data(from: url)
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 404 {
                return nil
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw ExampleSlideshowLibraryError.invalidRemoteURL("\(path) returned HTTP \(httpResponse.statusCode)")
            }
        }
        return try JSONDecoder.flick.decode(type, from: data)
    }

    private static func remoteURL(path: String, configuration: AppConfiguration) throws -> URL {
        let baseURL = try publicBaseURL(configuration: configuration)
        let base = baseURL.absoluteString.trimmingTrailingSlashes()
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/\(R2PercentEncoding.path(normalizedPath))") else {
            throw ExampleSlideshowLibraryError.invalidRemoteURL(path)
        }
        return url
    }

    private static func publicBaseURL(configuration: AppConfiguration) throws -> URL {
        guard let publicBaseURL = configuration.r2.publicBaseURL else {
            throw ExampleSlideshowLibraryError.missingPublicBaseURL
        }
        return publicBaseURL
    }

    private static func loadDeletionRegistry(storage: R2StorageService) async throws -> RemoteTemplateDeletionRegistry {
        do {
            let data = try await storage.data(path: deletionRegistryPath)
            return try JSONDecoder.flick.decode(RemoteTemplateDeletionRegistry.self, from: data)
        } catch let error as MediaStorageError {
            if case let .requestFailed(_, statusCode, _) = error, statusCode == 404 {
                return .empty
            }
            throw error
        }
    }

    private static func sourceObjectPaths(
        for template: ExampleSlideshowTemplate,
        index: ExampleSlideshowLibraryIndex,
        configuration: AppConfiguration
    ) -> [String] {
        var paths = template.slides.compactMap { slide in
            slide.remoteURL.flatMap { objectPath(from: $0, configuration: configuration) }
        }

        if let summary = index.collections.first(where: { $0.nicheSlug == template.nicheSlug }) {
            paths.append([
                index.basePath.trimmingTrailingSlashes(),
                "ExampleSlideshows",
                summary.folder,
                template.folder,
                "\(template.folder)-metadata.json"
            ].joined(separator: "/"))
        }

        return Array(Set(paths)).sorted()
    }

    private static func objectPath(from publicURL: URL, configuration: AppConfiguration) -> String? {
        guard let publicBaseURL = configuration.r2.publicBaseURL else { return nil }
        let base = publicBaseURL.absoluteString.trimmingTrailingSlashes()
        let urlString = publicURL.absoluteString
        let prefix = "\(base)/"
        guard urlString.hasPrefix(prefix) else { return nil }
        let encodedPath = String(urlString.dropFirst(prefix.count))
        return encodedPath.removingPercentEncoding ?? encodedPath
    }

    private static func makeTemplate(
        from slideshow: SlideshowDTO,
        summary: ExampleSlideshowCollectionSummary,
        layout: RemoteTemplateResourceLayout
    ) -> ExampleSlideshowTemplate {
        ExampleSlideshowTemplate(
            id: slideshow.id,
            niche: slideshow.niche,
            nicheSlug: slideshow.nicheSlug ?? summary.nicheSlug,
            sourceURL: URL(string: slideshow.sourceURL),
            postNumber: slideshow.postNumber,
            profile: slideshow.profile,
            profileDisplayName: slideshow.profileDisplayName,
            folder: slideshow.folder,
            slideCount: slideshow.slideCount,
            metrics: ExampleSlideshowMetrics(
                views: slideshow.metrics.views,
                likes: slideshow.metrics.likes,
                bookmarks: slideshow.metrics.bookmarks,
                shares: slideshow.metrics.shares
            ),
            product: ExampleSlideshowProduct(
                medium: slideshow.product.medium,
                name: slideshow.product.name,
                linkInBio: slideshow.product.linkInBio
            ),
            creator: ExampleSlideshowCreator(
                followerCount: slideshow.creator.followerCount,
                signature: slideshow.creator.signature,
                avatarURL: slideshow.creator.avatarUrl.flatMap(URL.init(string:)),
                region: slideshow.creator.region
            ),
            slides: slideshow.slides.map { slide in
                let candidateLocalURL = URL(fileURLWithPath: slide.relativePath)
                let localURL = FileManager.default.isReadableFile(atPath: candidateLocalURL.path)
                    ? candidateLocalURL
                    : nil
                return ExampleSlideshowSlide(
                    id: "\(slideshow.id)-slide-\(slide.index)",
                    index: slide.index,
                    filename: slide.filename,
                    relativePath: slide.relativePath,
                    localURL: localURL,
                    sourceURL: URL(string: slide.url),
                    remoteURL: layout.remoteURL(for: slide.relativePath)
                )
            }
        )
    }
}

private struct RemoteTemplateRelease: Decodable {
    var releaseID: String
    var basePath: String
    var indexPath: String?
}

private struct RemoteTemplateIndexDTO: Decodable {
    var releaseID: String
    var basePath: String
    var pageSize: Int
    var niches: [RemoteTemplateNicheDTO]
}

private struct RemoteTemplateDeletionRegistry: Codable, Hashable {
    var version: Int
    var updatedAt: Date
    var templates: [ExampleSlideshowDeletedTemplate]

    static var empty: RemoteTemplateDeletionRegistry {
        RemoteTemplateDeletionRegistry(version: 1, updatedAt: Date(timeIntervalSince1970: 0), templates: [])
    }
}

private struct RemoteTemplateNicheDTO: Decodable {
    var folder: String
    var title: String
    var nicheSlug: String
    var sourcePage: String?
    var slideshowCount: Int
    var totalSlideCount: Int
    var pageSize: Int
    var pageCount: Int
}

private struct RemoteTemplatePageDTO: Decodable {
    var pageNumber: Int
    var pageSize: Int
    var pageCount: Int
    var slideshows: [SlideshowDTO]
}

private struct SlideshowDTO: Decodable {
    var id: String
    var niche: String
    var nicheSlug: String?
    var sourceURL: String
    var postNumber: Int
    var profile: String
    var profileDisplayName: String
    var folder: String
    var slideCount: Int
    var metrics: MetricsDTO
    var product: ProductDTO
    var creator: CreatorDTO
    var slides: [SlideDTO]

    private enum CodingKeys: String, CodingKey {
        case id
        case niche
        case nicheSlug
        case sourceURL = "sourceUrl"
        case postNumber
        case profile
        case profileDisplayName
        case folder
        case slideCount
        case metrics
        case product
        case creator
        case slides
    }
}

private struct MetricsDTO: Decodable {
    var views: String?
    var likes: String?
    var bookmarks: String?
    var shares: String?
}

private struct ProductDTO: Decodable {
    var medium: String?
    var name: String?
    var linkInBio: String?
}

private struct CreatorDTO: Decodable {
    var followerCount: String?
    var signature: String?
    var avatarUrl: String?
    var region: String?
}

private struct SlideDTO: Decodable {
    var index: Int
    var url: String
    var filename: String
    var relativePath: String
}

private struct RemoteTemplateResourceLayout {
    var publicBaseURL: URL
    var releaseBasePath: String
    var collectionFolder: String

    func remoteURL(for slideRelativePath: String) -> URL? {
        let objectPath = [
            releaseBasePath.trimmingTrailingSlashes(),
            "ExampleSlideshows",
            collectionFolder,
            slideRelativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "/")

        let base = publicBaseURL.absoluteString.trimmingTrailingSlashes()
        return URL(string: "\(base)/\(R2PercentEncoding.path(objectPath))")
    }
}
