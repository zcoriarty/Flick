//
//  CreateCadenceSection.swift
//  Flick
//

import Foundation
import SwiftUI

struct CreateCadenceSection: View {
    @Binding var postTime: Date
    @Binding var selectedWeekdays: Set<CreateWeekday>

    var body: some View {
        Section("Cadence") {
            FlickSettingsRow(
                title: "Time to post",
                systemImage: "clock",
                iconColor: .orange
            ) {
                DatePicker(
                    "Time to post",
                    selection: $postTime,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
            }

            WeekdaySelectionRow(selectedWeekdays: $selectedWeekdays)
        }
    }
}

enum CreateWeekday: Int, CaseIterable, Identifiable, Hashable {
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    var id: Int { rawValue }

    static var orderedCases: [CreateWeekday] { allCases }

    static var current: CreateWeekday {
        switch Calendar.current.component(.weekday, from: Date()) {
        case 1: .sunday
        case 2: .monday
        case 3: .tuesday
        case 4: .wednesday
        case 5: .thursday
        case 6: .friday
        case 7: .saturday
        default: .monday
        }
    }

    var shortTitle: String {
        switch self {
        case .monday: "M"
        case .tuesday: "T"
        case .wednesday: "W"
        case .thursday: "T"
        case .friday: "F"
        case .saturday: "S"
        case .sunday: "S"
        }
    }

    var title: String {
        switch self {
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        case .sunday: "Sunday"
        }
    }
}

private struct WeekdaySelectionRow: View {
    @Binding var selectedWeekdays: Set<CreateWeekday>

    private var weekdayColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 34), spacing: 8), count: 7)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Days to post", systemImage: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: weekdayColumns, spacing: 8) {
                ForEach(CreateWeekday.orderedCases) { weekday in
                    Button {
                        toggle(weekday)
                    } label: {
                        Text(weekday.shortTitle)
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .foregroundStyle(selectedWeekdays.contains(weekday) ? .white : .primary)
                            .background(
                                selectedWeekdays.contains(weekday) ? Color.indigo : Color.secondary.opacity(0.12),
                                in: .rect(cornerRadius: 8)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(weekday.title)
                    .accessibilityValue(selectedWeekdays.contains(weekday) ? "Selected" : "Not selected")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func toggle(_ weekday: CreateWeekday) {
        if selectedWeekdays.contains(weekday) {
            guard selectedWeekdays.count > 1 else { return }
            selectedWeekdays.remove(weekday)
        } else {
            selectedWeekdays.insert(weekday)
        }
    }
}
