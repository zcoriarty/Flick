//
//  FlickSettingsList.swift
//  Flick
//

import SwiftUI

struct FlickSettingsRow<Accessory: View>: View {
    var title: String
    var systemImage: String?
    var iconColor: Color
    let accessory: Accessory

    init(
        title: String,
        systemImage: String? = nil,
        iconColor: Color = .primary,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.systemImage = systemImage
        self.iconColor = iconColor
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(iconColor)
                    .frame(width: 24)
            }

            Text(title)
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            accessory
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension FlickSettingsRow where Accessory == EmptyView {
    init(
        title: String,
        systemImage: String? = nil,
        iconColor: Color = .primary
    ) {
        self.title = title
        self.systemImage = systemImage
        self.iconColor = iconColor
        self.accessory = EmptyView()
    }
}

struct FlickSettingsRowLabel: View {
    var title: String
    var systemImage: String
    var iconColor: Color = .primary
    var value: String?
    var valueLineLimit: Int? = 1
    var showsChevron = false

    var body: some View {
        FlickSettingsRow(
            title: title,
            systemImage: systemImage,
            iconColor: iconColor
        ) {
            HStack(spacing: 8) {
                if let value {
                    Text(value)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(valueLineLimit)
                }

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

struct FlickSettingsValueRow: View {
    var title: String
    var systemImage: String
    var iconColor: Color = .primary
    var value: String?
    var valueLineLimit: Int? = 1

    var body: some View {
        FlickSettingsRowLabel(
            title: title,
            systemImage: systemImage,
            iconColor: iconColor,
            value: value,
            valueLineLimit: valueLineLimit
        )
    }
}

struct FlickSettingsActionRow: View {
    var title: String
    var systemImage: String
    var iconColor: Color = .primary
    var value: String?
    var valueLineLimit: Int? = 1
    var showsChevron = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            FlickSettingsRowLabel(
                title: title,
                systemImage: systemImage,
                iconColor: iconColor,
                value: value,
                valueLineLimit: valueLineLimit,
                showsChevron: showsChevron
            )
        }
        .buttonStyle(.plain)
    }
}

struct FlickSettingsNavigationRow<Destination: View>: View {
    var title: String
    var systemImage: String
    var iconColor: Color
    var value: String?
    var valueLineLimit: Int?
    let destination: Destination

    init(
        title: String,
        systemImage: String,
        iconColor: Color = .primary,
        value: String? = nil,
        valueLineLimit: Int? = 1,
        @ViewBuilder destination: () -> Destination
    ) {
        self.title = title
        self.systemImage = systemImage
        self.iconColor = iconColor
        self.value = value
        self.valueLineLimit = valueLineLimit
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            FlickSettingsRowLabel(
                title: title,
                systemImage: systemImage,
                iconColor: iconColor,
                value: value,
                valueLineLimit: valueLineLimit
            )
        }
    }
}

struct FlickSettingsRouteRow<Route: Hashable>: View {
    var title: String
    var systemImage: String
    var route: Route
    var iconColor: Color = .primary
    var value: String?
    var valueLineLimit: Int? = 1

    var body: some View {
        NavigationLink(value: route) {
            FlickSettingsRowLabel(
                title: title,
                systemImage: systemImage,
                iconColor: iconColor,
                value: value,
                valueLineLimit: valueLineLimit
            )
        }
    }
}

private struct FlickSettingsListStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
        #if os(macOS)
        .listStyle(.inset)
        #else
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .flickAppBackground()
    }
}

extension View {
    func flickSettingsListStyle() -> some View {
        modifier(FlickSettingsListStyleModifier())
    }
}
