//
//  SettingsView.swift
//  Flick
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        #if os(macOS) || targetEnvironment(macCatalyst)
        MacSettingsView()
        #else
        IOSSettingsView()
        #endif
    }
}
