//
//  ProductImageCropSheet.swift
//  Flick
//

import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#endif

struct ProductImageCropItem: Identifiable, Hashable {
    var id = UUID()
    var fileURL: URL
    var contentType: UTType
}

#if canImport(UIKit)
struct ProductImageCropSheet: View {
    @Environment(\.dismiss) private var dismiss

    static let generatedSlideTargetPixelSize = CGSize(
        width: CGFloat(SlideshowImageGenerationSettings.draft.width),
        height: CGFloat(SlideshowImageGenerationSettings.draft.height)
    )

    var item: ProductImageCropItem
    var targetPixelSize: CGSize = Self.generatedSlideTargetPixelSize
    var importAction: (Data, UTType) async throws -> Void

    @State private var image: UIImage?
    @State private var cropState = ProductImageCropState()
    @State private var loadErrorMessage: String?
    @State private var saveErrorMessage: String?
    @State private var isSaving = false

    private var targetAspectRatio: CGFloat {
        targetPixelSize.width / max(targetPixelSize.height, 1)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    cropContent(image)
                } else {
                    ProductImageCropMessage(
                        title: "Image unavailable",
                        message: loadErrorMessage ?? "Flick could not load this image for cropping.",
                        systemImage: "photo.badge.exclamationmark"
                    )
                    .padding(24)
                }
            }
            .flickAppBackground()
            .flickToolbarTitle("Crop Product Image")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        finishAndDismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Import", systemImage: "checkmark") {
                        save()
                    }
                    .disabled(image == nil || isSaving)
                }
            }
        }
        .task {
            loadImage()
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func cropContent(_ image: UIImage) -> some View {
        VStack(spacing: 16) {
            GeometryReader { proxy in
                let viewportSize = ProductImageCropLayout.viewportSize(
                    in: proxy.size,
                    targetAspectRatio: targetAspectRatio
                )

                ProductImageCropCanvas(
                    image: image,
                    targetAspectRatio: targetAspectRatio,
                    cropState: $cropState
                )
                .frame(width: viewportSize.width, height: viewportSize.height)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .frame(maxWidth: 420, minHeight: 360, maxHeight: 560)
            .padding(.horizontal, 20)
            .padding(.top, 18)

            ProductImageCropControls(
                zoom: $cropState.zoom,
                targetPixelSize: targetPixelSize,
                resetAction: resetCrop
            )
            .padding(.horizontal, 20)

            if let saveErrorMessage {
                Text(saveErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            }

            Spacer(minLength: 12)
        }
        .onChange(of: cropState.zoom) { _, _ in
            cropState.clamp(
                imageSize: image.productCropPixelSize,
                targetAspectRatio: targetAspectRatio
            )
        }
    }

    private func loadImage() {
        guard image == nil, loadErrorMessage == nil else { return }

        guard let loadedImage = ProductImageCropLoader.loadImage(at: item.fileURL) else {
            loadErrorMessage = ProductImageCropError.imageUnavailable.localizedDescription
            return
        }

        image = loadedImage
        cropState.clamp(
            imageSize: loadedImage.productCropPixelSize,
            targetAspectRatio: targetAspectRatio
        )
    }

    private func resetCrop() {
        guard let image else { return }

        withAnimation(.smooth(duration: 0.18)) {
            cropState = ProductImageCropState()
            cropState.clamp(
                imageSize: image.productCropPixelSize,
                targetAspectRatio: targetAspectRatio
            )
        }
    }

    private func save() {
        guard let image, !isSaving else { return }

        isSaving = true
        saveErrorMessage = nil

        Task {
            do {
                let jpegData = try ProductImageCropRenderer.jpegData(
                    image: image,
                    cropState: cropState,
                    targetPixelSize: targetPixelSize
                )
                try await importAction(jpegData, .jpeg)
                finishAndDismiss()
            } catch {
                saveErrorMessage = error.localizedDescription
            }

            isSaving = false
        }
    }

    private func finishAndDismiss() {
        dismiss()
    }
}

struct ProductImageCropState: Equatable {
    var center = CGPoint(x: 0.5, y: 0.5)
    var zoom: CGFloat = 1

    func cropRect(in imageSize: CGSize, targetAspectRatio: CGFloat) -> CGRect {
        let imageSize = normalizedImageSize(imageSize)
        let cropSize = baseCropSize(in: imageSize, targetAspectRatio: targetAspectRatio) / normalizedZoom
        let centerPoint = CGPoint(
            x: center.x.clamped(to: 0...1) * imageSize.width,
            y: center.y.clamped(to: 0...1) * imageSize.height
        )
        let origin = CGPoint(
            x: (centerPoint.x - cropSize.width / 2).clamped(to: 0...max(0, imageSize.width - cropSize.width)),
            y: (centerPoint.y - cropSize.height / 2).clamped(to: 0...max(0, imageSize.height - cropSize.height))
        )

        return CGRect(origin: origin, size: cropSize)
    }

    mutating func move(
        by translation: CGSize,
        viewportSize: CGSize,
        imageSize: CGSize,
        targetAspectRatio: CGFloat
    ) {
        let imageSize = normalizedImageSize(imageSize)
        let viewportSize = CGSize(width: max(1, viewportSize.width), height: max(1, viewportSize.height))
        let cropRect = cropRect(in: imageSize, targetAspectRatio: targetAspectRatio)
        let deltaX = -translation.width / viewportSize.width * cropRect.width
        let deltaY = -translation.height / viewportSize.height * cropRect.height

        center.x += deltaX / imageSize.width
        center.y += deltaY / imageSize.height
        clamp(imageSize: imageSize, targetAspectRatio: targetAspectRatio)
    }

    mutating func clamp(imageSize: CGSize, targetAspectRatio: CGFloat) {
        let imageSize = normalizedImageSize(imageSize)
        zoom = normalizedZoom

        let rect = cropRect(in: imageSize, targetAspectRatio: targetAspectRatio)
        center = CGPoint(
            x: (rect.midX / imageSize.width).clamped(to: 0...1),
            y: (rect.midY / imageSize.height).clamped(to: 0...1)
        )
    }

    private var normalizedZoom: CGFloat {
        zoom.clamped(to: 1...6)
    }

    private func normalizedImageSize(_ imageSize: CGSize) -> CGSize {
        CGSize(width: max(1, imageSize.width), height: max(1, imageSize.height))
    }

    private func baseCropSize(in imageSize: CGSize, targetAspectRatio: CGFloat) -> CGSize {
        let targetAspectRatio = max(0.01, targetAspectRatio)
        let imageAspectRatio = imageSize.width / max(imageSize.height, 1)

        if imageAspectRatio > targetAspectRatio {
            return CGSize(width: imageSize.height * targetAspectRatio, height: imageSize.height)
        }

        return CGSize(width: imageSize.width, height: imageSize.width / targetAspectRatio)
    }
}

enum ProductImageCropRenderer {
    static func jpegData(
        image: UIImage,
        cropState: ProductImageCropState,
        targetPixelSize: CGSize,
        compressionQuality: CGFloat = 0.92
    ) throws -> Data {
        guard let cgImage = image.cgImage else {
            throw ProductImageCropError.imageUnavailable
        }

        let imageSize = image.productCropPixelSize
        let targetAspectRatio = targetPixelSize.width / max(targetPixelSize.height, 1)
        let cropRect = cropState.cropRect(in: imageSize, targetAspectRatio: targetAspectRatio)
        let sourceRect = sourcePixelRect(
            cropRect: cropRect,
            imageSize: imageSize,
            cgImageSize: CGSize(width: cgImage.width, height: cgImage.height)
        )

        guard let croppedImage = cgImage.cropping(to: sourceRect) else {
            throw ProductImageCropError.cropFailed
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetPixelSize, format: format)
        return renderer.jpegData(withCompressionQuality: compressionQuality) { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: targetPixelSize))
            UIImage(cgImage: croppedImage).draw(in: CGRect(origin: .zero, size: targetPixelSize))
        }
    }

    private static func sourcePixelRect(cropRect: CGRect, imageSize: CGSize, cgImageSize: CGSize) -> CGRect {
        let scaleX = cgImageSize.width / max(imageSize.width, 1)
        let scaleY = cgImageSize.height / max(imageSize.height, 1)
        let pixelBounds = CGRect(origin: .zero, size: cgImageSize)
        let rect = CGRect(
            x: cropRect.minX * scaleX,
            y: cropRect.minY * scaleY,
            width: cropRect.width * scaleX,
            height: cropRect.height * scaleY
        )
        return rect.integral.intersection(pixelBounds)
    }
}

