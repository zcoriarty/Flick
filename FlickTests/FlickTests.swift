//
//  FlickTests.swift
//  FlickTests
//

import XCTest
@testable import Flick

@MainActor
final class FlickTests: XCTestCase {
    func testPublishingStatusTransitionsGuardInvalidJumps() throws {
        XCTAssertTrue(PublishingJobStatus.awaitingApproval.canTransition(to: .approved))
        XCTAssertTrue(PublishingJobStatus.approved.canTransition(to: .rendering))
        XCTAssertTrue(PublishingJobStatus.uploadingMedia.canTransition(to: .publishing))
        XCTAssertFalse(PublishingJobStatus.draft.canTransition(to: .published))
        XCTAssertFalse(PublishingJobStatus.published.canTransition(to: .queued))
    }

    func testSchedulerClaimsOnlyUnleasedEligibleJobs() {
        let scheduler = PublishingScheduler()
        let workerDeviceID = UUID()
        let secondWorkerDeviceID = UUID()
        let job = makePublishingJob()
        let claimed = scheduler.claim(job, workerDeviceID: workerDeviceID, leaseDuration: 60)

        XCTAssertEqual(claimed?.workerDeviceID, workerDeviceID)
        XCTAssertNotNil(claimed?.workerLeaseExpiresAt)
        XCTAssertNil(claimed.flatMap { scheduler.claim($0, workerDeviceID: secondWorkerDeviceID, leaseDuration: 60) })
    }

    func testLiveAppModelStartsWithoutSeedData() {
        let model = LiveAppModelTestCache.model

        XCTAssertTrue(model.overview.drafts.isEmpty)
        XCTAssertTrue(model.overview.publishingJobs.isEmpty)
        XCTAssertTrue(model.overview.trends.isEmpty)
        XCTAssertTrue(model.overview.analyticsPerformance.isEmpty)
    }

    func testCredentialVaultStoresOnlySupportedNonEmptyValues() throws {
        let store = MemorySecretStore()
        let vault = CredentialVault(store: store)

        try vault.storeValue("client-id", for: "TIKTOK_CLIENT_ID")
        XCTAssertThrowsError(try vault.storeValue("ignored", for: "UNKNOWN_KEY"))
        XCTAssertThrowsError(try vault.storeValue("", for: "OPENAI_API_KEY"))
        XCTAssertEqual(String(data: try XCTUnwrap(store.data(for: "TIKTOK_CLIENT_ID")), encoding: .utf8), "client-id")
    }

    func testTikTokAuthorizationParametersRequireUniversalLinkRedirect() throws {
        let configuration = TikTokConfiguration(values: [
            "TIKTOK_CLIENT_ID": "client-id",
            "TIKTOK_REDIRECT_URI": "https://example.com/oauth/tiktok",
            "TIKTOK_SCOPES": "user.info.basic,video.publish"
        ])

        let parameters = try TikTokLoginKitAuthorizationParameters(
            configuration: configuration,
            state: "state-token"
        )

        XCTAssertEqual(parameters.redirectURI, "https://example.com/oauth/tiktok")
        XCTAssertEqual(parameters.scopes, ["user.info.basic", "video.publish"])
        XCTAssertEqual(parameters.state, "state-token")
    }

    func testTikTokAuthorizationParametersRejectCustomSchemeRedirect() throws {
        let configuration = TikTokConfiguration(values: [
            "TIKTOK_CLIENT_ID": "client-id",
            "TIKTOK_REDIRECT_URI": "flick://oauth/tiktok",
            "TIKTOK_SCOPES": "user.info.basic,video.publish"
        ])

        XCTAssertThrowsError(
            try TikTokLoginKitAuthorizationParameters(configuration: configuration)
        )
    }

    func testLoginKitAccountStoreOnlyReturnsLoginKitAccounts() throws {
        let store = MemorySecretStore()
        let accountStore = LoginKitAccountStore(store: store)
        let loginKitAccount = LoginKitAccountMapper.connectedAccount(
            from: LoginKitAuthorizedUser(
                platform: .tiktok,
                openID: "real-open-id",
                displayName: "@realaccount",
                avatarURL: nil,
                scopes: ["user.info.basic", "video.publish"]
            )
        )
        var manualAccount = loginKitAccount
        manualAccount.id = UUID()
        manualAccount.platformUserID = "manual"
        manualAccount.authorizationSource = .manualImport

        try accountStore.saveAccounts([manualAccount, loginKitAccount])

        let accounts = accountStore.loadAccounts()
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts.first?.platformUserID, "real-open-id")
        XCTAssertEqual(accounts.first?.displayName, "@realaccount")
        XCTAssertEqual(accounts.first?.authorizationSource, .loginKit)
    }

    func testAccountManagementPolicyIsIOSOnly() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        XCTAssertTrue(AccountManagementPolicy.canAuthorizeAccountsOnThisDevice)
        #else
        XCTAssertFalse(AccountManagementPolicy.canAuthorizeAccountsOnThisDevice)
        #endif
    }

    func testLoginKitStoresUseSynchronizableKeychainByDefault() {
        let accountStore = LoginKitAccountStore()
        let tokenStore = LoginKitTokenStore()

        XCTAssertEqual((accountStore.store as? KeychainSecretStore)?.synchronizesAcrossDevices, true)
        XCTAssertEqual((tokenStore.store as? KeychainSecretStore)?.synchronizesAcrossDevices, true)
    }
}

private func makePublishingJob(status: PublishingJobStatus = .queued) -> PublishingJob {
    let now = Date()
    return PublishingJob(
        id: UUID(),
        platform: .tiktok,
        accountID: UUID(),
        draftID: UUID(),
        scheduledAt: now,
        status: status,
        publishMode: .photoDirectPost,
        requiresApproval: true,
        approvedAt: nil,
        approvedByDeviceID: nil,
        workerDeviceID: nil,
        workerLeaseExpiresAt: nil,
        attemptCount: 0,
        lastAttemptAt: nil,
        lastError: nil,
        platformPublishID: nil,
        createdAt: now,
        updatedAt: now
    )
}

@MainActor
private enum LiveAppModelTestCache {
    static let model = FlickAppModel.live()
}

private final class MemorySecretStore: SecretStoring {
    private var values: [String: Data] = [:]

    func data(for key: String) throws -> Data? {
        values[key]
    }

    func save(_ data: Data, for key: String) throws {
        values[key] = data
    }

    func delete(_ key: String) throws {
        values[key] = nil
    }
}

private extension Array where Element == URLQueryItem {
    func value(named name: String) -> String? {
        first { $0.name == name }?.value
    }
}
