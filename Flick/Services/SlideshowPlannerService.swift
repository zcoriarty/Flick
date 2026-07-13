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
        productImage: SlideshowProductImage? = nil,
        imageVibe: SlideshowImageVibe = .defaultValue
    ) async throws -> PlannedSlideshow {
        let templateProductImageSlideNumbers = styleGuide.productImageSlideNumbers(limitedTo: template.slideCount)
        let expectedSlideCount = expectedSlideCount(
            templateSlideCount: template.slideCount,
            templateProductImageSlideNumbers: templateProductImageSlideNumbers,
            productImage: productImage
        )
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
                - Template product or medium: suppressed; template product metadata is not a selected product and must not be used
                - Detected template product-image slide numbers: \(slideNumberSummary(templateProductImageSlideNumbers))

                Template style guide:
                \(styleGuide.promptSummary)

                Template slide blueprints:
                \(templateSlideBlueprintSummary(
                    styleGuide.slideBlueprints,
                    slideCount: template.slideCount,
                    productImage: productImage
                ))

                \(imageVibe.planningInstructions)

                \(creationModelInstructions(for: creationModel))

                \(productImageInstructions(
                    for: productImage,
                    templateSlideCount: template.slideCount,
                    templateProductImageSlideNumbers: templateProductImageSlideNumbers
                ))

                Create a complete slideshow plan with exactly \(expectedSlideCount) planned slides.
                Create a concise one-line TikTok post title for the post settings title field.
                Base each slide's editable text, textPosition, visual subject, person placement, and composition on the matching template slide blueprint.
                Reuse the template visibleText directly when it is generic, non-brand wording and still fits the user brief. Retarget it only when the selected product image, selected product summary, or user brief requires different specifics.
                Never copy creator names, usernames, handles, brand names, product names, logos, UI text, watermarks, or product-specific claims from the template.
                Avoid generic business filler phrases such as "Move the needle" unless that exact phrase appears in the user brief or template visible text reference.
                \(imageVibe.plannedPromptVisualRequirement)
                Flick will render all text separately, so generated image prompts must forbid readable text, captions, logos, watermarks, fake UI text, and gibberish.
                Set each slide's textPosition to the matching template blueprint's textPosition when available; use center only when no blueprint exists.
                Keep the chosen overlay region clean and low-detail for Flick-rendered text.
                Keep product-image placeholder handling exactly as specified above.
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
            instructions: planningInstructions(for: imageVibe),
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
        instruction: String,
        imageVibe: SlideshowImageVibe? = nil
    ) async throws -> SlidePromptRewrite {
        let resolvedImageVibe = imageVibe ?? draft.imageVibe
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

                        \(resolvedImageVibe.planningInstructions)

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
            instructions: promptRewriteInstructions(for: resolvedImageVibe),
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

    private func planningInstructions(for imageVibe: SlideshowImageVibe) -> String {
        """
        You are Flick's slideshow planner and prompt writer.
        Normalize the brief, reuse the selected template structurally, and create one cohesive TikTok/Instagram-style image carousel plan.
        Use the existing Flick template as style, pacing, layout, and safe-copy reference.
        Preserve the selected template's slide-by-slide copy role, text density, overlay placement, subject framing, person position, and composition rhythm.
        Safe generic template wording may be copied directly when it fits the new post; retarget it only for selected product images, selected product summaries, or user-specific brief details.
        Do not copy creator names, usernames, handles, brand names, product names, logos, UI text, watermarks, or product-specific claims from the template.
        Avoid generic filler copy such as "Move the needle", "Unlock your potential", "Level up", or "Game changer" unless those exact words are supplied by the user brief or template visible text reference.
        \(imageVibe.plannerVisualRequirement)
        Template people are reference material for pose, camera framing, environment, and background only; never copy their face, hair, skin tone, body, age, gender expression, clothing, or accessories.
        When a selected creation model is supplied, any visible person in generated slide prompts must match that model JSON and stay visually consistent across slides.
        Do not create image variants or candidate grids.
        Every slide must have editable Flick-rendered overlay text and exactly one vertical portrait image prompt.
        The generated images are backgrounds and must leave clean low-detail room for text overlays.
        Treat template product images, app screenshots, product UI, logos, packaging, and other product-specific visuals as placeholders only.
        When a selected product image is supplied, replace detected template product-image placeholders with that actual image; only append a final product-image slide when the template has no detected product-image placeholders.
        When no selected product image is supplied, generated image prompts must not include or recreate template product imagery.
        """
    }

    private func promptRewriteInstructions(for imageVibe: SlideshowImageVibe) -> String {
        """
        Rewrite a single slide image prompt for gpt-image-2.
        Preserve the selected Flick template style guide, slideshow continuity, current text overlay position, and user edit instruction.
        \(imageVibe.rewriteVisualRequirement)
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
        templateSlideCount: Int,
        templateProductImageSlideNumbers: [Int]
    ) -> String {
        let slideNumbers = slideNumberSummary(templateProductImageSlideNumbers)

        guard let productImage else {
            if templateProductImageSlideNumbers.isEmpty {
                return """
                No selected product image was supplied.
                Set usesProductImage to false for every slide.
                Do not create product-image slides or visual subjects that look like an app, product, device mockup, store page, package, logo, or product hero.
                Generated image prompts must not mention, recreate, imply, or visually describe any template product, app screens, screenshots, device UI, logos, packaging, product names, or store pages.
                """
            }

            return """
            No selected product image was supplied.
            Detected template product-image slide numbers: \(slideNumbers).
            Keep the template's pacing and narrative beats, but turn those positions into non-product generated visuals.
            Set usesProductImage to false for every slide.
            Do not create a substitute product, app UI, phone mockup, store page, packaging, logo, or product hero.
            For matching product-placeholder blueprints, use only copy role, overlay position, pacing, person placement, and non-product style cues; ignore their template product/app/UI/package/logo/store-page visible text, main subject, and composition details.
            Image prompts must not mention, recreate, imply, or visually describe the template product, app screens, screenshots, device UI, logos, packaging, product names, or store pages.
            """
        }

        let summary = productImage.product.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let productDetails = """
        Selected product image:
        - Product name: \(productImage.product.name)
        - Product summary: \(summary.isEmpty ? "Not provided" : summary)
        - Actual image dimensions: \(productImage.asset.width)x\(productImage.asset.height)
        """

        if !templateProductImageSlideNumbers.isEmpty {
            return """
            \(productDetails)

            Detected template product-image slide numbers: \(slideNumbers).
            Replace those template product-image positions with the attached selected product image. Do not add an extra product-image slide.
            Keep exactly \(templateSlideCount) total slides.
            Set usesProductImage to true only for those detected template product-image positions and false for every other slide.
            For each product-image slide, write overlay text and caption language that matches \(productImage.product.name), the selected product summary, and the fact that the actual selected image will be shown.
            Keep imagePrompt on each product-image slide as a short note that Flick should use the selected product image directly.
            For generated slides, never include the template product, app screens, screenshots, device UI, logos, packaging, product names, or store pages.
            """
        }

        return """
        \(productDetails)

        No template product-image slides were detected.
        Append the selected product image as one final actual slide image at the end of the carousel.
        Keep exactly \(templateSlideCount) non-product generated/template slides, plus this final product-image slide.
        Set usesProductImage to true only for the final slide and false for every other slide.
        For the product-image slide, curate the overlay text and caption language knowing the actual product image will be shown; keep imagePrompt as a short note that Flick should use the selected product image directly.
        For all other slides, set usesProductImage to false, keep generated visuals aligned to the selected template's slide style, and never include the template product, app screens, screenshots, device UI, logos, packaging, product names, or store pages.
        """
    }

    private func expectedSlideCount(
        templateSlideCount: Int,
        templateProductImageSlideNumbers: [Int],
        productImage: SlideshowProductImage?
    ) -> Int {
        guard productImage != nil else { return templateSlideCount }
        return templateProductImageSlideNumbers.isEmpty ? templateSlideCount + 1 : templateSlideCount
    }

    private func slideNumberSummary(_ slideNumbers: [Int]) -> String {
        slideNumbers.isEmpty ? "none" : slideNumbers.map(String.init).joined(separator: ", ")
    }

    private func templateSlideBlueprintSummary(
        _ blueprints: [TemplateSlideBlueprint],
        slideCount: Int,
        productImage: SlideshowProductImage?
    ) -> String {
        let visibleBlueprints = blueprints
            .filter { $0.slideNumber > 0 && $0.slideNumber <= slideCount }
            .sorted { $0.slideNumber < $1.slideNumber }

        guard !visibleBlueprints.isEmpty else {
            return "No per-slide blueprint was extracted. Use the slide count, style guide, and product-placeholder instructions as the only template structure."
        }

        return visibleBlueprints.map { blueprint in
            if blueprint.isProductPlaceholder {
                let detailHandling: String
                if productImage == nil {
                    detailHandling = "Product placeholder details suppressed because no selected product image was supplied; preserve only copy role, overlay position, pacing, person placement, and non-product style cues, then convert this slot into a non-product generated visual."
                } else {
                    detailHandling = "Product placeholder details suppressed because the template product must be replaced by the selected product image; preserve only copy role, overlay position, pacing, person placement, and non-product style cues, then retarget this slot to the selected product."
                }

                return """
                Slide \(blueprint.slideNumber):
                - Visible text reference: suppressed for product placeholder
                - Copy role: \(templateBlueprintValue(blueprint.copyRole, fallback: "unspecified"))
                - Overlay position: \(blueprint.textPosition.rawValue)
                - Person presence: \(templateBlueprintValue(blueprint.personPresence, fallback: "none"))
                - Person position: \(templateBlueprintValue(blueprint.personPosition, fallback: "none"))
                - Main subject: suppressed for product placeholder
                - Composition: suppressed for product placeholder
                - Product placeholder: yes
                - Product placeholder detail handling: \(detailHandling)
                """
            }

            return """
            Slide \(blueprint.slideNumber):
            - Visible text reference: \(templateBlueprintValue(blueprint.visibleText, fallback: "none"))
            - Copy role: \(templateBlueprintValue(blueprint.copyRole, fallback: "unspecified"))
            - Overlay position: \(blueprint.textPosition.rawValue)
            - Person presence: \(templateBlueprintValue(blueprint.personPresence, fallback: "none"))
            - Person position: \(templateBlueprintValue(blueprint.personPosition, fallback: "none"))
            - Main subject: \(templateBlueprintValue(blueprint.mainSubject, fallback: "unspecified"))
            - Composition: \(templateBlueprintValue(blueprint.composition, fallback: "unspecified"))
            - Product placeholder: \(blueprint.isProductPlaceholder ? "yes" : "no")
            """
        }
        .joined(separator: "\n")
    }

    private func templateBlueprintValue(_ value: String, fallback: String) -> String {
        let normalized = value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return normalized.isEmpty ? fallback : normalized
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
        - Keep the selected model's face, hair, skin details, eyes, body, styling, accessories, and signature pose consistent across slides.
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
        previousVisualSummary: String,
        imageVibe: SlideshowImageVibe? = nil
    ) -> String {
        let resolvedImageVibe = imageVibe ?? draft.imageVibe
        return """
        Create a vertical portrait social slideshow image for slide \(slide.index + 1), optimized for TikTok and Instagram Reels.

        Template style:
        \(styleGuide.promptSummary)

        \(resolvedImageVibe.promptSectionTitle):
        \(resolvedImageVibe.combinedGenerationContract)

        \(modelIdentityContract(for: draft.creationModel))

        Continuity from previous slide:
        \(previousVisualSummary.isEmpty ? "This is the first slide; establish the motif cleanly." : previousVisualSummary)

        Composition:
        - Keep the \(slide.textPosition.rawValue) overlay region clean and low-detail for Flick-rendered text.
        - Use the recurring motif: \(draft.globalVisualMotif).
        - \(resolvedImageVibe.compositionStyleRequirement)

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
        - Keep the model's face, hair, skin details, eyes, body, styling, accessories, and signature pose consistent.
        - Use template/source people only for pose, camera framing, environment, and background.
        - Do not copy a template person's face, hair, skin tone, body, age, gender expression, clothing, or accessories when they differ from the model JSON.
        """
    }
}