private struct ProductImageCropCanvas: View {
    var image: UIImage
    var targetAspectRatio: CGFloat
    @Binding var cropState: ProductImageCropState

    @State private var lastDragTranslation: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let imageSize = image.productCropPixelSize
            let cropRect = cropState.cropRect(
                in: imageSize,
                targetAspectRatio: targetAspectRatio
            )
            let displayScale = proxy.size.width / max(cropRect.width, 1)
            let displaySize = CGSize(
                width: imageSize.width * displayScale,
                height: imageSize.height * displayScale
            )
            let displayOrigin = CGPoint(
                x: -cropRect.minX * displayScale,
                y: -cropRect.minY * displayScale
            )

            Image(uiImage: image)
                .resizable()
                .frame(width: displaySize.width, height: displaySize.height)
                .position(
                    x: displayOrigin.x + displaySize.width / 2,
                    y: displayOrigin.y + displaySize.height / 2
                )
                .gesture(dragGesture(viewportSize: proxy.size, imageSize: imageSize))
        }
        .background(Color.black)
        .clipShape(.rect(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.28), lineWidth: 1)
        }
        .overlay {
            ProductImageCropGrid()
                .clipShape(.rect(cornerRadius: 18, style: .continuous))
        }
        .compositingGroup()
        .accessibilityLabel("Product image crop")
        .accessibilityHint("Drag the image to adjust the crop.")
    }

    private func dragGesture(viewportSize: CGSize, imageSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let delta = CGSize(
                    width: value.translation.width - lastDragTranslation.width,
                    height: value.translation.height - lastDragTranslation.height
                )
                cropState.move(
                    by: delta,
                    viewportSize: viewportSize,
                    imageSize: imageSize,
                    targetAspectRatio: targetAspectRatio
                )
                lastDragTranslation = value.translation
            }
            .onEnded { _ in
                lastDragTranslation = .zero
            }
    }
}

