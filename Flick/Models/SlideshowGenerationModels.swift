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
    var productImageSlideNumbers: [Int]

    private enum CodingKeys: String, CodingKey {
        case styleName
        case visualTraits
        case colorPalette
        case lighting
        case recurringMotifs
        case reuseStructurally
        case avoidCopyingDirectly
        case imageGenerationRules
        case productImageSlideNumbers
    }

    init(
        styleName: String,
        visualTraits: [String],
        colorPalette: [String],
        lighting: String,
        recurringMotifs: [String],
        reuseStructurally: [String],
        avoidCopyingDirectly: [String],
        imageGenerationRules: [String],
        productImageSlideNumbers: [Int] = []
    ) {
        self.styleName = styleName
        self.visualTraits = visualTraits
        self.colorPalette = colorPalette
        self.lighting = lighting
        self.recurringMotifs = recurringMotifs
        self.reuseStructurally = reuseStructurally
        self.avoidCopyingDirectly = avoidCopyingDirectly
        self.imageGenerationRules = imageGenerationRules
        self.productImageSlideNumbers = Self.normalizedSlideNumbers(productImageSlideNumbers)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        styleName = try container.decode(String.self, forKey: .styleName)
        visualTraits = try container.decode([String].self, forKey: .visualTraits)
        colorPalette = try container.decode([String].self, forKey: .colorPalette)
        lighting = try container.decode(String.self, forKey: .lighting)
        recurringMotifs = try container.decode([String].self, forKey: .recurringMotifs)
        reuseStructurally = try container.decode([String].self, forKey: .reuseStructurally)
        avoidCopyingDirectly = try container.decode([String].self, forKey: .avoidCopyingDirectly)
        imageGenerationRules = try container.decode([String].self, forKey: .imageGenerationRules)
        productImageSlideNumbers = Self.normalizedSlideNumbers(
            try container.decodeIfPresent([Int].self, forKey: .productImageSlideNumbers) ?? []
        )
    }

    private static func normalizedSlideNumbers(_ slideNumbers: [Int]) -> [Int] {
        Array(Set(slideNumbers.filter { $0 > 0 })).sorted()
    }

    static var empty: TemplateStyleGuide {
        TemplateStyleGuide(
            styleName: "",
            visualTraits: [],
            colorPalette: [],
            lighting: "",
            recurringMotifs: [],
            reuseStructurally: [],
            avoidCopyingDirectly: [],
            imageGenerationRules: [],
            productImageSlideNumbers: []
        )
    }
}

struct PlannedSlideshow: Codable, Hashable {
    var title: String
    var tikTokTitle: String
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
    var usesProductImage: Bool
}

struct SlidePromptRewrite: Codable, Hashable {
    var imagePrompt: String
    var selectedVisualSummary: String
}

struct SlideshowProductImage: Hashable {
    var product: FlickProduct
    var asset: MediaAsset
}

enum SlideshowImageVibe: String, CaseIterable, Codable, Identifiable, Hashable {
    nonisolated static let defaultValue: SlideshowImageVibe = .realisticCamera

