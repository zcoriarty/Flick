//
//  SlideshowPlannerService.swift
//  Flick
//

import Foundation
import UniformTypeIdentifiers

struct SlideshowPlannerService {
    var client = OpenAIClient()

    func createPlan(
        brief: String,
        template: ExampleSlideshowTemplate,
        styleGuide: TemplateStyleGuide,
        creationModel: SlideshowCreationModelReference? = nil,
        productImage: SlideshowProductImage? = nil
    ) async throws -> PlannedSlideshow {
        let expectedSlideCount = template.slideCount + (productImage == nil ? 0 : 1)
        var content: [[String: Any]] = [
            [
                "type": "input_text",
                "text": """
                User brief:
                \(brief)

                Selected Flick template:
                - Niche: \(template.niche)
                - Creator profile: @\(template.profile)
                - Template slide count to keep: \(template.slideCount)
                - Total planned slide count to return: \(expectedSlideCount)
                - Template product or medium: \(template.subtitle)

                Template style guide:
                \(styleGuide.promptSummary)

                \(creationModelInstructions(for: creationModel))

                \(productImageInstructions(for: productImage, templateSlideCount: template.slideCount))

                Create a complete slideshow plan with exactly \(expectedSlideCount) planned slides.
                Create a concise one-line TikTok post title for the post settings title field.
                Flick will render all text separately, so generated image prompts must forbid readable text, captions, logos, watermarks, fake UI text, and gibberish.
                Set each slide's textPosition to center and keep the centered text area low-detail.
                """
            ]
        ]

        if let productImage {
            content.append([
                "type": "input_image",
                "image_url": try imageURL(for: productImage.asset)
            ])
        }

        let input: [[String: Any]] = [
            [
                "role": "user",
                "content": content
            ]
        ]

        return try await client.createStructuredResponse(
            instructions: planningInstructions,
            input: input,
            schemaName: "slideshow_plan",
            schema: Self.planSchema,
            as: PlannedSlideshow.self
        )
    }

    func rewritePrompt(
        draft: SlideshowDraft,
        slide: Slide,
        styleGuide: TemplateStyleGuide,
        previousVisualSummary: String,
        instruction: String
    ) async throws -> SlidePromptRewrite {
        let input: [[String: Any]] = [
            [
                "role": "user",
                "content": [
                    [
                        "type": "input_text",
                        "text": """
                        Rewrite the image prompt for one slide after manual edits.

                        Slideshow title: \(draft.title)
                        Brief: \(draft.brief)
                        Topic: \(draft.topic)
                        Audience: \(draft.audience)
                        Goal: \(draft.goal)
                        Tone: \(draft.tone)
                        Global visual motif: \(draft.globalVisualMotif)
                        Template style:
                        \(styleGuide.promptSummary)

                        \(creationModelInstructions(for: draft.creationModel))

                        Slide \(slide.index + 1):
                        - Text rendered by Flick: \(slide.text)
                        - Text overlay position: \(slide.textPosition.rawValue)
                        - Previous selected slide summary: \(previousVisualSummary)
                        - Current image prompt: \(slide.prompt)

                        User edit instruction:
                        \(instruction)

                        Return a single final image prompt and a short expected visual summary.
                        """
                    ]
                ]
            ]
        ]

        return try await client.createStructuredResponse(
            instructions: promptRewriteInstructions,
            input: input,
            schemaName: "slide_prompt_rewrite",
            schema: Self.promptRewriteSchema,
            as: SlidePromptRewrite.self
        )
    }

    func summarizeGeneratedImage(data: Data, contentType: String, slide: Slide) async throws -> String {
        let input: [[String: Any]] = [
            [
                "role": "user",
                "content": [
                    [
                        "type": "input_text",
                        "text": """
                        Summarize this generated slide image for visual continuity with the next generated slide.
                        Keep it under 24 words. Describe visible subject, composition, color, lighting, motif, and open text area.
                        Do not evaluate quality or mention whether text/logos are present.

                        Text overlay position: \(slide.textPosition.rawValue)
                        """
                    ],
                    [
                        "type": "input_image",
                        "image_url": "data:\(contentType);base64,\(data.base64EncodedString())"
                    ]
                ]
            ]
        ]

        let response = try await client.createStructuredResponse(
            instructions: "Return only the concise visual continuity summary in the requested JSON shape.",
            input: input,
            schemaName: "generated_image_summary",
            schema: Self.visualSummarySchema,
            as: VisualSummaryResponse.self
        )
        return response.visualSummary
    }

