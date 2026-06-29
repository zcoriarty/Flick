//
//  ShareViewController.swift
//  FlickShareExtension
//

import UIKit
import UniformTypeIdentifiers

private enum ShareExtensionConfiguration {
    static let appGroupIdentifier = "group.com.orion.Flick"
    static let importsDirectoryName = "ShareImports"
    static let manifestFilename = "manifest.json"
    static let urlScheme = "flick"
    static let urlHost = "share-import"
}

private struct ShareImportManifest: Codable {
    var id: UUID
    var createdAt: Date
    var items: [ShareImportManifestItem]
}

private struct ShareImportManifestItem: Codable {
    var id: UUID
    var filename: String
    var contentTypeIdentifier: String
    var originalSuggestedName: String?
}

final class ShareViewController: UIViewController {
    private let fileManager = FileManager.default
    private var didStartImport = false
    private var pendingOpenURL: URL?
    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let openButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStartImport else { return }
        didStartImport = true

        Task {
            await importSharedImages()
        }
    }

    private func configureView() {
        view.backgroundColor = .systemBackground

        statusLabel.text = "Preparing import"
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        activityIndicator.startAnimating()
        openButton.setTitle("Open Flick", for: .normal)
        openButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        openButton.isHidden = true
        openButton.addTarget(self, action: #selector(openButtonTapped), for: .touchUpInside)

        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        doneButton.isHidden = true
        doneButton.addTarget(self, action: #selector(doneButtonTapped), for: .touchUpInside)

        let stackView = UIStackView(arrangedSubviews: [activityIndicator, statusLabel, openButton, doneButton])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
    }

    private func importSharedImages() async {
        do {
            let importID = UUID()
            let importDirectoryURL = try importDirectoryURL(for: importID)
            try fileManager.createDirectory(at: importDirectoryURL, withIntermediateDirectories: true)

            let providers = imageProviders()
            var items: [ShareImportManifestItem] = []
            for provider in providers {
                if let item = try await copyImage(from: provider, into: importDirectoryURL, index: items.count) {
                    items.append(item)
                }
            }

            guard !items.isEmpty else {
                throw ShareExtensionError.noImages
            }

            let manifest = ShareImportManifest(id: importID, createdAt: Date(), items: items)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let manifestData = try encoder.encode(manifest)
            try manifestData.write(
                to: importDirectoryURL.appendingPathComponent(ShareExtensionConfiguration.manifestFilename),
                options: [.atomic]
            )

            statusLabel.text = "Opening Flick"
            let url = URL(string: "\(ShareExtensionConfiguration.urlScheme)://\(ShareExtensionConfiguration.urlHost)/\(importID.uuidString)")!
            pendingOpenURL = url
            let didOpen = await openContainingApp(url)
            if didOpen {
                extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            } else {
                showOpenFallback(for: url)
            }
        } catch {
            showError(error)
        }
    }

    @objc private func openButtonTapped() {
        guard let pendingOpenURL else { return }

        activityIndicator.startAnimating()
        openButton.isHidden = true
        doneButton.isHidden = true
        statusLabel.text = "Opening Flick"

        Task {
            let didOpen = await openContainingApp(pendingOpenURL)
            if didOpen {
                extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            } else {
                showManualOpenFallback(for: pendingOpenURL)
            }
        }
    }

    @objc private func doneButtonTapped() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func imageProviders() -> [NSItemProvider] {
        let inputItems = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        return inputItems
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
    }

    private func copyImage(
        from provider: NSItemProvider,
        into directoryURL: URL,
        index: Int
    ) async throws -> ShareImportManifestItem? {
        let contentType = imageContentType(for: provider)
        if let item = try? await copyFileRepresentation(
            from: provider,
            contentType: contentType,
            into: directoryURL,
            index: index
        ) {
            return item
        }

        let loadedItem = try await loadItem(from: provider, contentType: contentType)
        return try writeLoadedItem(
            loadedItem,
            provider: provider,
            contentType: contentType,
            into: directoryURL,
            index: index
        )
    }

    private func copyFileRepresentation(
        from provider: NSItemProvider,
        contentType: UTType,
        into directoryURL: URL,
        index: Int
    ) async throws -> ShareImportManifestItem {
        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: contentType.identifier) { [weak self] sourceURL, error in
                do {
                    guard let self else {
                        throw ShareExtensionError.unreadableImage
                    }
                    if let error {
                        throw error
                    }
                    guard let sourceURL else {
                        throw ShareExtensionError.unreadableImage
                    }

                    let resolvedType = UTType(filenameExtension: sourceURL.pathExtension) ?? contentType
                    let destinationURL = self.destinationURL(
                        in: directoryURL,
                        index: index,
                        contentType: resolvedType,
                        sourceURL: sourceURL
                    )
                    if self.fileManager.fileExists(atPath: destinationURL.path) {
                        try self.fileManager.removeItem(at: destinationURL)
                    }
                    try self.fileManager.copyItem(at: sourceURL, to: destinationURL)
                    continuation.resume(returning: self.manifestItem(
                        for: destinationURL,
                        originalSuggestedName: suggestedName,
                        contentType: resolvedType
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func loadItem(from provider: NSItemProvider, contentType: UTType) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: contentType.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let item else {
                    continuation.resume(throwing: ShareExtensionError.unreadableImage)
                    return
                }
                continuation.resume(returning: item)
            }
        }
    }

    private func writeLoadedItem(
        _ item: Any,
        provider: NSItemProvider,
        contentType: UTType,
        into directoryURL: URL,
        index: Int
    ) throws -> ShareImportManifestItem? {
        if let fileURL = item as? URL {
            let resolvedType = UTType(filenameExtension: fileURL.pathExtension) ?? contentType
            let destinationURL = destinationURL(
                in: directoryURL,
                index: index,
                contentType: resolvedType,
                sourceURL: fileURL
            )
            try fileManager.copyItem(at: fileURL, to: destinationURL)
            return manifestItem(for: destinationURL, originalSuggestedName: provider.suggestedName, contentType: resolvedType)
        }

        if let data = item as? Data {
            let destinationURL = destinationURL(in: directoryURL, index: index, contentType: contentType, sourceURL: nil)
            try data.write(to: destinationURL, options: [.atomic])
            return manifestItem(for: destinationURL, originalSuggestedName: provider.suggestedName, contentType: contentType)
        }

        if let image = item as? UIImage, let data = image.jpegData(compressionQuality: 0.95) {
            let destinationURL = destinationURL(in: directoryURL, index: index, contentType: .jpeg, sourceURL: nil)
            try data.write(to: destinationURL, options: [.atomic])
            return manifestItem(for: destinationURL, originalSuggestedName: provider.suggestedName, contentType: .jpeg)
        }

        return nil
    }

    private func imageContentType(for provider: NSItemProvider) -> UTType {
        provider.registeredTypeIdentifiers
            .compactMap(UTType.init)
            .first { $0.conforms(to: .image) }
            ?? .image
    }

    private func destinationURL(
        in directoryURL: URL,
        index: Int,
        contentType: UTType,
        sourceURL: URL?
    ) -> URL {
        let fileExtension = sourceURL?.pathExtension.isEmpty == false
            ? sourceURL?.pathExtension
            : contentType.preferredFilenameExtension
        return directoryURL.appendingPathComponent(
            "\(String(format: "%03d", index + 1))-\(UUID().uuidString).\(fileExtension ?? "jpg")"
        )
    }

    private func manifestItem(
        for fileURL: URL,
        originalSuggestedName: String?,
        contentType: UTType
    ) -> ShareImportManifestItem {
        ShareImportManifestItem(
            id: UUID(),
            filename: fileURL.lastPathComponent,
            contentTypeIdentifier: contentType.identifier,
            originalSuggestedName: originalSuggestedName
        )
    }

    private func importDirectoryURL(for importID: UUID) throws -> URL {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: ShareExtensionConfiguration.appGroupIdentifier
        ) else {
            throw ShareExtensionError.appGroupUnavailable
        }
        return containerURL
            .appendingPathComponent(ShareExtensionConfiguration.importsDirectoryName, isDirectory: true)
            .appendingPathComponent(importID.uuidString, isDirectory: true)
    }

    private func openContainingApp(_ url: URL) async -> Bool {
        guard let extensionContext else { return false }
        return await withCheckedContinuation { continuation in
            extensionContext.open(url) { didOpen in
                continuation.resume(returning: didOpen)
            }
        }
    }

    private func showError(_ error: Error) {
        activityIndicator.stopAnimating()
        openButton.isHidden = true
        doneButton.isHidden = true
        statusLabel.text = error.localizedDescription

        let action = UIAlertAction(title: "Done", style: .default) { [weak self] _ in
            self?.extensionContext?.cancelRequest(withError: error)
        }
        let alert = UIAlertController(title: "Import Failed", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(action)
        present(alert, animated: true)
    }

    private func showOpenFallback(for url: URL) {
        pendingOpenURL = url
        activityIndicator.stopAnimating()
        openButton.setTitle("Open Flick", for: .normal)
        statusLabel.text = "Photos are ready in Flick. Tap Open Flick to continue."
        openButton.isHidden = false
        doneButton.isHidden = true
    }

    private func showManualOpenFallback(for url: URL) {
        pendingOpenURL = url
        activityIndicator.stopAnimating()
        openButton.setTitle("Try Again", for: .normal)
        statusLabel.text = "iOS did not allow Photos to open Flick. Your photos are saved; open Flick to continue."
        openButton.isHidden = false
        doneButton.isHidden = false
    }
}

private enum ShareExtensionError: LocalizedError {
    case appGroupUnavailable
    case noImages
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            "Flick could not access its shared import container."
        case .noImages:
            "Select one or more images to import into Flick."
        case .unreadableImage:
            "Flick could not read one of the selected images."
        }
    }
}
