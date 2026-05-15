//
//  CreateMediaLibraryPicker.swift
//  Flick
//

#if os(iOS) && canImport(MediaPlayer)
import MediaPlayer
import SwiftUI

struct MediaLibraryPicker: UIViewControllerRepresentable {
    @Binding var selectedSongs: [SelectedSong]
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let picker = MPMediaPickerController(mediaTypes: .music)
        picker.delegate = context.coordinator
        picker.allowsPickingMultipleItems = true
        picker.showsCloudItems = false
        picker.prompt = "Select songs"
        return picker
    }

    func updateUIViewController(_ uiViewController: MPMediaPickerController, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedSongs: $selectedSongs, dismiss: dismiss)
    }

    final class Coordinator: NSObject, MPMediaPickerControllerDelegate {
        @Binding private var selectedSongs: [SelectedSong]
        private let dismiss: DismissAction

        init(selectedSongs: Binding<[SelectedSong]>, dismiss: DismissAction) {
            _selectedSongs = selectedSongs
            self.dismiss = dismiss
        }

        func mediaPicker(_ mediaPicker: MPMediaPickerController, didPickMediaItems mediaItemCollection: MPMediaItemCollection) {
            selectedSongs = mediaItemCollection.items.map(SelectedSong.init)
            dismiss()
        }

        func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
            dismiss()
        }
    }
}

private extension SelectedSong {
    nonisolated init(item: MPMediaItem) {
        self.init(
            id: String(item.persistentID),
            title: item.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Untitled song",
            artist: item.artist?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Unknown artist",
            duration: item.playbackDuration > 0 ? item.playbackDuration : nil
        )
    }
}

private extension String {
    nonisolated var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
#endif
