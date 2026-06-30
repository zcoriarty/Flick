//
//  ExampleSlideshowTemplate+Preview.swift
//  Flick
//

import SwiftUI

extension ExampleSlideshowTemplate {
    var displayableSlides: [ExampleSlideshowSlide] {
        #if canImport(UIKit) || canImport(AppKit)
        slides.filter(\.hasDisplayableMediaLocation)
        #else
        slides
        #endif
    }

    var displayablePreviewSlide: ExampleSlideshowSlide? {
        #if canImport(UIKit) || canImport(AppKit)
        slides.first(where: \.hasDisplayableMediaLocation)
        #else
        displayableSlides.first
        #endif
    }

    var hasDisplayablePreview: Bool {
        displayablePreviewSlide != nil
    }
}

private extension ExampleSlideshowSlide {
    var hasDisplayableMediaLocation: Bool {
        if remoteURL != nil {
            return true
        }
        guard let localURL else {
            return false
        }
        return FileManager.default.isReadableFile(atPath: localURL.path)
    }
}
