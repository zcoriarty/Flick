//
//  CreationModelModels.swift
//  Flick
//

import Foundation

struct FlickCreationModel: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var metadata: CreationModelMetadata
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        metadata: CreationModelMetadata = CreationModelMetadata(),
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var aiMetadata: CreationModelAIMetadata {
        CreationModelAIMetadata(
            name: name,
            identity: metadata.identity,
            ethnicity: metadata.ethnicity,
            skinDetails: metadata.skinDetails,
            faceShape: metadata.faceShape,
            faceDetails: metadata.faceDetails,
            hair: metadata.hair,
            eyesAndBrows: metadata.eyesAndBrows,
            noseAndEars: metadata.noseAndEars,
            body: metadata.body,
            styleAndAccessories: metadata.styleAndAccessories
        )
    }

    func aiMetadataJSONData() throws -> Data {
        try JSONEncoder.flick.encode(aiMetadata)
    }

    var generationReference: SlideshowCreationModelReference {
        SlideshowCreationModelReference(model: self)
    }
}

struct SlideshowCreationModelReference: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var aiMetadata: CreationModelAIMetadata

    init(id: UUID, name: String, aiMetadata: CreationModelAIMetadata) {
        self.id = id
        self.name = name
        self.aiMetadata = aiMetadata
    }

    init(model: FlickCreationModel) {
        self.init(
            id: model.id,
            name: model.name,
            aiMetadata: model.aiMetadata
        )
    }

    var metadataSummary: String {
        let values = [
            aiMetadata.identity.gender,
            aiMetadata.identity.ageRange,
            aiMetadata.ethnicity.ethnicity,
            aiMetadata.hair.color,
            aiMetadata.hair.style,
            aiMetadata.body.build,
            aiMetadata.styleAndAccessories.aesthetic
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !values.isEmpty else { return "Not set" }
        return values.joined(separator: " / ")
    }

    func aiMetadataJSONString() -> String {
        guard
            let data = try? JSONEncoder.flick.encode(aiMetadata),
            let json = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return json
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case aiMetadata = "ai_metadata"
    }
}

struct CreationModelAIMetadata: Codable, Hashable {
    var name: String
    var identity: CreationModelIdentity
    var ethnicity: CreationModelEthnicity
    var skinDetails: CreationModelSkinDetails
    var faceShape: CreationModelFaceShape
    var faceDetails: CreationModelFaceDetails
    var hair: CreationModelHair
    var eyesAndBrows: CreationModelEyesAndBrows
    var noseAndEars: CreationModelNoseAndEars
    var body: CreationModelBody
    var styleAndAccessories: CreationModelStyleAndAccessories

    enum CodingKeys: String, CodingKey {
        case name
        case identity
        case ethnicity
        case skinDetails = "skin_details"
        case faceShape = "face_shape"
        case faceDetails = "face_details"
        case hair
        case eyesAndBrows = "eyes_and_brows"
        case noseAndEars = "nose_and_ears"
        case body
        case styleAndAccessories = "style_and_accessories"
    }
}

struct CreationModelMetadata: Codable, Hashable {
    var identity = CreationModelIdentity()
    var ethnicity = CreationModelEthnicity()
    var skinDetails = CreationModelSkinDetails()
    var faceShape = CreationModelFaceShape()
    var faceDetails = CreationModelFaceDetails()
    var hair = CreationModelHair()
    var eyesAndBrows = CreationModelEyesAndBrows()
    var noseAndEars = CreationModelNoseAndEars()
    var body = CreationModelBody()
    var styleAndAccessories = CreationModelStyleAndAccessories()

    enum CodingKeys: String, CodingKey {
        case identity
        case ethnicity
        case skinDetails = "skin_details"
        case faceShape = "face_shape"
        case faceDetails = "face_details"
        case hair
        case eyesAndBrows = "eyes_and_brows"
        case noseAndEars = "nose_and_ears"
        case body
        case styleAndAccessories = "style_and_accessories"
    }
}

extension CreationModelMetadata {
    static func randomized() -> CreationModelMetadata {
        var metadata = CreationModelMetadata()

        for field in CreationModelField.allCases {
            metadata[keyPath: field.keyPath] = field.options.randomElement() ?? ""
        }

        return metadata
    }
}

