//
//  CoreDataFlickRepository.swift
//  Flick
//

import CloudKit
import CoreData
import Foundation

nonisolated private struct OverviewRecordKey: Hashable, Sendable {
    var kind: OverviewRecordKind
    var id: UUID
}

private typealias DeletionTombstones = [OverviewRecordKey: Date]

nonisolated final class CoreDataFlickRepository: FlickRepository, @unchecked Sendable {
    private let context: NSManagedObjectContext
    private let cloudAvailability: () async -> Bool
    private let resetsContextBeforeOperations: Bool

    init(
        context: NSManagedObjectContext,
        cloudAvailability: @escaping () async -> Bool = CoreDataFlickRepository.defaultCloudAvailability,
        resetsContextBeforeOperations: Bool = false
    ) {
        self.context = context
        self.cloudAvailability = cloudAvailability
        self.resetsContextBeforeOperations = resetsContextBeforeOperations
    }

    @MainActor
    convenience init(
        container: NSPersistentContainer,
        cloudAvailability: @escaping () async -> Bool = CoreDataFlickRepository.defaultCloudAvailability
    ) {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.transactionAuthor = PersistentHistoryChangeMonitor.appTransactionAuthor
        context.automaticallyMergesChangesFromParent = true
        self.init(
            context: context,
            cloudAvailability: cloudAvailability,
            resetsContextBeforeOperations: true
        )
    }

    @MainActor
    func loadOverview() async throws -> FlickOverviewState {
        var state = try await context.perform { [self] in
            resetContextIfNeeded()
            return try loadOverviewFromStore()
        }
        state.dashboard.syncHealth.iCloudAvailable = await cloudAvailability()
        return state
    }

    private func loadOverviewFromStore() throws -> FlickOverviewState {
        let tombstones = try fetchDeletionTombstones()
        var state = FlickEmptyState.make()
        state.accounts = try fetchConnectedAccounts().filter {
            isVisible(id: $0.id, updatedAt: $0.updatedAt, kind: .connectedAccount, tombstones: tombstones)
        }
        state.products = try fetchProducts().filter {
            isVisible(id: $0.id, updatedAt: $0.updatedAt, kind: .product, tombstones: tombstones)
        }
        state.creationModels = try fetchCreationModels().filter {
            isVisible(id: $0.id, updatedAt: $0.updatedAt, kind: .creationModel, tombstones: tombstones)
        }
        state.assets = try fetchAssets().filter {
            isVisible(id: $0.id, updatedAt: $0.updatedAt, kind: .asset, tombstones: tombstones)
        }
        state.templates = try fetchTemplates().filter {
            isVisible(id: $0.id, updatedAt: $0.updatedAt, kind: .template, tombstones: tombstones)
        }
        let slidesByDraftID = try fetchSlidesByDraftID(tombstones: tombstones)
        state.drafts = try fetchDrafts(slidesByDraftID: slidesByDraftID).filter {
            isVisible(id: $0.id, updatedAt: $0.updatedAt, kind: .draft, tombstones: tombstones)
        }
        state.automations = try fetchAutomations().filter {
            isVisible(id: $0.id, updatedAt: $0.updatedAt, kind: .automation, tombstones: tombstones)
        }
        state.automationPostProgresses = try fetchAutomationPostProgresses().filter {
            isVisible(id: $0.id, updatedAt: $0.updatedAt, kind: .automationPostProgress, tombstones: tombstones)
        }
        state.macRunnerHeartbeat = try fetchMacRunnerHeartbeat()
        state.publishingJobs = try fetchPublishingJobs().filter {
            isVisible(id: $0.id, updatedAt: $0.updatedAt, kind: .publishingJob, tombstones: tombstones)
        }
        state.publishedPosts = try fetchPublishedPosts().filter {
            isVisible(id: $0.id, updatedAt: $0.updatedAt, kind: .publishedPost, tombstones: tombstones)
        }
        state.refreshDerivedState()
        state.dashboard.connectedAccounts = state.accounts
        return state
    }

    @MainActor
    func saveOverview(
        _ state: FlickOverviewState,
        deletions: [OverviewDeletion]
    ) async throws {
        try await context.perform { [self] in
            resetContextIfNeeded()
            let deletions = deletions.deduplicatedByLatestDeletion()
            let tombstones = try persistDeletionTombstones(deletions)
            try syncOverview(state, tombstones: tombstones)
            if deletions.contains(where: { $0.kind == .automationPostProgress }) {
                try mergeAutomationPostProgresses(
                    state.automationPostProgresses,
                    tombstones: tombstones
                )
            }
            try applyPhysicalDeletions(deletions, tombstones: tombstones)
            try saveIfNeeded()
        }
    }

    @MainActor
    func saveCreateState(
        drafts: [SlideshowDraft],
        templates: [CreativeTemplate],
        assets: [MediaAsset],
        deletions: [OverviewDeletion]
    ) async throws {
        try await context.perform { [self] in
            resetContextIfNeeded()
            let deletions = deletions.deduplicatedByLatestDeletion()
            let tombstones = try persistDeletionTombstones(deletions)
            try syncAssets(assets, tombstones: tombstones)
            try syncTemplates(templates, tombstones: tombstones)
            try syncDrafts(drafts, tombstones: tombstones)
            try syncSlides(in: drafts, tombstones: tombstones)
            if deletions.contains(where: { $0.kind == .automationPostProgress }) {
                try mergeAutomationPostProgresses([], tombstones: tombstones)
            }
            try applyPhysicalDeletions(deletions, tombstones: tombstones)
            try saveIfNeeded()
        }
    }

    private func syncOverview(
        _ state: FlickOverviewState,
        tombstones: DeletionTombstones
    ) throws {
        try syncConnectedAccounts(state.accounts, tombstones: tombstones)
        try syncProducts(state.products, tombstones: tombstones)
        try syncCreationModels(state.creationModels, tombstones: tombstones)
        try syncAssets(state.assets, tombstones: tombstones)
        try syncTemplates(state.templates, tombstones: tombstones)
        try syncDrafts(state.drafts, tombstones: tombstones)
        try syncSlides(in: state.drafts, tombstones: tombstones)
        try syncAutomations(state.automations, tombstones: tombstones)
        try syncPublishingJobs(state.publishingJobs, tombstones: tombstones)
        try syncPublishedPosts(state.publishedPosts, tombstones: tombstones)
    }

    @MainActor
    func saveMacRunnerHeartbeat(_ heartbeat: MacRunnerHeartbeat) async throws {
        try await context.perform { [self] in
            resetContextIfNeeded()
            try syncMacRunnerHeartbeat(heartbeat)
            try saveIfNeeded()
        }
    }

    @MainActor
    func saveAutomationPostProgresses(_ progresses: [AutomationPostProgress]) async throws {
        try await context.perform { [self] in
            resetContextIfNeeded()
            try mergeAutomationPostProgresses(
                progresses,
                tombstones: try fetchDeletionTombstones()
            )
            try saveIfNeeded()
        }
    }

    @MainActor
    func upsertConnectedAccount(_ account: ConnectedAccount) async throws {
        try await context.perform { [self] in
            resetContextIfNeeded()
            let tombstones = try fetchDeletionTombstones()
            guard isVisible(
                id: account.id,
                updatedAt: account.updatedAt,
                kind: .connectedAccount,
                tombstones: tombstones
            ) else { return }
            let existingObject = try fetchConnectedAccount(id: account.id)
            if let existingObject,
               updatedAt(for: existingObject, key: ConnectedAccountKey.updatedAt) >= account.updatedAt {
                return
            }
            let object = existingObject ?? insertConnectedAccountObject()
            apply(account, to: object)
            try saveIfNeeded()
        }
    }

    @MainActor
    func deleteConnectedAccount(id: UUID) async throws {
        try await context.perform { [self] in
            resetContextIfNeeded()
            let deletion = OverviewDeletion(kind: .connectedAccount, id: id, deletedAt: Date())
            let tombstones = try persistDeletionTombstones([deletion])
            try applyPhysicalDeletions([deletion], tombstones: tombstones)
            try saveIfNeeded()
        }
    }

    @MainActor
    func upsertProduct(_ product: FlickProduct) async throws {
        try await context.perform { [self] in
            resetContextIfNeeded()
            let tombstones = try fetchDeletionTombstones()
            guard isVisible(
                id: product.id,
                updatedAt: product.updatedAt,
                kind: .product,
                tombstones: tombstones
            ) else { return }
            let existingObject = try fetchProduct(id: product.id)
            if let existingObject,
               updatedAt(for: existingObject, key: ProductKey.updatedAt) >= product.updatedAt {
                return
            }
            let object = existingObject ?? insertProductObject()
            apply(product, to: object)
            try saveIfNeeded()
        }
    }

    @MainActor
    func upsertAsset(_ asset: MediaAsset) async throws {
        try await context.perform { [self] in
            resetContextIfNeeded()
            let tombstones = try fetchDeletionTombstones()
            guard isVisible(
                id: asset.id,
                updatedAt: asset.updatedAt,
                kind: .asset,
                tombstones: tombstones
            ) else { return }
            let existingObject = try fetchAsset(id: asset.id)
            if let existingObject,
               updatedAt(for: existingObject, key: AssetKey.updatedAt) >= asset.updatedAt {
                return
            }
            let object = existingObject ?? insertAssetObject()
            apply(asset, to: object)
            try saveIfNeeded()
        }
    }

    @MainActor
    func deleteAsset(id: UUID) async throws {
        try await context.perform { [self] in
            resetContextIfNeeded()
            let deletion = OverviewDeletion(kind: .asset, id: id, deletedAt: Date())
            let tombstones = try persistDeletionTombstones([deletion])
            try applyPhysicalDeletions([deletion], tombstones: tombstones)
            try saveIfNeeded()
        }
    }

    private func existingObjectsByID(
        from objects: [NSManagedObject],
        idKey: String,
        updatedAtKey: String
    ) -> [UUID: NSManagedObject] {
        var objectsByID: [UUID: NSManagedObject] = [:]

        for object in objects {
            guard let id = object.value(forKey: idKey) as? UUID else { continue }

            guard let existing = objectsByID[id] else {
                objectsByID[id] = object
                continue
            }

            if updatedAt(for: object, key: updatedAtKey) > updatedAt(for: existing, key: updatedAtKey) {
                context.delete(existing)
                objectsByID[id] = object
            } else {
                context.delete(object)
            }
        }

        return objectsByID
    }

    private func fetchCanonicalObject(
        id: UUID,
        request: NSFetchRequest<NSManagedObject>,
        idKey: String,
        updatedAtKey: String
    ) throws -> NSManagedObject? {
        request.predicate = NSPredicate(format: "%K == %@", idKey, id as NSUUID)
        request.sortDescriptors = [
            NSSortDescriptor(key: updatedAtKey, ascending: false)
        ]
        let objects = try context.fetch(request)
        objects.dropFirst().forEach { context.delete($0) }
        return objects.first
    }

    private func updatedAt(for object: NSManagedObject, key: String) -> Date {
        object.value(forKey: key) as? Date ?? .distantPast
    }

    private enum ExistingObjectFetchScope {
        case all
        case ids(Set<UUID>)
    }

    private func fetchExistingObjects(
        using request: NSFetchRequest<NSManagedObject>,
        idKey: String,
        scope: ExistingObjectFetchScope
    ) throws -> [NSManagedObject] {
        switch scope {
        case .all:
            return try context.fetch(request)
        case let .ids(ids):
            guard !ids.isEmpty else { return [] }

            let ids = Array(ids)
            let batchSize = 400
            var objects: [NSManagedObject] = []
            objects.reserveCapacity(ids.count)

            for start in stride(from: 0, to: ids.count, by: batchSize) {
                let end = min(start + batchSize, ids.count)
                let batch = ids[start..<end].map { $0 as NSUUID }
                request.predicate = NSPredicate(format: "%K IN %@", idKey, batch as NSArray)
                objects.append(contentsOf: try context.fetch(request))
            }
            return objects
        }
    }

    private func isVisible(
        id: UUID,
        updatedAt: Date,
        kind: OverviewRecordKind,
        tombstones: DeletionTombstones
    ) -> Bool {
        guard let deletedAt = tombstones[OverviewRecordKey(kind: kind, id: id)] else {
            return true
        }
        return updatedAt > deletedAt
    }

    private func fetchDeletionTombstones() throws -> DeletionTombstones {
        let request = auditEventFetchRequest()
        request.predicate = NSPredicate(
            format: "%K BEGINSWITH %@",
            AuditEventKey.eventType,
            AuditEventKey.deletionEventTypePrefix
        )

        return try context.fetch(request).reduce(into: DeletionTombstones()) { result, object in
            guard let deletion = deletionTombstone(from: object) else { return }
            let key = OverviewRecordKey(kind: deletion.kind, id: deletion.id)
            result[key] = max(result[key] ?? .distantPast, deletion.deletedAt)
        }
    }

    private func persistDeletionTombstones(
        _ deletions: [OverviewDeletion]
    ) throws -> DeletionTombstones {
        var tombstones = try fetchDeletionTombstones()

        for deletion in deletions.deduplicatedByLatestDeletion() {
            let key = OverviewRecordKey(kind: deletion.kind, id: deletion.id)
            let effectiveDeletion = OverviewDeletion(
                kind: deletion.kind,
                id: deletion.id,
                deletedAt: max(tombstones[key] ?? .distantPast, deletion.deletedAt)
            )
            tombstones[key] = effectiveDeletion.deletedAt
            try upsertDeletionTombstone(effectiveDeletion)
        }

        return tombstones
    }

    private func upsertDeletionTombstone(_ deletion: OverviewDeletion) throws {
        let eventType = AuditEventKey.deletionEventType(for: deletion.kind)
        let request = auditEventFetchRequest()
        request.predicate = NSPredicate(
            format: "%K == %@ AND %K == %@",
            AuditEventKey.eventType,
            eventType,
            AuditEventKey.id,
            deletion.id as NSUUID
        )
        request.sortDescriptors = [
            NSSortDescriptor(key: AuditEventKey.createdAt, ascending: false)
        ]

        let objects = try context.fetch(request)
        let object = objects.first ?? insertAuditEventObject()
        objects.dropFirst().forEach { context.delete($0) }

        let storedDeletedAt = object.value(forKey: AuditEventKey.createdAt) as? Date ?? .distantPast
        let effectiveDeletion = OverviewDeletion(
            kind: deletion.kind,
            id: deletion.id,
            deletedAt: max(storedDeletedAt, deletion.deletedAt)
        )
        object.setValueIfChanged(effectiveDeletion.id, forKey: AuditEventKey.id)
        object.setValueIfChanged(eventType, forKey: AuditEventKey.eventType)
        object.setValueIfChanged(effectiveDeletion.deletedAt, forKey: AuditEventKey.createdAt)
        object.setValueIfChanged(
            "Deleted \(effectiveDeletion.kind.rawValue) \(effectiveDeletion.id.uuidString)",
            forKey: AuditEventKey.summary
        )
        object.setValueIfChanged(effectiveDeletion, asJSONForKey: AuditEventKey.metadataJSON)
    }

    private func deletionTombstone(from object: NSManagedObject) -> OverviewDeletion? {
        guard
            let eventType = object.value(forKey: AuditEventKey.eventType) as? String,
            eventType.hasPrefix(AuditEventKey.deletionEventTypePrefix),
            let kind = OverviewRecordKind(
                rawValue: String(eventType.dropFirst(AuditEventKey.deletionEventTypePrefix.count))
            )
        else {
            return nil
        }

        let metadata = object.decodedJSON(OverviewDeletion.self, forKey: AuditEventKey.metadataJSON)
        guard let id = object.value(forKey: AuditEventKey.id) as? UUID ?? metadata?.id else {
            return nil
        }
        let createdAt = object.value(forKey: AuditEventKey.createdAt) as? Date ?? .distantPast
        return OverviewDeletion(
            kind: kind,
            id: id,
            deletedAt: max(createdAt, metadata?.deletedAt ?? .distantPast)
        )
    }

    private func applyPhysicalDeletions(
        _ deletions: [OverviewDeletion],
        tombstones: DeletionTombstones
    ) throws {
        for deletion in deletions.deduplicatedByLatestDeletion() {
            let key = OverviewRecordKey(kind: deletion.kind, id: deletion.id)
            let deletedAt = tombstones[key] ?? deletion.deletedAt

            switch deletion.kind {
            case .connectedAccount:
                try deleteStoredRecord(
                    id: deletion.id,
                    deletedAt: deletedAt,
                    request: connectedAccountFetchRequest(),
                    idKey: ConnectedAccountKey.id,
                    updatedAtKey: ConnectedAccountKey.updatedAt
                )
            case .product:
                try deleteStoredRecord(
                    id: deletion.id,
                    deletedAt: deletedAt,
                    request: productFetchRequest(),
                    idKey: ProductKey.id,
                    updatedAtKey: ProductKey.updatedAt
                )
            case .creationModel:
                try deleteStoredRecord(
                    id: deletion.id,
                    deletedAt: deletedAt,
                    request: creationModelFetchRequest(),
                    idKey: CreationModelKey.id,
                    updatedAtKey: CreationModelKey.updatedAt
                )
            case .asset:
                try deleteStoredRecord(
                    id: deletion.id,
                    deletedAt: deletedAt,
                    request: assetFetchRequest(),
                    idKey: AssetKey.id,
                    updatedAtKey: AssetKey.updatedAt
                )
            case .template:
                try deleteStoredRecord(
                    id: deletion.id,
                    deletedAt: deletedAt,
                    request: templateFetchRequest(),
                    idKey: TemplateKey.id,
                    updatedAtKey: TemplateKey.updatedAt
                )
            case .draft:
                try deleteStoredRecord(
                    id: deletion.id,
                    deletedAt: deletedAt,
                    request: draftFetchRequest(),
                    idKey: DraftKey.id,
                    updatedAtKey: DraftKey.updatedAt
                )
            case .slide:
                try deleteStoredRecord(
                    id: deletion.id,
                    deletedAt: deletedAt,
                    request: slideFetchRequest(),
                    idKey: SlideKey.id,
                    updatedAtKey: SlideKey.updatedAt
                )
            case .automation:
                try deleteStoredRecord(
                    id: deletion.id,
                    deletedAt: deletedAt,
                    request: automationFetchRequest(),
                    idKey: AutomationKey.id,
                    updatedAtKey: AutomationKey.updatedAt
                )
            case .automationPostProgress:
                break
            case .publishingJob:
                try deleteStoredRecord(
                    id: deletion.id,
                    deletedAt: deletedAt,
                    request: publishingJobFetchRequest(),
                    idKey: PublishingJobKey.id,
                    updatedAtKey: PublishingJobKey.updatedAt
                )
            case .publishedPost:
                try deleteStoredRecord(
                    id: deletion.id,
                    deletedAt: deletedAt,
                    request: publishedPostFetchRequest(),
                    idKey: PublishedPostKey.id,
                    updatedAtKey: PublishedPostKey.updatedAt
                )
            }
        }
    }

    private func deleteStoredRecord(
        id: UUID,
        deletedAt: Date,
        request: NSFetchRequest<NSManagedObject>,
        idKey: String,
        updatedAtKey: String
    ) throws {
        let objects = try fetchExistingObjects(
            using: request,
            idKey: idKey,
            scope: .ids([id])
        )
        for object in objects where updatedAt(for: object, key: updatedAtKey) <= deletedAt {
            context.delete(object)
        }
    }

    private func syncRecords<Record: CoreDataSyncRecordIdentity>(
        _ records: [Record],
        kind: OverviewRecordKind,
        request: NSFetchRequest<NSManagedObject>,
        idKey: String,
        updatedAtKey: String,
        tombstones: DeletionTombstones,
        insert: () -> NSManagedObject,
        apply: (Record, NSManagedObject) -> Void
    ) throws {
        let records = records
            .deduplicatedByLatestUpdate()
            .filter {
                isVisible(
                    id: $0.id,
                    updatedAt: $0.updatedAt,
                    kind: kind,
                    tombstones: tombstones
                )
            }
        let recordIDs = Set(records.map(\.id))
        let existingObjects = try fetchExistingObjects(
            using: request,
            idKey: idKey,
            scope: .ids(recordIDs)
        )
        var existingByID = existingObjectsByID(
            from: existingObjects,
            idKey: idKey,
            updatedAtKey: updatedAtKey
        )

        for record in records {
            let existingObject = existingByID.removeValue(forKey: record.id)
            if let existingObject,
               updatedAt(for: existingObject, key: updatedAtKey) >= record.updatedAt {
                continue
            }
            apply(record, existingObject ?? insert())
        }
    }

    private func syncConnectedAccounts(
        _ accounts: [ConnectedAccount],
        tombstones: DeletionTombstones
    ) throws {
        try syncRecords(
            accounts,
            kind: .connectedAccount,
            request: connectedAccountFetchRequest(),
            idKey: ConnectedAccountKey.id,
            updatedAtKey: ConnectedAccountKey.updatedAt,
            tombstones: tombstones,
            insert: insertConnectedAccountObject,
            apply: apply
        )
    }

    private func syncProducts(
        _ products: [FlickProduct],
        tombstones: DeletionTombstones
    ) throws {
        try syncRecords(
            products,
            kind: .product,
            request: productFetchRequest(),
            idKey: ProductKey.id,
            updatedAtKey: ProductKey.updatedAt,
            tombstones: tombstones,
            insert: insertProductObject,
            apply: apply
        )
    }

    private func syncCreationModels(
        _ creationModels: [FlickCreationModel],
        tombstones: DeletionTombstones
    ) throws {
        try syncRecords(
            creationModels,
            kind: .creationModel,
            request: creationModelFetchRequest(),
            idKey: CreationModelKey.id,
            updatedAtKey: CreationModelKey.updatedAt,
            tombstones: tombstones,
            insert: insertCreationModelObject,
            apply: apply
        )
    }

    private func syncAssets(
        _ assets: [MediaAsset],
        tombstones: DeletionTombstones
    ) throws {
        try syncRecords(
            assets,
            kind: .asset,
            request: assetFetchRequest(),
            idKey: AssetKey.id,
            updatedAtKey: AssetKey.updatedAt,
            tombstones: tombstones,
            insert: insertAssetObject,
            apply: apply
        )
    }

    private func syncTemplates(
        _ templates: [CreativeTemplate],
        tombstones: DeletionTombstones
    ) throws {
        try syncRecords(
            templates,
            kind: .template,
            request: templateFetchRequest(),
            idKey: TemplateKey.id,
            updatedAtKey: TemplateKey.updatedAt,
            tombstones: tombstones,
            insert: insertTemplateObject,
            apply: apply
        )
    }

    private func syncDrafts(
        _ drafts: [SlideshowDraft],
        tombstones: DeletionTombstones
    ) throws {
        try syncRecords(
            drafts,
            kind: .draft,
            request: draftFetchRequest(),
            idKey: DraftKey.id,
            updatedAtKey: DraftKey.updatedAt,
            tombstones: tombstones,
            insert: insertDraftObject,
            apply: apply
        )
    }

    private func syncSlides(
        in drafts: [SlideshowDraft],
        tombstones: DeletionTombstones
    ) throws {
        let visibleDrafts = drafts.filter {
            isVisible(id: $0.id, updatedAt: $0.updatedAt, kind: .draft, tombstones: tombstones)
        }
        let draftSlides = newestUniqueDraftSlides(in: visibleDrafts).filter {
            isVisible(
                id: $0.slide.id,
                updatedAt: $0.slide.updatedAt,
                kind: .slide,
                tombstones: tombstones
            )
        }
        let slideIDs = Set(draftSlides.map(\.slide.id))
        let existingSlides = try fetchExistingObjects(
            using: slideFetchRequest(),
            idKey: SlideKey.id,
            scope: .ids(slideIDs)
        )
        var existingByID = existingObjectsByID(
            from: existingSlides,
            idKey: SlideKey.id,
            updatedAtKey: SlideKey.updatedAt
        )

        for (draftID, slide) in draftSlides {
            let existingObject = existingByID.removeValue(forKey: slide.id)
            if let existingObject,
               updatedAt(for: existingObject, key: SlideKey.updatedAt) >= slide.updatedAt {
                continue
            }
            apply(slide, draftID: draftID, to: existingObject ?? insertSlideObject())
        }
    }

    private func newestUniqueDraftSlides(in drafts: [SlideshowDraft]) -> [(draftID: UUID, slide: Slide)] {
        var indicesBySlideID: [UUID: Int] = [:]
        var draftSlides: [(draftID: UUID, slide: Slide)] = []

        for draft in drafts {
            for slide in draft.slides {
                if let existingIndex = indicesBySlideID[slide.id] {
                    if slide.updatedAt > draftSlides[existingIndex].slide.updatedAt {
                        draftSlides[existingIndex] = (draft.id, slide)
                    }
                } else {
                    indicesBySlideID[slide.id] = draftSlides.count
                    draftSlides.append((draft.id, slide))
                }
            }
        }

        return draftSlides
    }

    private func syncAutomations(
        _ automations: [ContentAutomation],
        tombstones: DeletionTombstones
    ) throws {
        try syncRecords(
            automations,
            kind: .automation,
            request: automationFetchRequest(),
            idKey: AutomationKey.id,
            updatedAtKey: AutomationKey.updatedAt,
            tombstones: tombstones,
            insert: insertAutomationObject,
            apply: apply
        )
    }

    private func syncPublishingJobs(
        _ jobs: [PublishingJob],
        tombstones: DeletionTombstones
    ) throws {
        try syncRecords(
            jobs,
            kind: .publishingJob,
            request: publishingJobFetchRequest(),
            idKey: PublishingJobKey.id,
            updatedAtKey: PublishingJobKey.updatedAt,
            tombstones: tombstones,
            insert: insertPublishingJobObject,
            apply: apply
        )
    }

    private func mergeAutomationPostProgresses(
        _ progresses: [AutomationPostProgress],
        tombstones: DeletionTombstones
    ) throws {
        let existing = try fetchAutomationPostProgresses().filter {
            isVisible(
                id: $0.id,
                updatedAt: $0.updatedAt,
                kind: .automationPostProgress,
                tombstones: tombstones
            )
        }
        let incoming = progresses.deduplicatedByLatestUpdate().filter {
            isVisible(
                id: $0.id,
                updatedAt: $0.updatedAt,
                kind: .automationPostProgress,
                tombstones: tombstones
            )
        }
        let merged = existing.mergingLatestUpdates(incoming)
        try syncAutomationPostProgressesBlob(merged)
    }

    private func syncAutomationPostProgressesBlob(_ progresses: [AutomationPostProgress]) throws {
        let objects = try fetchWorkflowStateObjects(key: WorkflowStateValueKey.automationPostProgresses)

        if progresses.isEmpty {
            objects.forEach { context.delete($0) }
            return
        }

        let object = objects.first ?? insertWorkflowStateObject()
        objects.dropFirst().forEach { context.delete($0) }
        var changed = object.setValueIfChanged(
            object.value(forKey: WorkflowStateKey.id) as? UUID ?? UUID(),
            forKey: WorkflowStateKey.id
        )
        changed = object.setValueIfChanged(
            WorkflowStateValueKey.automationPostProgresses,
            forKey: WorkflowStateKey.key
        ) || changed
        changed = object.setValueIfChanged(
            progresses,
            asJSONForKey: WorkflowStateKey.valueJSON
        ) || changed
        if changed {
            object.setValue(Date(), forKey: WorkflowStateKey.updatedAt)
        }
    }

    private func syncMacRunnerHeartbeat(_ heartbeat: MacRunnerHeartbeat) throws {
        let objects = try fetchWorkflowStateObjects(key: WorkflowStateValueKey.macRunnerHeartbeat)

        if heartbeat.lastSeenAt == nil {
            objects.forEach { context.delete($0) }
            return
        }

        let object = objects.first ?? insertWorkflowStateObject()
        objects.dropFirst().forEach { context.delete($0) }
        var changed = object.setValueIfChanged(
            object.value(forKey: WorkflowStateKey.id) as? UUID ?? UUID(),
            forKey: WorkflowStateKey.id
        )
        changed = object.setValueIfChanged(
            WorkflowStateValueKey.macRunnerHeartbeat,
            forKey: WorkflowStateKey.key
        ) || changed
        changed = object.setValueIfChanged(
            heartbeat,
            asJSONForKey: WorkflowStateKey.valueJSON
        ) || changed
        if changed {
            object.setValue(Date(), forKey: WorkflowStateKey.updatedAt)
        }
    }

    private func syncPublishedPosts(
        _ posts: [PublishedPost],
        tombstones: DeletionTombstones
    ) throws {
        try syncRecords(
            posts,
            kind: .publishedPost,
            request: publishedPostFetchRequest(),
            idKey: PublishedPostKey.id,
            updatedAtKey: PublishedPostKey.updatedAt,
            tombstones: tombstones,
            insert: insertPublishedPostObject,
            apply: apply
        )
    }

    private func fetchAssets() throws -> [MediaAsset] {
        let request = assetFetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: AssetKey.createdAt, ascending: false)
        ]
        return try context.fetch(request).compactMap(MediaAsset.init)
    }

    private func fetchProducts() throws -> [FlickProduct] {
        let request = productFetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: ProductKey.updatedAt, ascending: false)
        ]
        return try context.fetch(request).compactMap(FlickProduct.init)
    }

    private func fetchCreationModels() throws -> [FlickCreationModel] {
        let request = creationModelFetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: CreationModelKey.updatedAt, ascending: false)
        ]
        return try context.fetch(request).compactMap(FlickCreationModel.init)
    }

    private func fetchProduct(id: UUID) throws -> NSManagedObject? {
        try fetchCanonicalObject(
            id: id,
            request: productFetchRequest(),
            idKey: ProductKey.id,
            updatedAtKey: ProductKey.updatedAt
        )
    }

    private func fetchAsset(id: UUID) throws -> NSManagedObject? {
        try fetchCanonicalObject(
            id: id,
            request: assetFetchRequest(),
            idKey: AssetKey.id,
            updatedAtKey: AssetKey.updatedAt
        )
    }

    private func fetchTemplates() throws -> [CreativeTemplate] {
        let request = templateFetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: TemplateKey.updatedAt, ascending: false)
        ]
        return try context.fetch(request).compactMap(CreativeTemplate.init)
    }

    private func fetchDrafts(slidesByDraftID: [UUID: [Slide]]) throws -> [SlideshowDraft] {
        let request = draftFetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: DraftKey.updatedAt, ascending: false)
        ]
        return try context.fetch(request).compactMap { object in
            SlideshowDraft(managedObject: object, slides: slidesByDraftID[object.uuidValue(forKey: DraftKey.id) ?? UUID()] ?? [])
        }
    }

    private func fetchSlidesByDraftID(
        tombstones: DeletionTombstones
    ) throws -> [UUID: [Slide]] {
        let request = slideFetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: SlideKey.index, ascending: true)
        ]
        return try context.fetch(request).reduce(into: [UUID: [Slide]]()) { result, object in
            guard
                let draftID = object.value(forKey: SlideKey.draftID) as? UUID,
                let slide = Slide(managedObject: object),
                isVisible(
                    id: slide.id,
                    updatedAt: slide.updatedAt,
                    kind: .slide,
                    tombstones: tombstones
                )
            else {
                return
            }
            result[draftID, default: []].append(slide)
        }
    }

    private func fetchAutomations() throws -> [ContentAutomation] {
        let request = automationFetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: AutomationKey.updatedAt, ascending: false)
        ]
        return try context.fetch(request).compactMap(ContentAutomation.init)
    }

    private func fetchAutomationPostProgresses() throws -> [AutomationPostProgress] {
        try fetchWorkflowStateObjects(key: WorkflowStateValueKey.automationPostProgresses)
            .flatMap {
                $0.decodedJSON([AutomationPostProgress].self, forKey: WorkflowStateKey.valueJSON) ?? []
            }
            .deduplicatedByLatestUpdate()
    }

    private func fetchMacRunnerHeartbeat() throws -> MacRunnerHeartbeat {
        guard let object = try fetchWorkflowStateObjects(key: WorkflowStateValueKey.macRunnerHeartbeat).first else {
            return MacRunnerHeartbeat()
        }

        return object.decodedJSON(MacRunnerHeartbeat.self, forKey: WorkflowStateKey.valueJSON) ?? MacRunnerHeartbeat()
    }

    private func fetchPublishingJobs() throws -> [PublishingJob] {
        let request = publishingJobFetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: PublishingJobKey.updatedAt, ascending: false)
        ]
        return try context.fetch(request).compactMap(PublishingJob.init)
    }

    private func fetchPublishedPosts() throws -> [PublishedPost] {
        let request = publishedPostFetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: PublishedPostKey.publishedAt, ascending: false)
        ]
        return try context.fetch(request).compactMap(PublishedPost.init)
    }

    private func fetchConnectedAccounts() throws -> [ConnectedAccount] {
        let request = connectedAccountFetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: ConnectedAccountKey.platform, ascending: true),
            NSSortDescriptor(key: ConnectedAccountKey.displayName, ascending: true)
        ]
        return try context.fetch(request).compactMap(ConnectedAccount.init)
    }

    private func fetchConnectedAccount(id: UUID) throws -> NSManagedObject? {
        try fetchCanonicalObject(
            id: id,
            request: connectedAccountFetchRequest(),
            idKey: ConnectedAccountKey.id,
            updatedAtKey: ConnectedAccountKey.updatedAt
        )
    }

    private func connectedAccountFetchRequest() -> NSFetchRequest<NSManagedObject> {
        NSFetchRequest<NSManagedObject>(entityName: "CDConnectedAccount")
    }

    private func assetFetchRequest() -> NSFetchRequest<NSManagedObject> {
        NSFetchRequest<NSManagedObject>(entityName: "CDAsset")
    }

    private func productFetchRequest() -> NSFetchRequest<NSManagedObject> {
        NSFetchRequest<NSManagedObject>(entityName: "CDProduct")
    }

    private func creationModelFetchRequest() -> NSFetchRequest<NSManagedObject> {
        NSFetchRequest<NSManagedObject>(entityName: "CDCreationModel")
    }

    private func templateFetchRequest() -> NSFetchRequest<NSManagedObject> {
        NSFetchRequest<NSManagedObject>(entityName: "CDCreativeTemplate")
    }

    private func draftFetchRequest() -> NSFetchRequest<NSManagedObject> {
        NSFetchRequest<NSManagedObject>(entityName: "CDSlideshowDraft")
    }

    private func automationFetchRequest() -> NSFetchRequest<NSManagedObject> {
        NSFetchRequest<NSManagedObject>(entityName: "CDContentAutomation")
    }

    private func slideFetchRequest() -> NSFetchRequest<NSManagedObject> {
        NSFetchRequest<NSManagedObject>(entityName: "CDSlide")
    }

    private func publishingJobFetchRequest() -> NSFetchRequest<NSManagedObject> {
        NSFetchRequest<NSManagedObject>(entityName: "CDPublishingJob")
    }

    private func publishedPostFetchRequest() -> NSFetchRequest<NSManagedObject> {
        NSFetchRequest<NSManagedObject>(entityName: "CDPublishedPost")
    }

    private func workflowStateFetchRequest() -> NSFetchRequest<NSManagedObject> {
        NSFetchRequest<NSManagedObject>(entityName: "CDWorkflowState")
    }

    private func auditEventFetchRequest() -> NSFetchRequest<NSManagedObject> {
        NSFetchRequest<NSManagedObject>(entityName: "CDAuditEvent")
    }

    private func fetchWorkflowStateObjects(key: String) throws -> [NSManagedObject] {
        let request = workflowStateFetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", WorkflowStateKey.key, key)
        request.sortDescriptors = [
            NSSortDescriptor(key: WorkflowStateKey.updatedAt, ascending: false)
        ]
        return try context.fetch(request)
    }

    private func insertAssetObject() -> NSManagedObject {
        NSEntityDescription.insertNewObject(forEntityName: "CDAsset", into: context)
    }

    private func insertProductObject() -> NSManagedObject {
        NSEntityDescription.insertNewObject(forEntityName: "CDProduct", into: context)
    }

    private func insertCreationModelObject() -> NSManagedObject {
        NSEntityDescription.insertNewObject(forEntityName: "CDCreationModel", into: context)
    }

    private func insertTemplateObject() -> NSManagedObject {
        NSEntityDescription.insertNewObject(forEntityName: "CDCreativeTemplate", into: context)
    }

    private func insertDraftObject() -> NSManagedObject {
        NSEntityDescription.insertNewObject(forEntityName: "CDSlideshowDraft", into: context)
    }

    private func insertSlideObject() -> NSManagedObject {
        NSEntityDescription.insertNewObject(forEntityName: "CDSlide", into: context)
    }

    private func insertAutomationObject() -> NSManagedObject {
        NSEntityDescription.insertNewObject(forEntityName: "CDContentAutomation", into: context)
    }

    private func insertPublishingJobObject() -> NSManagedObject {
        NSEntityDescription.insertNewObject(forEntityName: "CDPublishingJob", into: context)
    }

    private func insertPublishedPostObject() -> NSManagedObject {
        NSEntityDescription.insertNewObject(forEntityName: "CDPublishedPost", into: context)
    }

    private func insertWorkflowStateObject() -> NSManagedObject {
        NSEntityDescription.insertNewObject(forEntityName: "CDWorkflowState", into: context)
    }

    private func insertAuditEventObject() -> NSManagedObject {
        NSEntityDescription.insertNewObject(forEntityName: "CDAuditEvent", into: context)
    }

    private func insertConnectedAccountObject() -> NSManagedObject {
        NSEntityDescription.insertNewObject(forEntityName: "CDConnectedAccount", into: context)
    }

    private func apply(_ account: ConnectedAccount, to object: NSManagedObject) {
        object.setValueIfChanged(account.id, forKey: ConnectedAccountKey.id)
        object.setValueIfChanged(account.platform.rawValue, forKey: ConnectedAccountKey.platform)
        object.setValueIfChanged(account.displayName, forKey: ConnectedAccountKey.displayName)
        object.setValueIfChanged(account.platformUserID, forKey: ConnectedAccountKey.platformUserID)
        object.setValueIfChanged(account.avatarURL, forKey: ConnectedAccountKey.avatarURL)
        object.setValueIfChanged(account.scopes, asJSONForKey: ConnectedAccountKey.scopesJSON)
        object.setValueIfChanged(account.status.rawValue, forKey: ConnectedAccountKey.status)
        object.setValueIfChanged(account.authorizationSource.rawValue, forKey: ConnectedAccountKey.authorizationSource)
        object.setValueIfChanged(account.tokenStatus.rawValue, forKey: ConnectedAccountKey.tokenStatus)
        object.setValueIfChanged(account.isPublishingEnabled, forKey: ConnectedAccountKey.isPublishingEnabled)
        object.setValueIfChanged(account.defaultPrivacyLevel, forKey: ConnectedAccountKey.defaultPrivacyLevel)
        object.setValueIfChanged(account.lastValidatedAt, forKey: ConnectedAccountKey.lastValidatedAt)
        object.setValueIfChanged(account.createdAt, forKey: ConnectedAccountKey.createdAt)
        object.setValueIfChanged(account.updatedAt, forKey: ConnectedAccountKey.updatedAt)
    }

    private func apply(_ asset: MediaAsset, to object: NSManagedObject) {
        object.setValueIfChanged(asset.id, forKey: AssetKey.id)
        object.setValueIfChanged(asset.mediaType.rawValue, forKey: AssetKey.mediaType)
        object.setValueIfChanged(asset.source.rawValue, forKey: AssetKey.source)
        object.setValueIfChanged(asset.localFilePath, forKey: AssetKey.localFilePath)
        object.setValueIfChanged(asset.storageBucket, forKey: AssetKey.storageBucket)
        object.setValueIfChanged(asset.storagePath, forKey: AssetKey.storagePath)
        object.setValueIfChanged(asset.publicURL, forKey: AssetKey.publicURL)
        object.setValueIfChanged(asset.signedURLExpiration, forKey: AssetKey.signedURLExpiration)
        object.setValueIfChanged(asset.width, forKey: AssetKey.width)
        object.setValueIfChanged(asset.height, forKey: AssetKey.height)
        object.setValueIfChanged(asset.duration, forKey: AssetKey.duration)
        object.setValueIfChanged(asset.fileSize, forKey: AssetKey.fileSize)
        object.setValueIfChanged(asset.checksum, forKey: AssetKey.checksum)
        object.setValueIfChanged(asset.trendTags.map(\.id.uuidString), asJSONForKey: AssetKey.trendTagIDsJSON)
        object.setValueIfChanged(asset.productIDs.map(\.uuidString), asJSONForKey: AssetKey.productIDsJSON)
        object.setValueIfChanged(asset.createdAt, forKey: AssetKey.createdAt)
        object.setValueIfChanged(asset.updatedAt, forKey: AssetKey.updatedAt)
    }

    private func apply(_ product: FlickProduct, to object: NSManagedObject) {
        object.setValueIfChanged(product.id, forKey: ProductKey.id)
        object.setValueIfChanged(product.name, forKey: ProductKey.name)
        object.setValueIfChanged(product.summary, forKey: ProductKey.summary)
        object.setValueIfChanged(product.createdAt, forKey: ProductKey.createdAt)
        object.setValueIfChanged(product.updatedAt, forKey: ProductKey.updatedAt)
    }

    private func apply(_ creationModel: FlickCreationModel, to object: NSManagedObject) {
        object.setValueIfChanged(creationModel.id, forKey: CreationModelKey.id)
        object.setValueIfChanged(creationModel.name, forKey: CreationModelKey.name)
        object.setValueIfChanged(creationModel.metadata, asJSONForKey: CreationModelKey.metadataJSON)
        object.setValueIfChanged(creationModel.createdAt, forKey: CreationModelKey.createdAt)
        object.setValueIfChanged(creationModel.updatedAt, forKey: CreationModelKey.updatedAt)
    }

    private func apply(_ template: CreativeTemplate, to object: NSManagedObject) {
        object.setValueIfChanged(template.id, forKey: TemplateKey.id)
        object.setValueIfChanged(template.name, forKey: TemplateKey.name)
        object.setValueIfChanged(template.description, forKey: TemplateKey.summary)
        object.setValueIfChanged(template.platform.rawValue, forKey: TemplateKey.platform)
        object.setValueIfChanged(template.slideCount, forKey: TemplateKey.slideCount)
        object.setValueIfChanged(template.analysisSchemaVersion, forKey: TemplateKey.analysisSchemaVersion)
        object.setValueIfChanged(template.sourceTemplateFingerprint, forKey: TemplateKey.sourceTemplateFingerprint)
        object.setValueIfChanged(template.sourceTemplateID, forKey: TemplateKey.sourceTemplateID)
        object.setValueIfChanged(template.styleJSON, forKey: TemplateKey.styleJSON)
        object.setValueIfChanged(template.defaultTextRules, forKey: TemplateKey.defaultTextRules)
        object.setValueIfChanged(template.tags.map(\.id.uuidString), asJSONForKey: TemplateKey.tagIDsJSON)
        object.setValueIfChanged(template.createdAt, forKey: TemplateKey.createdAt)
        object.setValueIfChanged(template.updatedAt, forKey: TemplateKey.updatedAt)
    }

    private func apply(_ draft: SlideshowDraft, to object: NSManagedObject) {
        object.setValueIfChanged(draft.id, forKey: DraftKey.id)
        object.setValueIfChanged(draft.automationID, forKey: DraftKey.automationID)
        object.setValueIfChanged(draft.title, forKey: DraftKey.title)
        object.setValueIfChanged(draft.templateID, forKey: DraftKey.templateID)
        object.setValueIfChanged(draft.creationModel?.id, forKey: DraftKey.creationModelID)
        object.setValueIfChanged(draft.creationModel, asJSONForKey: DraftKey.creationModelJSON)
        object.setValueIfChanged(draft.imageVibe.rawValue, forKey: DraftKey.imageVibe)
        object.setValueIfChanged(draft.brief, forKey: DraftKey.brief)
        object.setValueIfChanged(draft.topic, forKey: DraftKey.topic)
        object.setValueIfChanged(draft.audience, forKey: DraftKey.audience)
        object.setValueIfChanged(draft.goal, forKey: DraftKey.goal)
        object.setValueIfChanged(draft.tone, forKey: DraftKey.tone)
        object.setValueIfChanged(draft.narrativeArc, asJSONForKey: DraftKey.narrativeArcJSON)
        object.setValueIfChanged(draft.globalVisualMotif, forKey: DraftKey.globalVisualMotif)
        object.setValueIfChanged(draft.planSummary, forKey: DraftKey.planSummary)
        object.setValueIfChanged(draft.slides.sorted { $0.index < $1.index }.map(\.id.uuidString), asJSONForKey: DraftKey.slideIDsJSON)
        object.setValueIfChanged(draft.caption, forKey: DraftKey.caption)
        object.setValueIfChanged(draft.hashtags, asJSONForKey: DraftKey.hashtagsJSON)
        object.setValueIfChanged(draft.targetPlatforms.map(\.rawValue), asJSONForKey: DraftKey.targetPlatformsJSON)
        object.setValueIfChanged(draft.accountSelections, asJSONForKey: DraftKey.accountSelectionsJSON)
        object.setValueIfChanged(draft.tikTokSettings, asJSONForKey: DraftKey.tikTokSettingsJSON)
        object.setValueIfChanged(draft.youtubeSettings, asJSONForKey: DraftKey.youtubeSettingsJSON)
        object.setValueIfChanged(draft.selectedSongs, asJSONForKey: DraftKey.selectedSongsJSON)
        object.setValueIfChanged(draft.status.rawValue, forKey: DraftKey.status)
        object.setValueIfChanged(draft.exportedImageAssetIDs.map(\.uuidString), asJSONForKey: DraftKey.exportedImageAssetIDsJSON)
        object.setValueIfChanged(draft.createdAt, forKey: DraftKey.createdAt)
        object.setValueIfChanged(draft.updatedAt, forKey: DraftKey.updatedAt)
    }

    private func apply(_ slide: Slide, draftID: UUID, to object: NSManagedObject) {
        object.setValueIfChanged(slide.id, forKey: SlideKey.id)
        object.setValueIfChanged(draftID, forKey: SlideKey.draftID)
        object.setValueIfChanged(slide.index, forKey: SlideKey.index)
        object.setValueIfChanged(slide.imageAssetID, forKey: SlideKey.imageAssetID)
        object.setValueIfChanged(slide.prompt, forKey: SlideKey.prompt)
        object.setValueIfChanged(slide.text, forKey: SlideKey.text)
        object.setValueIfChanged(slide.textPosition.rawValue, forKey: SlideKey.textPosition)
        object.setValueIfChanged(slide.textStyle, asJSONForKey: SlideKey.textStyleJSON)
        object.setValueIfChanged(slide.selectedVisualSummary, forKey: SlideKey.selectedVisualSummary)
        object.setValueIfChanged(slide.generationStatus.rawValue, forKey: SlideKey.generationStatus)
        object.setValueIfChanged(slide.generationErrorMessage, forKey: SlideKey.generationErrorMessage)
        object.setValueIfChanged(slide.promptVersion, forKey: SlideKey.promptVersion)
        object.setValueIfChanged(slide.createdAt, forKey: SlideKey.createdAt)
        object.setValueIfChanged(slide.updatedAt, forKey: SlideKey.updatedAt)
    }

    private func apply(_ automation: ContentAutomation, to object: NSManagedObject) {
        object.setValueIfChanged(automation.id, forKey: AutomationKey.id)
        object.setValueIfChanged(automation.name, forKey: AutomationKey.name)
        object.setValueIfChanged(automation.templateIDs, asJSONForKey: AutomationKey.templateIDsJSON)
        object.setValueIfChanged(automation.templateNicheIDs, asJSONForKey: AutomationKey.templateNicheIDsJSON)
        object.setValueIfChanged(automation.productID, forKey: AutomationKey.productID)
        object.setValueIfChanged(automation.productImageAssetIDs.map(\.uuidString), asJSONForKey: AutomationKey.productImageAssetIDsJSON)
        object.setValueIfChanged(automation.creationModel?.id, forKey: AutomationKey.creationModelID)
        object.setValueIfChanged(automation.creationModel, asJSONForKey: AutomationKey.creationModelJSON)
        object.setValueIfChanged(automation.imageVibe.rawValue, forKey: AutomationKey.imageVibe)
        object.setValueIfChanged(automation.schedule, asJSONForKey: AutomationKey.scheduleJSON)
        object.setValueIfChanged(automation.tikTokSettings, asJSONForKey: AutomationKey.tikTokSettingsJSON)
        object.setValueIfChanged(automation.youtubeSettings, asJSONForKey: AutomationKey.youtubeSettingsJSON)
        object.setValueIfChanged(automation.targetPlatforms.map(\.rawValue), asJSONForKey: AutomationKey.targetPlatformsJSON)
        object.setValueIfChanged(automation.accountSelections, asJSONForKey: AutomationKey.accountSelectionsJSON)
        object.setValueIfChanged(automation.status.rawValue, forKey: AutomationKey.status)
        object.setValueIfChanged(automation.nextScheduledAt, forKey: AutomationKey.nextScheduledAt)
        object.setValueIfChanged(automation.lastRunAt, forKey: AutomationKey.lastRunAt)
        object.setValueIfChanged(automation.lastErrorMessage, forKey: AutomationKey.lastErrorMessage)
        object.setValueIfChanged(automation.consecutiveFailureCount, forKey: AutomationKey.consecutiveFailureCount)
        object.setValueIfChanged(automation.createdAt, forKey: AutomationKey.createdAt)
        object.setValueIfChanged(automation.updatedAt, forKey: AutomationKey.updatedAt)
    }

    private func apply(_ job: PublishingJob, to object: NSManagedObject) {
        object.setValueIfChanged(job.id, forKey: PublishingJobKey.id)
        object.setValueIfChanged(job.platform.rawValue, forKey: PublishingJobKey.platform)
        object.setValueIfChanged(job.accountID, forKey: PublishingJobKey.accountID)
        object.setValueIfChanged(job.automationID, forKey: PublishingJobKey.automationID)
        object.setValueIfChanged(job.draftID, forKey: PublishingJobKey.draftID)
        object.setValueIfChanged(job.status.rawValue, forKey: PublishingJobKey.status)
        object.setValueIfChanged(job.publishMode.rawValue, forKey: PublishingJobKey.publishMode)
        object.setValueIfChanged(job.attemptCount, forKey: PublishingJobKey.attemptCount)
        object.setValueIfChanged(job.lastAttemptAt, forKey: PublishingJobKey.lastAttemptAt)
        object.setValueIfChanged(job.lastError, asJSONForKey: PublishingJobKey.lastErrorJSON)
        object.setValueIfChanged(job.platformPublishID, forKey: PublishingJobKey.platformPublishID)
        object.setValueIfChanged(job.createdAt, forKey: PublishingJobKey.createdAt)
        object.setValueIfChanged(job.updatedAt, forKey: PublishingJobKey.updatedAt)
    }

    private func apply(_ post: PublishedPost, to object: NSManagedObject) {
        object.setValueIfChanged(post.id, forKey: PublishedPostKey.id)
        object.setValueIfChanged(post.platform.rawValue, forKey: PublishedPostKey.platform)
        object.setValueIfChanged(post.accountID, forKey: PublishedPostKey.accountID)
        object.setValueIfChanged(post.automationID, forKey: PublishedPostKey.automationID)
        object.setValueIfChanged(post.platformPostID, forKey: PublishedPostKey.platformPostID)
        object.setValueIfChanged(post.platformURL, forKey: PublishedPostKey.platformURL)
        object.setValueIfChanged(post.publishedAt, forKey: PublishedPostKey.publishedAt)
        object.setValueIfChanged(post.draftID, forKey: PublishedPostKey.draftID)
        object.setValueIfChanged(post.templateID, forKey: PublishedPostKey.templateID)
        object.setValueIfChanged(post.trendTags.map(\.id.uuidString), asJSONForKey: PublishedPostKey.trendTagIDsJSON)
        object.setValueIfChanged(post.caption, forKey: PublishedPostKey.caption)
        object.setValueIfChanged(post.createdAt, forKey: PublishedPostKey.createdAt)
        object.setValueIfChanged(post.updatedAt, forKey: PublishedPostKey.updatedAt)
    }

    private func saveIfNeeded() throws {
        guard context.hasChanges else { return }
        try context.save()
    }

    private func resetContextIfNeeded() {
        guard resetsContextBeforeOperations else { return }
        context.reset()
    }

    private static func defaultCloudAvailability() async -> Bool {
        guard !ProcessInfo.processInfo.flickIsRunningXCTest else { return false }

        return await withCheckedContinuation { continuation in
            CKContainer(identifier: PersistenceController.cloudKitContainerIdentifier).accountStatus { status, _ in
                continuation.resume(returning: status == .available)
            }
        }
    }
}

