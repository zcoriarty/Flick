//
//  CreateTextEditorRow.swift
//  Flick
//

import SwiftUI

struct CreateTextEditorRow: View {
    var title: String
    var systemImage: String
    @Binding var text: String
    var placeholder: String
    var minHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .frame(minHeight: minHeight)
                    .scrollContentBackground(.hidden)
                    .accessibilityLabel(title)

                if text.isEmpty {
                    Text(placeholder)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(8)
            .background(
                Color.secondary.opacity(0.08),
                in: .rect(cornerRadius: FlickStyle.controlCornerRadius)
            )
        }
        .accessibilityElement(children: .contain)
    }
}
