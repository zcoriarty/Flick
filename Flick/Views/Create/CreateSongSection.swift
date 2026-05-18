//
//  CreateSongSection.swift
//  Flick
//

import Foundation
import SwiftUI

struct CreateSongSection: View {
    @Binding var selectedSongs: [SelectedSong]
    var selectAction: () -> Void

    var body: some View {
        Section("Songs") {
            FlickSettingsActionRow(
                title: selectedSongs.isEmpty ? "Select songs" : "Change songs",
                systemImage: "music.note.list",
                iconColor: .pink,
                value: selectedSongs.isEmpty ? "None" : "\(selectedSongs.count) selected",
                action: selectAction
            )

            if selectedSongs.isEmpty {
                CreateMessageRow(
                    title: "No songs selected",
                    message: "Choose one or more tracks from the device music library."
                )
            } else {
                ForEach(selectedSongs) { song in
                    SelectedSongRow(song: song) {
                        selectedSongs.removeAll { $0.id == song.id }
                    }
                }
            }
        }
    }
}

private struct SelectedSongRow: View {
    var song: SelectedSong
    var removeAction: () -> Void

    var body: some View {
        FlickSettingsRow(
            title: song.title,
            systemImage: "music.note",
            iconColor: .pink
        ) {
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(song.artist)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let duration = song.duration {
                        Text(duration.formattedSongDuration)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Button("Remove", systemImage: "xmark.circle.fill", action: removeAction)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }
        }
    }
}

private extension TimeInterval {
    var formattedSongDuration: String {
        let totalSeconds = max(0, Int(rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}