nonisolated private protocol CoreDataSyncRecordIdentity {
    var id: UUID { get }
    var updatedAt: Date { get }
}

nonisolated extension ConnectedAccount: CoreDataSyncRecordIdentity {}
nonisolated extension FlickProduct: CoreDataSyncRecordIdentity {}
nonisolated extension FlickCreationModel: CoreDataSyncRecordIdentity {}
nonisolated extension MediaAsset: CoreDataSyncRecordIdentity {}
nonisolated extension CreativeTemplate: CoreDataSyncRecordIdentity {}
nonisolated extension SlideshowDraft: CoreDataSyncRecordIdentity {}
nonisolated extension Slide: CoreDataSyncRecordIdentity {}
nonisolated extension ContentAutomation: CoreDataSyncRecordIdentity {}
nonisolated extension AutomationPostProgress: CoreDataSyncRecordIdentity {}
nonisolated extension PublishingJob: CoreDataSyncRecordIdentity {}
nonisolated extension PublishedPost: CoreDataSyncRecordIdentity {}

nonisolated private extension Array where Element: CoreDataSyncRecordIdentity {
    func deduplicatedByLatestUpdate() -> [Element] {
        var indicesByID: [UUID: Int] = [:]
        var records: [Element] = []

        for record in self {
            if let existingIndex = indicesByID[record.id] {
                if record.updatedAt > records[existingIndex].updatedAt {
                    records[existingIndex] = record
                }
            } else {
                indicesByID[record.id] = records.count
                records.append(record)
            }
        }

        return records
    }

    func mergingLatestUpdates(_ records: [Element]) -> [Element] {
        var merged = deduplicatedByLatestUpdate()
        var indicesByID = Dictionary(uniqueKeysWithValues: merged.indices.map { (merged[$0].id, $0) })

        for record in records.deduplicatedByLatestUpdate() {
            if let index = indicesByID[record.id] {
                if record.updatedAt > merged[index].updatedAt {
                    merged[index] = record
                }
            } else {
                indicesByID[record.id] = merged.count
                merged.append(record)
            }
        }

        return merged
    }
}

