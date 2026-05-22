//
//  TemplatesView.swift
//  Flick
//

import SwiftUI

struct TemplatesView: View {
    var body: some View {
        #if os(macOS) || targetEnvironment(macCatalyst)
        MacTemplatesView()
        #else
        IOSTemplatesView()
        #endif
    }
}
