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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