nonisolated private extension Array where Element == OverviewDeletion {
    func deduplicatedByLatestDeletion() -> [OverviewDeletion] {
        var indicesByKey: [OverviewRecordKey: Int] = [:]
        var deletions: [OverviewDeletion] = []

        for deletion in self {
            let key = OverviewRecordKey(kind: deletion.kind, id: deletion.id)
            if let index = indicesByKey[key] {
                if deletion.deletedAt > deletions[index].deletedAt {
                    deletions[index] = deletion
                }
            } else {
                indicesByKey[key] = deletions.count
                deletions.append(deletion)
            }
        }

        return deletions
    }
}

nonisolated private enum AssetKey {
    static let checksum = "checksum"
    static let createdAt = "createdAt"
    static let duration = "duration"
    static let fileSize = "fileSize"
    static let height = "height"
    static let id = "id"
    static let localFilePath = "localFilePath"
    static let mediaType = "mediaType"
    static let productIDsJSON = "productIDsJSON"
    static let publicURL = "publicURL"
    static let signedURLExpiration = "signedURLExpiration"
    static let source = "source"
    static let storageBucket = "storageBucket"
    static let storagePath = "storagePath"
    static let trendTagIDsJSON = "trendTagIDsJSON"
    static let updatedAt = "updatedAt"
    static let width = "width"
}