private struct ProductImageCropGrid: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let thirdWidth = proxy.size.width / 3
                let thirdHeight = proxy.size.height / 3

                for index in 1...2 {
                    let x = CGFloat(index) * thirdWidth
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: proxy.size.height))

                    let y = CGFloat(index) * thirdHeight
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                }
            }
            .stroke(.white.opacity(0.32), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

private struct ProductImageCropControls: View {
    @Binding var zoom: CGFloat
    var targetPixelSize: CGSize
    var resetAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("Zoom", systemImage: "plus.magnifyingglass")
                    .font(.callout.weight(.semibold))

                Spacer()

                Text("\(Int(targetPixelSize.width)) x \(Int(targetPixelSize.height))")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button("Reset", systemImage: "arrow.counterclockwise", action: resetAction)
                    .buttonStyle(.borderless)
            }

            Slider(value: $zoom, in: 1...6)
        }
        .padding(14)
        .background(.thinMaterial, in: .rect(cornerRadius: 14, style: .continuous))
    }
}

private struct ProductImageCropMessage: View {
    var title: String
    var message: String
    var systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private enum ProductImageCropLayout {
    static func viewportSize(in availableSize: CGSize, targetAspectRatio: CGFloat) -> CGSize {
        let availableSize = CGSize(
            width: max(1, availableSize.width),
            height: max(1, availableSize.height)
        )
        let heightForAvailableWidth = availableSize.width / max(targetAspectRatio, 0.01)
        if heightForAvailableWidth <= availableSize.height {
            return CGSize(width: availableSize.width, height: heightForAvailableWidth)
        }

        return CGSize(
            width: availableSize.height * targetAspectRatio,
            height: availableSize.height
        )
    }
}

private enum ProductImageCropLoader {
    static func loadImage(at fileURL: URL) -> UIImage? {
        guard
            let data = try? Data(contentsOf: fileURL),
            let image = UIImage(data: data)
        else {
            return nil
        }

        return image.normalizedForProductCrop()
    }
}

enum ProductImageCropError: LocalizedError {
    case imageUnavailable
    case cropFailed

    var errorDescription: String? {
        switch self {
        case .imageUnavailable:
            "Flick could not load this image."
        case .cropFailed:
            "Flick could not crop this image."
        }
    }
}

private extension UIImage {
    var productCropPixelSize: CGSize {
        guard let cgImage else { return size }
        return CGSize(width: cgImage.width, height: cgImage.height)
    }

    func normalizedForProductCrop() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private extension CGSize {
    static func / (size: CGSize, divisor: CGFloat) -> CGSize {
        CGSize(width: size.width / divisor, height: size.height / divisor)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
#else
struct ProductImageCropSheet: View {
    var item: ProductImageCropItem
    var targetPixelSize: CGSize = .zero
    var importAction: (Data, UTType) async throws -> Void

    var body: some View {
        ProductImageCropMessage(
            title: "Image cropping unavailable",
            message: "This platform cannot crop product images.",
            systemImage: "photo.badge.exclamationmark"
        )
    }
}

private struct ProductImageCropMessage: View {
    var title: String
    var message: String
    var systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
            Text(title)
            Text(message)
        }
        .padding()
    }
}
#endif
