//
//  TextOverlayRenderService.swift
//  Flick
//

import CoreGraphics
import Foundation
import ImageIO

#if canImport(SwiftUI)
import SwiftUI
#endif

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct TextOverlayRenderService {
    var renderDirectory: URL
    var urlSession: URLSession = .shared
    var fileManager: FileManager = .default

    func renderImages(
        from draft: SlideshowDraft,
        assets: [MediaAsset],
        options: ImageRenderOptions
    ) async throws -> [RenderedImage] {
        guard !draft.slides.isEmpty else {
            throw RenderingError.missingSlides
        }

        try fileManager.createDirectory(at: renderDirectory, withIntermediateDirectories: true)
        let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })

        var renderedImages: [RenderedImage] = []
        for slide in draft.slides.sorted(by: { $0.index < $1.index }) {
            guard let assetID = slide.imageAssetID, let asset = assetsByID[assetID] else {
                throw TextOverlayRenderError.missingImageAsset(slide.index + 1)
            }

            let background = try await loadCGImage(for: asset)
            let renderedData = try await renderImageData(
                background: background,
                slide: slide,
                options: options
            )
            let renderedDimensions = try decodedImageDimensions(from: renderedData)
            guard renderedDimensions.width == options.width, renderedDimensions.height == options.height else {
                throw TextOverlayRenderError.renderedImageSizeMismatch(
                    expectedWidth: options.width,
                    expectedHeight: options.height,
                    actualWidth: renderedDimensions.width,
                    actualHeight: renderedDimensions.height
                )
            }
            let fileURL = renderDirectory.appending(path: "slide-\(String(format: "%02d", slide.index + 1))-\(slide.id.uuidString).\(options.fileExtension)")
            try renderedData.write(to: fileURL, options: [.atomic])

            renderedImages.append(
                RenderedImage(
                    fileURL: fileURL,
                    width: renderedDimensions.width,
                    height: renderedDimensions.height,
                    contentType: options.contentType,
                    slideID: slide.id
                )
            )
        }

        return renderedImages
    }

    private func loadCGImage(for asset: MediaAsset) async throws -> CGImage {
        let data: Data
        if let localFileURL = asset.localFileURL {
            data = try Data(contentsOf: localFileURL)
        } else if let publicURL = asset.publicURL {
            data = try await urlSession.data(from: publicURL).0
        } else {
            throw TextOverlayRenderError.missingImageLocation(asset.id)
        }

        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw TextOverlayRenderError.invalidImage(asset.id)
        }
        return image
    }

    private func renderImageData(background: CGImage, slide: Slide, options: ImageRenderOptions) async throws -> Data {
        #if canImport(UIKit)
        return await MainActor.run {
            renderImageDataWithUIKit(background: background, slide: slide, options: options)
        }
        #elseif canImport(AppKit)
        return try await MainActor.run {
            try renderImageDataWithAppKit(background: background, slide: slide, options: options)
        }
        #else
        throw TextOverlayRenderError.rendererUnavailable
        #endif
    }
}

enum TextOverlayRenderError: LocalizedError {
    case missingImageAsset(Int)
    case missingImageLocation(UUID)
    case invalidImage(UUID)
    case rendererUnavailable
    case imageEncodingFailed
    case renderedImageSizeMismatch(expectedWidth: Int, expectedHeight: Int, actualWidth: Int, actualHeight: Int)

    var errorDescription: String? {
        switch self {
        case let .missingImageAsset(index):
            "Slide \(index) needs a generated image before export."
        case let .missingImageLocation(id):
            "Media asset \(id.uuidString) does not have a local file or public URL."
        case let .invalidImage(id):
            "Media asset \(id.uuidString) could not be decoded as an image."
        case .rendererUnavailable:
            "Image rendering is unavailable on this platform."
        case .imageEncodingFailed:
            "The rendered slide could not be encoded."
        case let .renderedImageSizeMismatch(expectedWidth, expectedHeight, actualWidth, actualHeight):
            "The rendered slide encoded at \(actualWidth)x\(actualHeight), expected \(expectedWidth)x\(expectedHeight)."
        }
    }
}