    private var planningInstructions: String {
        """
        You are Flick's slideshow planner and prompt writer.
        Normalize the brief, reuse the selected template structurally, and create one cohesive TikTok/Instagram-style image carousel plan.
        Use the existing Flick template as style and pacing reference only.
        Template people are reference material for pose, camera framing, environment, and background only; never copy their face, hair, skin tone, body, age, gender expression, clothing, or accessories.
        When a selected creation model is supplied, any visible person in generated slide prompts must match that model JSON and stay visually consistent across slides.
        Do not create image variants or candidate grids.
        Every slide must have editable Flick-rendered overlay text and exactly one vertical portrait image prompt.
        The generated images are backgrounds and must leave clean low-detail room for text overlays.
        When a selected product image is supplied, choose the single best slide position for that actual product image and write the surrounding slide strings with that image in the carousel.
        """
    }

    private var promptRewriteInstructions: String {
        """
        Rewrite a single slide image prompt for gpt-image-2.
        Preserve the selected Flick template style guide, slideshow continuity, current text overlay position, and user edit instruction.
        Preserve the draft's selected creation model whenever one is supplied, and treat template people as pose/environment references only.
        The output prompt must request one vertical portrait social slideshow image and must forbid readable text, captions, logos, watermarks, fake UI text, and gibberish.
        Do not propose variants.
        """
    }

    private static let stringArraySchema: [String: Any] = [
        "type": "array",
        "items": ["type": "string"]
    ]

    private static let textPositionEnum = ["left", "right", "top", "center", "bottom", "split"]

