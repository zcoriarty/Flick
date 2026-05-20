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

enum LocalMediaPathResolver {
    static func readableFileURL(
        for storedPath: String?,
        source: AssetSource,
        fileManager: FileManager = .default,
        additionalResourceRoots: [URL] = []
    ) -> URL? {
        guard
            let storedPath = storedPath?.trimmingCharacters(in: .whitespacesAndNewlines),
            !storedPath.isEmpty
        else {
            return nil
        }

        return candidateFileURLs(
            for: storedPath,
            source: source,
            fileManager: fileManager,
            additionalResourceRoots: additionalResourceRoots
        )
            .first { fileManager.isReadableFile(atPath: $0.path) }
    }

    private static func candidateFileURLs(
        for storedPath: String,
        source: AssetSource,
        fileManager: FileManager,
        additionalResourceRoots: [URL]
    ) -> [URL] {
        let pathComponents = storedPath.split(separator: "/").map(String.init)
        let filename = URL(fileURLWithPath: storedPath).lastPathComponent
        var candidates: [URL] = []

        if storedPath.hasPrefix("/") {
            candidates.append(URL(fileURLWithPath: storedPath))
        }

        if let applicationSupportFlickDirectory = applicationSupportFlickDirectory(fileManager: fileManager) {
            candidates.append(applicationSupportFlickDirectory.appending(path: storedPath))
            candidates.append(contentsOf: sourceDirectoryNames(for: source).map { directoryName in
                applicationSupportFlickDirectory
                    .appendingPathComponent(directoryName, isDirectory: true)
                    .appendingPathComponent(URL(fileURLWithPath: storedPath).lastPathComponent)
            })

            if let reconstructed = reconstructedURL(after: "Flick", in: pathComponents, root: applicationSupportFlickDirectory) {
                candidates.append(reconstructed)
            }
        }

        if let documentsFlickDirectory = documentsFlickDirectory(fileManager: fileManager) {
            candidates.append(documentsFlickDirectory.appending(path: storedPath))
            if let reconstructed = reconstructedURL(after: "Flick", in: pathComponents, root: documentsFlickDirectory) {
                candidates.append(reconstructed)
            }
        }

        if let bundleResourceURL = Bundle.main.resourceURL {
            appendResourceCandidates(
                root: bundleResourceURL,
                storedPath: storedPath,
                filename: filename,
                pathComponents: pathComponents,
                source: source,
                to: &candidates
            )
            if let exampleSlideshowsURL = reconstructedURL(
                after: "ExampleSlideshows",
                in: pathComponents,
                root: bundleResourceURL.appendingPathComponent("ExampleSlideshows", isDirectory: true)
            ) {
                candidates.append(exampleSlideshowsURL)
            }
            if let flatResourceURL = flatBundleResourceURL(for: storedPath) {
                candidates.append(flatResourceURL)
            }
        }

        for resourceRoot in additionalResourceRoots {
            appendResourceCandidates(
                root: resourceRoot,
                storedPath: storedPath,
                filename: filename,
                pathComponents: pathComponents,
                source: source,
                to: &candidates
            )
        }

        #if DEBUG
        for resourceRoot in sourceTreeResourceRoots() {
            appendResourceCandidates(
                root: resourceRoot,
                storedPath: storedPath,
                filename: filename,
                pathComponents: pathComponents,
                source: source,
                to: &candidates
            )
        }
        #endif

        return unique(candidates)
    }

    private static func appendResourceCandidates(
        root: URL,
        storedPath: String,
        filename: String,
        pathComponents: [String],
        source: AssetSource,
        to candidates: inout [URL]
    ) {
        candidates.append(root.appending(path: storedPath))
        if !filename.isEmpty {
            candidates.append(root.appendingPathComponent(filename))
        }

        if let flickRelativeURL = reconstructedURL(after: "Flick", in: pathComponents, root: root) {
            candidates.append(flickRelativeURL)
        }

        for directoryName in sourceDirectoryNames(for: source) {
            let sourceRoot = root.appendingPathComponent(directoryName, isDirectory: true)
            if !filename.isEmpty {
                candidates.append(sourceRoot.appendingPathComponent(filename))
            }
            if let sourceRelativeURL = reconstructedURL(after: directoryName, in: pathComponents, root: sourceRoot) {
                candidates.append(sourceRelativeURL)
            }
        }
    }

    private static func sourceDirectoryNames(for source: AssetSource) -> [String] {
        switch source {
        case .uploaded:
            ["ProductMedia"]
        case .generated:
            ["GeneratedImages"]
        case .rendered:
            ["Renders"]
        case .reference:
            []
        }
    }

    #if DEBUG
    private static func sourceTreeResourceRoots() -> [URL] {
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let flickSourceDirectory = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return unique([
            flickSourceDirectory,
            flickSourceDirectory.deletingLastPathComponent()
        ])
    }
    #endif

    private static func applicationSupportFlickDirectory(fileManager: FileManager) -> URL? {
        try? fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("Flick", isDirectory: true)
    }

    private static func documentsFlickDirectory(fileManager: FileManager) -> URL? {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Flick", isDirectory: true)
    }

    private static func reconstructedURL(after marker: String, in pathComponents: [String], root: URL) -> URL? {
        guard let markerIndex = pathComponents.lastIndex(of: marker) else { return nil }
        let suffixStart = pathComponents.index(after: markerIndex)
        guard suffixStart < pathComponents.endIndex else { return nil }
        return pathComponents[suffixStart...].reduce(root) { partialURL, component in
            partialURL.appendingPathComponent(component)
        }
    }

    private static func flatBundleResourceURL(for storedPath: String) -> URL? {
        let filename = URL(fileURLWithPath: storedPath).lastPathComponent
        guard !filename.isEmpty else { return nil }
        let fileURL = URL(fileURLWithPath: filename)
        let stem = fileURL.deletingPathExtension().lastPathComponent
        let fileExtension = fileURL.pathExtension
        return Bundle.main.url(forResource: stem, withExtension: fileExtension.isEmpty ? nil : fileExtension)
    }

    private static func unique(_ urls: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        return urls.filter { url in
            seenPaths.insert(url.standardizedFileURL.path).inserted
        }
    }
}

extension MediaAsset {
    var localFileURL: URL? {
        LocalMediaPathResolver.readableFileURL(for: localFilePath, source: source)
    }

    var hasAvailableMediaLocation: Bool {
        localFileURL != nil || publicURL != nil
    }
}
