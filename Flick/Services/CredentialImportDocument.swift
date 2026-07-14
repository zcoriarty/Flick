//
//  CredentialImportDocument.swift
//  Flick
//

import Foundation

nonisolated enum CredentialImportDocumentError: LocalizedError, Equatable {
    case emptyObject
    case invalidJSON
    case nonStringValue(String)
    case topLevelObjectRequired

    var errorDescription: String? {
        switch self {
        case .emptyObject:
            "The JSON object is empty. Add at least one credential."
        case .invalidJSON:
            "The credential text is not valid JSON."
        case let .nonStringValue(key):
            "The value for \(key) must be JSON text in quotation marks."
        case .topLevelObjectRequired:
            "Credentials must be a JSON object with credential keys and text values."
        }
    }
}

nonisolated struct CredentialImportDocument: Hashable, Sendable {
    var values: [String: String]

    init(data: Data) throws {
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CredentialImportDocumentError.invalidJSON
        }

        guard let jsonValues = jsonObject as? [String: Any] else {
            throw CredentialImportDocumentError.topLevelObjectRequired
        }
        guard !jsonValues.isEmpty else {
            throw CredentialImportDocumentError.emptyObject
        }

        var values: [String: String] = [:]
        for key in jsonValues.keys.sorted() {
            guard let value = jsonValues[key] as? String else {
                throw CredentialImportDocumentError.nonStringValue(key)
            }
            values[key] = value
        }
        self.values = values
    }

    init(jsonText: String) throws {
        try self.init(data: Data(jsonText.utf8))
    }
}