nonisolated private enum AuditEventKey {
    static let createdAt = "createdAt"
    static let eventType = "eventType"
    static let id = "id"
    static let metadataJSON = "metadataJSON"
    static let summary = "summary"
    static let deletionEventTypePrefix = "deletion-tombstone.v1."

    static func deletionEventType(for kind: OverviewRecordKind) -> String {
        deletionEventTypePrefix + kind.rawValue
    }
}

nonisolated private enum ConnectedAccountKey {
    static let authorizationSource = "authorizationSource"
    static let avatarURL = "avatarURL"
    static let createdAt = "createdAt"
    static let defaultPrivacyLevel = "defaultPrivacyLevel"
    static let displayName = "displayName"
    static let id = "id"
    static let isPublishingEnabled = "isPublishingEnabled"
    static let lastValidatedAt = "lastValidatedAt"
    static let platform = "platform"
    static let platformUserID = "platformUserID"
    static let scopesJSON = "scopesJSON"
    static let status = "status"
    static let tokenStatus = "tokenStatus"
    static let updatedAt = "updatedAt"
}

nonisolated private enum ProductKey {
    static let createdAt = "createdAt"
    static let id = "id"
    static let name = "name"
    static let summary = "summary"
    static let updatedAt = "updatedAt"
}

nonisolated private enum CreationModelKey {
    static let createdAt = "createdAt"
    static let id = "id"
    static let metadataJSON = "metadataJSON"
    static let name = "name"
    static let updatedAt = "updatedAt"
}

