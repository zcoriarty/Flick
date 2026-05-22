//
//  PublishedPostNotificationService.swift
//  Flick
//

import CloudKit
import Foundation
import OSLog

protocol PublishedPostNotificationPublishing {
    func publishNotification(
        for post: PublishedPost,
        account: ConnectedAccount?,
        draft: SlideshowDraft?
    ) async

    func publishDraftUploadNotification(
        for job: PublishingJob,
        account: ConnectedAccount?,
        draft: SlideshowDraft?,
        result: PublishResult
    ) async
}

struct NoopPublishedPostNotificationPublisher: PublishedPostNotificationPublishing {
    func publishNotification(
        for post: PublishedPost,
        account: ConnectedAccount?,
        draft: SlideshowDraft?
    ) async {}

    func publishDraftUploadNotification(
        for job: PublishingJob,
        account: ConnectedAccount?,
        draft: SlideshowDraft?,
        result: PublishResult
    ) async {}
}

struct CloudKitPublishedPostNotificationPublisher: PublishedPostNotificationPublishing {
    private let store: CloudKitPublishedPostNotificationStore
    private let logger: Logger

    init(
        store: CloudKitPublishedPostNotificationStore = CloudKitPublishedPostNotificationStore(),
        logger: Logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.orion.Flick", category: "Notifications")
    ) {
        self.store = store
        self.logger = logger
    }

    static var live: any PublishedPostNotificationPublishing {
        if ProcessInfo.processInfo.flickIsRunningXCTest {
            NoopPublishedPostNotificationPublisher()
        } else {
            CloudKitPublishedPostNotificationPublisher()
        }
    }

