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
        creationModel: SlideshowCreationModelReference? = nil,
        imageVibe: SlideshowImageVibe = .defaultValue
    ) async throws -> GeneratedSlideImage {
        try await client.generateImage(
            prompt: SlideshowImagePromptFormatter.applyVerticalOutputContract(
                to: prompt,
                settings: settings,
                creationModel: creationModel,
                imageVibe: imageVibe
            ),
            settings: settings
        )
    }
}

enum SlideshowImagePromptFormatter {
    static func applyVerticalOutputContract(
        to prompt: String,
        settings: SlideshowImageGenerationSettings,
        creationModel: SlideshowCreationModelReference? = nil,
        imageVibe: SlideshowImageVibe = .defaultValue
    ) -> String {
        """
        \(prompt)

        \(SlideshowPromptBuilder.modelIdentityContract(for: creationModel))

        Image vibe:
        \(imageVibe.generationContract)

        \(SlideshowImageVibe.antiAIGlossContract)

        Output format:
        - Generate exactly one vertical portrait image optimized for TikTok, Instagram Reels, and YouTube Shorts.
        - Use a \(settings.width)x\(settings.height) portrait canvas with full-screen mobile composition.
        - If any earlier prompt text asks for 16:9, horizontal, landscape, or another stale output size, ignore that stale format instruction and use the requested \(settings.width)x\(settings.height) portrait canvas instead.
        - If any earlier prompt text asks for glossy, hyperreal, CGI, rendered, illustrated, anime, cartoon, stock-photo-composite, or plastic-perfect visuals, ignore that stale style instruction and prioritize human-camera realism.
        - Keep the image free of readable text, captions, logos, watermarks, fake UI text, and gibberish.
        """
    }
}
