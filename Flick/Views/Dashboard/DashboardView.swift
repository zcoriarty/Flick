//
//  DashboardView.swift
//  Flick
//

import SwiftUI

struct DashboardView: View {
    var body: some View {
        #if os(macOS)
        MacAutomationDashboardView()
        #else
        IOSDashboardView()
        #endif
    }
}
