//
//  CreateAutomationStartSuccessView.swift
//  Flick
//

import SwiftUI

struct CreateAutomationStartSuccessView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.green)

            VStack(spacing: 6) {
                Text("Automation started")
                    .font(.title2.weight(.semibold))
                Text("Your cadence is active.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FlickStyle.pageBackground.ignoresSafeArea())
        .accessibilityElement(children: .combine)
    }
}
