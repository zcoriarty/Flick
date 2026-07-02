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
        Capture visual style, polish, palette, lighting, recurring motifs, reusable copy structure, and protected identity/product details that should not be copied.
        Extract one slideBlueprint for each attached reference slide so planning can preserve the template's copy rhythm, overlay placement, person placement, subject, and composition.
        Record visible readable text as a reusable copy reference when it is generic, non-brand wording. Preserve or copy generic non-brand wording that defines the template's hook, cadence, or slide structure.
        Do not include creator names, usernames, handles, product names, logos, UI text, watermarks, brand-specific claims, or other protected third-party identity/product wording in visibleText.
        Do not copy people, exact products, product screenshots, app UI, logos, creators, usernames, handles, product names, or brand-specific captions from the reference template into reusable generated content.
        Identify any 1-based slide numbers where a visible product image, app screenshot, product UI, device mockup, product packaging, or product logo is a meaningful subject; return those numbers in productImageSlideNumbers.
        Mark the matching slideBlueprint isProductPlaceholder values true. Treat detected product images as replaceable placeholders only, never as visual details to reuse in generated prompts.
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

                Analyze the attached slide images as reusable style and structure references. Build a guide for new content in the same visual language.
                For each attached slide, extract a slideBlueprint with visible text reference, copy role, text overlay position, person presence and position, main subject, composition, and product-placeholder status.
                For visibleText, keep generic reusable words and short phrases that are safe to copy directly. Omit or generalize creator names, usernames, handles, product names, brand names, logos, UI text, watermarks, and product-specific claims.
                Product images from the template are examples from someone else's post. Detect their slide numbers, but exclude their product, app, UI, logo, package, and screenshot details from reusable style guidance.
                """
            ]
        ]

        for slide in template.slides.prefix(12) {
            content.append([
                "type": "input_text",
                "text": "Reference slide \(slide.index). Extract one slideBlueprint for slide \(slide.index). Use composition, lighting, palette, motifs, text placement, copy role, text density, person placement, and visual-style cues. Preserve generic non-brand visible words that can be reused as overlay text. Omit protected creator, brand, product, logo, UI, watermark, username, handle, and product-specific wording. If this slide contains a product image, app screenshot, product UI, device mockup, packaging, or product logo as a meaningful subject, include slide \(slide.index) in productImageSlideNumbers and set isProductPlaceholder true."
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

    private static let textPositionEnum = ["left", "right", "top", "center", "bottom", "split"]

    private static let slideBlueprintSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": [
            "slideNumber",
            "visibleText",
            "copyRole",
            "textPosition",
            "personPresence",
            "personPosition",
            "mainSubject",
            "composition",
            "isProductPlaceholder"
        ],
        "properties": [
            "slideNumber": ["type": "integer"],
            "visibleText": ["type": "string"],
            "copyRole": ["type": "string"],
            "textPosition": ["type": "string", "enum": textPositionEnum],
            "personPresence": ["type": "string"],
            "personPosition": ["type": "string"],
            "mainSubject": ["type": "string"],
            "composition": ["type": "string"],
            "isProductPlaceholder": ["type": "boolean"]
        ]
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
            "productImageSlideNumbers",
            "slideBlueprints"
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
            ],
            "slideBlueprints": [
                "type": "array",
                "items": slideBlueprintSchema
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
