//
//  MediaView.swift
//  Flick
//

import SwiftUI

struct MediaView: View {
    var body: some View {
        #if os(macOS) || targetEnvironment(macCatalyst)
        ProductView()
        #else
        IOSMediaView()
        #endif
    }
}
