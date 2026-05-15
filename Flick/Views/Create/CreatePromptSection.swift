//
//  CreatePromptSection.swift
//  Flick
//

import SwiftUI

struct CreatePromptSection: View {
    @Binding var hookPrompt: String
    @Binding var contentPrompt: String

    var body: some View {
        Section("Prompt") {
            VStack(alignment: .leading, spacing: 18) {
                CreateTextEditorRow(
                    title: "Hook",
                    systemImage: "quote.opening",
                    text: $hookPrompt,
                    placeholder: "Write the first slide hook.",
                    minHeight: 108
                )

                CreateTextEditorRow(
                    title: "Content",
                    systemImage: "text.alignleft",
                    text: $contentPrompt,
                    placeholder: "Write the direction for the remaining slides.",
                    minHeight: 108
                )
            }
            .padding(.vertical, 2)
        }
    }
}
