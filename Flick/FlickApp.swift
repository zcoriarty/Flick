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

    var body: some Scene {
        WindowGroup {
            FlickRootView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(appModel)
        }
    }
}