enum CreationModelPreset: String, CaseIterable, Identifiable, Hashable {
    case fromScratch
    case cottageHost
    case studioFounder
    case wellnessCreator
    case streetwearEditor
    case fitnessCoach

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fromScratch: "From Scratch"
        case .cottageHost: "Cottage Host"
        case .studioFounder: "Studio Founder"
        case .wellnessCreator: "Wellness Creator"
        case .streetwearEditor: "Streetwear Editor"
        case .fitnessCoach: "Fitness Coach"
        }
    }

    var subtitle: String {
        switch self {
        case .fromScratch:
            "Blank"
        case .cottageHost:
            "Cottagecore"
        case .studioFounder:
            "Business casual"
        case .wellnessCreator:
            "Coastal"
        case .streetwearEditor:
            "Streetwear"
        case .fitnessCoach:
            "Athleisure"
        }
    }

    var metadata: CreationModelMetadata {
        switch self {
        case .fromScratch:
            return CreationModelMetadata()
        case .cottageHost:
            var metadata = CreationModelMetadata()
            metadata.identity.gender = "Female"
            metadata.identity.ageRange = "41-50"
            metadata.ethnicity.ethnicity = "Samoan"
            metadata.skinDetails.clarity = "Clear"
            metadata.skinDetails.freckles = "Light Subtle"
            metadata.skinDetails.moles = "Few Scattered"
            metadata.skinDetails.underEyes = "Bright"
            metadata.faceShape.shape = "Oval"
            metadata.faceDetails.jawline = "Sharp"
            metadata.faceDetails.cheekbones = "Subtle"
            metadata.faceDetails.chin = "Receding"
            metadata.faceDetails.dimples = "Chin Dimple"
            metadata.faceDetails.lips = "Wide"
            metadata.hair.color = "Auburn"
            metadata.hair.style = "Bob"
            metadata.hair.highlights = "Face Framing Highlights"
            metadata.eyesAndBrows.shape = "Close Set"
            metadata.eyesAndBrows.color = "Green"
            metadata.eyesAndBrows.eyebrows = "Feathered"
            metadata.noseAndEars.nose = "Straight"
            metadata.noseAndEars.ears = "Attached Lobe"
            metadata.body.build = "Athletic"
            metadata.body.height = "Very Tall"
            metadata.body.shoulders = "Wide"
            metadata.styleAndAccessories.aesthetic = "Cottagecore"
            metadata.styleAndAccessories.glasses = "Prescription Square"
            metadata.styleAndAccessories.jewelry = "Delicate Chain"
            metadata.styleAndAccessories.headwear = "None"
            return metadata
        case .studioFounder:
            var metadata = CreationModelMetadata()
            metadata.identity.gender = "Female"
            metadata.identity.ageRange = "31-40"
            metadata.ethnicity.ethnicity = "Mixed"
            metadata.skinDetails.clarity = "Dewy"
            metadata.skinDetails.freckles = "None"
            metadata.skinDetails.moles = "Beauty Mark"
            metadata.skinDetails.underEyes = "Bright"
            metadata.faceShape.shape = "Diamond"
            metadata.faceDetails.jawline = "Defined"
            metadata.faceDetails.cheekbones = "High"
            metadata.faceDetails.chin = "Pointed"
            metadata.faceDetails.dimples = "None"
            metadata.faceDetails.lips = "Full"
            metadata.hair.color = "Dark Brown"
            metadata.hair.style = "Long Wavy"
            metadata.hair.highlights = "Subtle Highlights"
            metadata.eyesAndBrows.shape = "Almond"
            metadata.eyesAndBrows.color = "Brown"
            metadata.eyesAndBrows.eyebrows = "Arched"
            metadata.noseAndEars.nose = "Straight"
            metadata.noseAndEars.ears = "Free Lobe"
            metadata.body.build = "Slim"
            metadata.body.height = "Tall"
            metadata.body.shoulders = "Average"
            metadata.styleAndAccessories.aesthetic = "Business Casual"
            metadata.styleAndAccessories.glasses = "Wire Frames"
            metadata.styleAndAccessories.jewelry = "Layered Necklaces"
            metadata.styleAndAccessories.headwear = "None"
            return metadata
        case .wellnessCreator:
            var metadata = CreationModelMetadata()
            metadata.identity.gender = "Non-binary"
            metadata.identity.ageRange = "25-30"
            metadata.ethnicity.ethnicity = "Latine"
            metadata.skinDetails.clarity = "Natural"
            metadata.skinDetails.freckles = "Medium"
            metadata.skinDetails.moles = "Few Scattered"
            metadata.skinDetails.underEyes = "Natural"
            metadata.faceShape.shape = "Heart"
            metadata.faceDetails.jawline = "Soft"
            metadata.faceDetails.cheekbones = "Defined"
            metadata.faceDetails.chin = "Rounded"
            metadata.faceDetails.dimples = "Cheek Dimples"
            metadata.faceDetails.lips = "Bow Shaped"
            metadata.hair.color = "Brown"
            metadata.hair.style = "Curly"
            metadata.hair.highlights = "Balayage"
            metadata.eyesAndBrows.shape = "Round"
            metadata.eyesAndBrows.color = "Hazel"
            metadata.eyesAndBrows.eyebrows = "Natural"
            metadata.noseAndEars.nose = "Button"
            metadata.noseAndEars.ears = "Pierced"
            metadata.body.build = "Average"
            metadata.body.height = "Average"
            metadata.body.shoulders = "Sloped"
            metadata.styleAndAccessories.aesthetic = "Coastal"
            metadata.styleAndAccessories.glasses = "Round Frames"
            metadata.styleAndAccessories.jewelry = "Stud Earrings"
            metadata.styleAndAccessories.headwear = "Headscarf"
            return metadata
        case .streetwearEditor:
            var metadata = CreationModelMetadata()
            metadata.identity.gender = "Male"
            metadata.identity.ageRange = "18-24"
            metadata.ethnicity.ethnicity = "East Asian"
            metadata.skinDetails.clarity = "Matte"
            metadata.skinDetails.freckles = "None"
            metadata.skinDetails.moles = "None"
            metadata.skinDetails.underEyes = "Soft Shadows"
            metadata.faceShape.shape = "Square"
            metadata.faceDetails.jawline = "Square"
            metadata.faceDetails.cheekbones = "Defined"
            metadata.faceDetails.chin = "Square"
            metadata.faceDetails.dimples = "None"
            metadata.faceDetails.lips = "Natural"
            metadata.hair.color = "Black"
            metadata.hair.style = "Short Crop"
            metadata.hair.highlights = "None"
            metadata.eyesAndBrows.shape = "Close Set"
            metadata.eyesAndBrows.color = "Brown"
            metadata.eyesAndBrows.eyebrows = "Straight"
            metadata.noseAndEars.nose = "Narrow"
            metadata.noseAndEars.ears = "Small"
            metadata.body.build = "Slim"
            metadata.body.height = "Tall"
            metadata.body.shoulders = "Narrow"
            metadata.styleAndAccessories.aesthetic = "Streetwear"
            metadata.styleAndAccessories.glasses = "Aviators"
            metadata.styleAndAccessories.jewelry = "Statement Rings"
            metadata.styleAndAccessories.headwear = "Beanie"
            return metadata
        case .fitnessCoach:
            var metadata = CreationModelMetadata()
            metadata.identity.gender = "Female"
            metadata.identity.ageRange = "25-30"
            metadata.ethnicity.ethnicity = "Black"
            metadata.skinDetails.clarity = "Clear"
            metadata.skinDetails.freckles = "None"
            metadata.skinDetails.moles = "None"
            metadata.skinDetails.underEyes = "Bright"
            metadata.faceShape.shape = "Oblong"
            metadata.faceDetails.jawline = "Defined"
            metadata.faceDetails.cheekbones = "High"
            metadata.faceDetails.chin = "Rounded"
            metadata.faceDetails.dimples = "One-Sided Dimple"
            metadata.faceDetails.lips = "Full"
            metadata.hair.color = "Black"
            metadata.hair.style = "Ponytail"
            metadata.hair.highlights = "None"
            metadata.eyesAndBrows.shape = "Upturned"
            metadata.eyesAndBrows.color = "Brown"
            metadata.eyesAndBrows.eyebrows = "Thick"
            metadata.noseAndEars.nose = "Wide"
            metadata.noseAndEars.ears = "Free Lobe"
            metadata.body.build = "Athletic"
            metadata.body.height = "Tall"
            metadata.body.shoulders = "Wide"
            metadata.styleAndAccessories.aesthetic = "Athleisure"
            metadata.styleAndAccessories.glasses = "None"
            metadata.styleAndAccessories.jewelry = "Hoops"
            metadata.styleAndAccessories.headwear = "Baseball Cap"
            return metadata
        }
    }
}

