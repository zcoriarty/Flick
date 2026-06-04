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

struct AutomationScheduleSlot: Codable, Hashable {
    var time: AutomationTimeOfDay?

    init(time: AutomationTimeOfDay? = nil) {
        self.time = time
    }

    static var random: AutomationScheduleSlot {
        AutomationScheduleSlot()
    }
}

enum AutomationIntervalUnit: String, CaseIterable, Codable, Identifiable, Hashable {
    case minutes
    case hours

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .minutes: "Min"
        case .hours: "Hr"
        }
    }

    var summaryName: String {
        switch self {
        case .minutes: "minutes"
        case .hours: "hours"
        }
    }

    var valueRange: ClosedRange<Int> {
        switch self {
        case .minutes: 5...720
        case .hours: 1...24
        }
    }

    var valueStep: Int {
        switch self {
        case .minutes: 5
        case .hours: 1
        }
    }
}

struct AutomationIntervalCadence: Codable, Hashable {
    var value: Int
    var unit: AutomationIntervalUnit

    init(value: Int = 2, unit: AutomationIntervalUnit = .hours) {
        self.value = value
        self.unit = unit
        normalize()
    }

    var seconds: TimeInterval {
        switch unit {
        case .minutes: TimeInterval(value * 60)
        case .hours: TimeInterval(value * 60 * 60)
        }
    }

    var summary: String {
        if value == 1 {
            switch unit {
            case .minutes: return "Every minute"
            case .hours: return "Every hour"
            }
        }

        return "Every \(value) \(unit.summaryName)"
    }

    mutating func normalize() {
        let range = unit.valueRange
        value = min(max(value, range.lowerBound), range.upperBound)

        if unit == .minutes {
            let remainder = value % unit.valueStep
            if remainder != 0 {
                value += unit.valueStep - remainder
                value = min(value, range.upperBound)
            }
        }
    }
}

enum AutomationScheduleCadence: Hashable {
    enum Kind: String, CaseIterable, Identifiable {
        case slots
        case interval

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .slots: "Posts"
            case .interval: "Every"
            }
        }
    }

    case slots([AutomationScheduleSlot])
    case interval(AutomationIntervalCadence)

    var kind: Kind {
        switch self {
        case .slots: .slots
        case .interval: .interval
        }
    }

    var normalized: AutomationScheduleCadence {
        switch self {
        case let .slots(slots):
            let normalizedSlots = Array(slots.prefix(AutomationSchedule.maximumPostsPerDay))
            return .slots(normalizedSlots.isEmpty ? [.random] : normalizedSlots)
        case var .interval(interval):
            interval.normalize()
            return .interval(interval)
        }
    }
}

extension AutomationScheduleCadence: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case slots
        case interval
    }

    private enum KindValue: String, Codable {
        case slots
        case interval
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(KindValue.self, forKey: .kind)

        switch kind {
        case .slots:
            let slots = try container.decode([AutomationScheduleSlot].self, forKey: .slots)
            self = .slots(slots)
        case .interval:
            let interval = try container.decode(AutomationIntervalCadence.self, forKey: .interval)
            self = .interval(interval)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .slots(slots):
            try container.encode(KindValue.slots, forKey: .kind)
            try container.encode(slots, forKey: .slots)
        case let .interval(interval):
            try container.encode(KindValue.interval, forKey: .kind)
            try container.encode(interval, forKey: .interval)
        }
    }
}

struct AutomationSchedule: Codable, Hashable {
    static let maximumPostsPerDay = 6

    var weekdays: [AutomationWeekday]
    var cadence: AutomationScheduleCadence

    init(
        weekdays: [AutomationWeekday] = [.monday, .tuesday, .wednesday, .thursday, .friday],
        fixedTimes: [AutomationTimeOfDay]
    ) {
        self.weekdays = weekdays.uniqued().sorted()
        cadence = .slots(fixedTimes.uniqued().sorted().map { AutomationScheduleSlot(time: $0) })
        reconcileCadence()
    }

    init(
        weekdays: [AutomationWeekday] = [.monday, .tuesday, .wednesday, .thursday, .friday],
        slots: [AutomationScheduleSlot] = [.random]
    ) {
        self.weekdays = weekdays.uniqued().sorted()
        cadence = .slots(slots)
        reconcileCadence()
    }

    init(
        weekdays: [AutomationWeekday] = [.monday, .tuesday, .wednesday, .thursday, .friday],
        cadence: AutomationScheduleCadence
    ) {
        self.weekdays = weekdays.uniqued().sorted()
        self.cadence = cadence
        reconcileCadence()
    }

