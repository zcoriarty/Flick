//
//  VerticalMediaFrame.swift
//  Flick
//

import SwiftUI

struct VerticalMediaFrame: View {
    static let targetPixelSize = CGSize(width: 1_080, height: 1_920)
    static let targetAspectRatio = targetPixelSize.width / targetPixelSize.height

    var fileURL: URL?
    var remoteURL: URL?
    var cornerRadius: CGFloat = 8
    var maxPixelSize: Int = 1_080

    var body: some View {
        ZStack {
            Color.black

            GeometryReader { proxy in
                LocalAssetImage(
                    fileURL: fileURL,
                    remoteURL: remoteURL,
                    contentMode: .fit,
                    maxPixelSize: maxPixelSize
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .aspectRatio(Self.targetAspectRatio, contentMode: .fit)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .compositingGroup()
    }
}
