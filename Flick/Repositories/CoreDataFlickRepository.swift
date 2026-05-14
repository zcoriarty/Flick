//
//  CoreDataFlickRepository.swift
//  Flick
//

import CloudKit
import CoreData
import Foundation

@MainActor
final class CoreDataFlickRepository: FlickRepository {
    private let context: NSManagedObjectContext
    private let cloudAvailability: () async -> Bool

    init(
        context: NSManagedObjectContext,
        cloudAvailability: @escaping () async -> Bool = CoreDataFlickRepository.defaultCloudAvailability
    ) {
        self.context = context
        self.cloudAvailability = cloudAvailability
    }

    func loadOverview() async throws -> FlickOverviewState {
        var state = FlickEmptyState.make()
        state.assets = try fetchAssets()
        state.dashboard.syncHealth.iCloudAvailable = await cloudAvailability()
        state.dashboard.syncHealth.pendingChanges = context.hasChanges ? 1 : 0
        return state
    }

    func saveOverview(_ state: FlickOverviewState) async throws {
        let request = assetFetchRequest()
        let existingAssets = try context.fetch(request)
        var existingByID = Dictionary(uniqueKeysWithValues: existingAssets.compactMap { object -> (UUID, NSManagedObject)? in
            guard let id = object.value(forKey: AssetKey.id) as? UUID else { return nil }
            return (id, object)
        })
        let stateIDs = Set(state.assets.map(\.id))

        for asset in state.assets {
            let object = existingByID.removeValue(forKey: asset.id) ?? insertAssetObject()
            apply(asset, to: object)
        }

        for (id, object) in existingByID where !stateIDs.contains(id) {
            context.delete(object)
        }

        try saveIfNeeded()
    }

    func upsertAsset(_ asset: MediaAsset) async throws {
        let object = try fetchAsset(id: asset.id) ?? insertAssetObject()
        apply(asset, to: object)
        try saveIfNeeded()
    }

    func deleteAsset(id: UUID) async throws {
        guard let object = try fetchAsset(id: id) else { return }
        context.delete(object)
        try saveIfNeeded()
    }

    private func fetchAssets() throws -> [MediaAsset] {
        let request = assetFetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: AssetKey.createdAt, ascending: false)
        ]
        return try context.fetch(request).compactMap(MediaAsset.init)
    }

    private func fetchAsset(id: UUID) throws -> NSManagedObject? {
        let request = assetFetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", AssetKey.id, id as NSUUID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func assetFetchRequest() -> NSFetchRequest<NSManagedObject> {
        NSFetchRequest<NSManagedObject>(entityName: "CDAsset")
    }

    private func insertAssetObject() -> NSManagedObject {
        NSEntityDescription.insertNewObject(forEntityName: "CDAsset", into: context)
    }

    private func apply(_ asset: MediaAsset, to object: NSManagedObject) {
        object.setValue(asset.id, forKey: AssetKey.id)
        object.setValue(asset.mediaType.rawValue, forKey: AssetKey.mediaType)
        object.setValue(asset.source.rawValue, forKey: AssetKey.source)
        object.setValue(asset.localFilePath, forKey: AssetKey.localFilePath)
        object.setValue(asset.storageBucket, forKey: AssetKey.storageBucket)
        object.setValue(asset.storagePath, forKey: AssetKey.storagePath)
        object.setValue(asset.publicURL, forKey: AssetKey.publicURL)
        object.setValue(asset.signedURLExpiration, forKey: AssetKey.signedURLExpiration)
        object.setValue(asset.width, forKey: AssetKey.width)
        object.setValue(asset.height, forKey: AssetKey.height)
        object.setValue(asset.duration, forKey: AssetKey.duration)
        object.setValue(asset.fileSize, forKey: AssetKey.fileSize)
        object.setValue(asset.checksum, forKey: AssetKey.checksum)
        object.setValue(asset.trendTags.map(\.id.uuidString), asJSONForKey: AssetKey.trendTagIDsJSON)
        object.setValue(asset.createdAt, forKey: AssetKey.createdAt)
        object.setValue(asset.updatedAt, forKey: AssetKey.updatedAt)
    }

    private func saveIfNeeded() throws {
        guard context.hasChanges else { return }
        try context.save()
    }

    private static func defaultCloudAvailability() async -> Bool {
        await withCheckedContinuation { continuation in
            CKContainer(identifier: PersistenceController.cloudKitContainerIdentifier).accountStatus { status, _ in
                continuation.resume(returning: status == .available)
            }
        }
    }
}

private enum AssetKey {
    static let checksum = "checksum"
    static let createdAt = "createdAt"
    static let duration = "duration"
    static let fileSize = "fileSize"
    static let height = "height"
    static let id = "id"
    static let localFilePath = "localFilePath"
    static let mediaType = "mediaType"
    static let publicURL = "publicURL"
    static let signedURLExpiration = "signedURLExpiration"
    static let source = "source"
    static let storageBucket = "storageBucket"
    static let storagePath = "storagePath"
    static let trendTagIDsJSON = "trendTagIDsJSON"
    static let updatedAt = "updatedAt"
    static let width = "width"
}

private extension MediaAsset {
    init?(managedObject: NSManagedObject) {
        guard
            let id = managedObject.value(forKey: AssetKey.id) as? UUID,
            let mediaTypeRawValue = managedObject.value(forKey: AssetKey.mediaType) as? String,
            let mediaType = AssetMediaType(rawValue: mediaTypeRawValue),
            let sourceRawValue = managedObject.value(forKey: AssetKey.source) as? String,
            let source = AssetSource(rawValue: sourceRawValue)
        else {
            return nil
        }

        self.init(
            id: id,
            mediaType: mediaType,
            source: source,
            localFilePath: managedObject.value(forKey: AssetKey.localFilePath) as? String,
            storageBucket: managedObject.value(forKey: AssetKey.storageBucket) as? String,
            storagePath: managedObject.value(forKey: AssetKey.storagePath) as? String,
            publicURL: managedObject.value(forKey: AssetKey.publicURL) as? URL,
            signedURLExpiration: managedObject.value(forKey: AssetKey.signedURLExpiration) as? Date,
            width: managedObject.integerValue(forKey: AssetKey.width),
            height: managedObject.integerValue(forKey: AssetKey.height),
            duration: managedObject.doubleValue(forKey: AssetKey.duration),
            fileSize: managedObject.int64Value(forKey: AssetKey.fileSize),
            checksum: managedObject.value(forKey: AssetKey.checksum) as? String,
            trendTags: [],
            createdAt: managedObject.value(forKey: AssetKey.createdAt) as? Date ?? Date(),
            updatedAt: managedObject.value(forKey: AssetKey.updatedAt) as? Date ?? Date()
        )
    }
}

private extension NSManagedObject {
    func integerValue(forKey key: String) -> Int {
        (value(forKey: key) as? NSNumber)?.intValue ?? 0
    }

    func int64Value(forKey key: String) -> Int64? {
        (value(forKey: key) as? NSNumber)?.int64Value
    }

    func doubleValue(forKey key: String) -> Double? {
        (value(forKey: key) as? NSNumber)?.doubleValue
    }

    func setValue<T: Encodable>(_ value: T, asJSONForKey key: String) {
        guard
            let data = try? JSONEncoder().encode(value),
            let json = String(data: data, encoding: .utf8)
        else {
            setValue(nil, forKey: key)
            return
        }

        setValue(json, forKey: key)
    }
}