nonisolated private enum TemplateKey {
    static let createdAt = "createdAt"
    static let defaultTextRules = "defaultTextRules"
    static let id = "id"
    static let name = "name"
    static let platform = "platform"
    static let slideCount = "slideCount"
    static let analysisSchemaVersion = "analysisSchemaVersion"
    static let sourceTemplateFingerprint = "sourceTemplateFingerprint"
    static let sourceTemplateID = "sourceTemplateID"
    static let styleJSON = "styleJSON"
    static let summary = "summary"
    static let tagIDsJSON = "tagIDsJSON"
    static let updatedAt = "updatedAt"
}

nonisolated private enum DraftKey {
    static let accountSelectionsJSON = "accountSelectionsJSON"
    static let automationID = "automationID"
    static let brief = "brief"
    static let caption = "caption"
    static let creationModelID = "creationModelID"
    static let creationModelJSON = "creationModelJSON"
    static let createdAt = "createdAt"
    static let exportedImageAssetIDsJSON = "exportedImageAssetIDsJSON"
    static let globalVisualMotif = "globalVisualMotif"
    static let goal = "goal"
    static let hashtagsJSON = "hashtagsJSON"
    static let id = "id"
    static let imageVibe = "imageVibe"
    static let narrativeArcJSON = "narrativeArcJSON"
    static let planSummary = "planSummary"
    static let selectedSongsJSON = "selectedSongsJSON"
    static let slideIDsJSON = "slideIDsJSON"
    static let status = "status"
    static let targetPlatformsJSON = "targetPlatformsJSON"
    static let templateID = "templateID"
    static let tikTokSettingsJSON = "tikTokSettingsJSON"
    static let youtubeSettingsJSON = "youtubeSettingsJSON"
    static let title = "title"
    static let tone = "tone"
    static let topic = "topic"
    static let audience = "audience"
    static let updatedAt = "updatedAt"
}

