//
//  AutomationDashboardFormatting.swift
//  Flick
//

import Foundation

enum AutomationDashboardFormatting {
    static func relativeDate(_ date: Date?) -> String {
        guard let date else { return "Not set" }
        return RelativeDateTimeFormatter.automationDashboardShort.localizedString(for: date, relativeTo: Date())
    }

    static func absoluteDate(_ date: Date?) -> String {
        guard let date else { return "Not set" }
        return DateFormatter.automationDashboardAbsolute.string(from: date)
    }

    static func postCount(_ count: Int) -> String {
        count == 1 ? "1 post" : "\(count.formatted()) posts"
    }
}

private extension RelativeDateTimeFormatter {
    static var automationDashboardShort: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }
}

private extension DateFormatter {
    static var automationDashboardAbsolute: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
}
