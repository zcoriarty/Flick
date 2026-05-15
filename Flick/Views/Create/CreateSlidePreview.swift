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
                Text(slide.text)
                    .font(.system(size: 24, weight: slide.textStyle.swiftUIFontWeight, design: slide.textStyle.swiftUIFontDesign))
                    .minimumScaleFactor(0.55)
                    .lineLimit(4)
            }
        }
        .multilineTextAlignment(textAlignment)
        .foregroundStyle(Color(hex: slide.textStyle.foregroundHex))
        .padding(14)
        .background(Color(hex: slide.textStyle.backgroundHex).opacity(0.38), in: .rect(cornerRadius: 8))
        .padding(10)
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
        switch slide.textPosition {
        case .left, .split:
            CGRect(x: 0, y: 0, width: size.width * 0.45, height: size.height)
        case .right:
            CGRect(x: size.width * 0.55, y: 0, width: size.width * 0.45, height: size.height)
        case .top:
            CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.42)
        case .center:
            CGRect(x: size.width * 0.16, y: size.height * 0.2, width: size.width * 0.68, height: size.height * 0.6)
        case .bottom:
            CGRect(x: 0, y: size.height * 0.58, width: size.width, height: size.height * 0.42)
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
