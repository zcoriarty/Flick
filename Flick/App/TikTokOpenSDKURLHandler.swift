//
//  TikTokOpenSDKURLHandler.swift
//  Flick
//

import Foundation
import OSLog

#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(TikTokOpenSDKCore)
import TikTokOpenSDKCore
#endif

enum TikTokOpenSDKURLHandler {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.orion.Flick", category: "TikTokOpenSDK")

    static func handle(_ url: URL?, source: String = "unknown") -> Bool {
        guard let url else {
            logger.info("TikTok OpenSDK callback missing URL from \(source, privacy: .public).")
            return false
        }

        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(TikTokOpenSDKCore)
        let handled = TikTokURLHandler.handleOpenURL(url)
        logger.info("TikTok OpenSDK callback from \(source, privacy: .public) handled=\(handled, privacy: .public) scheme=\(url.scheme ?? "", privacy: .public) host=\(url.host ?? "", privacy: .public) path=\(url.path, privacy: .public).")
        return handled
        #else
        logger.info("TikTok OpenSDK callback ignored on this platform from \(source, privacy: .public) scheme=\(url.scheme ?? "", privacy: .public) host=\(url.host ?? "", privacy: .public) path=\(url.path, privacy: .public).")
        return false
        #endif
    }
}
