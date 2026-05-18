//
//  FlickSection.swift
//  Flick
//

import Foundation

enum FlickSection: String, CaseIterable, Identifiable {
    case dashboard
    case product
    case create
    case templates
    case accounts
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .product: "Product"
        case .create: "Create"
        case .templates: "Templates"
        case .accounts: "Accounts"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "house"
        case .product: "shippingbox"
        case .create: "wand.and.sparkles"
        case .templates: "rectangle.stack.badge.play"
        case .accounts: "person.2.badge.gearshape"
        case .settings: "gearshape"
        }
    }
}
