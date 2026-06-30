//
//  ExampleSlideshowModels.swift
//  Flick
//

import Foundation

struct ExampleSlideshowCollection: Identifiable, Hashable {
    var id: String { folder }

    var folder: String
    var title: String
    var nicheSlug: String
    var sourcePage: URL?
    var slideshowCount: Int
    var totalSlideCount: Int
    var templates: [ExampleSlideshowTemplate]
}

struct ExampleSlideshowCollectionSummary: Identifiable, Codable, Hashable {
    var id: String { folder }

    var folder: String
    var title: String
    var nicheSlug: String
    var sourcePage: URL?
    var slideshowCount: Int
    var totalSlideCount: Int
    var pageSize: Int
    var pageCount: Int
}

struct ExampleSlideshowLibraryIndex: Codable, Hashable {
    var releaseID: String
    var basePath: String
    var pageSize: Int
    var collections: [ExampleSlideshowCollectionSummary]
    var deletedTemplates: [ExampleSlideshowDeletedTemplate] = []

    var deletedTemplateIDs: Set<String> {
        Set(deletedTemplates.map(\.templateID))
    }
}

struct ExampleSlideshowDeletedTemplate: Identifiable, Codable, Hashable {
    var id: String { templateID }

    var templateID: String
    var releaseID: String
    var nicheID: String
    var fingerprint: String
    var slideCount: Int
    var deletedAt: Date
}

struct ExampleSlideshowPage: Hashable {
    var collection: ExampleSlideshowCollection
    var pageNumber: Int
    var pageSize: Int
    var pageCount: Int

    var hasNextPage: Bool {
        pageNumber < pageCount
    }
}

struct ExampleSlideshowTemplate: Identifiable, Hashable {
    var id: String
    var niche: String
    var nicheSlug: String
    var sourceURL: URL?
    var postNumber: Int
    var profile: String
    var profileDisplayName: String
    var folder: String
    var slideCount: Int
    var metrics: ExampleSlideshowMetrics
    var product: ExampleSlideshowProduct
    var creator: ExampleSlideshowCreator
    var slides: [ExampleSlideshowSlide]

    var title: String {
        "@\(profile)"
    }

    var subtitle: String {
        if let name = product.name, !name.isEmpty, name != "No product", name != "Analysis failed" {
            name
        } else if let medium = product.medium, !medium.isEmpty, medium != "None" {
            medium
        } else {
            profileDisplayName
        }
    }
}

struct ExampleSlideshowMetrics: Hashable {
    var views: String?
    var likes: String?
    var bookmarks: String?
    var shares: String?
}

struct ExampleSlideshowProduct: Hashable {
    var medium: String?
    var name: String?
    var linkInBio: String?
}

struct ExampleSlideshowCreator: Hashable {
    var followerCount: String?
    var signature: String?
    var avatarURL: URL?
    var region: String?
}

struct ExampleSlideshowSlide: Identifiable, Hashable {
    var id: String
    var index: Int
    var filename: String
    var relativePath: String
    var localURL: URL?
    var sourceURL: URL?
    var remoteURL: URL?
}