nonisolated private enum SlideKey {
    static let createdAt = "createdAt"
    static let draftID = "draftID"
    static let generationErrorMessage = "generationErrorMessage"
    static let generationStatus = "generationStatus"
    static let id = "id"
    static let imageAssetID = "imageAssetID"
    static let index = "index"
    static let prompt = "prompt"
    static let promptVersion = "promptVersion"
    static let selectedVisualSummary = "selectedVisualSummary"
    static let text = "text"
    static let textPosition = "textPosition"
    static let textStyleJSON = "textStyleJSON"
    static let updatedAt = "updatedAt"
}

nonisolated private enum AutomationKey {
    static let accountSelectionsJSON = "accountSelectionsJSON"
    static let consecutiveFailureCount = "consecutiveFailureCount"
    static let creationModelID = "creationModelID"
    static let creationModelJSON = "creationModelJSON"
    static let createdAt = "createdAt"
    static let id = "id"
    static let imageVibe = "imageVibe"
    static let lastErrorMessage = "lastErrorMessage"
    static let lastRunAt = "lastRunAt"
    static let name = "name"
    static let nextScheduledAt = "nextScheduledAt"
    static let productID = "productID"
    static let productImageAssetIDsJSON = "productImageAssetIDsJSON"
    static let scheduleJSON = "scheduleJSON"
    static let status = "status"
    static let targetPlatformsJSON = "targetPlatformsJSON"
    static let templateIDsJSON = "templateIDsJSON"
    static let templateNicheIDsJSON = "templateNicheIDsJSON"
    static let tikTokSettingsJSON = "tikTokSettingsJSON"
    static let youtubeSettingsJSON = "youtubeSettingsJSON"
    static let updatedAt = "updatedAt"
}

