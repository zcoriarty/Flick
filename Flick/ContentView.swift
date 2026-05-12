//
//  ContentView.swift
//  Flick
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        FlickRootView()
    }
}

#Preview {
    @Previewable @State var appModel = FlickAppModel.live()
    ContentView()
        .environment(appModel)
}