struct CreationModelIdentity: Codable, Hashable {
    var gender = ""
    var ageRange = ""

    enum CodingKeys: String, CodingKey {
        case gender
        case ageRange = "age_range"
    }
}

struct CreationModelEthnicity: Codable, Hashable {
    var ethnicity = ""
}

struct CreationModelSkinDetails: Codable, Hashable {
    var clarity = ""
    var freckles = ""
    var moles = ""
    var underEyes = ""

    enum CodingKeys: String, CodingKey {
        case clarity
        case freckles
        case moles
        case underEyes = "under_eyes"
    }
}

struct CreationModelFaceShape: Codable, Hashable {
    var shape = ""
}

struct CreationModelFaceDetails: Codable, Hashable {
    var jawline = ""
    var cheekbones = ""
    var chin = ""
    var dimples = ""
    var lips = ""
}

struct CreationModelHair: Codable, Hashable {
    var color = ""
    var style = ""
    var highlights = ""
}

struct CreationModelEyesAndBrows: Codable, Hashable {
    var shape = ""
    var color = ""
    var eyebrows = ""
}

struct CreationModelNoseAndEars: Codable, Hashable {
    var nose = ""
    var ears = ""
}

struct CreationModelBody: Codable, Hashable {
    var build = ""
    var height = ""
    var shoulders = ""
}