    static var `default`: AutomationSchedule {
        AutomationSchedule()
    }

    var normalizedWeekdays: [AutomationWeekday] {
        weekdays.uniqued().sorted()
    }

    var postSlots: [AutomationScheduleSlot] {
        get {
            guard case let .slots(slots) = cadence else { return [] }
            return slots
        }
        set {
            cadence = .slots(newValue)
            reconcileCadence()
        }
    }

    var intervalCadence: AutomationIntervalCadence {
        get {
            guard case let .interval(interval) = cadence else {
                return AutomationIntervalCadence()
            }
            return interval
        }
        set {
            cadence = .interval(newValue)
            reconcileCadence()
        }
    }

    var fixedTimes: [AutomationTimeOfDay] {
        get {
            guard case let .slots(slots) = cadence else { return [] }
            return slots.compactMap(\.time).sorted()
        }
        set {
            cadence = .slots(newValue.uniqued().sorted().map { AutomationScheduleSlot(time: $0) })
            reconcileCadence()
        }
    }

    var postsPerDay: Int {
        switch cadence {
        case let .slots(slots): slots.count
        case .interval: 0
        }
    }

    var isValid: Bool {
        guard !normalizedWeekdays.isEmpty else { return false }
        switch cadence.normalized {
        case let .slots(slots):
            return !slots.isEmpty && slots.count <= Self.maximumPostsPerDay
        case let .interval(interval):
            return interval.seconds > 0
        }
    }

    mutating func reconcileCadence() {
        weekdays = normalizedWeekdays
        cadence = cadence.normalized
    }

    mutating func reconcileFixedTimes() {
        reconcileCadence()
    }

    func nextOccurrence(after referenceDate: Date, automationID: UUID, calendar: Calendar = .current) -> Date? {
        let selectedWeekdays = Set(normalizedWeekdays)
        guard !selectedWeekdays.isEmpty else { return nil }

        switch cadence.normalized {
        case let .slots(slots):
            return nextSlotOccurrence(
                after: referenceDate,
                automationID: automationID,
                slots: slots,
                selectedWeekdays: selectedWeekdays,
                calendar: calendar
            )
        case let .interval(interval):
            return nextIntervalOccurrence(
                after: referenceDate,
                interval: interval,
                selectedWeekdays: selectedWeekdays,
                calendar: calendar
            )
        }
    }

    func summary(calendar: Calendar = .current) -> String {
        let dayText = weekdaySummary

        switch cadence.normalized {
        case let .slots(slots):
            let countText = slots.count == 1 ? "1 post" : "\(slots.count) posts"
            let timeText = slotTimeSummary(slots: slots, calendar: calendar)
            return [dayText, countText, timeText]
                .filter { !$0.isEmpty }
                .joined(separator: " - ")
        case let .interval(interval):
            return [dayText, interval.summary]
                .filter { !$0.isEmpty }
                .joined(separator: " - ")
        }
    }

    mutating func setCadenceKind(_ kind: AutomationScheduleCadence.Kind) {
        guard cadence.kind != kind else { return }

        switch kind {
        case .slots:
            cadence = .slots([.random])
        case .interval:
            cadence = .interval(AutomationIntervalCadence())
        }

        reconcileCadence()
    }

    mutating func addSlot() {
        guard case var .slots(slots) = cadence else { return }
        guard slots.count < Self.maximumPostsPerDay else { return }
        slots.append(.random)
        cadence = .slots(slots)
        reconcileCadence()
    }

    mutating func removeSlot(at index: Int) {
        guard case var .slots(slots) = cadence else { return }
        guard slots.count > 1, slots.indices.contains(index) else { return }
        slots.remove(at: index)
        cadence = .slots(slots)
        reconcileCadence()
    }

    mutating func addTime() {
        addSlot()
    }

    mutating func removeTime(at index: Int) {
        removeSlot(at: index)
    }

    private func nextSlotOccurrence(
        after referenceDate: Date,
        automationID: UUID,
        slots: [AutomationScheduleSlot],
        selectedWeekdays: Set<AutomationWeekday>,
        calendar: Calendar
    ) -> Date? {
        guard !slots.isEmpty else { return nil }

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

            for time in resolvedTimes(on: day, slots: slots, automationID: automationID, calendar: calendar) {
                guard let candidate = time.date(on: day, calendar: calendar), candidate > referenceDate else {
                    continue
                }
                return candidate
            }
        }

