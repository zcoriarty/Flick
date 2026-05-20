//
//  MediaView.swift
//  Flick
//

import SwiftUI

struct MediaView: View {
    @State private var selectedSection: MediaSection = .products

    var body: some View {
        VStack(spacing: 0) {
            MediaSectionPicker(selection: $selectedSection)

            Group {
                switch selectedSection {
                case .products:
                    ProductView()
                case .templates:
                    TemplatesView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .flickAppBackground()
    }
}

private enum MediaSection: String, CaseIterable, Identifiable {
    case products
    case templates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .products: "Products"
        case .templates: "Templates"
        }
    }
}

private struct MediaSectionPicker: View {
    @Binding var selection: MediaSection

    var body: some View {
        Picker("Media", selection: $selection) {
            ForEach(MediaSection.allCases) { section in
                Text(section.title)
                    .tag(section)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(FlickStyle.pageBackground)
    }
}

#Preview {
    @Previewable @State var appModel = FlickAppModel.live()
    NavigationStack {
        MediaView()
    }
    .environment(appModel)
}
