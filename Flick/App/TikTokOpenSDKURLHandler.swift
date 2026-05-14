//
//  TikTokOpenSDKURLHandler.swift
//  Flick
//

import Foundation

#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(TikTokOpenSDKCore)
import TikTokOpenSDKCore
#endif

enum TikTokOpenSDKURLHandler {
    static func handle(_ url: URL?) -> Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(TikTokOpenSDKCore)
        TikTokURLHandler.handleOpenURL(url)
        #else
        false
        #endif
    }
}