private func decodedImageDimensions(from data: Data) throws -> (width: Int, height: Int) {
    guard
        let source = CGImageSourceCreateWithData(data as CFData, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let width = imageDimensionValue(properties[kCGImagePropertyPixelWidth]),
        let height = imageDimensionValue(properties[kCGImagePropertyPixelHeight])
    else {
        throw TextOverlayRenderError.imageEncodingFailed
    }

    return (width, height)
}

private func imageDimensionValue(_ value: Any?) -> Int? {
    if let number = value as? NSNumber {
        return number.intValue
    }
    if let intValue = value as? Int {
        return intValue
    }
    return nil
}

private struct OverlayTextLayout {
    var attributedText: NSAttributedString
    var boundingSize: CGSize
}

#if canImport(UIKit)
@MainActor
private func renderImageDataWithUIKit(background: CGImage, slide: Slide, options: ImageRenderOptions) -> Data {
    let size = CGSize(width: options.width, height: options.height)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true

    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    return renderer.jpegData(withCompressionQuality: options.jpegQuality) { context in
        drawRenderedSlideUIKit(background: background, slide: slide, size: size, context: context)
    }
}

@MainActor
private func drawRenderedSlideUIKit(
    background: CGImage,
    slide: Slide,
    size: CGSize,
    context: UIGraphicsImageRendererContext
) {
    UIColor.black.setFill()
    context.fill(CGRect(origin: .zero, size: size))

    let backgroundRect = aspectFillRect(imageSize: CGSize(width: background.width, height: background.height), canvasSize: size)
    UIImage(cgImage: background).draw(in: backgroundRect)
    if let overlayImage = renderOverlayPreviewImage(slide: slide, pixelSize: size) {
        UIImage(cgImage: overlayImage).draw(in: CGRect(origin: .zero, size: size))
    } else {
        drawOverlayTextUIKit(slide: slide, canvasSize: size)
    }
}

private func drawOverlayTextUIKit(slide: Slide, canvasSize: CGSize) {
    let text = slide.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }

    let overlayRect = overlayContainerRect(for: slide.textPosition, canvasSize: canvasSize)
    let textRect = overlayRect.insetBy(dx: 0, dy: canvasSize.height * 0.04)
    let layout = fittedOverlayTextLayoutUIKit(
        text: text,
        slide: slide,
        canvasSize: canvasSize,
        textRect: textRect
    )
    let drawRect = alignedTextRect(for: layout.boundingSize, in: textRect, position: slide.textPosition)
    layout.attributedText.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
}

private func fittedOverlayTextLayoutUIKit(
    text: String,
    slide: Slide,
    canvasSize: CGSize,
    textRect: CGRect
) -> OverlayTextLayout {
    let baseFontSize = canvasSize.height * 0.058 * slide.textStyle.sizeScale
    let minimumFontSize = max(8, baseFontSize * 0.45)
    let baseLayout = overlayTextLayoutUIKit(
        text: text,
        slide: slide,
        fontSize: baseFontSize,
        maxWidth: textRect.width
    )
    guard baseLayout.boundingSize.height > textRect.height else {
        return baseLayout
    }

    var lowerBound = minimumFontSize
    var upperBound = baseFontSize
    var bestLayout = overlayTextLayoutUIKit(
        text: text,
        slide: slide,
        fontSize: minimumFontSize,
        maxWidth: textRect.width
    )

    for _ in 0..<7 {
        let candidateFontSize = (lowerBound + upperBound) / 2
        let candidate = overlayTextLayoutUIKit(
            text: text,
            slide: slide,
            fontSize: candidateFontSize,
            maxWidth: textRect.width
        )

        if candidate.boundingSize.height <= textRect.height {
            bestLayout = candidate
            lowerBound = candidateFontSize
        } else {
            upperBound = candidateFontSize
        }
    }

    return bestLayout
}

private func overlayTextLayoutUIKit(
    text: String,
    slide: Slide,
    fontSize: CGFloat,
    maxWidth: CGFloat
) -> OverlayTextLayout {
    let attributedText = NSMutableAttributedString()
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = NSTextAlignment(slide.textPosition)
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.lineSpacing = 8

    let headlineFont = UIFont.flickFont(
        name: slide.textStyle.fontName,
        size: fontSize,
        weight: UIFont.Weight(slide.textStyle.weight)
    )
    let foreground = UIColor(hex: slide.textStyle.foregroundHex)
    let outline = UIColor(hex: slide.textStyle.outlineColorHex)

    attributedText.append(NSAttributedString(
        string: text,
        attributes: [
            .font: headlineFont,
            .foregroundColor: foreground,
            .paragraphStyle: paragraph,
            .strokeColor: outline,
            .strokeWidth: -3.0
        ]
    ))

    let boundingSize = attributedText.boundingRect(
        with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        context: nil
    ).integral.size
    return OverlayTextLayout(attributedText: attributedText, boundingSize: boundingSize)
}
#endif