nonisolated private enum PublishingJobKey {
    static let accountID = "accountID"
    static let attemptCount = "attemptCount"
    static let automationID = "automationID"
    static let createdAt = "createdAt"
    static let draftID = "draftID"
    static let id = "id"
    static let lastAttemptAt = "lastAttemptAt"
    static let lastErrorJSON = "lastErrorJSON"
    static let platform = "platform"
    static let platformPublishID = "platformPublishID"
    static let publishMode = "publishMode"
    static let status = "status"
    static let updatedAt = "updatedAt"
}

nonisolated private enum PublishedPostKey {
    static let accountID = "accountID"
    static let automationID = "automationID"
    static let caption = "caption"
    static let createdAt = "createdAt"
    static let draftID = "draftID"
    static let id = "id"
    static let platform = "platform"
    static let platformPostID = "platformPostID"
    static let platformURL = "platformURL"
    static let publishedAt = "publishedAt"
    static let templateID = "templateID"
    static let trendTagIDsJSON = "trendTagIDsJSON"
    static let updatedAt = "updatedAt"
}

nonisolated private enum WorkflowStateKey {
    static let id = "id"
    static let key = "key"
    static let updatedAt = "updatedAt"
    static let valueJSON = "valueJSON"
}

nonisolated private enum WorkflowStateValueKey {
    static let automationPostProgresses = "automation-post-progresses"
    static let macRunnerHeartbeat = "mac-runner-heartbeat"
}

nonisolated private extension MediaAsset {
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

        let productIDStrings: [String] = managedObject.decodedJSON([String].self, forKey: AssetKey.productIDsJSON) ?? []

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
            productIDs: productIDStrings.compactMap(UUID.init(uuidString:)),
            createdAt: managedObject.value(forKey: AssetKey.createdAt) as? Date ?? Date(),
            updatedAt: managedObject.value(forKey: AssetKey.updatedAt) as? Date ?? Date()
        )
    }
}

nonisolated private extension FlickProduct {
    init?(managedObject: NSManagedObject) {
        guard
            let id = managedObject.value(forKey: ProductKey.id) as? UUID,
            let name = managedObject.value(forKey: ProductKey.name) as? String
        else {
            return nil
        }

        self.init(
            id: id,
            name: name,
            summary: managedObject.value(forKey: ProductKey.summary) as? String ?? "",
            createdAt: managedObject.value(forKey: ProductKey.createdAt) as? Date ?? Date(),
            updatedAt: managedObject.value(forKey: ProductKey.updatedAt) as? Date ?? Date()
        )
    }
}

nonisolated private extension FlickCreationModel {
    init?(managedObject: NSManagedObject) {
        guard
            let id = managedObject.value(forKey: CreationModelKey.id) as? UUID,
            let name = managedObject.value(forKey: CreationModelKey.name) as? String
        else {
            return nil
        }

        self.init(
            id: id,
            name: name,
            metadata: managedObject.decodedJSON(CreationModelMetadata.self, forKey: CreationModelKey.metadataJSON) ?? CreationModelMetadata(),
            createdAt: managedObject.value(forKey: CreationModelKey.createdAt) as? Date ?? Date(),
            updatedAt: managedObject.value(forKey: CreationModelKey.updatedAt) as? Date ?? Date()
        )
    }
}

nonisolated private extension ConnectedAccount {
    init?(managedObject: NSManagedObject) {
        guard
            let id = managedObject.value(forKey: ConnectedAccountKey.id) as? UUID,
            let platformRawValue = managedObject.value(forKey: ConnectedAccountKey.platform) as? String,
            let platform = SocialPlatform(rawValue: platformRawValue),
            let displayName = managedObject.value(forKey: ConnectedAccountKey.displayName) as? String,
            let platformUserID = managedObject.value(forKey: ConnectedAccountKey.platformUserID) as? String,
            let statusRawValue = managedObject.value(forKey: ConnectedAccountKey.status) as? String,
            let status = AccountStatus(rawValue: statusRawValue),
            let authorizationSourceRawValue = managedObject.value(forKey: ConnectedAccountKey.authorizationSource) as? String,
            let authorizationSource = AccountAuthorizationSource(rawValue: authorizationSourceRawValue),
            let tokenStatusRawValue = managedObject.value(forKey: ConnectedAccountKey.tokenStatus) as? String,
            let tokenStatus = OAuthTokenStatus(rawValue: tokenStatusRawValue)
        else {
            return nil
        }

        self.init(
            id: id,
            platform: platform,
            displayName: displayName,
            platformUserID: platformUserID,
            avatarURL: managedObject.value(forKey: ConnectedAccountKey.avatarURL) as? URL,
            scopes: managedObject.decodedJSON([String].self, forKey: ConnectedAccountKey.scopesJSON) ?? [],
            status: status,
            authorizationSource: authorizationSource,
            tokenStatus: tokenStatus,
            isPublishingEnabled: managedObject.boolValue(forKey: ConnectedAccountKey.isPublishingEnabled, defaultValue: false),
            defaultPrivacyLevel: managedObject.value(forKey: ConnectedAccountKey.defaultPrivacyLevel) as? String ?? "Platform default",
            lastValidatedAt: managedObject.value(forKey: ConnectedAccountKey.lastValidatedAt) as? Date,
            createdAt: managedObject.value(forKey: ConnectedAccountKey.createdAt) as? Date ?? Date(),
            updatedAt: managedObject.value(forKey: ConnectedAccountKey.updatedAt) as? Date ?? Date()
        )
    }
}

nonisolated private extension CreativeTemplate {
    init?(managedObject: NSManagedObject) {
        guard
            let id = managedObject.value(forKey: TemplateKey.id) as? UUID,
            let name = managedObject.value(forKey: TemplateKey.name) as? String,
            let platformRawValue = managedObject.value(forKey: TemplateKey.platform) as? String,
            let platform = SocialPlatform(rawValue: platformRawValue)
        else {
            return nil
        }

        self.init(
            id: id,
            name: name,
            description: managedObject.value(forKey: TemplateKey.summary) as? String ?? "",
            platform: platform,
            slideCount: managedObject.integerValue(forKey: TemplateKey.slideCount),
            styleJSON: managedObject.value(forKey: TemplateKey.styleJSON) as? String ?? "{}",
            defaultTextRules: managedObject.value(forKey: TemplateKey.defaultTextRules) as? String ?? "",
            sourceTemplateID: managedObject.value(forKey: TemplateKey.sourceTemplateID) as? String,
            sourceTemplateFingerprint: managedObject.value(forKey: TemplateKey.sourceTemplateFingerprint) as? String,
            analysisSchemaVersion: (managedObject.value(forKey: TemplateKey.analysisSchemaVersion) as? NSNumber)?.intValue
                ?? managedObject.value(forKey: TemplateKey.analysisSchemaVersion) as? Int,
            tags: [],
            createdAt: managedObject.value(forKey: TemplateKey.createdAt) as? Date ?? Date(),
            updatedAt: managedObject.value(forKey: TemplateKey.updatedAt) as? Date ?? Date()
        )
    }
}

nonisolated private extension SlideshowDraft {
    init?(managedObject: NSManagedObject, slides: [Slide]) {
        guard
            let id = managedObject.value(forKey: DraftKey.id) as? UUID,
            let title = managedObject.value(forKey: DraftKey.title) as? String,
            let statusRawValue = managedObject.value(forKey: DraftKey.status) as? String,
            let status = SlideshowDraftStatus(rawValue: statusRawValue)
        else {
            return nil
        }

        let targetPlatformsRawValues: [String] = managedObject.decodedJSON([String].self, forKey: DraftKey.targetPlatformsJSON) ?? []
        let targetPlatforms = targetPlatformsRawValues.compactMap(SocialPlatform.init(rawValue:))
        let accountSelections = managedObject.decodedJSON([PlatformAccountSelection].self, forKey: DraftKey.accountSelectionsJSON)?
            .normalizedUniqueSelections()
            ?? []
        let exportedIDs: [String] = managedObject.decodedJSON([String].self, forKey: DraftKey.exportedImageAssetIDsJSON) ?? []
        let tikTokSettings = managedObject.decodedJSON(DraftTikTokSettings.self, forKey: DraftKey.tikTokSettingsJSON)
        let youtubeSettings = managedObject.decodedJSON(DraftYouTubeSettings.self, forKey: DraftKey.youtubeSettingsJSON)
        let selectedSongs = managedObject.decodedJSON([SelectedSong].self, forKey: DraftKey.selectedSongsJSON) ?? []

        self.init(
            id: id,
            automationID: managedObject.value(forKey: DraftKey.automationID) as? UUID,
            title: title,
            templateID: managedObject.value(forKey: DraftKey.templateID) as? UUID,
            creationModel: managedObject.decodedJSON(SlideshowCreationModelReference.self, forKey: DraftKey.creationModelJSON),
            imageVibe: SlideshowImageVibe(rawValue: managedObject.value(forKey: DraftKey.imageVibe) as? String ?? "")
                ?? .defaultValue,
            brief: managedObject.value(forKey: DraftKey.brief) as? String ?? "",
            topic: managedObject.value(forKey: DraftKey.topic) as? String ?? "",
            audience: managedObject.value(forKey: DraftKey.audience) as? String ?? "",
            goal: managedObject.value(forKey: DraftKey.goal) as? String ?? "",
            tone: managedObject.value(forKey: DraftKey.tone) as? String ?? "",
            narrativeArc: managedObject.decodedJSON([String].self, forKey: DraftKey.narrativeArcJSON) ?? [],
            globalVisualMotif: managedObject.value(forKey: DraftKey.globalVisualMotif) as? String ?? "",
            planSummary: managedObject.value(forKey: DraftKey.planSummary) as? String ?? "",
            slides: slides.sorted { $0.index < $1.index },
            caption: managedObject.value(forKey: DraftKey.caption) as? String ?? "",
            hashtags: managedObject.decodedJSON([String].self, forKey: DraftKey.hashtagsJSON) ?? [],
            targetPlatforms: targetPlatforms.isEmpty ? [.tiktok] : targetPlatforms,
            accountSelections: accountSelections,
            tikTokSettings: tikTokSettings,
            youtubeSettings: youtubeSettings,
            selectedSongs: selectedSongs,
            status: status,
            exportedImageAssetIDs: exportedIDs.compactMap(UUID.init(uuidString:)),
            createdAt: managedObject.value(forKey: DraftKey.createdAt) as? Date ?? Date(),
            updatedAt: managedObject.value(forKey: DraftKey.updatedAt) as? Date ?? Date()
        )
    }
}

