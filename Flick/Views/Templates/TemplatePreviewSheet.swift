//
//  TemplatePreviewSheet.swift
//  Flick
//

import SwiftUI

struct TemplatePreviewSheet: View {
    @Environment(FlickAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    var template: ExampleSlideshowTemplate

    @State private var selectedSlideID: ExampleSlideshowSlide.ID

    init(template: ExampleSlideshowTemplate) {
        self.template = template
        _selectedSlideID = State(initialValue: template.displayablePreviewSlide?.id ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                focusedSlide
                slideStrip
                metadata
            }
            .padding(FlickStyle.pagePadding)
        }
        .background(FlickStyle.pageBackground.ignoresSafeArea())
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            ToolbarItem(placement: .principal) {
                Text("Template")
                    .font(.system(.body, weight: .semibold))
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Use Template", systemImage: "wand.and.sparkles") {
                    appModel.createDraft(from: template)
                    dismiss()
                }
                .buttonStyle(.glassProminent)
            }
        }
        .templatePreviewSheetSizing()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(displayMedium)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 12)

                StatusBadge(title: template.niche, tint: .indigo, systemImage: "tag")
            }

            Text(displayProduct)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 12) {
                Text("@\(template.profile)")
                if let views = template.metrics.views {
                    Label(views, systemImage: "play.fill")
                }
                if let likes = template.metrics.likes {
                    Label(likes, systemImage: "heart.fill")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    @ViewBuilder
    private var focusedSlide: some View {
        if let selectedSlide {
            ZStack {
                VerticalMediaFrame(fileURL: selectedSlide.localURL, cornerRadius: 18, maxPixelSize: 1_920)
                    .frame(maxWidth: 360, maxHeight: 520)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.32), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 10)
                    .onTapGesture {
                        showNextSlide()
                    }

                HStack {
                    slideStepButton(systemImage: "chevron.left", action: showPreviousSlide)
                    Spacer()
                    slideStepButton(systemImage: "chevron.right", action: showNextSlide)
                }
                .padding(.horizontal, 12)

                VStack {
                    Spacer()
                    HStack {
                        Text("Slide \(selectedSlide.index) of \(previewSlides.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.38), in: .capsule)
                        Spacer()
                    }
                    .padding(12)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Slide \(selectedSlide.index) of \(previewSlides.count)")
            .accessibilityAddTraits(.isButton)
        } else {
            FlickEmptyStateCard(
                title: "Preview unavailable",
                message: "This template does not have a displayable slide.",
                systemImage: "photo"
            )
        }
    }

    private var slideStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(previewSlides) { slide in
                        Button {
                            selectedSlideID = slide.id
                        } label: {
                            VerticalMediaFrame(fileURL: slide.localURL, cornerRadius: 8, maxPixelSize: 360)
                                .frame(width: 58)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(slide.id == selectedSlideID ? Color.indigo : Color.clear, lineWidth: 3)
                                }
                                .overlay(alignment: .bottomLeading) {
                                    Text("\(slide.index)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 3)
                                        .background(.black.opacity(0.42), in: .capsule)
                                        .padding(5)
                                }
                        }
                        .buttonStyle(.plain)
                        .id(slide.id)
                        .accessibilityLabel("Show slide \(slide.index)")
                    }
                }
                .padding(.horizontal, FlickStyle.pagePadding)
                .padding(.vertical, 3)
            }
            .contentMargins(.horizontal, -FlickStyle.pagePadding, for: .scrollContent)
            .scrollIndicators(.hidden)
            .onChange(of: selectedSlideID) { _, newValue in
                withAnimation(.snappy) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private var metadata: some View {
        FlickGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                DetailRow(title: "Creator", value: "@\(template.profile)")
                DetailRow(title: "Followers", value: template.creator.followerCount ?? "Unknown")
                DetailRow(title: "Slides", value: "\(previewSlides.count) previewable of \(template.slideCount)")
                DetailRow(title: "Product", value: displayProduct)
            }
        }
    }

    private func slideStepButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.38), in: .circle)
        }
        .buttonStyle(.plain)
    }

    private var previewSlides: [ExampleSlideshowSlide] {
        template.displayableSlides
    }

    private var selectedSlide: ExampleSlideshowSlide? {
        previewSlides.first { $0.id == selectedSlideID } ?? previewSlides.first
    }

    private func showPreviousSlide() {
        guard let selectedSlide, let index = previewSlides.firstIndex(of: selectedSlide) else { return }
        let previousIndex = index == previewSlides.startIndex ? previewSlides.index(before: previewSlides.endIndex) : previewSlides.index(before: index)
        selectedSlideID = previewSlides[previousIndex].id
    }

    private func showNextSlide() {
        guard let selectedSlide, let index = previewSlides.firstIndex(of: selectedSlide) else { return }
        let nextIndex = previewSlides.index(after: index) == previewSlides.endIndex ? previewSlides.startIndex : previewSlides.index(after: index)
        selectedSlideID = previewSlides[nextIndex].id
    }

    private var displayMedium: String {
        guard let medium = template.product.medium?.trimmingCharacters(in: .whitespacesAndNewlines), !medium.isEmpty else {
            return "None"
        }
        return medium
    }

    private var displayProduct: String {
        guard let product = template.product.name?.trimmingCharacters(in: .whitespacesAndNewlines), !product.isEmpty else {
            return "No product"
        }
        return product
    }
}

private struct DetailRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.callout.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension View {
    @ViewBuilder
    func templatePreviewSheetSizing() -> some View {
        #if os(macOS) || targetEnvironment(macCatalyst)
        frame(minWidth: 460, idealWidth: 520, maxWidth: 640, minHeight: 620, idealHeight: 760)
        #else
        self
        #endif
    }
}
