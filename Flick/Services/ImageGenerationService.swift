//
//  ImageGenerationService.swift
//  Flick
//

import Foundation

struct ImageGenerationService {
    var client = OpenAIClient()

    func generateSlideImage(prompt: String, settings: SlideshowImageGenerationSettings) async throws -> GeneratedSlideImage {
        try await client.generateImage(prompt: prompt, settings: settings)
    }
}
