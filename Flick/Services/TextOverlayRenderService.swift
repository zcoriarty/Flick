//
//  TextOverlayRenderService.swift
//  Flick
//

import CoreGraphics
import Foundation
import ImageIO

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
            let pngData = try await renderPNGData(
                background: background,
                slide: slide,
                width: options.width,
                height: options.height
            )
            let fileURL = renderDirectory.appending(path: "slide-\(String(format: "%02d", slide.index + 1))-\(slide.id.uuidString).png")
            try pngData.write(to: fileURL, options: [.atomic])

            renderedImages.append(
                RenderedImage(
                    fileURL: fileURL,
                    width: options.width,
                    height: options.height,
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

    private func renderPNGData(background: CGImage, slide: Slide, width: Int, height: Int) async throws -> Data {
        #if canImport(UIKit)
        return await MainActor.run {
            renderPNGDataWithUIKit(background: background, slide: slide, width: width, height: height)
        }
        #elseif canImport(AppKit)
        return try await MainActor.run {
            try renderPNGDataWithAppKit(background: background, slide: slide, width: width, height: height)
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
    case pngEncodingFailed

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
        case .pngEncodingFailed:
            "The rendered slide could not be encoded as PNG."
        }
    }
}

#if canImport(UIKit)
private func renderPNGDataWithUIKit(background: CGImage, slide: Slide, width: Int, height: Int) -> Data {
    let size = CGSize(width: width, height: height)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true

    return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
        UIColor.black.setFill()
        context.fill(CGRect(origin: .zero, size: size))

        let backgroundRect = aspectFillRect(imageSize: CGSize(width: background.width, height: background.height), canvasSize: size)
        UIImage(cgImage: background).draw(in: backgroundRect)
        drawOverlayTextUIKit(slide: slide, canvasSize: size)
    }
}

private func drawOverlayTextUIKit(slide: Slide, canvasSize: CGSize) {
    let text = slide.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }

    let overlayRect = overlayContainerRect(for: slide.textPosition, canvasSize: canvasSize)
    let textRect = overlayRect.insetBy(dx: canvasSize.width * 0.035, dy: canvasSize.height * 0.04)
    let attributedText = NSMutableAttributedString()
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = NSTextAlignment(slide.textStyle.alignment)
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.lineSpacing = 8

    let headlineFont = UIFont.flickFont(
        name: slide.textStyle.fontName,
        size: canvasSize.height * 0.058,
        weight: UIFont.Weight(slide.textStyle.weight)
    )
    let foreground = UIColor(hex: slide.textStyle.foregroundHex)

    attributedText.append(NSAttributedString(
        string: text,
        attributes: [.font: headlineFont, .foregroundColor: foreground, .paragraphStyle: paragraph]
    ))

    let boundingSize = attributedText.boundingRect(
        with: textRect.size,
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        context: nil
    ).integral.size
    let drawRect = alignedTextRect(for: boundingSize, in: textRect, position: slide.textPosition)
    let backgroundColor = UIColor(hex: slide.textStyle.backgroundHex).withAlphaComponent(0.38)
    let backgroundRect = drawRect.insetBy(dx: -canvasSize.width * 0.018, dy: -canvasSize.height * 0.018)
    backgroundColor.setFill()
    UIBezierPath(roundedRect: backgroundRect, cornerRadius: 22).fill()
    attributedText.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
}
#endif

#if canImport(AppKit)
private func renderPNGDataWithAppKit(background: CGImage, slide: Slide, width: Int, height: Int) throws -> Data {
    let size = CGSize(width: width, height: height)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.black.setFill()
    NSRect(origin: .zero, size: size).fill()

    let backgroundRect = aspectFillRect(imageSize: CGSize(width: background.width, height: background.height), canvasSize: size)
    NSImage(cgImage: background, size: CGSize(width: background.width, height: background.height))
        .draw(in: backgroundRect, from: .zero, operation: .sourceOver, fraction: 1)
    drawOverlayTextAppKit(slide: slide, canvasSize: size)
    image.unlockFocus()

    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw TextOverlayRenderError.pngEncodingFailed
    }
    return pngData
}

private func drawOverlayTextAppKit(slide: Slide, canvasSize: CGSize) {
    let text = slide.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }

    let overlayRect = overlayContainerRect(for: slide.textPosition, canvasSize: canvasSize)
    let textRect = overlayRect.insetBy(dx: canvasSize.width * 0.035, dy: canvasSize.height * 0.04)
    let attributedText = NSMutableAttributedString()
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = NSTextAlignment(slide.textStyle.alignment)
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.lineSpacing = 8

    let headlineFont = NSFont.systemFont(ofSize: canvasSize.height * 0.058, weight: NSFont.Weight(slide.textStyle.weight))
    let foreground = NSColor(hex: slide.textStyle.foregroundHex)

    attributedText.append(NSAttributedString(
        string: text,
        attributes: [.font: headlineFont, .foregroundColor: foreground, .paragraphStyle: paragraph]
    ))

    let boundingSize = attributedText.boundingRect(
        with: textRect.size,
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    ).integral.size
    let drawRect = alignedTextRect(for: boundingSize, in: textRect, position: slide.textPosition)
    let backgroundColor = NSColor(hex: slide.textStyle.backgroundHex).withAlphaComponent(0.38)
    backgroundColor.setFill()
    NSBezierPath(roundedRect: drawRect.insetBy(dx: -canvasSize.width * 0.018, dy: -canvasSize.height * 0.018), xRadius: 22, yRadius: 22).fill()
    attributedText.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
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
    switch position {
    case .left, .split:
        CGRect(x: 0, y: 0, width: canvasSize.width * 0.45, height: canvasSize.height)
    case .right:
        CGRect(x: canvasSize.width * 0.55, y: 0, width: canvasSize.width * 0.45, height: canvasSize.height)
    case .top:
        CGRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height * 0.38)
    case .center:
        CGRect(x: canvasSize.width * 0.18, y: canvasSize.height * 0.2, width: canvasSize.width * 0.64, height: canvasSize.height * 0.6)
    case .bottom:
        CGRect(x: 0, y: canvasSize.height * 0.62, width: canvasSize.width, height: canvasSize.height * 0.38)
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
    init(_ value: String) {
        switch value.lowercased() {
        case "left", "leading":
            self = .left
        case "right", "trailing":
            self = .right
        default:
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
