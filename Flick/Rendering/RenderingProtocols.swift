//
//  RenderingProtocols.swift
//  Flick
//

import Foundation

struct RenderOptions: Hashable {
    var canvasWidth: Int = 1024
    var canvasHeight: Int = 1536
    var framesPerSecond: Int = 30
    var includeAudio: Bool = false
}

struct ImageRenderOptions: Hashable {
    var width: Int = 1024
    var height: Int = 1536
    var scale: Double = 1
    var format: ImageRenderFormat = .png

    static let tikTokPhotoPost = ImageRenderOptions(
        width: 720,
        height: 1080,
        scale: 1,
        format: .jpeg(quality: 0.92)
    )
}

enum ImageRenderFormat: Hashable {
    case png
    case jpeg(quality: Double)

    var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        }
    }

    var contentType: String {
        switch self {
        case .png: "image/png"
        case .jpeg: "image/jpeg"
        }
    }
}

struct RenderedVideo: Hashable {
    var fileURL: URL
    var duration: TimeInterval
    var width: Int
    var height: Int
}

struct RenderedImage: Hashable {
    var fileURL: URL
    var width: Int
    var height: Int
    var contentType: String
    var fileExtension: String
    var slideID: UUID
}

protocol SlideshowRendering {
    func renderVideo(from slideshow: SlideshowDraft, options: RenderOptions) async throws -> RenderedVideo
    func renderImages(from slideshow: SlideshowDraft, options: ImageRenderOptions) async throws -> [RenderedImage]
}

enum RenderingError: LocalizedError {
    case notImplemented
    case missingSlides

    var errorDescription: String? {
        switch self {
        case .notImplemented:
            "AVFoundation rendering is scaffolded but not wired to an exporter yet."
        case .missingSlides:
            "A slideshow must contain at least one slide before rendering."
        }
    }
}

struct AVFoundationSlideshowRenderer: SlideshowRendering {
    func renderVideo(from slideshow: SlideshowDraft, options: RenderOptions) async throws -> RenderedVideo {
        guard !slideshow.slides.isEmpty else {
            throw RenderingError.missingSlides
        }
        _ = options
        throw RenderingError.notImplemented
    }

    func renderImages(from slideshow: SlideshowDraft, options: ImageRenderOptions) async throws -> [RenderedImage] {
        guard !slideshow.slides.isEmpty else {
            throw RenderingError.missingSlides
        }
        _ = options
        throw RenderingError.notImplemented
    }
}