    private static let planSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": [
            "title",
            "tikTokTitle",
            "topic",
            "audience",
            "goal",
            "tone",
            "slideCount",
            "narrativeArc",
            "globalVisualMotif",
            "planSummary",
            "slides",
            "caption",
            "hashtags"
        ],
        "properties": [
            "title": ["type": "string"],
            "tikTokTitle": ["type": "string"],
            "topic": ["type": "string"],
            "audience": ["type": "string"],
            "goal": ["type": "string"],
            "tone": ["type": "string"],
            "slideCount": ["type": "integer"],
            "narrativeArc": stringArraySchema,
            "globalVisualMotif": ["type": "string"],
            "planSummary": ["type": "string"],
            "caption": ["type": "string"],
            "hashtags": stringArraySchema,
            "slides": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": [
                        "index",
                        "text",
                        "textPosition",
                        "imagePrompt",
                        "selectedVisualSummary",
                        "usesProductImage"
                    ],
                    "properties": [
                        "index": ["type": "integer"],
                        "text": ["type": "string"],
                        "textPosition": ["type": "string", "enum": textPositionEnum],
                        "imagePrompt": ["type": "string"],
                        "selectedVisualSummary": ["type": "string"],
                        "usesProductImage": ["type": "boolean"]
                    ]
                ]
            ]
        ]
    ]

    private static let promptRewriteSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["imagePrompt", "selectedVisualSummary"],
        "properties": [
            "imagePrompt": ["type": "string"],
            "selectedVisualSummary": ["type": "string"]
        ]
    ]

    private static let visualSummarySchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["visualSummary"],
        "properties": [
            "visualSummary": ["type": "string"]
        ]
    ]

    private func productImageInstructions(
        for productImage: SlideshowProductImage?,
        templateSlideCount: Int
    ) -> String {
        guard let productImage else {
            return "No selected product image was supplied. Set usesProductImage to false for every slide."
        }

        let summary = productImage.product.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        Selected product image:
        - Product name: \(productImage.product.name)
        - Product summary: \(summary.isEmpty ? "Not provided" : summary)
        - Actual image dimensions: \(productImage.asset.width)x\(productImage.asset.height)

        The attached image must be added as one extra actual slide image in the carousel. It must not replace one of the template slides.
        Keep exactly \(templateSlideCount) non-product generated/template slides, plus this one product-image slide.
        Choose the best narrative slide position for it and set usesProductImage to true only for that one slide.
        For the product-image slide, curate the overlay text knowing the actual product image will be shown; keep imagePrompt as a short note that Flick should use the selected product image directly.
        For all other slides, set usesProductImage to false and keep generated visuals aligned to the selected template's slide style.
        """
    }

    private func creationModelInstructions(for creationModel: SlideshowCreationModelReference?) -> String {
        guard let creationModel else {
            return """
            No selected creation model was supplied.
            If a generated slide includes a person, do not copy the person from the template image; use the template only for pose, composition, camera framing, environment, and background.
            """
        }

        return """
        Selected creation model:
        - Model name: \(creationModel.name)
        - Model JSON:
        \(creationModel.aiMetadataJSONString())

        Person identity rules:
        - Any visible generated person must be based on the selected model JSON.
        - Keep the selected model's face, hair, skin details, eyes, body, styling, and accessories consistent across slides.
        - Use template people only for pose, composition, camera framing, environment, and background.
        - Do not copy the template person's face, hair, skin tone, body, age, gender expression, clothing, or accessories when they differ from the selected model.
        - Do not force a person into slides where the visual concept does not need one.
        """
    }

    private func imageURL(for asset: MediaAsset) throws -> String {
        if let localFileURL = asset.localFileURL {
            let data = try Data(contentsOf: localFileURL)
            let fileExtension = localFileURL.pathExtension
            let contentType = UTType(filenameExtension: fileExtension)?.preferredMIMEType ?? "image/jpeg"
            return "data:\(contentType);base64,\(data.base64EncodedString())"
        }

        if let publicURL = asset.publicURL {
            return publicURL.absoluteString
        }

        throw SlideshowPlannerError.productImageUnavailable
    }
}

private struct VisualSummaryResponse: Decodable {
    var visualSummary: String
}

enum SlideshowPlannerError: LocalizedError {
    case productImageUnavailable

    var errorDescription: String? {
        switch self {
        case .productImageUnavailable:
            "The selected product image is no longer available."
        }
    }
}

enum SlideshowPromptBuilder {
    static func imagePrompt(
        for slide: Slide,
        draft: SlideshowDraft,
        styleGuide: TemplateStyleGuide,
        previousVisualSummary: String
    ) -> String {
        """
        Create a vertical portrait social slideshow image for slide \(slide.index + 1), optimized for TikTok and Instagram Reels.

        Template style:
        \(styleGuide.promptSummary)

        \(modelIdentityContract(for: draft.creationModel))

        Continuity from previous slide:
        \(previousVisualSummary.isEmpty ? "This is the first slide; establish the motif cleanly." : previousVisualSummary)

        Composition:
        - Keep the \(slide.textPosition.rawValue) overlay region clean and low-detail for Flick-rendered text.
        - Use the recurring motif: \(draft.globalVisualMotif).
        - Match the template lighting, palette, spacing, and polish.

        Strict rules:
        - No readable text.
        - No captions.
        - No logos.
        - No watermarks.
        - No fake UI text or gibberish.
        """
    }

    static func modelIdentityContract(for creationModel: SlideshowCreationModelReference?) -> String {
        guard let creationModel else {
            return """
            Person identity:
            - Use template/source people only for pose, camera framing, environment, and background.
            - Do not copy a template person's face, hair, skin tone, body, age, gender expression, clothing, or accessories.
            """
        }

        return """
        Selected creation model:
        \(creationModel.aiMetadataJSONString())

        Person identity:
        - Any visible generated person must match this selected creation model.
        - Keep the model's face, hair, skin details, eyes, body, styling, and accessories consistent.
        - Use template/source people only for pose, camera framing, environment, and background.
        - Do not copy a template person's face, hair, skin tone, body, age, gender expression, clothing, or accessories when they differ from the model JSON.
        """
    }
}
