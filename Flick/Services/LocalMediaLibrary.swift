//
//  LocalMediaLibrary.swift
//  Flick
//

import Foundation
import UniformTypeIdentifiers

struct StoredLocalMedia: Hashable {
    var fileURL: URL
    var contentType: UTType
    var fileSize: Int64?
}

struct LocalMediaLibrary {
    var directoryName: String
    var fileManager: FileManager = .default

    func store(data: Data, contentType: UTType) throws -> StoredLocalMedia {
        let directoryURL = try mediaDirectoryURL()
        let normalizedContentType = normalized(contentType)
        let fileExtension = normalizedContentType.preferredFilenameExtension ?? fallbackExtension(for: normalizedContentType)
        let fileURL = directoryURL.appendingPathComponent("\(UUID().uuidString).\(fileExtension)")

        try data.write(to: fileURL, options: [.atomic])

        return StoredLocalMedia(
            fileURL: fileURL,
            contentType: normalizedContentType,
            fileSize: fileSize(at: fileURL)
        )
    }

    func store(fileURL sourceURL: URL, contentType: UTType) throws -> StoredLocalMedia {
        let directoryURL = try mediaDirectoryURL()
        let normalizedContentType = normalized(contentType)
        let fallbackFileExtension = normalizedContentType.preferredFilenameExtension ?? fallbackExtension(for: normalizedContentType)
        let sourceFileExtension = sourceURL.pathExtension.isEmpty ? fallbackFileExtension : sourceURL.pathExtension
        let fileURL = directoryURL.appendingPathComponent("\(UUID().uuidString).\(sourceFileExtension)")

        try fileManager.copyItem(at: sourceURL, to: fileURL)

        return StoredLocalMedia(
            fileURL: fileURL,
            contentType: normalizedContentType,
            fileSize: fileSize(at: fileURL)
        )
    }

    private func mediaDirectoryURL() throws -> URL {
        let supportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let mediaURL = supportURL
            .appendingPathComponent("Flick", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)

        try fileManager.createDirectory(at: mediaURL, withIntermediateDirectories: true)
        return mediaURL
    }

    private func normalized(_ contentType: UTType) -> UTType {
        if contentType.conforms(to: .movie) {
            return contentType
        }
        if contentType.conforms(to: .image) {
            return contentType
        }
        return .data
    }

    private func fallbackExtension(for contentType: UTType) -> String {
        if contentType.conforms(to: .movie) {
            return "mov"
        }
        if contentType.conforms(to: .image) {
            return "jpg"
        }
        return "dat"
    }

    private func fileSize(at fileURL: URL) -> Int64? {
        guard let size = try? fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber else {
            return nil
        }
        return size.int64Value
    }
}