struct CreationModelStyleAndAccessories: Codable, Hashable {
    var aesthetic = ""
    var glasses = ""
    var jewelry = ""
    var headwear = ""
}

enum CreationModelSection: String, CaseIterable, Identifiable, Codable, Hashable {
    case identity
    case ethnicity
    case skinDetails
    case faceShape
    case faceDetails
    case hair
    case eyesAndBrows
    case noseAndEars
    case body
    case styleAndAccessories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .identity: "Identity"
        case .ethnicity: "Ethnicity"
        case .skinDetails: "Skin Details"
        case .faceShape: "Face Shape"
        case .faceDetails: "Face Details"
        case .hair: "Hair"
        case .eyesAndBrows: "Eyes & Brows"
        case .noseAndEars: "Nose & Ears"
        case .body: "Body"
        case .styleAndAccessories: "Style & Accessories"
        }
    }

    var fields: [CreationModelField] {
        switch self {
        case .identity:
            [.gender, .ageRange]
        case .ethnicity:
            [.ethnicity]
        case .skinDetails:
            [.skinClarity, .freckles, .moles, .underEyes]
        case .faceShape:
            [.faceShape]
        case .faceDetails:
            [.jawline, .cheekbones, .chin, .dimples, .lips]
        case .hair:
            [.hairColor, .hairStyle, .highlights]
        case .eyesAndBrows:
            [.eyeShape, .eyeColor, .eyebrows]
        case .noseAndEars:
            [.nose, .ears]
        case .body:
            [.build, .height, .shoulders]
        case .styleAndAccessories:
            [.aesthetic, .glasses, .jewelry, .headwear]
        }
    }

    func summary(for metadata: CreationModelMetadata) -> String {
        let values = fields
            .map { $0.value(in: metadata) }
            .filter { !$0.isEmpty }

        guard !values.isEmpty else { return "Not set" }
        return values.joined(separator: ", ")
    }
}