    func publishNotification(
        for post: PublishedPost,
        account: ConnectedAccount?,
        draft: SlideshowDraft?
    ) async {
        #if os(macOS) || targetEnvironment(macCatalyst)
        do {
            try await store.createPublishedPostNotificationRecord(
                for: post,
                account: account,
                draft: draft
            )
        } catch {
            logger.error("Failed to create published post notification record postID=\(post.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    func publishDraftUploadNotification(
        for job: PublishingJob,
        account: ConnectedAccount?,
        draft: SlideshowDraft?,
        result: PublishResult
    ) async {
        #if os(macOS) || targetEnvironment(macCatalyst)
        do {
            try await store.createDraftUploadNotificationRecord(
                for: job,
                account: account,
                draft: draft,
                result: result
            )
        } catch {
            logger.error("Failed to create draft upload notification record jobID=\(job.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }
        #endif
    }
}

struct CloudKitPublishedPostNotificationStore {
    static let recordType = "PublishedPostNotification"
    static let subscriptionID = "published-post-notifications-v1"

    private static let bootstrapRecordName = "published-post-notification-bootstrap"
    private static let fieldAccountDisplayName = "accountDisplayName"
    private static let fieldCaption = "caption"
    private static let fieldDraftID = "draftID"
    private static let fieldDraftTitle = "draftTitle"
    private static let fieldEventType = "eventType"
    private static let fieldJobID = "jobID"
    private static let fieldNotificationBody = "notificationBody"
    private static let fieldNotificationTitle = "notificationTitle"
    private static let fieldPlatform = "platform"
    private static let fieldPlatformPostID = "platformPostID"
    private static let fieldPlatformStatus = "platformStatus"
    private static let fieldPlatformURL = "platformURL"
    private static let fieldPublishedAt = "publishedAt"
    private static let fieldPublishedPostID = "publishedPostID"

    private let database: CKDatabase

    init(containerIdentifier: String = PersistenceController.cloudKitContainerIdentifier) {
        self.database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
    }

    func createPublishedPostNotificationRecord(
        for post: PublishedPost,
        account: ConnectedAccount?,
        draft: SlideshowDraft?
    ) async throws {
        try await ensurePublishedPostNotificationSubscription()

        let recordID = Self.recordID(for: post)
        guard try await !recordExists(with: recordID) else { return }

        let notificationText = Self.notificationText(for: post, account: account, draft: draft)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record[Self.fieldEventType] = "publishedPost" as NSString
        record[Self.fieldPublishedPostID] = post.id.uuidString as NSString
        record[Self.fieldPlatform] = post.platform.rawValue as NSString
        record[Self.fieldPlatformPostID] = post.platformPostID as NSString
        record[Self.fieldPublishedAt] = post.publishedAt as NSDate
        record[Self.fieldDraftID] = post.draftID.uuidString as NSString
        record[Self.fieldCaption] = Self.truncated(post.caption, maximumLength: 240) as NSString
        record[Self.fieldNotificationTitle] = notificationText.title as NSString
        record[Self.fieldNotificationBody] = notificationText.body as NSString

        if let draft {
            record[Self.fieldDraftTitle] = draft.title as NSString
        }
        if let account {
            record[Self.fieldAccountDisplayName] = account.displayName as NSString
        }
        if let platformURL = post.platformURL?.absoluteString {
            record[Self.fieldPlatformURL] = platformURL as NSString
        }

        do {
            try await save(record)
        } catch let error as CKError where error.code == .serverRecordChanged || error.code == .constraintViolation {
            return
        }
    }

    func createDraftUploadNotificationRecord(
        for job: PublishingJob,
        account: ConnectedAccount?,
        draft: SlideshowDraft?,
        result: PublishResult
    ) async throws {
        try await ensurePublishedPostNotificationSubscription()

        let recordID = Self.draftUploadRecordID(for: job)
        guard try await !recordExists(with: recordID) else { return }

        let notificationText = Self.draftUploadNotificationText(for: job, account: account, draft: draft)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record[Self.fieldEventType] = "draftUpload" as NSString
        record[Self.fieldJobID] = job.id.uuidString as NSString
        record[Self.fieldDraftID] = job.draftID.uuidString as NSString
        record[Self.fieldPlatform] = job.platform.rawValue as NSString
        record[Self.fieldPlatformPostID] = result.platformPostID as NSString
        record[Self.fieldPlatformStatus] = (result.platformStatus ?? "") as NSString
        record[Self.fieldNotificationTitle] = notificationText.title as NSString
        record[Self.fieldNotificationBody] = notificationText.body as NSString

        if let draft {
            record[Self.fieldDraftTitle] = draft.title as NSString
            record[Self.fieldCaption] = Self.truncated(draft.caption, maximumLength: 240) as NSString
        }
        if let account {
            record[Self.fieldAccountDisplayName] = account.displayName as NSString
        }

        do {
            try await save(record)
        } catch let error as CKError where error.code == .serverRecordChanged || error.code == .constraintViolation {
            return
        }
    }

    func ensurePublishedPostNotificationSubscription() async throws {
        guard try await !subscriptionExists(withID: Self.subscriptionID) else { return }
        try await ensureNotificationRecordTypeExists()

        let subscription = CKQuerySubscription(
            recordType: Self.recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: Self.subscriptionID,
            options: [.firesOnRecordCreation]
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.title = "Flick"
        notificationInfo.alertBody = "Flick has a TikTok update."
        notificationInfo.soundName = "default"
        notificationInfo.shouldSendContentAvailable = true
        notificationInfo.desiredKeys = [
            Self.fieldEventType,
            Self.fieldJobID,
            Self.fieldPublishedPostID,
            Self.fieldPlatform,
            Self.fieldPlatformPostID,
            Self.fieldPlatformStatus,
            Self.fieldNotificationTitle,
            Self.fieldNotificationBody
        ]
        subscription.notificationInfo = notificationInfo

        do {
            try await save(subscription)
        } catch let error as CKError where error.code == .serverRejectedRequest {
            if try await subscriptionExists(withID: Self.subscriptionID) {
                return
            }
            throw error
        }
    }

    private func ensureNotificationRecordTypeExists() async throws {
        let recordID = CKRecord.ID(recordName: Self.bootstrapRecordName)
        guard try await !recordExists(with: recordID) else { return }

        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record[Self.fieldEventType] = "bootstrap" as NSString
        record[Self.fieldNotificationTitle] = "Flick" as NSString
        record[Self.fieldNotificationBody] = "" as NSString

        do {
            try await save(record)
        } catch let error as CKError where error.code == .serverRecordChanged || error.code == .constraintViolation {
            return
        }
    }

    private func recordExists(with recordID: CKRecord.ID) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            database.fetch(withRecordID: recordID) { _, error in
                if let error {
                    if let cloudKitError = error as? CKError, cloudKitError.code == .unknownItem {
                        continuation.resume(returning: false)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                continuation.resume(returning: true)
            }
        }
    }

    private func subscriptionExists(withID subscriptionID: CKSubscription.ID) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            database.fetch(withSubscriptionID: subscriptionID) { _, error in
                if let error {
                    if let cloudKitError = error as? CKError, cloudKitError.code == .unknownItem {
                        continuation.resume(returning: false)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                continuation.resume(returning: true)
            }
        }
    }

    private func save(_ record: CKRecord) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            database.save(record) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func save(_ subscription: CKSubscription) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            database.save(subscription) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func recordID(for post: PublishedPost) -> CKRecord.ID {
        CKRecord.ID(recordName: "published-post-\(post.id.uuidString)")
    }

    private static func draftUploadRecordID(for job: PublishingJob) -> CKRecord.ID {
        CKRecord.ID(recordName: "draft-upload-\(job.id.uuidString)")
    }

    private static func notificationText(
        for post: PublishedPost,
        account: ConnectedAccount?,
        draft: SlideshowDraft?
    ) -> (title: String, body: String) {
        let platformName = post.platform.displayName
        let title = "New \(platformName) post published"

        if let draftTitle = draft?.title.trimmingCharacters(in: .whitespacesAndNewlines), !draftTitle.isEmpty {
            return (title, "Flick published \(draftTitle) to \(platformName).")
        }

        if let accountName = account?.displayName.trimmingCharacters(in: .whitespacesAndNewlines), !accountName.isEmpty {
            return (title, "Flick published a post for \(accountName).")
        }

        return (title, "Flick published a new post.")
    }

    private static func draftUploadNotificationText(
        for job: PublishingJob,
        account: ConnectedAccount?,
        draft: SlideshowDraft?
    ) -> (title: String, body: String) {
        let platformName = job.platform.displayName
        let title = "\(platformName) draft is ready"

        if let draftTitle = draft?.title.trimmingCharacters(in: .whitespacesAndNewlines), !draftTitle.isEmpty {
            return (title, "Flick sent \(draftTitle) to \(platformName). Open \(platformName) to finish posting.")
        }

        if let accountName = account?.displayName.trimmingCharacters(in: .whitespacesAndNewlines), !accountName.isEmpty {
            return (title, "Flick sent a post for \(accountName) to \(platformName). Open \(platformName) to finish posting.")
        }

        return (title, "Flick sent a post to \(platformName). Open \(platformName) to finish posting.")
    }

    private static func truncated(_ value: String, maximumLength: Int) -> String {
        guard value.count > maximumLength else { return value }
        return String(value.prefix(maximumLength))
    }
}

#if os(iOS) && !targetEnvironment(macCatalyst)
import UIKit
import UserNotifications

struct PublishedPostNotificationRegistrationService {
    static let shared = PublishedPostNotificationRegistrationService()

    private let store: CloudKitPublishedPostNotificationStore
    private let logger: Logger

    init(
        store: CloudKitPublishedPostNotificationStore = CloudKitPublishedPostNotificationStore(),
        logger: Logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.orion.Flick", category: "Notifications")
    ) {
        self.store = store
        self.logger = logger
    }

    func configure() async {
        guard !ProcessInfo.processInfo.flickIsRunningXCTest else { return }

        do {
            guard try await requestNotificationAuthorizationIfNeeded() else {
                logger.info("Published post notifications are not authorized on this device.")
                return
            }

            UIApplication.shared.registerForRemoteNotifications()
            try await store.ensurePublishedPostNotificationSubscription()
        } catch {
            logger.error("Failed to configure published post notifications error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func requestNotificationAuthorizationIfNeeded() async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await notificationSettings(center: center)

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return try await requestAuthorization(center: center)
        @unknown default:
            return false
        }
    }

    private func notificationSettings(center: UNUserNotificationCenter) async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private func requestAuthorization(center: UNUserNotificationCenter) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}
#endif
