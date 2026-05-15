//
//  CreateAutomationModeSection.swift
//  Flick
//

import SwiftUI

struct CreateAutomationModeSection: View {
    @Binding var isAutonomous: Bool

    var body: some View {
        Section("Mode") {
            FlickSettingsRow(
                title: "Autonomous",
                systemImage: "bolt.circle",
                iconColor: isAutonomous ? .purple : .secondary
            ) {
                Toggle("Autonomous", isOn: $isAutonomous)
                    .labelsHidden()
            }
        }
    }
}
