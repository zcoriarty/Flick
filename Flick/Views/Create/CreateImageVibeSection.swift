//
//  CreateImageVibeSection.swift
//  Flick
//

import SwiftUI

struct CreateImageVibeSection: View {
    @Binding var imageVibe: SlideshowImageVibe
    var includesNone = false

    private var availableImageVibes: [SlideshowImageVibe] {
        SlideshowImageVibe.allCases.filter { includesNone || $0 != .none }
    }

    var body: some View {
        Section("Visuals") {
            FlickSettingsRow(
                title: "Filter",
                systemImage: imageVibe.systemImage,
                iconColor: FlickStyle.appTint
            ) {
                Picker("Filter", selection: $imageVibe) {
                    ForEach(availableImageVibes) { vibe in
                        Text(vibe.displayName).tag(vibe)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Text(imageVibe.menuDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