#if canImport(AppKit)
@MainActor
private func renderImageDataWithAppKit(background: CGImage, slide: Slide, options: ImageRenderOptions) throws -> Data {
    let size = CGSize(width: options.width, height: options.height)
    guard
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: options.width,
            pixelsHigh: options.height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
        let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap)
    else {
        throw TextOverlayRenderError.imageEncodingFailed
    }

    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = graphicsContext
    graphicsContext.imageInterpolation = .high

    NSColor.black.setFill()
    NSRect(origin: .zero, size: size).fill()

    let backgroundRect = aspectFillRect(imageSize: CGSize(width: background.width, height: background.height), canvasSize: size)
    NSImage(cgImage: background, size: CGSize(width: background.width, height: background.height))
        .draw(in: backgroundRect, from: .zero, operation: .sourceOver, fraction: 1)
    if let overlayImage = renderOverlayPreviewImage(slide: slide, pixelSize: size) {
        NSImage(cgImage: overlayImage, size: size)
            .draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
    } else {
        drawOverlayTextAppKit(slide: slide, canvasSize: size)
    }

    guard let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: options.jpegQuality]) else {
        throw TextOverlayRenderError.imageEncodingFailed
    }
    return jpegData
}

private func drawOverlayTextAppKit(slide: Slide, canvasSize: CGSize) {
    let text = slide.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }

    let overlayRect = overlayContainerRect(for: slide.textPosition, canvasSize: canvasSize)
    let textRect = overlayRect.insetBy(dx: 0, dy: canvasSize.height * 0.04)
    let layout = fittedOverlayTextLayoutAppKit(
        text: text,
        slide: slide,
        canvasSize: canvasSize,
        textRect: textRect
    )
    let drawRect = alignedTextRect(for: layout.boundingSize, in: textRect, position: slide.textPosition)
    layout.attributedText.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
}

private func fittedOverlayTextLayoutAppKit(
    text: String,
    slide: Slide,
    canvasSize: CGSize,
    textRect: CGRect
) -> OverlayTextLayout {
    let baseFontSize = canvasSize.height * 0.058 * slide.textStyle.sizeScale
    let minimumFontSize = max(8, baseFontSize * 0.45)
    let baseLayout = overlayTextLayoutAppKit(
        text: text,
        slide: slide,
        fontSize: baseFontSize,
        maxWidth: textRect.width
    )
    guard baseLayout.boundingSize.height > textRect.height else {
        return baseLayout
    }

    var lowerBound = minimumFontSize
    var upperBound = baseFontSize
    var bestLayout = overlayTextLayoutAppKit(
        text: text,
        slide: slide,
        fontSize: minimumFontSize,
        maxWidth: textRect.width
    )

    for _ in 0..<7 {
        let candidateFontSize = (lowerBound + upperBound) / 2
        let candidate = overlayTextLayoutAppKit(
            text: text,
            slide: slide,
            fontSize: candidateFontSize,
            maxWidth: textRect.width
        )

        if candidate.boundingSize.height <= textRect.height {
            bestLayout = candidate
            lowerBound = candidateFontSize
        } else {
            upperBound = candidateFontSize
        }
    }

    return bestLayout
}

private func overlayTextLayoutAppKit(
    text: String,
    slide: Slide,
    fontSize: CGFloat,
    maxWidth: CGFloat
) -> OverlayTextLayout {
    let attributedText = NSMutableAttributedString()
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = NSTextAlignment(slide.textPosition)
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.lineSpacing = 8

    let headlineFont = NSFont.systemFont(ofSize: fontSize, weight: NSFont.Weight(slide.textStyle.weight))
    let foreground = NSColor(hex: slide.textStyle.foregroundHex)
    let outline = NSColor(hex: slide.textStyle.outlineColorHex)

    attributedText.append(NSAttributedString(
        string: text,
        attributes: [
            .font: headlineFont,
            .foregroundColor: foreground,
            .paragraphStyle: paragraph,
            .strokeColor: outline,
            .strokeWidth: -3.0
        ]
    ))

    let boundingSize = attributedText.boundingRect(
        with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    ).integral.size
    return OverlayTextLayout(attributedText: attributedText, boundingSize: boundingSize)
}
#endif

#if canImport(SwiftUI)
@MainActor
private func renderOverlayPreviewImage(slide: Slide, pixelSize: CGSize) -> CGImage? {
    let logicalSize = overlayPreviewLogicalSize(for: pixelSize)
    guard logicalSize.width > 0, logicalSize.height > 0 else { return nil }

    let renderer = ImageRenderer(
        content: SlideOverlayPreview(slide: slide)
            .frame(width: logicalSize.width, height: logicalSize.height)
    )
    renderer.proposedSize = ProposedViewSize(logicalSize)
    renderer.scale = pixelSize.height / logicalSize.height
    renderer.isOpaque = false
    return renderer.cgImage
}

