//
//  FlickStyle.swift
//  Flick
//

import SwiftUI

enum FlickStyle {
    static let appTint: Color = .indigo
    static let cardCornerRadius: CGFloat = 18
    static let controlCornerRadius: CGFloat = 12
    static let sectionSpacing: CGFloat = 20
    static let contentSpacing: CGFloat = 14
    static let pagePadding: CGFloat = 20

    static var pageBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }
}

private struct FlickAppBackgroundModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .background(FlickStyle.pageBackground.ignoresSafeArea())
            .toolbarBackground(FlickStyle.pageBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(FlickStyle.pageBackground, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
        #elseif os(macOS)
        content
            .background(FlickStyle.pageBackground.ignoresSafeArea())
            .toolbarBackground(.hidden, for: .windowToolbar)
        #else
        content
            .background(FlickStyle.pageBackground.ignoresSafeArea())
        #endif
    }
}

extension View {
    func flickAppBackground() -> some View {
        modifier(FlickAppBackgroundModifier())
    }
}

extension SocialPlatform {
    var systemImage: String {
        switch self {
        case .tiktok: "music.note"
        case .instagram: "camera"
        case .threads: "text.bubble"
        case .x: "xmark"
        }
    }
}

extension AccountStatus {
    var displayName: String {
        switch self {
        case .connected: "Connected"
        case .needsAuth: "Needs auth"
        case .missingScope: "Missing scope"
        case .rateLimited: "Rate limited"
        case .disabled: "Disabled"
        case .comingSoon: "Coming soon"
        }
    }

    var tint: Color {
        switch self {
        case .connected: .green
        case .needsAuth, .missingScope, .rateLimited: .orange
        case .disabled: .red
        case .comingSoon: .secondary
        }
    }
}

extension PublishingJobStatus {
    var displayName: String {
        switch self {
        case .awaitingApproval: "Awaiting approval"
        case .uploadingMedia: "Uploading media"
        default: rawValue.capitalized
        }
    }

    var tint: Color {
        switch self {
        case .published: .green
        case .failed, .canceled: .red
        case .awaitingApproval, .approved: .orange
        case .rendering, .uploadingMedia, .publishing: .blue
        case .paused: .secondary
        case .draft, .queued: .teal
        }
    }
}

extension TrendStatus {
    var displayName: String { rawValue.capitalized }

    var tint: Color {
        switch self {
        case .new: .blue
        case .active: .green
        case .testing: .orange
        case .winning: .purple
        case .declining: .red
        case .archived: .secondary
        }
    }
}

extension CredentialStatus.Source {
    var tint: Color {
        switch self {
        case .secureStore: .blue
        case .missing: .secondary
        }
    }

    var systemImage: String {
        switch self {
        case .secureStore: "lock.fill"
        case .missing: "minus.circle"
        }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red: Double
        let green: Double
        let blue: Double
        switch cleaned.count {
        case 6:
            red = Double((value & 0xFF0000) >> 16) / 255
            green = Double((value & 0x00FF00) >> 8) / 255
            blue = Double(value & 0x0000FF) / 255
        default:
            red = 0.5
            green = 0.5
            blue = 0.5
        }
        self.init(red: red, green: green, blue: blue)
    }
}
