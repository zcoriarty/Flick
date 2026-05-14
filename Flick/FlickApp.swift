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
    let persistenceController: PersistenceController
    @State private var appModel: FlickAppModel
    #if os(iOS) && !targetEnvironment(macCatalyst)
    @UIApplicationDelegateAdaptor(FlickAppDelegate.self) private var appDelegate
    #endif

    init() {
        let persistenceController = PersistenceController.shared
        self.persistenceController = persistenceController
        _appModel = State(initialValue: FlickAppModel.live(persistenceController: persistenceController))
    }

    var body: some Scene {
        WindowGroup {
            FlickRootView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(appModel)
        }
    }
}
