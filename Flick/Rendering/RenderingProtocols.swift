//
//  RenderingProtocols.swift
//  Flick
//

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import CoreVideo

struct RenderOptions: Hashable {
    var canvasWidth: Int = 1024
    var canvasHeight: Int = 1536
    var framesPerSecond: Int = 30
    var includeAudio: Bool = false
    var secondsPerSlide: TimeInterval = 2.5
    var maximumDuration: TimeInterval = 180

    static let youtubeShorts = RenderOptions(
        canvasWidth: 1080,
        canvasHeight: 1920,
        framesPerSecond: 30,
        includeAudio: false,
        secondsPerSlide: 2.5,
        maximumDuration: 180
    )
}

struct ImageRenderOptions: Hashable {
    static let tikTokPhotoPostMaximumPixelEdge = 1_080

    var width: Int
    var height: Int
    var jpegQuality: Double

    static let tikTokPhotoPost = ImageRenderOptions(
        width: 720,
        height: 1080,
        jpegQuality: 0.92
    )

    static let youtubeShortsFrame = ImageRenderOptions(
        width: 1080,
        height: 1920,
        jpegQuality: 0.94
    )

    var fileExtension: String {
        "jpg"
    }

    var contentType: String {
        "image/jpeg"
    }

    var fitsTikTokPhotoPostImageSize: Bool {
        max(width, height) <= Self.tikTokPhotoPostMaximumPixelEdge
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
    case missingRenderedFrames
    case videoWriterFailed(String)
    case pixelBufferCreationFailed
    case invalidRenderedFrame(URL)

    var errorDescription: String? {
        switch self {
        case .notImplemented:
            "AVFoundation rendering is scaffolded but not wired to an exporter yet."
        case .missingSlides:
            "A slideshow must contain at least one slide before rendering."
        case .missingRenderedFrames:
            "At least one rendered slide frame is required before video export."
        case let .videoWriterFailed(message):
            "Could not write the rendered YouTube Shorts video: \(message)"
        case .pixelBufferCreationFailed:
            "Could not allocate a video pixel buffer."
        case let .invalidRenderedFrame(url):
            "Could not decode rendered frame \(url.lastPathComponent)."
        }
    }
}

struct AVFoundationSlideshowRenderer: SlideshowRendering {
    var renderDirectory: URL = FileManager.default.temporaryDirectory
    var fileManager: FileManager = .default

    func renderVideo(from slideshow: SlideshowDraft, options: RenderOptions) async throws -> RenderedVideo {
        guard !slideshow.slides.isEmpty else {
            throw RenderingError.missingSlides
        }
        throw RenderingError.notImplemented
    }

    func renderImages(from slideshow: SlideshowDraft, options: ImageRenderOptions) async throws -> [RenderedImage] {
        guard !slideshow.slides.isEmpty else {
            throw RenderingError.missingSlides
        }
        _ = options
        throw RenderingError.notImplemented
    }

    func renderVideo(
        from renderedFrames: [RenderedImage],
        options: RenderOptions,
        outputFileName: String
    ) async throws -> RenderedVideo {
        guard !renderedFrames.isEmpty else {
            throw RenderingError.missingRenderedFrames
        }

        try fileManager.createDirectory(at: renderDirectory, withIntermediateDirectories: true)
        let outputURL = renderDirectory.appending(path: outputFileName)
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: options.canvasWidth,
            AVVideoHeightKey: options.canvasHeight
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: options.canvasWidth,
                kCVPixelBufferHeightKey as String: options.canvasHeight
            ]
        )
        guard writer.canAdd(input) else {
            throw RenderingError.videoWriterFailed("The H.264 writer input could not be added.")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw RenderingError.videoWriterFailed(writer.error?.localizedDescription ?? "The writer did not start.")
        }
        writer.startSession(atSourceTime: .zero)

        let fps = max(options.framesPerSecond, 1)
        let slideDuration = min(
            max(options.secondsPerSlide, 1.0 / Double(fps)),
            options.maximumDuration / Double(max(renderedFrames.count, 1))
        )
        let framesPerSlide = max(1, Int((slideDuration * Double(fps)).rounded()))
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        var frameIndex: Int64 = 0

        for renderedFrame in renderedFrames {
            let image = try decodeCGImage(at: renderedFrame.fileURL)
            let pixelBuffer = try makePixelBuffer(
                image: image,
                width: options.canvasWidth,
                height: options.canvasHeight
            )

            for _ in 0..<framesPerSlide {
                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(5))
                }
                let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
                guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                    throw RenderingError.videoWriterFailed(writer.error?.localizedDescription ?? "The writer rejected a frame.")
                }
                frameIndex += 1
            }
        }

        input.markAsFinished()
        await finishWriting(writer)
        guard writer.status == .completed else {
            throw RenderingError.videoWriterFailed(writer.error?.localizedDescription ?? "The writer ended with status \(writer.status.rawValue).")
        }

        return RenderedVideo(
            fileURL: outputURL,
            duration: Double(frameIndex) / Double(fps),
            width: options.canvasWidth,
            height: options.canvasHeight
        )
    }

    private func finishWriting(_ writer: AVAssetWriter) async {
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }
    }

    private func decodeCGImage(at fileURL: URL) throws -> CGImage {
        guard
            let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw RenderingError.invalidRenderedFrame(fileURL)
        }
        return image
    }

    private func makePixelBuffer(image: CGImage, width: Int, height: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true
            ] as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw RenderingError.pixelBufferCreationFailed
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(pixelBuffer),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
            )
        else {
            throw RenderingError.pixelBufferCreationFailed
        }

        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }
}
