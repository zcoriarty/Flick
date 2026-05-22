//
//  CreateView.swift
//  Flick
//

import SwiftUI

struct CreateView: View {
    var body: some View {
        #if os(macOS) || targetEnvironment(macCatalyst)
        MacCreateView()
        #else
        IOSCreateView()
        #endif
    }
}
