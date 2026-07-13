//
//  ShareImportService.swift
//  Flick
//

import Foundation
import UniformTypeIdentifiers

nonisolated enum ShareImportConfiguration {
    static let appGroupIdentifier = "group.com.orion.Flick"
    static let urlScheme = "flick"
    static let urlHost = "share-import"
    static let importsDirectoryName = "ShareImports"
    static let manifestFilename = "manifest.json"
}

nonisolated enum LocalAutomationTemplateIdentifier {
    private static let prefix = "local-template:"

    static func id(for templateID: UUID) -> String {
        "\(prefix)\(templateID.uuidString)"
    }

    static func templateID(from id: String) -> UUID? {
        guard id.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(id.dropFirst(prefix.count)))
    }
}

nonisolated struct ShareImportManifest: Codable, Hashable, Sendable {
    var id: UUID
    var createdAt: Date
    var items: [ShareImportManifestItem]
}

nonisolated struct ShareImportManifestItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var filename: String
    var contentTypeIdentifier: String
    var originalSuggestedName: String?
}

nonisolated struct ShareImportSession: Identifiable, Hashable, Sendable {
    var id: UUID
    var createdAt: Date
    var images: [ShareImportImage]
}

nonisolated struct ShareImportImage: Identifiable, Hashable, Sendable {
    var id: UUID
    var fileURL: URL
    var contentType: UTType
    var fileSize: Int64?
}

nonisolated struct ShareTemplateImportResult: Hashable, Sendable {
    var templateID: UUID
    var selectedTemplateID: String
}

nonisolated enum ShareImportError: LocalizedError {
    case appGroupUnavailable
    case missingImport(UUID)
    case emptyImport
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            "Flick could not access its shared import container."
        case let .missingImport(id):
            "Flick could not find the shared photo import \(id.uuidString)."
        case .emptyImport:
            "The shared import did not contain readable images."
        case .invalidURL:
            "Flick could not read the shared import link."
        }
    }
}

nonisolated struct ShareImportService {
    var appGroupIdentifier = ShareImportConfiguration.appGroupIdentifier
    var fileManager: FileManager = .default

    static func importID(from url: URL) -> UUID? {
        guard
            url.scheme == ShareImportConfiguration.urlScheme,
            url.host == ShareImportConfiguration.urlHost
        else {
            return nil
        }

        if let idValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "id" })?
            .value,
            let id = UUID(uuidString: idValue)
        {
            return id
        }

        return url.pathComponents
            .first { $0 != "/" }
            .flatMap(UUID.init(uuidString:))
    }

    static func importURL(for importID: UUID) -> URL {
        URL(string: "\(ShareImportConfiguration.urlScheme)://\(ShareImportConfiguration.urlHost)/\(importID.uuidString)")!
    }

    func pendingImportIDs() throws -> [UUID] {
        let rootURL = try importsRootURL()
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return []
        }

        let directoryURLs = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        return directoryURLs
            .filter { $0.hasDirectoryPath }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }
            .compactMap { UUID(uuidString: $0.lastPathComponent) }
    }

    func loadMostRecentImport() throws -> ShareImportSession? {
        for importID in try pendingImportIDs() {
            if let session = try? loadImport(id: importID) {
                return session
            }
        }
        return nil
    }

    func loadImport(id importID: UUID) throws -> ShareImportSession {
        let directoryURL = try importDirectoryURL(for: importID)
        let manifestURL = directoryURL.appendingPathComponent(ShareImportConfiguration.manifestFilename)
        guard fileManager.isReadableFile(atPath: manifestURL.path) else {
            throw ShareImportError.missingImport(importID)
        }

        let manifest = try JSONDecoder.flick.decode(ShareImportManifest.self, from: Data(contentsOf: manifestURL))
        let images = manifest.items.compactMap { item -> ShareImportImage? in
            let fileURL = directoryURL.appendingPathComponent(item.filename)
            guard fileManager.isReadableFile(atPath: fileURL.path) else { return nil }
            let contentType = UTType(item.contentTypeIdentifier) ?? .image
            return ShareImportImage(
                id: item.id,
                fileURL: fileURL,
                contentType: contentType,
                fileSize: fileSize(at: fileURL)
            )
        }

        guard !images.isEmpty else {
            throw ShareImportError.emptyImport
        }

        return ShareImportSession(
            id: manifest.id,
            createdAt: manifest.createdAt,
            images: images
        )
    }

    func discardImport(id importID: UUID) throws {
        let directoryURL = try importDirectoryURL(for: importID)
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        try fileManager.removeItem(at: directoryURL)
    }

    private func importsRootURL() throws -> URL {
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw ShareImportError.appGroupUnavailable
        }
        let rootURL = containerURL.appendingPathComponent(ShareImportConfiguration.importsDirectoryName, isDirectory: true)
        return rootURL
    }

    private func importDirectoryURL(for importID: UUID) throws -> URL {
        try importsRootURL().appendingPathComponent(importID.uuidString, isDirectory: true)
    }

    private func fileSize(at fileURL: URL) -> Int64? {
        guard let size = try? fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber else {
            return nil
        }
        return size.int64Value
    }
}
