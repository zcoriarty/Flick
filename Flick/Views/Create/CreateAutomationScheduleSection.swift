//
//  CreateAutomationScheduleSection.swift
//  Flick
//

import SwiftUI

struct CreateAutomationScheduleSection: View {
    @Binding var schedule: AutomationSchedule

    var body: some View {
        Section("Cadence") {
            AutomationWeekdayPicker(weekdays: $schedule.weekdays)

            ForEach(schedule.fixedTimes.indices, id: \.self) { index in
                AutomationTimeRow(
                    index: index,
                    time: fixedTimeBinding(at: index),
                    canRemove: schedule.fixedTimes.count > 1,
                    removeAction: { removeTime(at: index) }
                )
            }

            if schedule.fixedTimes.count < AutomationSchedule.maximumPostsPerDay {
                AddAutomationTimeRow(action: addTime)
            }
        }
    }

    private func fixedTimeBinding(at index: Int) -> Binding<AutomationTimeOfDay> {
        Binding(
            get: {
                var copy = schedule
                copy.reconcileFixedTimes()
                return copy.fixedTimes[min(index, copy.fixedTimes.count - 1)]
            },
            set: { newValue in
                schedule.reconcileFixedTimes()
                guard schedule.fixedTimes.indices.contains(index) else { return }
                schedule.fixedTimes[index] = newValue
                schedule.fixedTimes = schedule.fixedTimes.sorted()
            }
        )
    }

    private func addTime() {
        schedule.addTime()
    }

    private func removeTime(at index: Int) {
        schedule.removeTime(at: index)
    }
}

private struct AutomationWeekdayPicker: View {
    @Binding var weekdays: [AutomationWeekday]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AutomationWeekday.allCases) { weekday in
                Button {
                    toggle(weekday)
                } label: {
                    AutomationWeekdaySegment(
                        weekday: weekday,
                        isSelected: isSelected(weekday)
                    )
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.plain)
                .accessibilityLabel(weekday.displayName)
                .accessibilityAddTraits(isSelected(weekday) ? [.isSelected] : [])
            }
        }
        .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.24), lineWidth: 1)
        }
        .overlay {
            HStack(spacing: 0) {
                ForEach(1..<AutomationWeekday.allCases.count, id: \.self) { _ in
                    Spacer()
                    Rectangle()
                        .fill(Color.secondary.opacity(0.24))
                        .frame(width: 1)
                }
                Spacer()
            }
            .allowsHitTesting(false)
        }
        .clipShape(.rect(cornerRadius: 10))
        .padding(.vertical, 4)
    }

    private func isSelected(_ weekday: AutomationWeekday) -> Bool {
        weekdays.contains(weekday)
    }

    private func toggle(_ weekday: AutomationWeekday) {
        if weekdays.contains(weekday) {
            guard weekdays.count > 1 else { return }
            weekdays.removeAll { $0 == weekday }
        } else {
            weekdays.append(weekday)
            weekdays.sort()
        }
    }
}

private struct AutomationWeekdaySegment: View {
    var weekday: AutomationWeekday
    var isSelected: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(isSelected ? FlickStyle.appTint : Color.clear)

            Text(weekday.shortName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .frame(maxWidth: .infinity, minHeight: 38)
        .contentShape(.rect)
    }
}

private struct AutomationTimeRow: View {
    var index: Int
    @Binding var time: AutomationTimeOfDay
    var canRemove: Bool
    var removeAction: () -> Void

    private var dateBinding: Binding<Date> {
        Binding(
            get: {
                time.date(on: Date()) ?? Date()
            },
            set: { newValue in
                time = AutomationTimeOfDay(date: newValue)
            }
        )
    }

    var body: some View {
        FlickSettingsRow(
            title: "Post \(index + 1)",
            systemImage: "clock",
            iconColor: .orange
        ) {
            HStack(spacing: 8) {
                DatePicker("Post \(index + 1)", selection: dateBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()

                if canRemove {
                    Button("Remove time", systemImage: "minus.circle", action: removeAction)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove post \(index + 1) time")
                }
            }
        }
    }
}

private struct AddAutomationTimeRow: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            FlickSettingsRow(
                title: "Add time",
                systemImage: "plus.circle",
                iconColor: FlickStyle.appTint
            )
        }
        .buttonStyle(.plain)
    }
}
