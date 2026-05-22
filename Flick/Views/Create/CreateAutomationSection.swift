//
//  CreateAutomationSection.swift
//  Flick
//

import SwiftUI

struct CreateAutomationSection: View {
    @Binding var isAutomated: Bool
    @Binding var schedule: AutomationSchedule

    var body: some View {
        Section("Automation") {
            FlickSettingsRow(
                title: "Automated",
                systemImage: "calendar.badge.clock",
                iconColor: isAutomated ? .green : .secondary
            ) {
                Toggle("Automated", isOn: animatedAutomationBinding)
                    .labelsHidden()
            }

            if isAutomated {
                AutomationWeekdayPicker(weekdays: $schedule.weekdays)
                AutomationCadenceModePicker(selection: cadenceKindBinding)

                switch schedule.cadence.kind {
                case .slots:
                    ForEach(schedule.postSlots.indices, id: \.self) { index in
                        AutomationSlotRow(
                            index: index,
                            slot: slotBinding(at: index),
                            canRemove: schedule.postSlots.count > 1,
                            removeAction: { removeSlot(at: index) }
                        )
                    }

                    if schedule.postSlots.count < AutomationSchedule.maximumPostsPerDay {
                        AddAutomationSlotRow(action: addSlot)
                    }
                case .interval:
                    AutomationIntervalRow(interval: intervalBinding)
                }
            }
        }
        .animation(.snappy, value: isAutomated)
        .animation(.snappy, value: schedule.cadence.kind)
    }

    private var animatedAutomationBinding: Binding<Bool> {
        Binding(
            get: { isAutomated },
            set: { newValue in
                withAnimation(.snappy) {
                    isAutomated = newValue
                }
            }
        )
    }

    private var cadenceKindBinding: Binding<AutomationScheduleCadence.Kind> {
        Binding(
            get: { schedule.cadence.kind },
            set: { newValue in
                withAnimation(.snappy) {
                    schedule.setCadenceKind(newValue)
                }
            }
        )
    }

    private var intervalBinding: Binding<AutomationIntervalCadence> {
        Binding(
            get: { schedule.intervalCadence },
            set: { schedule.intervalCadence = $0 }
        )
    }

    private func slotBinding(at index: Int) -> Binding<AutomationScheduleSlot> {
        Binding(
            get: {
                var copy = schedule
                copy.reconcileCadence()
                let slots = copy.postSlots
                guard slots.indices.contains(index) else { return .random }
                return slots[index]
            },
            set: { newValue in
                schedule.reconcileCadence()
                guard schedule.postSlots.indices.contains(index) else { return }
                var slots = schedule.postSlots
                slots[index] = newValue
                schedule.postSlots = slots
            }
        )
    }

    private func addSlot() {
        schedule.addSlot()
    }

    private func removeSlot(at index: Int) {
        schedule.removeSlot(at: index)
    }
}

private struct AutomationCadenceModePicker: View {
    @Binding var selection: AutomationScheduleCadence.Kind

    var body: some View {
        Picker("Cadence", selection: $selection) {
            ForEach(AutomationScheduleCadence.Kind.allCases) { kind in
                Text(kind.displayName).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Cadence")
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

private struct AutomationSlotRow: View {
    var index: Int
    @Binding var slot: AutomationScheduleSlot
    var canRemove: Bool
    var removeAction: () -> Void

    private var dateBinding: Binding<Date> {
        Binding(
            get: {
                slot.time?.date(on: Date()) ?? Date()
            },
            set: { newValue in
                slot.time = AutomationTimeOfDay(date: newValue)
            }
        )
    }

    var body: some View {
        FlickSettingsRow(
            title: "Post \(index + 1)",
            systemImage: slot.time == nil ? "shuffle" : "clock",
            iconColor: slot.time == nil ? .blue : .orange
        ) {
            HStack(spacing: 8) {
                if slot.time == nil {
                    Button {
                        slot.time = AutomationTimeOfDay(date: Date())
                    } label: {
                        Label("Random", systemImage: "shuffle")
                    }
                    .labelStyle(.titleAndIcon)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Post \(index + 1) random time. Set fixed time.")
                } else {
                    DatePicker("Post \(index + 1)", selection: dateBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()

                    Button("Use random time", systemImage: "shuffle") {
                        slot.time = nil
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Use random time for post \(index + 1)")
                }

                if canRemove {
                    Button("Remove post", systemImage: "minus.circle", action: removeAction)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove post \(index + 1)")
                }
            }
        }
    }
}

private struct AutomationIntervalRow: View {
    @Binding var interval: AutomationIntervalCadence

    private var valueBinding: Binding<Int> {
        Binding(
            get: { interval.value },
            set: { newValue in
                interval.value = newValue
                interval.normalize()
            }
        )
    }

    private var unitBinding: Binding<AutomationIntervalUnit> {
        Binding(
            get: { interval.unit },
            set: { newValue in
                interval.unit = newValue
                interval.normalize()
            }
        )
    }

    var body: some View {
        FlickSettingsRow(
            title: "Repeat",
            systemImage: "repeat",
            iconColor: .teal
        ) {
            HStack(spacing: 10) {
                Stepper(value: valueBinding, in: interval.unit.valueRange, step: interval.unit.valueStep) {
                    Text("\(interval.value)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 28, alignment: .trailing)
                }
                .fixedSize()

                Picker("Unit", selection: unitBinding) {
                    ForEach(AutomationIntervalUnit.allCases) { unit in
                        Text(unit.shortName).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 104)
            }
            .controlSize(.small)
        }
    }
}

private struct AddAutomationSlotRow: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            FlickSettingsRow(
                title: "Add post",
                systemImage: "plus.circle",
                iconColor: FlickStyle.appTint
            )
        }
        .buttonStyle(.plain)
    }
}
