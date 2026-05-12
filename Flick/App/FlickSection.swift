//
//  FlickSection.swift
//  Flick
//

import Foundation

enum FlickSection: String, CaseIterable, Identifiable {
    case dashboard
    case create
    case queue
    case trends
    case analytics
    case accounts
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .create: "Create"
        case .queue: "Queue"
        case .trends: "Trends"
        case .analytics: "Analytics"
        case .accounts: "Accounts"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "house"
        case .create: "wand.and.sparkles"
        case .queue: "calendar.badge.clock"
        case .trends: "sparkles.rectangle.stack"
        case .analytics: "chart.xyaxis.line"
        case .accounts: "person.2.badge.gearshape"
        case .settings: "gearshape"
        }
    }
}
