//
//  FlickAutomationModels.swift
//  Flick
//

import Foundation

enum ContentAutomationStatus: String, CaseIterable, Codable, Identifiable, Hashable {
    case active
    case paused

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .active: "Active"
        case .paused: "Paused"
        }
    }
}

enum AutomationWeekday: Int, CaseIterable, Codable, Identifiable, Hashable, Comparable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var id: Int { rawValue }

    var shortName: String {
        switch self {
        case .sunday: "S"
        case .monday: "M"
        case .tuesday: "T"
        case .wednesday: "W"
        case .thursday: "T"
        case .friday: "F"
        case .saturday: "S"
        }
    }

    var displayName: String {
        switch self {
        case .sunday: "Sunday"
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        }
    }

    static func < (lhs: AutomationWeekday, rhs: AutomationWeekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct AutomationTimeOfDay: Codable, Hashable, Identifiable, Comparable {
    var hour: Int
    var minute: Int

    var id: Int { minutesAfterMidnight }

    var minutesAfterMidnight: Int {
        clampedHour * 60 + clampedMinute
    }

    private var clampedHour: Int {
        min(max(hour, 0), 23)
    }

    private var clampedMinute: Int {
        min(max(minute, 0), 59)
    }

    init(hour: Int, minute: Int = 0) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    init(date: Date, calendar: Calendar = .current) {
        self.init(
            hour: calendar.component(.hour, from: date),
            minute: calendar.component(.minute, from: date)
        )
    }

    func date(on day: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(
            bySettingHour: clampedHour,
            minute: clampedMinute,
            second: 0,
            of: calendar.startOfDay(for: day)
        )
    }

    static func < (lhs: AutomationTimeOfDay, rhs: AutomationTimeOfDay) -> Bool {
        lhs.minutesAfterMidnight < rhs.minutesAfterMidnight
    }
}

struct AutomationSchedule: Codable, Hashable {
    static let maximumPostsPerDay = 6

    var weekdays: [AutomationWeekday]
    var fixedTimes: [AutomationTimeOfDay]

    init(
        weekdays: [AutomationWeekday] = [.monday, .tuesday, .wednesday, .thursday, .friday],
        fixedTimes: [AutomationTimeOfDay] = [AutomationTimeOfDay(hour: 12)]
    ) {
        self.weekdays = weekdays.uniqued().sorted()
        self.fixedTimes = fixedTimes.uniqued().sorted()
        reconcileFixedTimes()
    }

    static var `default`: AutomationSchedule {
        AutomationSchedule()
    }

    var normalizedWeekdays: [AutomationWeekday] {
        weekdays.uniqued().sorted()
    }

    var postsPerDay: Int {
        fixedTimes.count
    }

    var isValid: Bool {
        guard !normalizedWeekdays.isEmpty else { return false }
        return !fixedTimes.isEmpty && fixedTimes.count <= Self.maximumPostsPerDay
    }

    mutating func reconcileFixedTimes() {
        weekdays = normalizedWeekdays
        fixedTimes = fixedTimes.uniqued().sorted()
        if fixedTimes.isEmpty {
            fixedTimes = [AutomationTimeOfDay(hour: 12)]
        }
        fixedTimes = Array(fixedTimes.prefix(Self.maximumPostsPerDay))
    }

    func nextOccurrence(after referenceDate: Date, automationID: UUID, calendar: Calendar = .current) -> Date? {
        let selectedWeekdays = Set(normalizedWeekdays)
        guard !selectedWeekdays.isEmpty else { return nil }

        let referenceStartOfDay = calendar.startOfDay(for: referenceDate)
        for dayOffset in 0...370 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: referenceStartOfDay) else {
                continue
            }
            guard
                let weekday = AutomationWeekday(rawValue: calendar.component(.weekday, from: day)),
                selectedWeekdays.contains(weekday)
            else {
                continue
            }

            var copy = self
            copy.reconcileFixedTimes()
            for time in copy.fixedTimes.sorted() {
                guard let candidate = time.date(on: day, calendar: calendar), candidate > referenceDate else {
                    continue
                }
                return candidate
            }
        }

        return nil
    }

    func summary(calendar: Calendar = .current) -> String {
        let dayText = weekdaySummary
        let countText = postsPerDay == 1 ? "1 post" : "\(postsPerDay) posts"
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let referenceDay = calendar.startOfDay(for: Date())
        let timeText = fixedTimes
            .sorted()
            .compactMap { $0.date(on: referenceDay, calendar: calendar) }
            .map(formatter.string(from:))
            .joined(separator: ", ")

        return [dayText, countText, timeText]
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
    }

    private var weekdaySummary: String {
        let days = normalizedWeekdays
        if days == AutomationWeekday.allCases {
            return "Daily"
        }
        if days == [.monday, .tuesday, .wednesday, .thursday, .friday] {
            return "Weekdays"
        }
        if days == [.saturday, .sunday] {
            return "Weekends"
        }
        return days.map(\.shortName).joined()
    }

    mutating func addTime() {
        guard fixedTimes.count < Self.maximumPostsPerDay else { return }
        let nextMinutes = min(
            23 * 60 + 45,
            (fixedTimes.sorted().last?.minutesAfterMidnight ?? 12 * 60) + 120
        )
        fixedTimes.append(AutomationTimeOfDay(hour: nextMinutes / 60, minute: nextMinutes % 60))
        reconcileFixedTimes()
    }

    mutating func removeTime(at index: Int) {
        guard fixedTimes.count > 1, fixedTimes.indices.contains(index) else { return }
        fixedTimes.remove(at: index)
        reconcileFixedTimes()
    }
}

