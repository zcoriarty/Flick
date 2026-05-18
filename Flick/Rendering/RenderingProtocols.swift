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
    var width: Int
    var height: Int
    var jpegQuality: Double

    static let tikTokPhotoPost = ImageRenderOptions(
        width: 720,
        height: 1080,
        jpegQuality: 0.92
    )

    var fileExtension: String {
        "jpg"
    }

    var contentType: String {
        "image/jpeg"
    }

    init(width: Int = 720, height: Int = 1080, jpegQuality: Double = 0.92) {
        self.width = width
        self.height = height
        self.jpegQuality = jpegQuality
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
