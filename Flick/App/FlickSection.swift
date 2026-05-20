//
//  FlickSection.swift
//  Flick
//

import Foundation

enum FlickSection: String, CaseIterable, Identifiable {
    case dashboard
    case media
    case product
    case models
    case create
    case templates
    case accounts
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .media: "Media"
        case .product: "Product"
        case .models: "Models"
        case .create: "Create"
        case .templates: "Templates"
        case .accounts: "Accounts"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "house"
        case .media: "photo.stack"
        case .product: "shippingbox"
        case .models: "person.fill.viewfinder"
        case .create: "wand.and.sparkles"
        case .templates: "rectangle.stack.badge.play"
        case .accounts: "person.2.badge.gearshape"
        case .settings: "gearshape"
        }
    }
}