struct ContentAutomation: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var templateIDs: [String]
    var productID: UUID?
    var productImageAssetIDs: [UUID]
    var schedule: AutomationSchedule
    var tikTokSettings: DraftTikTokSettings
    var targetPlatforms: [SocialPlatform]
    var status: ContentAutomationStatus
    var nextScheduledAt: Date?
    var lastRunAt: Date?
    var lastErrorMessage: String?
    var consecutiveFailureCount: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "",
        templateIDs: [String],
        productID: UUID?,
        productImageAssetIDs: [UUID],
        schedule: AutomationSchedule,
        tikTokSettings: DraftTikTokSettings,
        targetPlatforms: [SocialPlatform] = [.tiktok],
        status: ContentAutomationStatus = .active,
        nextScheduledAt: Date? = nil,
        lastRunAt: Date? = nil,
        lastErrorMessage: String? = nil,
        consecutiveFailureCount: Int = 0,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.templateIDs = templateIDs.uniqued()
        self.productID = productID
        self.productImageAssetIDs = productImageAssetIDs.uniqued()
        self.schedule = schedule
        self.tikTokSettings = tikTokSettings
        self.targetPlatforms = targetPlatforms.uniqued()
        self.status = status
        self.nextScheduledAt = nextScheduledAt
        self.lastRunAt = lastRunAt
        self.lastErrorMessage = lastErrorMessage
        self.consecutiveFailureCount = consecutiveFailureCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func displayName(
        templates: [ExampleSlideshowTemplate] = [],
        products: [FlickProduct] = []
    ) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty else { return trimmedName }
        return defaultName(templates: templates, products: products)
    }

    func defaultName(
        templates: [ExampleSlideshowTemplate] = [],
        products: [FlickProduct] = []
    ) -> String {
        let templateSummary: String
        let matchingTemplates = templates.filter { templateIDs.contains($0.id) }
        if matchingTemplates.count == 1, let template = matchingTemplates.first {
            templateSummary = template.niche
        } else if matchingTemplates.count > 1 {
            templateSummary = "\(matchingTemplates.count) templates"
        } else if templateIDs.count == 1 {
            templateSummary = "1 template"
        } else {
            templateSummary = "\(max(templateIDs.count, 1)) templates"
        }

        let productSummary = productID
            .flatMap { productID in products.first { $0.id == productID }?.name }
            ?? "product posts"

        return "\(productSummary) - \(templateSummary) - \(schedule.summary())"
    }

    func nextOccurrence(after referenceDate: Date, calendar: Calendar = .current) -> Date? {
        schedule.nextOccurrence(after: referenceDate, automationID: id, calendar: calendar)
    }

    var isReadyToSchedule: Bool {
        !templateIDs.isEmpty
            && productID != nil
            && !productImageAssetIDs.isEmpty
            && schedule.isValid
            && tikTokSettings.automatedPublishSettings(description: "") != nil
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
