//
//  SlideshowDraft+CreateReadiness.swift
//  Flick
//

import Foundation

extension SlideshowDraft {
    func createGeneratedImageCount(assetsByID: [UUID: MediaAsset]) -> Int {
        slides.filter { slide in
            guard let imageAssetID = slide.imageAssetID else { return false }
            guard let asset = assetsByID[imageAssetID] else { return false }
            return asset.hasAvailableMediaLocation
                && SlideshowImageGenerationSettings.draft.isSatisfied(by: asset)
                && slide.generationStatus == .complete
        }.count
    }

    func createMissingImageCount(assetsByID: [UUID: MediaAsset]) -> Int {
        slides.filter { slide in
            guard let imageAssetID = slide.imageAssetID else { return true }
            guard let asset = assetsByID[imageAssetID], asset.hasAvailableMediaLocation else { return true }
            return !SlideshowImageGenerationSettings.draft.isSatisfied(by: asset)
        }.count
    }

    func hasCompletedCreateImages(assetsByID: [UUID: MediaAsset]) -> Bool {
        !slides.isEmpty && createMissingImageCount(assetsByID: assetsByID) == 0
    }
}
