//
//  CreateModeSection.swift
//  Flick
//

import SwiftUI

struct CreateModeSection: View {
    @Binding var isAutomated: Bool

    var body: some View {
        FlickSettingsRow(
            title: "Automated",
            systemImage: "calendar.badge.clock",
            iconColor: isAutomated ? .green : .secondary
        ) {
            Toggle("Automated", isOn: $isAutomated)
                .labelsHidden()
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
    }
}
