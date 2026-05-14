//
//  FlickAppDelegate.swift
//  Flick
//

#if os(iOS) && !targetEnvironment(macCatalyst)
import UIKit

final class FlickAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        return TikTokOpenSDKURLHandler.handle(
            userActivity.webpageURL,
            source: "UIApplicationDelegate.continueUserActivity"
        )
    }
}
#endif
