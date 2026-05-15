//
//  CreateSlidePreview.swift
//  Flick
//

import SwiftUI

struct CreateSlidePreviewCanvas: View {
    var slide: Slide
    var asset: MediaAsset?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                GeneratedSlideImageView(asset: asset)
                    .frame(width: proxy.size.width, height: proxy.size.height)

                SlideOverlayPreview(slide: slide)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .id(slide.overlayPreviewID)
            }
            .clipShape(.rect(cornerRadius: 10))
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
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
