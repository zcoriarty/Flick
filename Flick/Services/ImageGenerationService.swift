//
//  ImageGenerationService.swift
//  Flick
//

import Foundation

struct ImageGenerationService {
    var client = OpenAIClient()

    func generateSlideImage(prompt: String, settings: SlideshowImageGenerationSettings) async throws -> GeneratedSlideImage {
        try await client.generateImage(
            prompt: SlideshowImagePromptFormatter.applyVerticalOutputContract(to: prompt, settings: settings),
            settings: settings
        )
    }
}

enum SlideshowImagePromptFormatter {
    static func applyVerticalOutputContract(to prompt: String, settings: SlideshowImageGenerationSettings) -> String {
        """
        \(prompt)

        Output format:
        - Generate exactly one vertical 9:16 image optimized for TikTok, Instagram Reels, and YouTube Shorts.
        - Use a \(settings.width)x\(settings.height) portrait canvas with full-screen mobile composition.
        - If any earlier prompt text asks for 16:9, horizontal, or landscape output, ignore that stale format instruction and use vertical 9:16 instead.
        - Keep the image free of readable text, captions, logos, watermarks, fake UI text, and gibberish.
        """
    }
}