        return nil
    }

    private func nextIntervalOccurrence(
        after referenceDate: Date,
        interval: AutomationIntervalCadence,
        selectedWeekdays: Set<AutomationWeekday>,
        calendar: Calendar
    ) -> Date? {
        var candidate = referenceDate.addingTimeInterval(interval.seconds)

        for _ in 0..<(370 * 24) {
            if isSelectedWeekday(candidate, selectedWeekdays: selectedWeekdays, calendar: calendar) {
                return candidate
            }

            guard let nextDay = calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: candidate)
            ) else {
                return nil
            }
            candidate = nextDay
        }

        return nil
    }

    private func resolvedTimes(
        on day: Date,
        slots: [AutomationScheduleSlot],
        automationID: UUID,
        calendar: Calendar
    ) -> [AutomationTimeOfDay] {
        var usedMinutes = Set(slots.compactMap { $0.time?.minutesAfterMidnight })
        return slots.enumerated()
            .map { index, slot in
                if let time = slot.time {
                    return time
                }

                let time = randomTime(
                    on: day,
                    slotIndex: index,
                    automationID: automationID,
                    usedMinutes: usedMinutes,
                    calendar: calendar
                )
                usedMinutes.insert(time.minutesAfterMidnight)
                return time
            }
            .sorted()
    }

    private func randomTime(
        on day: Date,
        slotIndex: Int,
        automationID: UUID,
        usedMinutes: Set<Int>,
        calendar: Calendar
    ) -> AutomationTimeOfDay {
        let dayOrdinal = calendar.ordinality(of: .day, in: .era, for: day) ?? Int(day.timeIntervalSince1970 / 86_400)
        let seed = stableSeed("\(automationID.uuidString)-\(dayOrdinal)-\(slotIndex)")
        let stepMinutes = 5
        let stepCount = (24 * 60) / stepMinutes
        let startStep = Int(seed % UInt64(stepCount))

        for offset in 0..<stepCount {
            let minutes = ((startStep + offset) % stepCount) * stepMinutes
            if !usedMinutes.contains(minutes) {
                return AutomationTimeOfDay(hour: minutes / 60, minute: minutes % 60)
            }
        }

        return AutomationTimeOfDay(hour: 12)
    }

    private func isSelectedWeekday(
        _ date: Date,
        selectedWeekdays: Set<AutomationWeekday>,
        calendar: Calendar
    ) -> Bool {
        guard let weekday = AutomationWeekday(rawValue: calendar.component(.weekday, from: date)) else {
            return false
        }
        return selectedWeekdays.contains(weekday)
    }

    private func slotTimeSummary(slots: [AutomationScheduleSlot], calendar: Calendar) -> String {
        let randomCount = slots.filter { $0.time == nil }.count
        guard randomCount != slots.count else {
            return slots.count == 1 ? "Random time" : "Random times"
        }

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let referenceDay = calendar.startOfDay(for: Date())
        return slots
            .map { slot in
                guard let time = slot.time else { return "Random" }
                guard let date = time.date(on: referenceDay, calendar: calendar) else { return "" }
                return formatter.string(from: date)
            }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
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
}

extension AutomationSchedule {
    private enum CodingKeys: String, CodingKey {
        case weekdays
        case fixedTimes
        case cadence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weekdays = try container.decodeIfPresent([AutomationWeekday].self, forKey: .weekdays)
            ?? [.monday, .tuesday, .wednesday, .thursday, .friday]

        if let cadence = try container.decodeIfPresent(AutomationScheduleCadence.self, forKey: .cadence) {
            self.cadence = cadence
        } else if let fixedTimes = try container.decodeIfPresent([AutomationTimeOfDay].self, forKey: .fixedTimes) {
            self.cadence = .slots(fixedTimes.uniqued().sorted().map { AutomationScheduleSlot(time: $0) })
        } else {
            cadence = .slots([.random])
        }

        reconcileCadence()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(weekdays, forKey: .weekdays)
        try container.encode(cadence.normalized, forKey: .cadence)
    }
}

