//
//  FlickApp.swift
//  Flick
//
//  Created by Zachary Coriarty on 5/11/26.
//

import SwiftUI
import CoreData

@main
struct FlickApp: App {
    let persistenceController = PersistenceController.shared
    @State private var appModel = FlickAppModel.live()
    #if os(iOS) && !targetEnvironment(macCatalyst)
    @UIApplicationDelegateAdaptor(FlickAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            FlickRootView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(appModel)
        }
    }
}
