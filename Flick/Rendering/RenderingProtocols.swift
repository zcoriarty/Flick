//
//  RenderingProtocols.swift
//  Flick
//

import Foundation

struct RenderOptions: Hashable {
    var canvasWidth: Int = 1080
    var canvasHeight: Int = 1920
    var framesPerSecond: Int = 30
    var includeAudio: Bool = false
}

struct ImageRenderOptions: Hashable {
    var width: Int = 1080
    var height: Int = 1920
    var scale: Double = 1
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
