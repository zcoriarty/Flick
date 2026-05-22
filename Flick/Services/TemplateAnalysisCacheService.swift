//
//  TemplateAnalysisCacheService.swift
//  Flick
//

import CryptoKit
import Foundation

protocol TemplateAnalysisStorageProviding {
    func uploadJSONIfAbsent(_ data: Data, path: String, metadata: [String: String]) async throws -> Bool
    func data(path: String) async throws -> Data
}

extension R2StorageService: TemplateAnalysisStorageProviding {}

struct TemplateAnalysisCacheService {
    static let schemaVersion = 1

    var openAIClient: OpenAIClient
    var storage: any TemplateAnalysisStorageProviding

    func resolveStyleGuide(for template: ExampleSlideshowTemplate) async throws -> TemplateStyleGuide {
        let fingerprint = Self.fingerprint(for: template)
        let path = Self.cachePath(templateID: template.id, fingerprint: fingerprint)

        do {
            if let cachedStyleGuide = try await cachedStyleGuide(path: path) {
                return cachedStyleGuide
            }
        } catch MediaStorageError.missingR2Configuration {
            return try await TemplateAnalysisService(client: openAIClient).createStyleGuide(from: template)
        }

        let styleGuide = try await TemplateAnalysisService(client: openAIClient).createStyleGuide(from: template)
        let record = TemplateAnalysisCacheRecord(
            templateID: template.id,
            fingerprint: fingerprint,
            schemaVersion: Self.schemaVersion,
            model: openAIClient.planningModel,
            createdAt: Date(),
            styleGuide: styleGuide
        )
        let data = try JSONEncoder.flick.encode(record)

        do {
            let didUpload = try await storage.uploadJSONIfAbsent(
                data,
                path: path,
                metadata: [
                    "template-id": template.id,
                    "fingerprint": fingerprint,
                    "schema-version": "\(Self.schemaVersion)",
                    "model": openAIClient.planningModel
                ]
            )

            if !didUpload, let winnerStyleGuide = try await cachedStyleGuide(path: path) {
                return winnerStyleGuide
            }
        } catch MediaStorageError.missingR2Configuration {
            return styleGuide
        }

        return styleGuide
    }

    static func cachePath(templateID: String, fingerprint: String) -> String {
        "template-analyses/v1/\(templateID)/\(fingerprint).json"
    }

    static func fingerprint(for template: ExampleSlideshowTemplate) -> String {
        let stableInput = [
            "schema:\(schemaVersion)",
            "template:\(template.id)",
            "niche:\(template.nicheSlug)",
            "profile:\(template.profile)",
            "slideCount:\(template.slideCount)",
            template.slides
                .sorted { $0.index < $1.index }
                .map { slide in
                    [
                        "\(slide.index)",
                        slide.relativePath,
                        slide.remoteURL?.absoluteString ?? "",
                        slide.sourceURL?.absoluteString ?? ""
                    ].joined(separator: "|")
                }
                .joined(separator: "\n")
        ]
        .joined(separator: "\n")

        let digest = SHA256.hash(data: Data(stableInput.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func cachedStyleGuide(path: String) async throws -> TemplateStyleGuide? {
        do {
            let data = try await storage.data(path: path)
            return try JSONDecoder.flick.decode(TemplateAnalysisCacheRecord.self, from: data).styleGuide
        } catch let error as MediaStorageError {
            if case let .requestFailed(_, statusCode, _) = error, statusCode == 404 {
                return nil
            }
            throw error
        }
    }
}

private struct TemplateAnalysisCacheRecord: Codable, Hashable {
    var templateID: String
    var fingerprint: String
    var schemaVersion: Int
    var model: String
    var createdAt: Date
    var styleGuide: TemplateStyleGuide
}
