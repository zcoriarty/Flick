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
        state.accounts = try fetchConnectedAccounts()
        state.products = try fetchProducts()
        state.assets = try fetchAssets()
        state.templates = try fetchTemplates()
        state.drafts = try fetchDrafts(slidesByDraftID: try fetchSlidesByDraftID())
        state.automations = try fetchAutomations()
        state.automationPostProgresses = try fetchAutomationPostProgresses()
        state.publishingJobs = try fetchPublishingJobs()
        state.publishedPosts = try fetchPublishedPosts()
        state.refreshDerivedState()
        state.dashboard.connectedAccounts = state.accounts
        state.dashboard.syncHealth.iCloudAvailable = await cloudAvailability()
        return state
    }

    func saveOverview(_ state: FlickOverviewState) async throws {
        try syncConnectedAccounts(state.accounts)
        try syncProducts(state.products)
        try syncAssets(state.assets)
        try syncTemplates(state.templates)
        try syncDrafts(state.drafts)
        try syncSlides(in: state.drafts)
        try syncAutomations(state.automations)
        try syncAutomationPostProgresses(state.automationPostProgresses)
        try syncPublishingJobs(state.publishingJobs)
        try syncPublishedPosts(state.publishedPosts)
        try saveIfNeeded()
    }

    func upsertConnectedAccount(_ account: ConnectedAccount) async throws {
        let object = try fetchConnectedAccount(id: account.id) ?? insertConnectedAccountObject()
        apply(account, to: object)
        try saveIfNeeded()
    }

    func deleteConnectedAccount(id: UUID) async throws {
        guard let object = try fetchConnectedAccount(id: id) else { return }
        context.delete(object)
        try saveIfNeeded()
    }

    func upsertProduct(_ product: FlickProduct) async throws {
        let object = try fetchProduct(id: product.id) ?? insertProductObject()
        apply(product, to: object)
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

    private func syncConnectedAccounts(_ accounts: [ConnectedAccount]) throws {
        let existingAccounts = try context.fetch(connectedAccountFetchRequest())
        var existingByID = Dictionary(uniqueKeysWithValues: existingAccounts.compactMap { object -> (UUID, NSManagedObject)? in
            guard let id = object.value(forKey: ConnectedAccountKey.id) as? UUID else { return nil }
            return (id, object)
        })
        let stateIDs = Set(accounts.map(\.id))

        for account in accounts {
            let object = existingByID.removeValue(forKey: account.id) ?? insertConnectedAccountObject()
            apply(account, to: object)
        }

        for (id, object) in existingByID where !stateIDs.contains(id) {
            context.delete(object)
        }
    }

    private func syncProducts(_ products: [FlickProduct]) throws {
        let existingProducts = try context.fetch(productFetchRequest())
        var existingByID = Dictionary(uniqueKeysWithValues: existingProducts.compactMap { object -> (UUID, NSManagedObject)? in
            guard let id = object.value(forKey: ProductKey.id) as? UUID else { return nil }
            return (id, object)
        })
        let stateIDs = Set(products.map(\.id))

        for product in products {
            let object = existingByID.removeValue(forKey: product.id) ?? insertProductObject()
            apply(product, to: object)
        }

        for (id, object) in existingByID where !stateIDs.contains(id) {
            context.delete(object)
        }
    }

    private func syncAssets(_ assets: [MediaAsset]) throws {
        let existingAssets = try context.fetch(assetFetchRequest())
        var existingByID = Dictionary(uniqueKeysWithValues: existingAssets.compactMap { object -> (UUID, NSManagedObject)? in
            guard let id = object.value(forKey: AssetKey.id) as? UUID else { return nil }
            return (id, object)
        })
        let stateIDs = Set(assets.map(\.id))

        for asset in assets {
            let object = existingByID.removeValue(forKey: asset.id) ?? insertAssetObject()
            apply(asset, to: object)
        }

        for (id, object) in existingByID where !stateIDs.contains(id) {
            context.delete(object)
        }
    }

    private func syncTemplates(_ templates: [CreativeTemplate]) throws {
        let existingTemplates = try context.fetch(templateFetchRequest())
        var existingByID = Dictionary(uniqueKeysWithValues: existingTemplates.compactMap { object -> (UUID, NSManagedObject)? in
            guard let id = object.value(forKey: TemplateKey.id) as? UUID else { return nil }
            return (id, object)
        })
        let stateIDs = Set(templates.map(\.id))

        for template in templates {
            let object = existingByID.removeValue(forKey: template.id) ?? insertTemplateObject()
            apply(template, to: object)
        }

        for (id, object) in existingByID where !stateIDs.contains(id) {
            context.delete(object)
        }
    }

    private func syncDrafts(_ drafts: [SlideshowDraft]) throws {
        let existingDrafts = try context.fetch(draftFetchRequest())
        var existingByID = Dictionary(uniqueKeysWithValues: existingDrafts.compactMap { object -> (UUID, NSManagedObject)? in
            guard let id = object.value(forKey: DraftKey.id) as? UUID else { return nil }
            return (id, object)
        })
        let stateIDs = Set(drafts.map(\.id))

        for draft in drafts {
            let object = existingByID.removeValue(forKey: draft.id) ?? insertDraftObject()
            apply(draft, to: object)
        }

        for (id, object) in existingByID where !stateIDs.contains(id) {
            context.delete(object)
        }
    }

    private func syncSlides(in drafts: [SlideshowDraft]) throws {
        let existingSlides = try context.fetch(slideFetchRequest())
        var existingByID = Dictionary(uniqueKeysWithValues: existingSlides.compactMap { object -> (UUID, NSManagedObject)? in
            guard let id = object.value(forKey: SlideKey.id) as? UUID else { return nil }
            return (id, object)
        })
        let draftSlides = drafts.flatMap { draft in
            draft.slides.map { (draft.id, $0) }
        }
        let stateIDs = Set(draftSlides.map(\.1.id))

        for (draftID, slide) in draftSlides {
            let object = existingByID.removeValue(forKey: slide.id) ?? insertSlideObject()
            apply(slide, draftID: draftID, to: object)
        }

        for (id, object) in existingByID where !stateIDs.contains(id) {
            context.delete(object)
        }
    }

    private func syncAutomations(_ automations: [ContentAutomation]) throws {
        let existingAutomations = try context.fetch(automationFetchRequest())
        var existingByID = Dictionary(uniqueKeysWithValues: existingAutomations.compactMap { object -> (UUID, NSManagedObject)? in
            guard let id = object.value(forKey: AutomationKey.id) as? UUID else { return nil }
            return (id, object)
        })
        let stateIDs = Set(automations.map(\.id))

        for automation in automations {
            let object = existingByID.removeValue(forKey: automation.id) ?? insertAutomationObject()
            apply(automation, to: object)
        }

        for (id, object) in existingByID where !stateIDs.contains(id) {
            context.delete(object)
        }
    }

    private func syncPublishingJobs(_ jobs: [PublishingJob]) throws {
        let existingJobs = try context.fetch(publishingJobFetchRequest())
        var existingByID = Dictionary(uniqueKeysWithValues: existingJobs.compactMap { object -> (UUID, NSManagedObject)? in
            guard let id = object.value(forKey: PublishingJobKey.id) as? UUID else { return nil }
            return (id, object)
        })
        let stateIDs = Set(jobs.map(\.id))

        for job in jobs {
            let object = existingByID.removeValue(forKey: job.id) ?? insertPublishingJobObject()
            apply(job, to: object)
        }

        for (id, object) in existingByID where !stateIDs.contains(id) {
            context.delete(object)
        }
    }

    private func syncAutomationPostProgresses(_ progresses: [AutomationPostProgress]) throws {
        let objects = try fetchWorkflowStateObjects(key: WorkflowStateValueKey.automationPostProgresses)

        if progresses.isEmpty {
            objects.forEach { context.delete($0) }
            return
        }

        let object = objects.first ?? insertWorkflowStateObject()
        objects.dropFirst().forEach { context.delete($0) }
        object.setValue(object.value(forKey: WorkflowStateKey.id) as? UUID ?? UUID(), forKey: WorkflowStateKey.id)
        object.setValue(WorkflowStateValueKey.automationPostProgresses, forKey: WorkflowStateKey.key)
        object.setValue(Date(), forKey: WorkflowStateKey.updatedAt)
        object.setValue(progresses, asJSONForKey: WorkflowStateKey.valueJSON)
    }

    private func syncPublishedPosts(_ posts: [PublishedPost]) throws {
        let existingPosts = try context.fetch(publishedPostFetchRequest())
        var existingByID = Dictionary(uniqueKeysWithValues: existingPosts.compactMap { object -> (UUID, NSManagedObject)? in
            guard let id = object.value(forKey: PublishedPostKey.id) as? UUID else { return nil }
            return (id, object)
        })
        let stateIDs = Set(posts.map(\.id))

        for post in posts {
            let object = existingByID.removeValue(forKey: post.id) ?? insertPublishedPostObject()
            apply(post, to: object)
        }

        for (id, object) in existingByID where !stateIDs.contains(id) {
            context.delete(object)
        }
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

    private func fetchProduct(id: UUID) throws -> NSManagedObject? {
        let request = productFetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", ProductKey.id, id as NSUUID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func fetchAsset(id: UUID) throws -> NSManagedObject? {
        let request = assetFetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", AssetKey.id, id as NSUUID)
        request.fetchLimit = 1
        return try context.fetch(request).first
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

    private func fetchSlidesByDraftID() throws -> [UUID: [Slide]] {
        let request = slideFetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: SlideKey.index, ascending: true)
        ]
        return try context.fetch(request).reduce(into: [UUID: [Slide]]()) { result, object in
            guard
                let draftID = object.value(forKey: SlideKey.draftID) as? UUID,
                let slide = Slide(managedObject: object)
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
        guard let object = try fetchWorkflowStateObjects(key: WorkflowStateValueKey.automationPostProgresses).first else {
            return []
        }

        return object.decodedJSON([AutomationPostProgress].self, forKey: WorkflowStateKey.valueJSON) ?? []
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
        let request = connectedAccountFetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", ConnectedAccountKey.id, id as NSUUID)
        request.fetchLimit = 1
        return try context.fetch(request).first
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

    private func insertConnectedAccountObject() -> NSManagedObject {
        NSEntityDescription.insertNewObject(forEntityName: "CDConnectedAccount", into: context)
    }

    private func apply(_ account: ConnectedAccount, to object: NSManagedObject) {
        object.setValue(account.id, forKey: ConnectedAccountKey.id)
        object.setValue(account.platform.rawValue, forKey: ConnectedAccountKey.platform)
        object.setValue(account.displayName, forKey: ConnectedAccountKey.displayName)
        object.setValue(account.platformUserID, forKey: ConnectedAccountKey.platformUserID)
        object.setValue(account.avatarURL, forKey: ConnectedAccountKey.avatarURL)
        object.setValue(account.scopes, asJSONForKey: ConnectedAccountKey.scopesJSON)
        object.setValue(account.status.rawValue, forKey: ConnectedAccountKey.status)
        object.setValue(account.authorizationSource.rawValue, forKey: ConnectedAccountKey.authorizationSource)
        object.setValue(account.tokenStatus.rawValue, forKey: ConnectedAccountKey.tokenStatus)
        object.setValue(account.isPublishingEnabled, forKey: ConnectedAccountKey.isPublishingEnabled)
        object.setValue(account.defaultPrivacyLevel, forKey: ConnectedAccountKey.defaultPrivacyLevel)
        object.setValue(account.lastValidatedAt, forKey: ConnectedAccountKey.lastValidatedAt)
        object.setValue(account.createdAt, forKey: ConnectedAccountKey.createdAt)
        object.setValue(account.updatedAt, forKey: ConnectedAccountKey.updatedAt)
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
        object.setValue(asset.productIDs.map(\.uuidString), asJSONForKey: AssetKey.productIDsJSON)
        object.setValue(asset.createdAt, forKey: AssetKey.createdAt)
        object.setValue(asset.updatedAt, forKey: AssetKey.updatedAt)
    }

    private func apply(_ product: FlickProduct, to object: NSManagedObject) {
        object.setValue(product.id, forKey: ProductKey.id)
        object.setValue(product.name, forKey: ProductKey.name)
        object.setValue(product.summary, forKey: ProductKey.summary)
        object.setValue(product.createdAt, forKey: ProductKey.createdAt)
        object.setValue(product.updatedAt, forKey: ProductKey.updatedAt)
    }

    private func apply(_ template: CreativeTemplate, to object: NSManagedObject) {
        object.setValue(template.id, forKey: TemplateKey.id)
        object.setValue(template.name, forKey: TemplateKey.name)
        object.setValue(template.description, forKey: TemplateKey.summary)
        object.setValue(template.platform.rawValue, forKey: TemplateKey.platform)
        object.setValue(template.slideCount, forKey: TemplateKey.slideCount)
        object.setValue(template.styleJSON, forKey: TemplateKey.styleJSON)
        object.setValue(template.defaultTextRules, forKey: TemplateKey.defaultTextRules)
        object.setValue(template.tags.map(\.id.uuidString), asJSONForKey: TemplateKey.tagIDsJSON)
        object.setValue(template.createdAt, forKey: TemplateKey.createdAt)
        object.setValue(template.updatedAt, forKey: TemplateKey.updatedAt)
    }

    private func apply(_ draft: SlideshowDraft, to object: NSManagedObject) {
        object.setValue(draft.id, forKey: DraftKey.id)
        object.setValue(draft.title, forKey: DraftKey.title)
        object.setValue(draft.templateID, forKey: DraftKey.templateID)
        object.setValue(draft.brief, forKey: DraftKey.brief)
        object.setValue(draft.topic, forKey: DraftKey.topic)
        object.setValue(draft.audience, forKey: DraftKey.audience)
        object.setValue(draft.goal, forKey: DraftKey.goal)
        object.setValue(draft.tone, forKey: DraftKey.tone)
        object.setValue(draft.narrativeArc, asJSONForKey: DraftKey.narrativeArcJSON)
        object.setValue(draft.globalVisualMotif, forKey: DraftKey.globalVisualMotif)
        object.setValue(draft.planSummary, forKey: DraftKey.planSummary)
        object.setValue(draft.slides.sorted { $0.index < $1.index }.map(\.id.uuidString), asJSONForKey: DraftKey.slideIDsJSON)
        object.setValue(draft.caption, forKey: DraftKey.caption)
        object.setValue(draft.hashtags, asJSONForKey: DraftKey.hashtagsJSON)
        object.setValue(draft.targetPlatforms.map(\.rawValue), asJSONForKey: DraftKey.targetPlatformsJSON)
        object.setValue(draft.tikTokSettings, asJSONForKey: DraftKey.tikTokSettingsJSON)
        object.setValue(draft.selectedSongs, asJSONForKey: DraftKey.selectedSongsJSON)
        object.setValue(draft.status.rawValue, forKey: DraftKey.status)
        object.setValue(draft.exportedImageAssetIDs.map(\.uuidString), asJSONForKey: DraftKey.exportedImageAssetIDsJSON)
        object.setValue(draft.createdAt, forKey: DraftKey.createdAt)
        object.setValue(draft.updatedAt, forKey: DraftKey.updatedAt)
    }

    private func apply(_ slide: Slide, draftID: UUID, to object: NSManagedObject) {
        object.setValue(slide.id, forKey: SlideKey.id)
        object.setValue(draftID, forKey: SlideKey.draftID)
        object.setValue(slide.index, forKey: SlideKey.index)
        object.setValue(slide.imageAssetID, forKey: SlideKey.imageAssetID)
        object.setValue(slide.prompt, forKey: SlideKey.prompt)
        object.setValue(slide.text, forKey: SlideKey.text)
        object.setValue(slide.textPosition.rawValue, forKey: SlideKey.textPosition)
        object.setValue(slide.textStyle, asJSONForKey: SlideKey.textStyleJSON)
        object.setValue(slide.selectedVisualSummary, forKey: SlideKey.selectedVisualSummary)
        object.setValue(slide.generationStatus.rawValue, forKey: SlideKey.generationStatus)
        object.setValue(slide.generationErrorMessage, forKey: SlideKey.generationErrorMessage)
        object.setValue(slide.promptVersion, forKey: SlideKey.promptVersion)
        object.setValue(slide.createdAt, forKey: SlideKey.createdAt)
        object.setValue(slide.updatedAt, forKey: SlideKey.updatedAt)
    }

    private func apply(_ automation: ContentAutomation, to object: NSManagedObject) {
        object.setValue(automation.id, forKey: AutomationKey.id)
        object.setValue(automation.name, forKey: AutomationKey.name)
        object.setValue(automation.templateIDs, asJSONForKey: AutomationKey.templateIDsJSON)
        object.setValue(automation.productID, forKey: AutomationKey.productID)
        object.setValue(automation.productImageAssetIDs.map(\.uuidString), asJSONForKey: AutomationKey.productImageAssetIDsJSON)
        object.setValue(automation.schedule, asJSONForKey: AutomationKey.scheduleJSON)
        object.setValue(automation.tikTokSettings, asJSONForKey: AutomationKey.tikTokSettingsJSON)
        object.setValue(automation.targetPlatforms.map(\.rawValue), asJSONForKey: AutomationKey.targetPlatformsJSON)
        object.setValue(automation.status.rawValue, forKey: AutomationKey.status)
        object.setValue(automation.nextScheduledAt, forKey: AutomationKey.nextScheduledAt)
        object.setValue(automation.lastRunAt, forKey: AutomationKey.lastRunAt)
        object.setValue(automation.lastErrorMessage, forKey: AutomationKey.lastErrorMessage)
        object.setValue(automation.consecutiveFailureCount, forKey: AutomationKey.consecutiveFailureCount)
        object.setValue(automation.createdAt, forKey: AutomationKey.createdAt)
        object.setValue(automation.updatedAt, forKey: AutomationKey.updatedAt)
    }

    private func apply(_ job: PublishingJob, to object: NSManagedObject) {
        object.setValue(job.id, forKey: PublishingJobKey.id)
        object.setValue(job.platform.rawValue, forKey: PublishingJobKey.platform)
        object.setValue(job.accountID, forKey: PublishingJobKey.accountID)
        object.setValue(job.automationID, forKey: PublishingJobKey.automationID)
        object.setValue(job.draftID, forKey: PublishingJobKey.draftID)
        object.setValue(job.status.rawValue, forKey: PublishingJobKey.status)
        object.setValue(job.publishMode.rawValue, forKey: PublishingJobKey.publishMode)
        object.setValue(job.attemptCount, forKey: PublishingJobKey.attemptCount)
        object.setValue(job.lastAttemptAt, forKey: PublishingJobKey.lastAttemptAt)
        object.setValue(job.lastError, asJSONForKey: PublishingJobKey.lastErrorJSON)
        object.setValue(job.platformPublishID, forKey: PublishingJobKey.platformPublishID)
        object.setValue(job.createdAt, forKey: PublishingJobKey.createdAt)
        object.setValue(job.updatedAt, forKey: PublishingJobKey.updatedAt)
    }

    private func apply(_ post: PublishedPost, to object: NSManagedObject) {
        object.setValue(post.id, forKey: PublishedPostKey.id)
        object.setValue(post.platform.rawValue, forKey: PublishedPostKey.platform)
        object.setValue(post.accountID, forKey: PublishedPostKey.accountID)
        object.setValue(post.automationID, forKey: PublishedPostKey.automationID)
        object.setValue(post.platformPostID, forKey: PublishedPostKey.platformPostID)
        object.setValue(post.platformURL, forKey: PublishedPostKey.platformURL)
        object.setValue(post.publishedAt, forKey: PublishedPostKey.publishedAt)
        object.setValue(post.draftID, forKey: PublishedPostKey.draftID)
        object.setValue(post.templateID, forKey: PublishedPostKey.templateID)
        object.setValue(post.trendTags.map(\.id.uuidString), asJSONForKey: PublishedPostKey.trendTagIDsJSON)
        object.setValue(post.caption, forKey: PublishedPostKey.caption)
        object.setValue(post.createdAt, forKey: PublishedPostKey.createdAt)
        object.setValue(post.updatedAt, forKey: PublishedPostKey.updatedAt)
    }

    private func saveIfNeeded() throws {
        guard context.hasChanges else { return }
        try context.save()
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

private enum AssetKey {
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

private enum ConnectedAccountKey {
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

private enum ProductKey {
    static let createdAt = "createdAt"
    static let id = "id"
    static let name = "name"
    static let summary = "summary"
    static let updatedAt = "updatedAt"
}

private enum TemplateKey {
    static let createdAt = "createdAt"
    static let defaultTextRules = "defaultTextRules"
    static let id = "id"
    static let name = "name"
    static let platform = "platform"
    static let slideCount = "slideCount"
    static let styleJSON = "styleJSON"
    static let summary = "summary"
    static let tagIDsJSON = "tagIDsJSON"
    static let updatedAt = "updatedAt"
}

private enum DraftKey {
    static let brief = "brief"
    static let caption = "caption"
    static let createdAt = "createdAt"
    static let exportedImageAssetIDsJSON = "exportedImageAssetIDsJSON"
    static let globalVisualMotif = "globalVisualMotif"
    static let goal = "goal"
    static let hashtagsJSON = "hashtagsJSON"
    static let id = "id"
    static let narrativeArcJSON = "narrativeArcJSON"
    static let planSummary = "planSummary"
    static let selectedSongsJSON = "selectedSongsJSON"
    static let slideIDsJSON = "slideIDsJSON"
    static let status = "status"
    static let targetPlatformsJSON = "targetPlatformsJSON"
    static let templateID = "templateID"
    static let tikTokSettingsJSON = "tikTokSettingsJSON"
    static let title = "title"
    static let tone = "tone"
    static let topic = "topic"
    static let audience = "audience"
    static let updatedAt = "updatedAt"
}

private enum SlideKey {
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

private enum AutomationKey {
    static let consecutiveFailureCount = "consecutiveFailureCount"
    static let createdAt = "createdAt"
    static let id = "id"
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
    static let tikTokSettingsJSON = "tikTokSettingsJSON"
    static let updatedAt = "updatedAt"
}

private enum PublishingJobKey {
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

private enum PublishedPostKey {
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

private enum WorkflowStateKey {
    static let id = "id"
    static let key = "key"
    static let updatedAt = "updatedAt"
    static let valueJSON = "valueJSON"
}

private enum WorkflowStateValueKey {
    static let automationPostProgresses = "automation-post-progresses"
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

private extension FlickProduct {
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

private extension ConnectedAccount {
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

private extension CreativeTemplate {
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
            tags: [],
            createdAt: managedObject.value(forKey: TemplateKey.createdAt) as? Date ?? Date(),
            updatedAt: managedObject.value(forKey: TemplateKey.updatedAt) as? Date ?? Date()
        )
    }
}

private extension SlideshowDraft {
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
        let exportedIDs: [String] = managedObject.decodedJSON([String].self, forKey: DraftKey.exportedImageAssetIDsJSON) ?? []
        let tikTokSettings = managedObject.decodedJSON(DraftTikTokSettings.self, forKey: DraftKey.tikTokSettingsJSON)
        let selectedSongs = managedObject.decodedJSON([SelectedSong].self, forKey: DraftKey.selectedSongsJSON) ?? []

        self.init(
            id: id,
            title: title,
            templateID: managedObject.value(forKey: DraftKey.templateID) as? UUID,
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
            tikTokSettings: tikTokSettings,
            selectedSongs: selectedSongs,
            status: status,
            exportedImageAssetIDs: exportedIDs.compactMap(UUID.init(uuidString:)),
            createdAt: managedObject.value(forKey: DraftKey.createdAt) as? Date ?? Date(),
            updatedAt: managedObject.value(forKey: DraftKey.updatedAt) as? Date ?? Date()
        )
    }
}

private extension Slide {
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

private extension ContentAutomation {
    init?(managedObject: NSManagedObject) {
        guard
            let id = managedObject.value(forKey: AutomationKey.id) as? UUID,
            let schedule = managedObject.decodedJSON(AutomationSchedule.self, forKey: AutomationKey.scheduleJSON),
            let tikTokSettings = managedObject.decodedJSON(DraftTikTokSettings.self, forKey: AutomationKey.tikTokSettingsJSON)
        else {
            return nil
        }

        let templateIDs = managedObject.decodedJSON([String].self, forKey: AutomationKey.templateIDsJSON) ?? []
        let productImageAssetIDStrings = managedObject.decodedJSON([String].self, forKey: AutomationKey.productImageAssetIDsJSON) ?? []
        let targetPlatformRawValues = managedObject.decodedJSON([String].self, forKey: AutomationKey.targetPlatformsJSON) ?? []
        let targetPlatforms = targetPlatformRawValues.compactMap(SocialPlatform.init(rawValue:))
        let statusRawValue = managedObject.value(forKey: AutomationKey.status) as? String

        self.init(
            id: id,
            name: managedObject.value(forKey: AutomationKey.name) as? String ?? "",
            templateIDs: templateIDs,
            productID: managedObject.value(forKey: AutomationKey.productID) as? UUID,
            productImageAssetIDs: productImageAssetIDStrings.compactMap(UUID.init(uuidString:)),
            schedule: schedule,
            tikTokSettings: tikTokSettings,
            targetPlatforms: targetPlatforms.isEmpty ? [.tiktok] : targetPlatforms,
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

private extension PublishingJob {
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

private extension PublishedPost {
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

private extension NSManagedObject {
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

    func setValue<T: Encodable>(_ value: T, asJSONForKey key: String) {
        guard
            let data = try? JSONEncoder.flick.encode(value),
            let json = String(data: data, encoding: .utf8)
        else {
            setValue(nil, forKey: key)
            return
        }

        setValue(json, forKey: key)
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
}
