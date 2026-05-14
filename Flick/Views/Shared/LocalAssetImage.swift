//
//  LocalAssetImage.swift
//  Flick
//

import SwiftUI
import AVFoundation

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
    var contentMode: ContentMode = .fill

    var body: some View {
        Group {
            #if canImport(UIKit) || canImport(AppKit)
            if let fileURL, let image = LocalAssetImageLoader.image(at: fileURL) {
                Image(flickPlatformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
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
    private static let imageCache = NSCache<NSURL, FlickPlatformImage>()

    static func image(at fileURL: URL) -> FlickPlatformImage? {
        let cacheKey = fileURL as NSURL
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            return cachedImage
        }

        guard let image = FlickPlatformImage(contentsOfFile: fileURL.path) ?? videoFrame(at: fileURL) else {
            return nil
        }

        imageCache.setObject(image, forKey: cacheKey)
        return image
    }

    private static func videoFrame(at fileURL: URL) -> FlickPlatformImage? {
        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1080, height: 1920)

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