nonisolated private extension Slide {
    init?(managedObject: NSManagedObject) {
        guard
            let id = managedObject.value(forKey: SlideKey.id) as? UUID,
            let textPositionRawValue = managedObject.value(forKey: SlideKey.textPosition) as? String,
            let textPosition = TextPosition(rawValue: textPositionRawValue),
            let textStyle = managedObject.decodedJSON(SlideTextStyle.self, forKey: SlideKey.textStyleJSON)
        else {
            return nil
        }

        let statusRawValue = managedObject.value(forKey: SlideKey.generationStatus) as? String
        self.init(
            id: id,
            index: managedObject.integerValue(forKey: SlideKey.index),
            imageAssetID: managedObject.value(forKey: SlideKey.imageAssetID) as? UUID,
            prompt: managedObject.value(forKey: SlideKey.prompt) as? String ?? "",
            text: managedObject.value(forKey: SlideKey.text) as? String ?? "",
            textPosition: textPosition,
            textStyle: textStyle,
            selectedVisualSummary: managedObject.value(forKey: SlideKey.selectedVisualSummary) as? String ?? "",
            generationStatus: statusRawValue.flatMap(SlideGenerationStatus.init(rawValue:)) ?? .notStarted,
            generationErrorMessage: managedObject.value(forKey: SlideKey.generationErrorMessage) as? String,
            promptVersion: max(1, managedObject.integerValue(forKey: SlideKey.promptVersion)),
            createdAt: managedObject.value(forKey: SlideKey.createdAt) as? Date ?? Date(),
            updatedAt: managedObject.value(forKey: SlideKey.updatedAt) as? Date ?? Date()
        )
    }
}

nonisolated private extension ContentAutomation {
    init?(managedObject: NSManagedObject) {
        guard
            let id = managedObject.value(forKey: AutomationKey.id) as? UUID,
            let schedule = managedObject.decodedJSON(AutomationSchedule.self, forKey: AutomationKey.scheduleJSON),
            let tikTokSettings = managedObject.decodedJSON(DraftTikTokSettings.self, forKey: AutomationKey.tikTokSettingsJSON)
        else {
            return nil
        }

        let templateIDs = managedObject.decodedJSON([String].self, forKey: AutomationKey.templateIDsJSON) ?? []
        let templateNicheIDs = managedObject.decodedJSON([String].self, forKey: AutomationKey.templateNicheIDsJSON) ?? []
        let productImageAssetIDStrings = managedObject.decodedJSON([String].self, forKey: AutomationKey.productImageAssetIDsJSON) ?? []
        let targetPlatformRawValues = managedObject.decodedJSON([String].self, forKey: AutomationKey.targetPlatformsJSON) ?? []
        let targetPlatforms = targetPlatformRawValues.compactMap(SocialPlatform.init(rawValue:))
        let accountSelections = managedObject.decodedJSON([PlatformAccountSelection].self, forKey: AutomationKey.accountSelectionsJSON)?
            .normalizedUniqueSelections()
            ?? []
        let youtubeSettings = managedObject.decodedJSON(DraftYouTubeSettings.self, forKey: AutomationKey.youtubeSettingsJSON)
            ?? DraftYouTubeSettings()
        let statusRawValue = managedObject.value(forKey: AutomationKey.status) as? String

        self.init(
            id: id,
            name: managedObject.value(forKey: AutomationKey.name) as? String ?? "",
            templateIDs: templateIDs,
            templateNicheIDs: templateNicheIDs,
            productID: managedObject.value(forKey: AutomationKey.productID) as? UUID,
            productImageAssetIDs: productImageAssetIDStrings.compactMap(UUID.init(uuidString:)),
            creationModel: managedObject.decodedJSON(SlideshowCreationModelReference.self, forKey: AutomationKey.creationModelJSON),
            imageVibe: SlideshowImageVibe(rawValue: managedObject.value(forKey: AutomationKey.imageVibe) as? String ?? "")
                ?? .defaultValue,
            schedule: schedule,
            tikTokSettings: tikTokSettings,
            youtubeSettings: youtubeSettings,
            targetPlatforms: targetPlatforms.isEmpty ? [.tiktok] : targetPlatforms,
            accountSelections: accountSelections,
            status: statusRawValue.flatMap(ContentAutomationStatus.init(rawValue:)) ?? .active,
            nextScheduledAt: managedObject.value(forKey: AutomationKey.nextScheduledAt) as? Date,
            lastRunAt: managedObject.value(forKey: AutomationKey.lastRunAt) as? Date,
            lastErrorMessage: managedObject.value(forKey: AutomationKey.lastErrorMessage) as? String,
            consecutiveFailureCount: managedObject.integerValue(forKey: AutomationKey.consecutiveFailureCount),
            createdAt: managedObject.value(forKey: AutomationKey.createdAt) as? Date ?? Date(),
            updatedAt: managedObject.value(forKey: AutomationKey.updatedAt) as? Date ?? Date()
        )
    }
}

nonisolated private extension PublishingJob {
    init?(managedObject: NSManagedObject) {
        guard
            let id = managedObject.value(forKey: PublishingJobKey.id) as? UUID,
            let platformRawValue = managedObject.value(forKey: PublishingJobKey.platform) as? String,
            let platform = SocialPlatform(rawValue: platformRawValue),
            let accountID = managedObject.value(forKey: PublishingJobKey.accountID) as? UUID,
            let draftID = managedObject.value(forKey: PublishingJobKey.draftID) as? UUID,
            let statusRawValue = managedObject.value(forKey: PublishingJobKey.status) as? String,
            let status = PublishingJobStatus(rawValue: statusRawValue),
            let publishModeRawValue = managedObject.value(forKey: PublishingJobKey.publishMode) as? String,
            let publishMode = PublishMode(rawValue: publishModeRawValue)
        else {
            return nil
        }

        self.init(
            id: id,
            platform: platform,
            accountID: accountID,
            automationID: managedObject.value(forKey: PublishingJobKey.automationID) as? UUID,
            draftID: draftID,
            status: status,
            publishMode: publishMode,
            attemptCount: managedObject.integerValue(forKey: PublishingJobKey.attemptCount),
            lastAttemptAt: managedObject.value(forKey: PublishingJobKey.lastAttemptAt) as? Date,
            lastError: managedObject.decodedJSON(PlatformFailure.self, forKey: PublishingJobKey.lastErrorJSON),
            platformPublishID: managedObject.value(forKey: PublishingJobKey.platformPublishID) as? String,
            createdAt: managedObject.value(forKey: PublishingJobKey.createdAt) as? Date ?? Date(),
            updatedAt: managedObject.value(forKey: PublishingJobKey.updatedAt) as? Date ?? Date()
        )
    }
}

nonisolated private extension PublishedPost {
    init?(managedObject: NSManagedObject) {
        guard
            let id = managedObject.value(forKey: PublishedPostKey.id) as? UUID,
            let platformRawValue = managedObject.value(forKey: PublishedPostKey.platform) as? String,
            let platform = SocialPlatform(rawValue: platformRawValue),
            let accountID = managedObject.value(forKey: PublishedPostKey.accountID) as? UUID,
            let platformPostID = managedObject.value(forKey: PublishedPostKey.platformPostID) as? String,
            let draftID = managedObject.value(forKey: PublishedPostKey.draftID) as? UUID
        else {
            return nil
        }

        self.init(
            id: id,
            platform: platform,
            accountID: accountID,
            automationID: managedObject.value(forKey: PublishedPostKey.automationID) as? UUID,
            platformPostID: platformPostID,
            platformURL: managedObject.value(forKey: PublishedPostKey.platformURL) as? URL,
            publishedAt: managedObject.value(forKey: PublishedPostKey.publishedAt) as? Date ?? Date(),
            draftID: draftID,
            templateID: managedObject.value(forKey: PublishedPostKey.templateID) as? UUID,
            trendTags: [],
            caption: managedObject.value(forKey: PublishedPostKey.caption) as? String ?? "",
            createdAt: managedObject.value(forKey: PublishedPostKey.createdAt) as? Date ?? Date(),
            updatedAt: managedObject.value(forKey: PublishedPostKey.updatedAt) as? Date ?? Date()
        )
    }
}

nonisolated private extension NSManagedObject {
    @discardableResult
    func setValueIfChanged(_ value: Any?, forKey key: String) -> Bool {
        let currentValue = self.value(forKey: key)

        switch (currentValue, value) {
        case (nil, nil):
            return false
        case let (current as NSObject, proposed as NSObject) where current.isEqual(proposed):
            return false
        default:
            setValue(value, forKey: key)
            return true
        }
    }

    @discardableResult
    func setValueIfChanged<T: Encodable>(_ value: T, asJSONForKey key: String) -> Bool {
        guard
            let data = try? JSONEncoder.flick.encode(value),
            let json = String(data: data, encoding: .utf8)
        else {
            return false
        }

        if let currentJSON = self.value(forKey: key) as? String,
           (currentJSON == json || Self.jsonObjectsAreEqual(currentJSON, json)) {
            return false
        }

        setValue(json, forKey: key)
        return true
    }

    func uuidValue(forKey key: String) -> UUID? {
        value(forKey: key) as? UUID
    }

    func integerValue(forKey key: String) -> Int {
        (value(forKey: key) as? NSNumber)?.intValue ?? 0
    }

    func boolValue(forKey key: String, defaultValue: Bool) -> Bool {
        (value(forKey: key) as? NSNumber)?.boolValue ?? defaultValue
    }

    func int64Value(forKey key: String) -> Int64? {
        (value(forKey: key) as? NSNumber)?.int64Value
    }

    func doubleValue(forKey key: String) -> Double? {
        (value(forKey: key) as? NSNumber)?.doubleValue
    }

    func decodedJSON<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        _ = type
        guard
            let json = value(forKey: key) as? String,
            let data = json.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder.flick.decode(T.self, from: data)
    }

    private static func jsonObjectsAreEqual(_ lhs: String, _ rhs: String) -> Bool {
        guard
            let lhsData = lhs.data(using: .utf8),
            let rhsData = rhs.data(using: .utf8),
            let lhsObject = try? JSONSerialization.jsonObject(with: lhsData, options: [.fragmentsAllowed]),
            let rhsObject = try? JSONSerialization.jsonObject(with: rhsData, options: [.fragmentsAllowed]),
            let lhsObject = lhsObject as? NSObject,
            let rhsObject = rhsObject as? NSObject
        else {
            return lhs == rhs
        }

        return lhsObject.isEqual(rhsObject)
    }
}
