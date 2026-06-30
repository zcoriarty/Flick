//
//  TemplateAnalysisService.swift
//  Flick
//

import Foundation
import UniformTypeIdentifiers

struct TemplateAnalysisService {
    var client = OpenAIClient()

    func createStyleGuide(from template: ExampleSlideshowTemplate) async throws -> TemplateStyleGuide {
        let input: [[String: Any]] = [
            [
                "role": "user",
                "content": try inputContent(for: template)
            ]
        ]

        return try await client.createStructuredResponse(
            instructions: instructions,
            input: input,
            schemaName: "template_style_guide",
            schema: Self.styleGuideSchema,
            as: TemplateStyleGuide.self
        )
    }

    private var instructions: String {
        """
        Convert the selected Flick slideshow template into a compact reusable style guide for AI-generated vertical portrait social carousel images.
        Capture visual style, polish, palette, lighting, recurring motifs, what to reuse structurally, and what not to copy directly.
        Do not copy people, exact products, product screenshots, app UI, logos, creators, captions, or readable text from the reference template.
        Identify any 1-based slide numbers where a visible product image, app screenshot, product UI, device mockup, product packaging, or product logo is a meaningful subject; return those numbers in productImageSlideNumbers.
        Treat detected product images as replaceable placeholders only, never as visual details to reuse in generated prompts.
        Always include image generation rules that require no readable text, no captions, no logos, no watermarks, no copied template products, and slide-to-slide continuity.
        """
    }

    private func inputContent(for template: ExampleSlideshowTemplate) throws -> [[String: Any]] {
        var content: [[String: Any]] = [
            [
                "type": "input_text",
                "text": """
                Template metadata:
                - Niche: \(template.niche)
                - Creator profile: @\(template.profile)
                - Slide count: \(template.slideCount)
                - Product or medium: \(template.subtitle)
                - Creator signature: \(template.creator.signature ?? "Unknown")

                Analyze the attached slide images as visual style references only. Build a reusable guide for new content in the same visual language.
                Product images from the template are examples from someone else's post. Detect their slide numbers, but exclude their product, app, UI, logo, package, and screenshot details from reusable style guidance.
                """
            ]
        ]

        for slide in template.slides.prefix(12) {
            content.append([
                "type": "input_text",
                "text": "Reference slide \(slide.index). Use only composition, lighting, palette, motifs, and visual-style cues. If this slide contains a product image, app screenshot, product UI, device mockup, packaging, or product logo as a meaningful subject, include slide \(slide.index) in productImageSlideNumbers."
            ])
            content.append([
                "type": "input_image",
                "image_url": try imageURL(for: slide)
            ])
        }

        return content
    }

    private func imageURL(for slide: ExampleSlideshowSlide) throws -> String {
        if let remoteURL = slide.remoteURL {
            return remoteURL.absoluteString
        }
        guard let localURL = slide.localURL else {
            throw TemplateAnalysisInputError.missingImageLocation(slide.index)
        }
        return try dataURL(for: localURL)
    }

    private func dataURL(for fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let fileExtension = fileURL.pathExtension
        let contentType = UTType(filenameExtension: fileExtension)?.preferredMIMEType ?? "image/jpeg"
        return "data:\(contentType);base64,\(data.base64EncodedString())"
    }

    private static let stringArraySchema: [String: Any] = [
        "type": "array",
        "items": ["type": "string"]
    ]

    private static let styleGuideSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": [
            "styleName",
            "visualTraits",
            "colorPalette",
            "lighting",
            "recurringMotifs",
            "reuseStructurally",
            "avoidCopyingDirectly",
            "imageGenerationRules",
            "productImageSlideNumbers"
        ],
        "properties": [
            "styleName": ["type": "string"],
            "visualTraits": stringArraySchema,
            "colorPalette": stringArraySchema,
            "lighting": ["type": "string"],
            "recurringMotifs": stringArraySchema,
            "reuseStructurally": stringArraySchema,
            "avoidCopyingDirectly": stringArraySchema,
            "imageGenerationRules": stringArraySchema,
            "productImageSlideNumbers": [
                "type": "array",
                "items": ["type": "integer"]
            ]
        ]
    ]
}

private enum TemplateAnalysisInputError: LocalizedError {
    case missingImageLocation(Int)

    var errorDescription: String? {
        switch self {
        case let .missingImageLocation(index):
            "Template slide \(index) does not have a local file or public URL."
        }
    }
}
