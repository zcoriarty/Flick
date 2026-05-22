//
//  ProductView.swift
//  Flick
//

import SwiftUI

struct ProductView: View {
    var body: some View {
        #if os(macOS) || targetEnvironment(macCatalyst)
        MacProductView()
        #else
        IOSProductView()
        #endif
    }
}