enum CreationModelField: String, CaseIterable, Identifiable, Codable, Hashable {
    case gender
    case ageRange
    case ethnicity
    case skinClarity
    case freckles
    case moles
    case underEyes
    case faceShape
    case jawline
    case cheekbones
    case chin
    case dimples
    case lips
    case hairColor
    case hairStyle
    case highlights
    case eyeShape
    case eyeColor
    case eyebrows
    case nose
    case ears
    case build
    case height
    case shoulders
    case aesthetic
    case glasses
    case jewelry
    case headwear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gender: "Gender"
        case .ageRange: "Age"
        case .ethnicity: "Ethnicity"
        case .skinClarity: "Clarity"
        case .freckles: "Freckles"
        case .moles: "Moles"
        case .underEyes: "Under-Eyes"
        case .faceShape: "Shape"
        case .jawline: "Jawline"
        case .cheekbones: "Cheekbones"
        case .chin: "Chin"
        case .dimples: "Dimples"
        case .lips: "Lips"
        case .hairColor: "Color"
        case .hairStyle: "Style"
        case .highlights: "Highlights"
        case .eyeShape: "Shape"
        case .eyeColor: "Color"
        case .eyebrows: "Eyebrows"
        case .nose: "Nose"
        case .ears: "Ears"
        case .build: "Build"
        case .height: "Height"
        case .shoulders: "Shoulders"
        case .aesthetic: "Aesthetic"
        case .glasses: "Glasses"
        case .jewelry: "Jewelry"
        case .headwear: "Headwear"
        }
    }

    var options: [String] {
        switch self {
        case .gender:
            ["Female", "Male", "Non-binary", "Androgynous"]
        case .ageRange:
            ["18-24", "25-30", "31-40", "41-50", "51-60", "60+"]
        case .ethnicity:
            [
                "Black",
                "East Asian",
                "Latine",
                "Middle Eastern",
                "Native American",
                "Pacific Islander",
                "Samoan",
                "South Asian",
                "Southeast Asian",
                "White",
                "Mixed"
            ]
        case .skinClarity:
            ["Clear", "Natural", "Textured", "Dewy", "Matte"]
        case .freckles:
            ["None", "Light Subtle", "Medium", "Heavy"]
        case .moles:
            ["None", "Few Scattered", "Beauty Mark", "Several"]
        case .underEyes:
            ["Bright", "Natural", "Soft Shadows", "Dark Circles"]
        case .faceShape:
            ["Oval", "Round", "Square", "Heart", "Diamond", "Oblong"]
        case .jawline:
            ["Soft", "Defined", "Sharp", "Rounded", "Square"]
        case .cheekbones:
            ["Subtle", "Defined", "High", "Soft"]
        case .chin:
            ["Rounded", "Pointed", "Square", "Receding", "Cleft"]
        case .dimples:
            ["None", "Cheek Dimples", "Chin Dimple", "One-Sided Dimple"]
        case .lips:
            ["Natural", "Full", "Thin", "Wide", "Bow Shaped"]
        case .hairColor:
            ["Black", "Brown", "Dark Brown", "Blonde", "Auburn", "Red", "Gray", "Silver", "Pastel"]
        case .hairStyle:
            ["Buzz Cut", "Short Crop", "Bob", "Lob", "Long Straight", "Long Wavy", "Curly", "Braids", "Bun", "Ponytail"]
        case .highlights:
            ["None", "Subtle Highlights", "Face Framing Highlights", "Balayage", "Chunky Highlights", "Ombre"]
        case .eyeShape:
            ["Almond", "Round", "Hooded", "Monolid", "Upturned", "Downturned", "Close Set", "Wide Set"]
        case .eyeColor:
            ["Brown", "Blue", "Green", "Hazel", "Gray", "Amber"]
        case .eyebrows:
            ["Natural", "Feathered", "Arched", "Straight", "Thick", "Thin"]
        case .nose:
            ["Straight", "Button", "Aquiline", "Wide", "Narrow", "Upturned"]
        case .ears:
            ["Attached Lobe", "Free Lobe", "Small", "Prominent", "Pierced"]
        case .build:
            ["Slim", "Average", "Athletic", "Curvy", "Broad", "Stocky"]
        case .height:
            ["Short", "Average", "Tall", "Very Tall"]
        case .shoulders:
            ["Narrow", "Average", "Wide", "Sloped"]
        case .aesthetic:
            ["Minimal", "Streetwear", "Cottagecore", "Athleisure", "Business Casual", "Old Money", "Y2K", "Bohemian", "Goth", "Coastal"]
        case .glasses:
            ["None", "Prescription Square", "Round Frames", "Aviators", "Cat Eye", "Wire Frames"]
        case .jewelry:
            ["None", "Delicate Chain", "Hoops", "Stud Earrings", "Layered Necklaces", "Statement Rings"]
        case .headwear:
            ["None", "Baseball Cap", "Beanie", "Headscarf", "Bucket Hat", "Wide Brim Hat"]
        }
    }

    var keyPath: WritableKeyPath<CreationModelMetadata, String> {
        switch self {
        case .gender: \.identity.gender
        case .ageRange: \.identity.ageRange
        case .ethnicity: \.ethnicity.ethnicity
        case .skinClarity: \.skinDetails.clarity
        case .freckles: \.skinDetails.freckles
        case .moles: \.skinDetails.moles
        case .underEyes: \.skinDetails.underEyes
        case .faceShape: \.faceShape.shape
        case .jawline: \.faceDetails.jawline
        case .cheekbones: \.faceDetails.cheekbones
        case .chin: \.faceDetails.chin
        case .dimples: \.faceDetails.dimples
        case .lips: \.faceDetails.lips
        case .hairColor: \.hair.color
        case .hairStyle: \.hair.style
        case .highlights: \.hair.highlights
        case .eyeShape: \.eyesAndBrows.shape
        case .eyeColor: \.eyesAndBrows.color
        case .eyebrows: \.eyesAndBrows.eyebrows
        case .nose: \.noseAndEars.nose
        case .ears: \.noseAndEars.ears
        case .build: \.body.build
        case .height: \.body.height
        case .shoulders: \.body.shoulders
        case .aesthetic: \.styleAndAccessories.aesthetic
        case .glasses: \.styleAndAccessories.glasses
        case .jewelry: \.styleAndAccessories.jewelry
        case .headwear: \.styleAndAccessories.headwear
        }
    }

    func value(in metadata: CreationModelMetadata) -> String {
        metadata[keyPath: keyPath]
    }
}
