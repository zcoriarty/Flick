//
//  CreateSlidePreview.swift
//  Flick
//

import SwiftUI

struct CreateSlidePreviewCanvas: View {
    var slide: Slide
    var asset: MediaAsset?
    var cornerRadius: CGFloat = 10
    var imageContentMode: ContentMode = .fill
    var aspectRatio: CGFloat = CGFloat(SlideshowImageGenerationSettings.finalExport.aspectRatio)

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                GeneratedSlideImageView(asset: asset, contentMode: imageContentMode)
                    .frame(width: proxy.size.width, height: proxy.size.height)

                SlideOverlayPreview(slide: slide)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .id(slide.overlayPreviewID)
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
    }
}

struct CreateSlidePreviewSelection: Identifiable {
    var slide: Slide
    var asset: MediaAsset?

    var id: UUID { slide.id }
}

struct CreateSlideFullSizePreviewSheet: View {
    var slide: Slide
    var asset: MediaAsset?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
                .ignoresSafeArea()

            GeometryReader { proxy in
                let size = previewSize(in: proxy.size)

                CreateSlidePreviewCanvas(
                    slide: slide,
                    asset: asset,
                    cornerRadius: 18,
                    imageContentMode: .fit,
                    aspectRatio: previewAspectRatio
                )
                .frame(width: size.width, height: size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, horizontalPadding / 2)
                .padding(.vertical, verticalPadding / 2)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.48), in: .circle)
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.18), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .padding(16)
            .accessibilityLabel("Close full-size slide")
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Full-size slide \(slide.index + 1)")
        #if os(macOS) || targetEnvironment(macCatalyst)
        .frame(
            minWidth: 460,
            idealWidth: 560,
            maxWidth: 760,
            minHeight: 620,
            idealHeight: 760,
            maxHeight: 920
        )
        #endif
    }

    private var horizontalPadding: CGFloat { 32 }
    private var verticalPadding: CGFloat { 88 }

    private var previewAspectRatio: CGFloat {
        if let asset, asset.width > 0, asset.height > 0 {
            return CGFloat(asset.width) / CGFloat(asset.height)
        }
        return CGFloat(SlideshowImageGenerationSettings.finalExport.aspectRatio)
    }

    private func previewSize(in size: CGSize) -> CGSize {
        let availableWidth = max(1, size.width - horizontalPadding)
        let availableHeight = max(1, size.height - verticalPadding)
        let width = min(availableWidth, availableHeight * previewAspectRatio)
        return CGSize(width: width, height: width / previewAspectRatio)
    }
}

struct SlideOverlayPreview: View {
    var slide: Slide

    var body: some View {
        GeometryReader { proxy in
            overlayContent
                .frame(width: overlayFrame(in: proxy.size).width, height: overlayFrame(in: proxy.size).height, alignment: overlayAlignment)
                .position(x: overlayFrame(in: proxy.size).midX, y: overlayFrame(in: proxy.size).midY)
        }
    }

    private var overlayContent: some View {
        VStack(alignment: stackAlignment, spacing: 6) {
            if !slide.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                OutlinedSlideText(
                    text: slide.text,
                    textStyle: slide.textStyle,
                    textAlignment: textAlignment
                )
            }
        }
        .multilineTextAlignment(textAlignment)
        .padding(.vertical, 24)
    }

    private var stackAlignment: HorizontalAlignment {
        switch slide.textPosition {
        case .right:
            .trailing
        case .center, .top, .bottom:
            .center
        case .left, .split:
            .leading
        }
    }

    private var textAlignment: TextAlignment {
        switch slide.textPosition {
        case .right:
            .trailing
        case .center, .top, .bottom:
            .center
        case .left, .split:
            .leading
        }
    }

    private var overlayAlignment: Alignment {
        switch slide.textPosition {
        case .right:
            .trailing
        case .top:
            .top
        case .bottom:
            .bottom
        case .center:
            .center
        case .left, .split:
            .leading
        }
    }

    private func overlayFrame(in size: CGSize) -> CGRect {
        let horizontalMargin: CGFloat = min(32, size.width / 2)
        let centeredWidth = max(0, size.width - horizontalMargin * 2)
        return switch slide.textPosition {
        case .left, .split:
            CGRect(
                x: horizontalMargin,
                y: 0,
                width: max(0, size.width * 0.45 - horizontalMargin),
                height: size.height
            )
        case .right:
            CGRect(
                x: size.width * 0.55,
                y: 0,
                width: max(0, size.width * 0.45 - horizontalMargin),
                height: size.height
            )
        case .top:
            CGRect(x: horizontalMargin, y: 0, width: centeredWidth, height: size.height * 0.42)
        case .center:
            CGRect(x: horizontalMargin, y: size.height * 0.2, width: centeredWidth, height: size.height * 0.6)
        case .bottom:
            CGRect(x: horizontalMargin, y: size.height * 0.58, width: centeredWidth, height: size.height * 0.42)
        }
    }
}

