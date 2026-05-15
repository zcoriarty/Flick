//
//  SlideshowPlannerService.swift
//  Flick
//

import Foundation

struct SlideshowPlannerService {
    var client = OpenAIClient()

    func createPlan(
        brief: String,
        template: ExampleSlideshowTemplate,
        styleGuide: TemplateStyleGuide
    ) async throws -> PlannedSlideshow {
        let input: [[String: Any]] = [
            [
                "role": "user",
                "content": [
                    [
                        "type": "input_text",
                        "text": """
                        User brief:
                        \(brief)

                        Selected Flick template:
                        - Niche: \(template.niche)
                        - Creator profile: @\(template.profile)
                        - Slide count to match exactly: \(template.slideCount)
                        - Template product or medium: \(template.subtitle)

                        Template style guide:
                        \(styleGuide.promptSummary)

                        Create a complete slideshow plan. Generate exactly \(template.slideCount) planned slides and exactly one image prompt per slide.
                        Flick will render all text separately, so image prompts must forbid readable text, captions, logos, watermarks, fake UI text, and gibberish.
                        Use Flick slide roles only: hook, problem, proof, demo, benefit, cta.
                        """
                    ]
                ]
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

                        Slide \(slide.index + 1):
                        - Role: \(slide.role.rawValue)
                        - Overlay text rendered by Flick: \(slide.overlayText)
                        - Supporting text rendered by Flick: \(slide.supportingText)
                        - CTA text rendered by Flick: \(slide.ctaText)
                        - Current visual goal: \(slide.visualGoal)
                        - Text-safe area: \(slide.textSafeArea)
                        - Main subject area: \(slide.mainSubjectArea)
                        - Previous selected slide summary: \(previousVisualSummary)
                        - Current image prompt: \(slide.prompt)

                        User edit instruction:
                        \(instruction)

                        Return an updated visual goal, a single final image prompt, and a short expected visual summary.
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

                        Slide role: \(slide.role.rawValue)
                        Slide visual goal: \(slide.visualGoal)
                        Text-safe area: \(slide.textSafeArea)
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
        Do not create image variants or candidate grids.
        Every slide must have editable Flick-rendered overlay text and exactly one 16:9 image prompt.
        The generated images are backgrounds and must leave clean low-detail safe areas for text overlays.
        """
    }

    private var promptRewriteInstructions: String {
        """
        Rewrite a single slide image prompt for gpt-image-2.
        Preserve the selected Flick template style guide, slideshow continuity, current safe area, and user edit instruction.
        The output prompt must request one 16:9 horizontal social slideshow image and must forbid readable text, captions, logos, watermarks, fake UI text, and gibberish.
        Do not propose variants.
        """
    }

    private static let stringArraySchema: [String: Any] = [
        "type": "array",
        "items": ["type": "string"]
    ]

    private static let slideRoleEnum = ["hook", "problem", "proof", "demo", "benefit", "cta"]
    private static let textPositionEnum = ["left", "right", "top", "center", "bottom", "split"]
    private static let transitionEnum = ["none", "dissolve", "push", "scale"]

    private static let planSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": [
            "title",
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
                        "role",
                        "overlayText",
                        "supportingText",
                        "ctaText",
                        "visualGoal",
                        "textPosition",
                        "textSafeArea",
                        "mainSubjectArea",
                        "transition",
                        "imagePrompt",
                        "selectedVisualSummary"
                    ],
                    "properties": [
                        "index": ["type": "integer"],
                        "role": ["type": "string", "enum": slideRoleEnum],
                        "overlayText": ["type": "string"],
                        "supportingText": ["type": "string"],
                        "ctaText": ["type": "string"],
                        "visualGoal": ["type": "string"],
                        "textPosition": ["type": "string", "enum": textPositionEnum],
                        "textSafeArea": ["type": "string"],
                        "mainSubjectArea": ["type": "string"],
                        "transition": ["type": "string", "enum": transitionEnum],
                        "imagePrompt": ["type": "string"],
                        "selectedVisualSummary": ["type": "string"]
                    ]
                ]
            ]
        ]
    ]

    private static let promptRewriteSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["imagePrompt", "visualGoal", "selectedVisualSummary"],
        "properties": [
            "imagePrompt": ["type": "string"],
            "visualGoal": ["type": "string"],
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
}

private struct VisualSummaryResponse: Decodable {
    var visualSummary: String
}

enum SlideshowPromptBuilder {
    static func imagePrompt(
        for slide: Slide,
        draft: SlideshowDraft,
        styleGuide: TemplateStyleGuide,
        previousVisualSummary: String
    ) -> String {
        """
        Create a 16:9 horizontal social slideshow image for slide \(slide.index + 1).

        Slide role:
        \(slide.role.rawValue)

        Visual goal:
        \(slide.visualGoal)

        Template style:
        \(styleGuide.promptSummary)

        Continuity from previous slide:
        \(previousVisualSummary.isEmpty ? "This is the first slide; establish the motif cleanly." : previousVisualSummary)

        Composition:
        - Leave \(slide.textSafeArea.isEmpty ? slide.textPosition.defaultSafeArea : slide.textSafeArea) clean and low-detail for Flick overlay text.
        - Main subject area: \(slide.mainSubjectArea.isEmpty ? slide.textPosition.defaultSubjectArea : slide.mainSubjectArea).
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
}
