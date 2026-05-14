//
//  ExampleSlideshowLibrary.swift
//  Flick
//

import Foundation

enum ExampleSlideshowLibraryError: LocalizedError {
    case missingResourceFolder
    case missingIndex(URL)

    var errorDescription: String? {
        switch self {
        case .missingResourceFolder:
            "ExampleSlideshows is not available in the app bundle."
        case let .missingIndex(url):
            "Example slideshow index is missing at \(url.path)."
        }
    }
}

enum ExampleSlideshowLibrary {
    static func load(bundle: Bundle = .main) throws -> [ExampleSlideshowCollection] {
        let layout = try resourceLayout(bundle: bundle)
        let indexURL = try layout.url(for: "index.json")

        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            throw ExampleSlideshowLibraryError.missingIndex(indexURL)
        }

        let index = try decode(IndexDTO.self, from: indexURL)

        return try index.niches.map { niche in
            let manifestURL = try layout.url(for: niche.manifest)
            let manifest = try decode(ManifestDTO.self, from: manifestURL)

            return ExampleSlideshowCollection(
                folder: niche.folder,
                title: manifest.niche,
                nicheSlug: manifest.nicheSlug ?? niche.nicheSlug,
                sourcePage: URL(string: manifest.sourcePage),
                slideshowCount: manifest.slideshowCount,
                totalSlideCount: manifest.totalSlideCount,
                templates: manifest.slideshows.map { slideshow in
                    makeTemplate(from: slideshow, niche: manifest, collection: niche, layout: layout)
                }
            )
        }
    }

    private static func resourceLayout(bundle: Bundle) throws -> ResourceLayout {
        if let url = bundle.resourceURL?.appending(path: "ExampleSlideshows", directoryHint: .isDirectory),
           FileManager.default.fileExists(atPath: url.path) {
            return .preservedFolder(url)
        }

        if let url = bundle.url(forResource: "ExampleSlideshows", withExtension: nil),
           FileManager.default.fileExists(atPath: url.path) {
            return .preservedFolder(url)
        }

        if bundle.url(forResource: "index", withExtension: "json") != nil {
            return .flat(bundle)
        }

        throw ExampleSlideshowLibraryError.missingResourceFolder
    }

    private static func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }

    private static func makeTemplate(
        from slideshow: SlideshowDTO,
        niche: ManifestDTO,
        collection: NicheDTO,
        layout: ResourceLayout
    ) -> ExampleSlideshowTemplate {
        ExampleSlideshowTemplate(
            id: slideshow.id,
            niche: slideshow.niche,
            nicheSlug: slideshow.nicheSlug ?? niche.nicheSlug ?? slug(for: niche.niche),
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
                let localURL = layout.optionalURL(for: "\(collection.folder)/\(slide.relativePath)")
                return ExampleSlideshowSlide(
                    id: "\(slideshow.id)-slide-\(slide.index)",
                    index: slide.index,
                    filename: slide.filename,
                    relativePath: slide.relativePath,
                    localURL: localURL ?? URL(fileURLWithPath: slide.relativePath),
                    sourceURL: URL(string: slide.url)
                )
            }
        )
    }

    private static func slug(for value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}

private enum ResourceLayout {
    case preservedFolder(URL)
    case flat(Bundle)

    func url(for relativePath: String) throws -> URL {
        if let url = optionalURL(for: relativePath) {
            return url
        }
        throw ExampleSlideshowLibraryError.missingIndex(URL(fileURLWithPath: relativePath))
    }

    func optionalURL(for relativePath: String) -> URL? {
        switch self {
        case let .preservedFolder(rootURL):
            return rootURL.appending(path: relativePath)
        case let .flat(bundle):
            let filename = URL(fileURLWithPath: relativePath).lastPathComponent
            let stem = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
            let ext = URL(fileURLWithPath: filename).pathExtension
            return bundle.url(forResource: stem, withExtension: ext.isEmpty ? nil : ext)
        }
    }
}

private struct IndexDTO: Decodable {
    var niches: [NicheDTO]
}

private struct NicheDTO: Decodable {
    var folder: String
    var nicheSlug: String
    var manifest: String
    var slideshowCount: Int
    var totalSlideCount: Int
}

private struct ManifestDTO: Decodable {
    var sourcePage: String
    var niche: String
    var nicheSlug: String?
    var slideshowCount: Int
    var totalSlideCount: Int
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
