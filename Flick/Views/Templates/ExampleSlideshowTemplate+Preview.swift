//
//  ExampleSlideshowTemplate+Preview.swift
//  Flick
//

import SwiftUI

extension ExampleSlideshowTemplate {
    var displayableSlides: [ExampleSlideshowSlide] {
        #if canImport(UIKit) || canImport(AppKit)
        slides.filter { slide in
            LocalAssetImageLoader.image(at: slide.localURL) != nil
        }
        #else
        slides
        #endif
    }

    var displayablePreviewSlide: ExampleSlideshowSlide? {
        displayableSlides.first
    }

    var hasDisplayablePreview: Bool {
        displayablePreviewSlide != nil
    }
}
