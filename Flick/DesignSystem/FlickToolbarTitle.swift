//
//  FlickToolbarTitle.swift
//  Flick
//

import SwiftUI

private struct FlickToolbarTitleModifier: ViewModifier {
    var title: String

    func body(content: Content) -> some View {
        content
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.system(.body, weight: .semibold))
                }
                .sharedBackgroundVisibility(.hidden)
            }
    }
}

extension View {
    func flickToolbarTitle(_ title: String) -> some View {
        modifier(FlickToolbarTitleModifier(title: title))
    }
}