private func overlayPreviewLogicalSize(for pixelSize: CGSize) -> CGSize {
    let logicalHeight = CGFloat(24) / 0.058
    return CGSize(
        width: logicalHeight * pixelSize.width / max(pixelSize.height, 1),
        height: logicalHeight
    )
}
#else
private func renderOverlayPreviewImage(slide: Slide, pixelSize: CGSize) -> CGImage? {
    nil
}
#endif

private func aspectFillRect(imageSize: CGSize, canvasSize: CGSize) -> CGRect {
    let scale = max(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
    let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    return CGRect(
        x: (canvasSize.width - size.width) / 2,
        y: (canvasSize.height - size.height) / 2,
        width: size.width,
        height: size.height
    )
}

private func overlayContainerRect(for position: TextPosition, canvasSize: CGSize) -> CGRect {
    let horizontalMargin: CGFloat = min(32, canvasSize.width / 2)
    let centeredWidth = max(0, canvasSize.width - horizontalMargin * 2)
    return switch position {
    case .left, .split:
        CGRect(
            x: horizontalMargin,
            y: 0,
            width: max(0, canvasSize.width * 0.45 - horizontalMargin),
            height: canvasSize.height
        )
    case .right:
        CGRect(
            x: canvasSize.width * 0.55,
            y: 0,
            width: max(0, canvasSize.width * 0.45 - horizontalMargin),
            height: canvasSize.height
        )
    case .top:
        CGRect(x: horizontalMargin, y: 0, width: centeredWidth, height: canvasSize.height * 0.38)
    case .center:
        CGRect(x: horizontalMargin, y: canvasSize.height * 0.2, width: centeredWidth, height: canvasSize.height * 0.6)
    case .bottom:
        CGRect(x: horizontalMargin, y: canvasSize.height * 0.62, width: centeredWidth, height: canvasSize.height * 0.38)
    }
}

private func alignedTextRect(for textSize: CGSize, in rect: CGRect, position: TextPosition) -> CGRect {
    let height = min(textSize.height, rect.height)
    let width = min(textSize.width, rect.width)
    let x: CGFloat
    switch position {
    case .right:
        x = rect.maxX - width
    case .center, .top, .bottom:
        x = rect.midX - width / 2
    case .left, .split:
        x = rect.minX
    }

    let y: CGFloat
    switch position {
    case .top:
        y = rect.minY
    case .bottom:
        y = rect.maxY - height
    default:
        y = rect.midY - height / 2
    }

    return CGRect(x: x, y: y, width: width, height: height)
}

private extension NSTextAlignment {
    init(_ position: TextPosition) {
        switch position {
        case .left, .split:
            self = .left
        case .right:
            self = .right
        case .top, .center, .bottom:
            self = .center
        }
    }
}

#if canImport(UIKit)
private extension UIFont.Weight {
    init(_ value: String) {
        switch value.lowercased() {
        case "regular": self = .regular
        case "medium": self = .medium
        case "semibold": self = .semibold
        case "bold": self = .bold
        case "black", "heavy": self = .black
        default: self = .bold
        }
    }
}

private extension UIFont {
    static func flickFont(name: String, size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let baseFont = UIFont.systemFont(ofSize: size, weight: weight)
        let design: UIFontDescriptor.SystemDesign?
        switch name.lowercased() {
        case "system rounded", "rounded":
            design = .rounded
        case "serif":
            design = .serif
        case "monospaced", "monospace":
            design = .monospaced
        default:
            design = nil
        }

        guard
            let design,
            let descriptor = baseFont.fontDescriptor.withDesign(design)
        else {
            return baseFont
        }
        return UIFont(descriptor: descriptor, size: size)
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let components = RGBComponents(hex: hex)
        self.init(red: components.red, green: components.green, blue: components.blue, alpha: 1)
    }
}
#endif

#if canImport(AppKit)
private extension NSFont.Weight {
    init(_ value: String) {
        switch value.lowercased() {
        case "regular": self = .regular
        case "medium": self = .medium
        case "semibold": self = .semibold
        case "bold": self = .bold
        case "black", "heavy": self = .black
        default: self = .bold
        }
    }
}

private extension NSColor {
    convenience init(hex: String) {
        let components = RGBComponents(hex: hex)
        self.init(red: components.red, green: components.green, blue: components.blue, alpha: 1)
    }
}
#endif

private struct RGBComponents {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat

    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        switch cleaned.count {
        case 6:
            red = CGFloat((value & 0xFF0000) >> 16) / 255
            green = CGFloat((value & 0x00FF00) >> 8) / 255
            blue = CGFloat(value & 0x0000FF) / 255
        default:
            red = 0.07
            green = 0.07
            blue = 0.07
        }
    }
}
