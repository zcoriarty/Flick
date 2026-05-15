//
//  SlideshowGenerationModels.swift
//  Flick
//

import Foundation

struct TemplateStyleGuide: Codable, Hashable {
    var styleName: String
    var visualTraits: [String]
    var colorPalette: [String]
    var lighting: String
    var recurringMotifs: [String]
    var reuseStructurally: [String]
    var avoidCopyingDirectly: [String]
    var imageGenerationRules: [String]

    static var empty: TemplateStyleGuide {
        TemplateStyleGuide(
            styleName: "",
            visualTraits: [],
            colorPalette: [],
            lighting: "",
            recurringMotifs: [],
            reuseStructurally: [],
            avoidCopyingDirectly: [],
            imageGenerationRules: []
        )
    }
}

struct PlannedSlideshow: Codable, Hashable {
    var title: String
    var topic: String
    var audience: String
    var goal: String
    var tone: String
    var slideCount: Int
    var narrativeArc: [String]
    var globalVisualMotif: String
    var planSummary: String
    var slides: [PlannedSlide]
    var caption: String
    var hashtags: [String]
}

struct PlannedSlide: Codable, Hashable {
    var index: Int
    var text: String
    var textPosition: TextPosition
    var imagePrompt: String
    var selectedVisualSummary: String
}

struct SlidePromptRewrite: Codable, Hashable {
    var imagePrompt: String
    var selectedVisualSummary: String
}

struct GeneratedSlideImage: Hashable {
    var data: Data
    var contentType: String
    var fileExtension: String
    var width: Int
    var height: Int
}

struct SlideshowImageGenerationSettings: Hashable {
    var size: String
    var quality: String
    var width: Int
    var height: Int

    static let draft = SlideshowImageGenerationSettings(
        size: "1536x864",
        quality: "medium",
        width: 1536,
        height: 864
    )

    static let finalExport = SlideshowImageGenerationSettings(
        size: "2560x1440",
        quality: "high",
        width: 2560,
        height: 1440
    )
}

extension TemplateStyleGuide {
    var promptSummary: String {
        let traits = visualTraits.prefix(5).joined(separator: ", ")
        let palette = colorPalette.prefix(5).joined(separator: ", ")
        let rules = imageGenerationRules.prefix(5).joined(separator: ", ")
        return [
            styleName.isEmpty ? nil : "Style: \(styleName)",
            traits.isEmpty ? nil : "Visual traits: \(traits)",
            palette.isEmpty ? nil : "Palette: \(palette)",
            lighting.isEmpty ? nil : "Lighting: \(lighting)",
            rules.isEmpty ? nil : "Rules: \(rules)"
        ]
        .compactMap(\.self)
        .joined(separator: "\n")
    }
}

extension CreativeTemplate {
    var decodedStyleGuide: TemplateStyleGuide? {
        guard let data = styleJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder.flick.decode(TemplateStyleGuide.self, from: data)
    }
}

extension TemplateStyleGuide {
    func encodedJSONString() -> String {
        guard
            let data = try? JSONEncoder.flick.encode(self),
            let json = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return json
    }
}

extension SlideGenerationStatus {
    var displayName: String {
        switch self {
        case .notStarted: "Not started"
        case .generating: "Generating"
        case .complete: "Complete"
        case .failed: "Failed"
        }
    }
}

extension TextPosition {
    var displayName: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .top: "Top"
        case .center: "Center"
        case .bottom: "Bottom"
        case .split: "Split"
        }
    }
}