private struct OutlinedSlideText: View {
    private let symbolID = "slide-text-stroke"

    var text: String
    var textStyle: SlideTextStyle
    var textAlignment: TextAlignment

    var body: some View {
        baseText
            .foregroundStyle(Color(hex: textStyle.foregroundHex))
            .padding(strokeWidth * 2)
            .background {
                GeometryReader { proxy in
                    Color(hex: textStyle.outlineColorHex)
                        .mask {
                            strokeMask(in: proxy.size)
                        }
                }
            }
            .id(renderID)
    }

    private var baseText: some View {
        Text(text)
            .font(.system(
                size: fontSize,
                weight: textStyle.swiftUIFontWeight,
                design: textStyle.swiftUIFontDesign
            ))
            .minimumScaleFactor(0.55)
            .lineLimit(4)
            .multilineTextAlignment(textAlignment)
    }

    private var fontSize: CGFloat {
        CGFloat(24 * textStyle.sizeScale)
    }

    private var strokeWidth: CGFloat {
        CGFloat(1.45 * textStyle.sizeScale)
    }

    private var textFrameAlignment: Alignment {
        switch textAlignment {
        case .leading:
            .leading
        case .trailing:
            .trailing
        case .center:
            .center
        }
    }

    private var renderID: String {
        [
            text,
            textStyle.fontName,
            textStyle.weight,
            String(format: "%.2f", textStyle.sizeScale),
            textStyle.foregroundHex,
            textStyle.outlineColorHex,
            textAlignment.renderID
        ].joined(separator: "|")
    }

    private func strokeMask(in size: CGSize) -> some View {
        Canvas { context, size in
            context.addFilter(.alphaThreshold(min: 0.01))
            if let resolvedView = context.resolveSymbol(id: symbolID) {
                context.draw(
                    resolvedView,
                    at: CGPoint(x: size.width / 2, y: size.height / 2)
                )
            }
        } symbols: {
            baseText
                .foregroundStyle(.white)
                .frame(
                    width: max(0, size.width - strokeWidth * 4),
                    height: max(0, size.height - strokeWidth * 4),
                    alignment: textFrameAlignment
                )
                .blur(radius: strokeWidth)
                .tag(symbolID)
        }
    }
}

private extension Slide {
    var overlayPreviewID: String {
        [
            text,
            textPosition.rawValue,
            textStyle.fontName,
            textStyle.weight,
            String(format: "%.2f", textStyle.sizeScale),
            textStyle.foregroundHex,
            textStyle.outlineColorHex
        ].joined(separator: "|")
    }
}

private extension TextAlignment {
    var renderID: String {
        switch self {
        case .leading:
            "leading"
        case .trailing:
            "trailing"
        case .center:
            "center"
        }
    }
}

private extension SlideTextStyle {
    var swiftUIFontDesign: Font.Design {
        switch fontName.lowercased() {
        case "system rounded", "rounded":
            .rounded
        case "serif":
            .serif
        case "monospaced", "monospace":
            .monospaced
        default:
            .default
        }
    }

    var swiftUIFontWeight: Font.Weight {
        switch weight.lowercased() {
        case "regular":
            .regular
        case "medium":
            .medium
        case "semibold":
            .semibold
        case "black", "heavy":
            .black
        default:
            .bold
        }
    }
}
