//
//  LocalAssetImage.swift
//  Flick
//

import SwiftUI
import AVFoundation
import ImageIO

#if canImport(UIKit)
import UIKit
typealias FlickPlatformImage = UIImage

private extension Image {
    init(flickPlatformImage: FlickPlatformImage) {
        self.init(uiImage: flickPlatformImage)
    }
}
#elseif canImport(AppKit)
import AppKit
typealias FlickPlatformImage = NSImage

private extension Image {
    init(flickPlatformImage: FlickPlatformImage) {
        self.init(nsImage: flickPlatformImage)
    }
}
#endif

struct LocalAssetImage: View {
    var fileURL: URL?
    var remoteURL: URL?
    var contentMode: ContentMode = .fill
    var maxPixelSize: Int = 1_920

    var body: some View {
        Group {
            #if canImport(UIKit) || canImport(AppKit)
            if let fileURL, let image = LocalAssetImageLoader.image(at: fileURL, maxPixelSize: maxPixelSize) {
                Image(flickPlatformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if let remoteURL {
                AsyncImage(url: remoteURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                    case .empty:
                        ZStack {
                            placeholder
                            ProgressView()
                        }
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
            #else
            placeholder
            #endif
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [.secondary.opacity(0.18), .secondary.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}

enum LocalAssetImageLoader {
    #if canImport(UIKit) || canImport(AppKit)
    private static let imageCache: NSCache<NSString, FlickPlatformImage> = {
        let cache = NSCache<NSString, FlickPlatformImage>()
        cache.countLimit = 180
        cache.totalCostLimit = 96 * 1_024 * 1_024
        return cache
    }()

    private static let failedImageCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 300
        return cache
    }()

    static func image(at fileURL: URL, maxPixelSize: Int = 1_920) -> FlickPlatformImage? {
        let normalizedMaxPixelSize = max(1, maxPixelSize)
        let cacheKey = cacheKey(for: fileURL, maxPixelSize: normalizedMaxPixelSize)
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            return cachedImage
        }
        if failedImageCache.object(forKey: cacheKey) != nil {
            return nil
        }

        guard let image = loadImage(at: fileURL, maxPixelSize: normalizedMaxPixelSize) else {
            failedImageCache.setObject(NSNumber(value: true), forKey: cacheKey)
            return nil
        }

        imageCache.setObject(image, forKey: cacheKey, cost: image.flickEstimatedCacheCost)
        return image
    }

    private static func loadImage(at fileURL: URL, maxPixelSize: Int) -> FlickPlatformImage? {
        switch stillImage(at: fileURL, maxPixelSize: maxPixelSize) {
        case let .image(image):
            return image
        case .unsupportedImage:
            return nil
        case .notStillImage:
            return videoFrame(at: fileURL, maxPixelSize: maxPixelSize)
        }
    }

    private static func cacheKey(for fileURL: URL, maxPixelSize: Int) -> NSString {
        let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let fileSize = values?.fileSize ?? -1
        let modificationDate = values?.contentModificationDate?.timeIntervalSince1970 ?? -1
        return "\(fileURL.path)#\(maxPixelSize)#\(fileSize)#\(modificationDate)" as NSString
    }

    private static func stillImage(at fileURL: URL, maxPixelSize: Int) -> StillImageLoadResult {
        guard !hasUnsupportedStillImageContainer(at: fileURL) else {
            return .unsupportedImage
        }

        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary

        guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions) else {
            return .notStillImage
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbnailOptions) else {
            return .unsupportedImage
        }

        #if canImport(UIKit)
        return .image(UIImage(cgImage: cgImage))
        #elseif canImport(AppKit)
        return .image(NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height)))
        #endif
    }

    private static func hasUnsupportedStillImageContainer(at fileURL: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return false
        }
        defer { try? handle.close() }

        guard let header = try? handle.read(upToCount: 12) else {
            return false
        }

        let bytes = [UInt8](header)
        guard bytes.count >= 12 else { return false }
        let ftyp = Array("ftyp".utf8)
        guard Array(bytes[4..<8]) == ftyp else { return false }

        // Some bundled sample slides are VVC still-image containers with .jpg names.
        // ImageIO identifies them as HEIF but logs before returning nil for thumbnails.
        let unsupportedBrands: Set<String> = ["vvic"]
        let majorBrand = String(decoding: bytes[8..<12], as: UTF8.self)
        return unsupportedBrands.contains(majorBrand)
    }

    private static func videoFrame(at fileURL: URL, maxPixelSize: Int) -> FlickPlatformImage? {
        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)

        guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else {
            return nil
        }

        #if canImport(UIKit)
        return UIImage(cgImage: cgImage)
        #elseif canImport(AppKit)
        return NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
        #endif
    }
    #endif
}

#if canImport(UIKit) || canImport(AppKit)
private enum StillImageLoadResult {
    case image(FlickPlatformImage)
    case notStillImage
    case unsupportedImage
}

private extension FlickPlatformImage {
    var flickEstimatedCacheCost: Int {
        #if canImport(UIKit)
        guard let cgImage else { return 1 }
        return cgImage.bytesPerRow * cgImage.height
        #elseif canImport(AppKit)
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 1 }
        return cgImage.bytesPerRow * cgImage.height
        #endif
    }
}
#endif