struct ContentAutomation: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var templateIDs: [String]
    var templateNicheIDs: [String]
    var productID: UUID?
    var productImageAssetIDs: [UUID]
    var creationModel: SlideshowCreationModelReference?
    var schedule: AutomationSchedule
    var tikTokSettings: DraftTikTokSettings
    var youtubeSettings: DraftYouTubeSettings
    var targetPlatforms: [SocialPlatform]
    var accountSelections: [PlatformAccountSelection]
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
        templateNicheIDs: [String] = [],
        productID: UUID?,
        productImageAssetIDs: [UUID],
        creationModel: SlideshowCreationModelReference? = nil,
        schedule: AutomationSchedule,
        tikTokSettings: DraftTikTokSettings,
        youtubeSettings: DraftYouTubeSettings = DraftYouTubeSettings(),
        targetPlatforms: [SocialPlatform] = [.tiktok],
        accountSelections: [PlatformAccountSelection] = [],
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
        self.templateNicheIDs = templateNicheIDs.uniqued()
        self.productID = productID
        self.productImageAssetIDs = productImageAssetIDs.uniqued()
        self.creationModel = creationModel
        self.schedule = schedule
        self.tikTokSettings = tikTokSettings
        self.youtubeSettings = youtubeSettings
        self.targetPlatforms = targetPlatforms.uniqued()
        self.accountSelections = accountSelections.normalizedUniqueSelections()
        self.status = status
        self.nextScheduledAt = nextScheduledAt
        self.lastRunAt = lastRunAt
        self.lastErrorMessage = lastErrorMessage
        self.consecutiveFailureCount = consecutiveFailureCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case templateIDs
        case templateNicheIDs
        case productID
        case productImageAssetIDs
        case creationModel
        case schedule
        case tikTokSettings
        case youtubeSettings
        case targetPlatforms
        case accountSelections
        case status
        case nextScheduledAt
        case lastRunAt
        case lastErrorMessage
        case consecutiveFailureCount
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        templateIDs = try container.decode([String].self, forKey: .templateIDs).uniqued()
        templateNicheIDs = try container.decodeIfPresent([String].self, forKey: .templateNicheIDs)?.uniqued() ?? []
        productID = try container.decodeIfPresent(UUID.self, forKey: .productID)
        productImageAssetIDs = try container.decode([UUID].self, forKey: .productImageAssetIDs).uniqued()
        creationModel = try container.decodeIfPresent(SlideshowCreationModelReference.self, forKey: .creationModel)
        schedule = try container.decode(AutomationSchedule.self, forKey: .schedule)
        tikTokSettings = try container.decode(DraftTikTokSettings.self, forKey: .tikTokSettings)
        youtubeSettings = try container.decodeIfPresent(DraftYouTubeSettings.self, forKey: .youtubeSettings) ?? DraftYouTubeSettings()
        targetPlatforms = try container.decode([SocialPlatform].self, forKey: .targetPlatforms).uniqued()
        accountSelections = try container.decodeIfPresent([PlatformAccountSelection].self, forKey: .accountSelections)?
            .normalizedUniqueSelections()
            ?? []
        status = try container.decode(ContentAutomationStatus.self, forKey: .status)
        nextScheduledAt = try container.decodeIfPresent(Date.self, forKey: .nextScheduledAt)
        lastRunAt = try container.decodeIfPresent(Date.self, forKey: .lastRunAt)
        lastErrorMessage = try container.decodeIfPresent(String.self, forKey: .lastErrorMessage)
        consecutiveFailureCount = try container.decode(Int.self, forKey: .consecutiveFailureCount)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
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
        if templateNicheIDs.count == 1, templateIDs.isEmpty {
            templateSummary = "1 niche"
        } else if templateNicheIDs.count > 1, templateIDs.isEmpty {
            templateSummary = "\(templateNicheIDs.count) niches"
        } else if !templateNicheIDs.isEmpty {
            let nicheText = templateNicheIDs.count == 1 ? "1 niche" : "\(templateNicheIDs.count) niches"
            let templateText = templateIDs.count == 1 ? "1 template" : "\(templateIDs.count) templates"
            templateSummary = "\(nicheText), \(templateText)"
        } else if matchingTemplates.count == 1, let template = matchingTemplates.first {
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
        (!templateIDs.isEmpty || !templateNicheIDs.isEmpty)
            && productID != nil
            && !productImageAssetIDs.isEmpty
            && schedule.isValid
            && hasValidPublishSettings
            && hasSelectedAccountForEachTarget
    }

    var hasValidPublishSettings: Bool {
        let targets = targetPlatforms.isEmpty ? [SocialPlatform.tiktok] : targetPlatforms
        return targets.allSatisfy { platform in
            switch platform {
            case .tiktok:
                tikTokSettings.automatedPublishSettings(description: "") != nil
            case .youtubeShorts:
                youtubeSettings.automatedPublishSettings(
                    fallbackTitle: name.isEmpty ? "Flick post" : name,
                    fallbackDescription: "",
                    fallbackHashtags: []
                ) != nil
            case .instagram, .threads, .x:
                false
            }
        }
    }

    var hasSelectedAccountForEachTarget: Bool {
        let targets = targetPlatforms.isEmpty ? [SocialPlatform.tiktok] : targetPlatforms
        return targets.allSatisfy { platform in
            !accountSelections.accountIDs(for: platform).isEmpty
        }
    }
}

private func stableSeed(_ string: String) -> UInt64 {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return hash
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
