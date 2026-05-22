//
//  ModelsView.swift
//  Flick
//

import SwiftUI

struct ModelsView: View {
    var body: some View {
        #if os(macOS) || targetEnvironment(macCatalyst)
        MacModelsView()
        #else
        IOSModelsView()
        #endif
    }
}