    case realisticCamera
    case phoneSnapshot
    case documentary
    case editorialNatural
    case warmFilm
    case flashCandid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .realisticCamera: "Real Camera"
        case .phoneSnapshot: "Phone Snapshot"
        case .documentary: "Documentary"
        case .editorialNatural: "Natural Editorial"
        case .warmFilm: "Warm Film"
        case .flashCandid: "Flash Candid"
        }
    }

    var menuDetail: String {
        switch self {
        case .realisticCamera:
            "Natural human-camera realism"
        case .phoneSnapshot:
            "Casual smartphone photo"
        case .documentary:
            "Observed real-life scene"
        case .editorialNatural:
            "Believable lifestyle shoot"
        case .warmFilm:
            "Soft analog photo texture"
        case .flashCandid:
            "Direct-flash candid energy"
        }
    }

    var systemImage: String {
        switch self {
        case .realisticCamera: "camera"
        case .phoneSnapshot: "iphone"
        case .documentary: "camera.viewfinder"
        case .editorialNatural: "person.crop.rectangle"
        case .warmFilm: "camera.filters"
        case .flashCandid: "bolt.fill"
        }
    }

    var planningInstructions: String {
        """
        Image vibe: \(displayName)
        \(generationContract)
        Every generated image prompt must include a concrete camera, lens, lighting, or capture cue that supports this vibe.
        Do not ask for glossy, hyperreal, cinematic, 3D-rendered, airbrushed, plastic, or stock-photo-composite visuals.
        """
    }

    var generationContract: String {
        switch self {
        case .realisticCamera:
            """
            Make the image look like a real photograph captured by a person with a physical camera.
            Use natural available light, realistic dynamic range, believable shadows, ordinary lens behavior, subtle sensor noise, real skin texture, and slightly imperfect framing.
            """
        case .phoneSnapshot:
            """
            Make the image look like a casual smartphone photo taken by a real person.
            Use ordinary phone-camera perspective, available light, mild motion blur or hand-held imperfection where natural, realistic focus, and everyday color response.
            """
        case .documentary:
            """
            Make the image look like observational documentary photography.
            Use ambient light, realistic moments, honest texture, imperfect posture or placement, restrained color, and the feeling of a captured real scene instead of a staged render.
            """
        case .editorialNatural:
            """
            Make the image look like a believable lifestyle editorial photo.
            Use controlled but natural light, real locations, authentic skin and material texture, modest retouching, and camera-real composition without ad-render gloss.
            """
        case .warmFilm:
            """
            Make the image look like a real 35mm or disposable-camera film photograph.
            Use soft grain, gentle halation, warm color response, imperfect exposure, real-world texture, and natural lens softness without synthetic vintage filters.
            """
        case .flashCandid:
            """
            Make the image look like a real direct-flash candid photo.
            Use on-camera flash falloff, realistic hard shadows, slight red-eye or specular highlights only when plausible, ordinary background detail, and candid human-camera framing.
            """
        }
    }

    static var antiAIGlossContract: String {
        """
        Photographic realism:
        - The result must read as a human-taken camera photo, not AI-generated artwork, CGI, illustration, a render, a mockup, or a stock-photo composite.
        - Preserve real-world imperfections: natural pores, fine hair, fabric texture, small asymmetry, realistic hands, normal teeth and eyes, product scuffs, ambient clutter, true perspective, and plausible depth of field.
        - Avoid AI gloss: waxy or porcelain skin, plastic faces, over-smoothed surfaces, perfect symmetry, hyper-sharp HDR, neon rim lighting, surreal bokeh, excessive teal-orange grading, glossy 3D product-render shine, airbrushed makeup, and immaculate unreal environments.
        - Prefer restrained contrast, believable color, realistic shadows, physical camera exposure limits, and small hand-held imperfections over polished synthetic perfection.
        """
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = SlideshowImageVibe(rawValue: rawValue) ?? .defaultValue
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct GeneratedSlideImage: Hashable {
    var data: Data
    var contentType: String
    var fileExtension: String
    var width: Int
    var height: Int
}

struct SlideshowImageGenerationSettings: Hashable {
    static let gptImage2MinimumPixels = 655_360
    static let gptImage2MaximumPixels = 8_294_400
    static let gptImage2MaximumEdgeLength = 3_840
    static let gptImage2MaximumAspectRatio = 3.0

    var size: String
    var quality: String
    var width: Int
    var height: Int

    var aspectRatio: Double {
        Double(width) / Double(height)
    }

    var isGPTImage2CompatibleCustomSize: Bool {
        guard width > 0, height > 0, width.isMultiple(of: 16), height.isMultiple(of: 16) else {
            return false
        }

        let pixelCount = width * height
        let longerEdge = max(width, height)
        let shorterEdge = min(width, height)
        let edgeRatio = Double(longerEdge) / Double(shorterEdge)
        return pixelCount >= Self.gptImage2MinimumPixels
            && pixelCount <= Self.gptImage2MaximumPixels
            && longerEdge <= Self.gptImage2MaximumEdgeLength
            && edgeRatio <= Self.gptImage2MaximumAspectRatio
    }

    static let draft = SlideshowImageGenerationSettings(
        size: "720x1280",
        quality: "medium",
        width: 720,
        height: 1280
    )

    static let finalExport = SlideshowImageGenerationSettings(
        size: "1024x1536",
        quality: "high",
        width: 1024,
        height: 1536
    )

    func isSatisfied(by asset: MediaAsset) -> Bool {
        guard asset.width >= width, asset.height >= height else {
            return false
        }

        let assetAspectRatio = Double(asset.width) / Double(asset.height)
        return abs(assetAspectRatio - aspectRatio) <= 0.01
    }

    func acceptsExistingSlideAsset(_ asset: MediaAsset) -> Bool {
        asset.hasAvailableMediaLocation && (asset.source == .uploaded || isSatisfied(by: asset))
    }
}

extension TemplateStyleGuide {
    func productImageSlideNumbers(limitedTo slideCount: Int) -> [Int] {
        productImageSlideNumbers.filter { $0 <= slideCount }
    }

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
