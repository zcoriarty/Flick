//
//  ExampleSlideshowTemplate+Preview.swift
//  Flick
//

import SwiftUI

extension ExampleSlideshowTemplate {
    var displayableSlides: [ExampleSlideshowSlide] {
        #if canImport(UIKit) || canImport(AppKit)
        slides.filter { slide in
            LocalAssetImageLoader.image(at: slide.localURL, maxPixelSize: 240) != nil
        }
        #else
        slides
        #endif
    }

    var displayablePreviewSlide: ExampleSlideshowSlide? {
        #if canImport(UIKit) || canImport(AppKit)
        slides.first { slide in
            LocalAssetImageLoader.image(at: slide.localURL, maxPixelSize: 240) != nil
        }
        #else
        displayableSlides.first
        #endif
    }

    var hasDisplayablePreview: Bool {
        displayablePreviewSlide != nil
    }
}
