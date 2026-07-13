//
//  PersistentHistoryChangeMonitor.swift
//  Flick
//

import CoreData
import Foundation

protocol PersistentHistoryChangeMonitoring: Sendable {
    func hasRelevantChanges() async throws -> Bool
}

actor PersistentHistoryChangeMonitor: PersistentHistoryChangeMonitoring {
    nonisolated static let appTransactionAuthor = "FlickApp"

    private nonisolated static let tokenDefaultsKey = "Flick.PersistentHistoryToken.v1"
    private nonisolated static let macRunnerHeartbeatKey = "mac-runner-heartbeat"
    private nonisolated static let relevantEntityNames: Set<String> = [
        "CDAsset",
        "CDAuditEvent",
        "CDConnectedAccount",
        "CDContentAutomation",
        "CDCreationModel",
        "CDCreativeTemplate",
        "CDPublishedPost",
        "CDProduct",
        "CDPublishingJob",
        "CDSlide",
        "CDSlideshowDraft",
        "CDWorkflowState"
    ]

    private let context: NSManagedObjectContext
    private nonisolated(unsafe) let userDefaults: UserDefaults
    private var tokenData: Data?

    init(
        container: NSPersistentContainer,
        userDefaults: UserDefaults = .standard
    ) {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.transactionAuthor = "FlickPersistentHistoryMonitor"
        self.context = context
        self.userDefaults = userDefaults
        self.tokenData = userDefaults.data(forKey: Self.tokenDefaultsKey)
    }

    func hasRelevantChanges() async throws -> Bool {
        let previousTokenData = tokenData
        let result: HistoryResult

        do {
            result = try await context.perform {
                let previousToken = previousTokenData.flatMap(Self.decodeToken)
                let request = NSPersistentHistoryChangeRequest.fetchHistory(after: previousToken)
                request.resultType = .transactionsAndChanges

                guard
                    let historyResult = try self.context.execute(request) as? NSPersistentHistoryResult,
                    let transactions = historyResult.result as? [NSPersistentHistoryTransaction]
                else {
                    return HistoryResult(hasRelevantChanges: true, tokenData: previousTokenData)
                }

                let hasRelevantChanges = transactions.contains { transaction in
                    guard transaction.author != Self.appTransactionAuthor else { return false }
                    guard let changes = transaction.changes else { return true }
                    return changes.contains { change in
                        guard let entityName = change.changedObjectID.entity.name else { return true }
                        guard Self.relevantEntityNames.contains(entityName) else { return false }
                        guard entityName == "CDWorkflowState", change.changeType != .delete else {
                            return true
                        }

                        guard
                            let object = try? self.context.existingObject(with: change.changedObjectID),
                            let key = object.value(forKey: "key") as? String
                        else {
                            return true
                        }
                        return key != Self.macRunnerHeartbeatKey
                    }
                }

                return HistoryResult(
                    hasRelevantChanges: hasRelevantChanges,
                    tokenData: transactions.last.flatMap { Self.encodeToken($0.token) } ?? previousTokenData
                )
            }
        } catch {
            tokenData = nil
            userDefaults.removeObject(forKey: Self.tokenDefaultsKey)
            throw error
        }

        if let newTokenData = result.tokenData, newTokenData != tokenData {
            tokenData = newTokenData
            userDefaults.set(newTokenData, forKey: Self.tokenDefaultsKey)
        }

        return result.hasRelevantChanges
    }

    private nonisolated static func encodeToken(_ token: NSPersistentHistoryToken) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    private nonisolated static func decodeToken(_ data: Data) -> NSPersistentHistoryToken? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: data)
    }
}

private struct HistoryResult: Sendable {
    var hasRelevantChanges: Bool
    var tokenData: Data?
}
