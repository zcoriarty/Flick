//
//  AccountsView.swift
//  Flick
//

import SwiftUI

struct AccountsView: View {
    var body: some View {
        #if os(macOS) || targetEnvironment(macCatalyst)
        MacAccountsView()
        #else
        IOSAccountsView()
        #endif
    }
}
