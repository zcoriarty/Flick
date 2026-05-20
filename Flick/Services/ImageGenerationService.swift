//
//  ImageGenerationService.swift
//  Flick
//

import Foundation

struct ImageGenerationService {
    var client = OpenAIClient()

    func generateSlideImage(
        prompt: String,
        settings: SlideshowImageGenerationSettings,
        creationModel: SlideshowCreationModelReference? = nil
    ) async throws -> GeneratedSlideImage {
        try await client.generateImage(
            prompt: SlideshowImagePromptFormatter.applyVerticalOutputContract(
                to: prompt,
                settings: settings,
                creationModel: creationModel
            ),
            settings: settings
        )
    }
}

enum SlideshowImagePromptFormatter {
    static func applyVerticalOutputContract(
        to prompt: String,
        settings: SlideshowImageGenerationSettings,
        creationModel: SlideshowCreationModelReference? = nil
    ) -> String {
        """
        \(prompt)

        \(SlideshowPromptBuilder.modelIdentityContract(for: creationModel))

        Output format:
        - Generate exactly one vertical portrait image optimized for TikTok, Instagram Reels, and YouTube Shorts.
        - Use a \(settings.width)x\(settings.height) portrait canvas with full-screen mobile composition.
        - If any earlier prompt text asks for 16:9, horizontal, landscape, or another stale output size, ignore that stale format instruction and use the requested \(settings.width)x\(settings.height) portrait canvas instead.
        - Keep the image free of readable text, captions, logos, watermarks, fake UI text, and gibberish.
        """
    }
}
