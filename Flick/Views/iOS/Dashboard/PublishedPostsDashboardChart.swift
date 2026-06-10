//
//  PublishedPostsDashboardChart.swift
//  Flick
//

#if !os(macOS)
import SwiftUI

struct PublishedPostsDashboardChart: View {
    var posts: [PublishedPost]
    var publishingJobs: [PublishingJob]
    var accounts: [ConnectedAccount]
    var horizontalPadding: CGFloat = 16

    @State private var selectedPostType: PublishedPostsChartType = .sent
    @State private var selectedPlatform: SocialPlatform?
    @State private var selectedAccountID: UUID?
    @State private var selectedBucketIndex: Int?
    @State private var hasInteractedWithChart = false
    @State private var selectionResetToken = 0

    private static let selectionResetDelay: Duration = .seconds(6)

    private static let accountPalette: [Color] = [
        .blue,
        .green,
        .orange,
        .purple,
        .teal,
        .indigo,
        .pink,
        .cyan,
        .mint,
        .brown
    ]

    private var accountByID: [UUID: ConnectedAccount] {
        Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
    }

    private var chartEvents: [PublishedPostsChartEvent] {
        selectedPostType.events(posts: posts, publishingJobs: publishingJobs)
    }

    private var platformOptions: [SocialPlatform] {
        SocialPlatform.allCases.filter { platform in
            chartEvents.contains { $0.platform == platform }
        }
    }

    private var effectiveSelectedPlatform: SocialPlatform? {
        guard let selectedPlatform,
              platformOptions.contains(selectedPlatform)
        else { return nil }

        return selectedPlatform
    }

    private var accountOptions: [PublishedPostsAccountOption] {
        guard let effectiveSelectedPlatform else { return [] }

        let platformEvents = chartEvents.filter { $0.platform == effectiveSelectedPlatform }
        let eventsByAccountID = Dictionary(grouping: platformEvents, by: \.accountID)

        return eventsByAccountID.map { accountID, accountEvents in
            let account = accountByID[accountID]
            return PublishedPostsAccountOption(
                id: accountID,
                displayName: account?.displayName.trimmedNonEmpty ?? "Unavailable account",
                platformUserID: account?.platformUserID.trimmedNonEmpty,
                postCount: accountEvents.count
            )
        }
        .sorted {
            if $0.postCount == $1.postCount {
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            return $0.postCount > $1.postCount
        }
    }

    private var accountColorByID: [UUID: Color] {
        Dictionary(uniqueKeysWithValues: accountOptions.enumerated().map { index, option in
            (option.id, Self.accountPalette[index % Self.accountPalette.count])
        })
    }

    private var effectiveSelectedAccountID: UUID? {
        guard effectiveSelectedPlatform != nil,
              let selectedAccountID,
              accountOptions.contains(where: { $0.id == selectedAccountID })
        else { return nil }

        return selectedAccountID
    }

    private var filteredEvents: [PublishedPostsChartEvent] {
        chartEvents.filter { event in
            if let effectiveSelectedPlatform, event.platform != effectiveSelectedPlatform {
                return false
            }

            if let effectiveSelectedAccountID, event.accountID != effectiveSelectedAccountID {
                return false
            }

            return true
        }
    }

    private var snapshot: PublishedPostsChartSnapshot {
        PublishedPostsChartSnapshot.make(
            events: filteredEvents,
            selectedPlatform: effectiveSelectedPlatform,
            selectedAccountID: effectiveSelectedAccountID,
            accountOptions: accountOptions,
            accountColorByID: accountColorByID
        )
    }

    private var effectiveSelectedBucket: PublishedPostsChartBucket? {
        guard let index = selectedBucketIndex else { return nil }
        return snapshot.buckets.first { $0.id == index }
    }

    private var filterDescription: String {
        if let effectiveSelectedPlatform {
            if let account = accountOptions.first(where: { $0.id == effectiveSelectedAccountID }) {
                return "\(effectiveSelectedPlatform.displayName), \(account.displayName)"
            }
            return "\(effectiveSelectedPlatform.displayName), all accounts"
        }

        return "All platforms"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            filterControls

            if snapshot.hasPosts {
                PublishedPostsChartCanvas(
                    snapshot: snapshot,
                    postType: selectedPostType,
                    selectedBucketIndex: $selectedBucketIndex,
                    hasInteractedWithChart: $hasInteractedWithChart,
                    onSelectionChanged: scheduleSelectionReset,
                    onDragEnded: clearSelection
                )
                .frame(height: 324)
                .transition(
                    .opacity
                        .combined(with: .scale(scale: 0.98, anchor: .top))
                )
            } else {
                emptyState
            }

            if let effectiveSelectedBucket {
                selectionSummary(for: effectiveSelectedBucket)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .onChange(of: posts) { _, _ in
            resetSelection()
        }
        .onChange(of: publishingJobs) { _, _ in
            resetSelection()
        }
        .onChange(of: selectedPostType) { _, _ in
            resetSelection()
        }
        .onChange(of: selectedPlatform) { _, _ in
            selectedAccountID = nil
            resetSelection()
        }
        .onChange(of: selectedAccountID) { _, _ in
            resetSelection()
        }
        .task(id: selectionResetToken) {
            guard selectedBucketIndex != nil else { return }

            do {
                try await Task.sleep(for: Self.selectionResetDelay)
            } catch {
                return
            }

            guard !Task.isCancelled, selectedBucketIndex != nil else { return }
            clearSelection()
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: snapshot.animationID)
        .accessibilityElement(children: .contain)
    }

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                PublishedPostsTypeMenu(selection: $selectedPostType)

                platformFilterBar
                    .frame(maxWidth: .infinity)
            }

            if effectiveSelectedPlatform != nil {
                accountFilterBar
                    .transition(
                        .move(edge: .top)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.98, anchor: .top))
                    )
            }
        }
    }

    private var platformFilterBar: some View {
        PublishedPostsFilterChipBar(
            options: platformFilterOptions,
            selectedID: effectiveSelectedPlatform?.rawValue ?? PublishedPostsFilterOption.allID,
            onSelect: selectPlatformFilter
        )
    }

    private var accountFilterBar: some View {
        PublishedPostsFilterChipBar(
            options: accountFilterOptions,
            selectedID: effectiveSelectedAccountID?.uuidString ?? PublishedPostsFilterOption.allID,
            onSelect: selectAccountFilter
        )
    }

    private var platformFilterOptions: [PublishedPostsFilterOption] {
        [
            PublishedPostsFilterOption(
                id: PublishedPostsFilterOption.allID,
                title: "All",
                systemImage: "square.grid.2x2",
                tint: FlickStyle.appTint
            )
        ] + platformOptions.map { platform in
            PublishedPostsFilterOption(
                id: platform.rawValue,
                title: platform.displayName,
                platform: platform,
                tint: platform.tint
            )
        }
    }

    private var accountFilterOptions: [PublishedPostsFilterOption] {
        [
            PublishedPostsFilterOption(
                id: PublishedPostsFilterOption.allID,
                title: "All accounts",
                systemImage: "person.2",
                tint: effectiveSelectedPlatform?.tint ?? FlickStyle.appTint
            )
        ] + accountOptions.map { option in
            PublishedPostsFilterOption(
                id: option.id.uuidString,
                title: option.displayName,
                systemImage: "person.crop.circle",
                tint: accountColorByID[option.id] ?? FlickStyle.appTint
            )
        }
    }

    private var emptyState: some View {
        DashboardMessageRow(
            title: effectiveSelectedPlatform == nil ? selectedPostType.emptyTitle : "No matching \(selectedPostType.pluralNoun)",
            message: effectiveSelectedPlatform == nil
                ? selectedPostType.emptyMessage
                : "Change the platform or account filter to see other \(selectedPostType.pluralNoun).",
            systemImage: selectedPostType.systemImage,
            iconColor: selectedPostType.tint
        )
        .padding(.top, 2)
    }

    private func selectionSummary(for bucket: PublishedPostsChartBucket) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(bucket.accessibilityDateLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(bucket.segmentSummary(series: snapshot.series, fallback: filterDescription))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            Text(selectedPostType.countText(bucket.totalCount))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func selectPlatformFilter(_ optionID: String) {
        let nextPlatform = platformOptions.first { $0.rawValue == optionID }
        guard selectedPlatform != nextPlatform else { return }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            selectedPlatform = nextPlatform
            selectedAccountID = nil
            resetSelection()
        }
    }

    private func selectAccountFilter(_ optionID: String) {
        let nextAccountID = optionID == PublishedPostsFilterOption.allID ? nil : UUID(uuidString: optionID)
        guard effectiveSelectedAccountID != nextAccountID else { return }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            selectedAccountID = nextAccountID
            resetSelection()
        }
    }

    private func resetSelection() {
        selectedBucketIndex = nil
        hasInteractedWithChart = false
        selectionResetToken += 1
    }

    private func scheduleSelectionReset() {
        selectionResetToken += 1
    }

    private func clearSelection() {
        guard selectedBucketIndex != nil || hasInteractedWithChart else { return }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            selectedBucketIndex = nil
            hasInteractedWithChart = false
        }
    }
}

private struct PublishedPostsChartCanvas: View {
    var snapshot: PublishedPostsChartSnapshot
    var postType: PublishedPostsChartType

    @Binding var selectedBucketIndex: Int?
    @Binding var hasInteractedWithChart: Bool
    var onSelectionChanged: () -> Void
    var onDragEnded: () -> Void

    private var effectiveSelectedBucketIndex: Int? {
        selectedBucketIndex
    }

    private var effectiveSelectedBucket: PublishedPostsChartBucket? {
        guard let effectiveSelectedBucketIndex else { return nil }
        return snapshot.buckets.first { $0.id == effectiveSelectedBucketIndex }
    }

    private var lineDomain: PublishedPostsChartDomain {
        PublishedPostsChartDomain(values: snapshot.lineValues, desiredTickCount: 4)
    }

    private var barDomain: PublishedPostsChartDomain {
        PublishedPostsChartDomain(values: snapshot.barValues, desiredTickCount: 3)
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = PublishedPostsChartLayout(
                size: geometry.size,
                bucketCount: snapshot.buckets.count,
                axisWidth: 40
            )

            ZStack(alignment: .topLeading) {
                gridLines(in: layout)
                lines(in: layout)
                bars(in: layout)
                selection(in: layout)
                axisLabels(in: layout)
                gestureOverlay(in: layout)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: snapshot.animationID)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(postType.title) chart")
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private func gridLines(in layout: PublishedPostsChartLayout) -> some View {
        ForEach(lineDomain.ticks, id: \.self) { tick in
            DashboardChartHorizontalLine(
                xRange: layout.plotXRange,
                y: layout.yPosition(for: Double(tick), domainMax: lineDomain.maxValue, in: layout.linePlot)
            )
            .stroke(Color.secondary.opacity(0.18), style: StrokeStyle(lineWidth: 0.7, dash: [3, 5]))
        }

        DashboardChartHorizontalLine(xRange: layout.plotXRange, y: layout.linePlot.maxY)
            .stroke(Color.secondary.opacity(0.22), lineWidth: 0.8)

        ForEach(barDomain.ticks, id: \.self) { tick in
            DashboardChartHorizontalLine(
                xRange: layout.plotXRange,
                y: layout.yPosition(for: Double(tick), domainMax: barDomain.maxValue, in: layout.barPlot)
            )
            .stroke(Color.secondary.opacity(0.16), style: StrokeStyle(lineWidth: 0.7, dash: [3, 5]))
        }

        DashboardChartHorizontalLine(xRange: layout.plotXRange, y: layout.barPlot.maxY)
            .stroke(Color.secondary.opacity(0.24), lineWidth: 0.8)
    }

    @ViewBuilder
    private func lines(in layout: PublishedPostsChartLayout) -> some View {
        ForEach(snapshot.series) { series in
            smoothPath(for: linePoints(for: series), in: layout.linePlot, layout: layout, domainMax: lineDomain.maxValue)
                .stroke(
                    series.tint.opacity(lineOpacity(for: series)),
                    style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .center)))
        }
    }

    @ViewBuilder
    private func bars(in layout: PublishedPostsChartLayout) -> some View {
        ForEach(snapshot.buckets) { bucket in
            ForEach(snapshot.series) { series in
                let value = bucket.count(for: series)

                if value > 0 {
                    let centerX = layout.xPosition(forBucketIndex: bucket.id)
                    let barWidth = layout.barWidth(seriesCount: snapshot.series.count)
                    let barHeight = layout.barHeight(for: value, domainMax: barDomain.maxValue)
                    let y = layout.barYCenter(for: value, domainMax: barDomain.maxValue)
                    let x = centerX + layout.barXOffset(
                        seriesIndex: series.index,
                        seriesCount: snapshot.series.count
                    )

                    RoundedRectangle(cornerRadius: layout.barCornerRadius(width: barWidth, height: barHeight), style: .continuous)
                        .fill(series.tint.opacity(barOpacity(for: bucket, series: series)))
                        .frame(width: barWidth, height: barHeight)
                        .position(x: x, y: y)
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottom)))
                }
            }
        }
    }

    @ViewBuilder
    private func selection(in layout: PublishedPostsChartLayout) -> some View {
        if let effectiveSelectedBucket {
            let selectedX = layout.xPosition(forBucketIndex: effectiveSelectedBucket.id)

            DashboardChartVerticalLine(x: selectedX, yRange: layout.linePlot.minY...layout.barPlot.maxY)
                .stroke(Color.secondary.opacity(0.54), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))

            ForEach(snapshot.series) { series in
                let value = effectiveSelectedBucket.cumulativeCount(for: series)

                if value > 0 {
                    Circle()
                        .fill(.background)
                        .frame(width: 12, height: 12)
                        .overlay {
                            Circle()
                                .stroke(series.tint, lineWidth: 3)
                        }
                        .position(
                            x: selectedX,
                            y: layout.yPosition(
                                for: Double(value),
                                domainMax: lineDomain.maxValue,
                                in: layout.linePlot
                            )
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.82)))
                }
            }
        }
    }

    @ViewBuilder
    private func axisLabels(in layout: PublishedPostsChartLayout) -> some View {
        ForEach(lineDomain.ticks, id: \.self) { tick in
            Text(tick.formatted())
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: layout.axisWidth - 4, alignment: .trailing)
                .position(
                    x: layout.axisLabelCenterX,
                    y: layout.yPosition(for: Double(tick), domainMax: lineDomain.maxValue, in: layout.linePlot)
                )
        }

        ForEach(barDomain.ticks, id: \.self) { tick in
            Text(tick.formatted())
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: layout.axisWidth - 4, alignment: .trailing)
                .position(
                    x: layout.axisLabelCenterX,
                    y: layout.yPosition(for: Double(tick), domainMax: barDomain.maxValue, in: layout.barPlot)
                )
        }

        ForEach(snapshot.buckets) { bucket in
            if shouldShowXAxisLabel(for: bucket) {
                Text(bucket.axisLabel)
                    .font(.caption2)
                    .fontWeight(bucket.id == effectiveSelectedBucketIndex ? .semibold : .regular)
                    .foregroundStyle(bucket.id == effectiveSelectedBucketIndex ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(width: layout.xAxisLabelWidth, alignment: .center)
                    .position(
                        x: layout.xPosition(forBucketIndex: bucket.id),
                        y: layout.xAxisLabelY
                    )
            }
        }
    }

    private func gestureOverlay(in layout: PublishedPostsChartLayout) -> some View {
        Rectangle()
            .fill(.clear)
            .contentShape(.rect)
            .frame(width: layout.plotWidth, height: layout.interactiveHeight)
            .position(x: layout.plotWidth / 2, y: layout.interactiveHeight / 2)
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        selectBucket(atX: value.location.x, in: layout)
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .local)
                    .onChanged { value in
                        guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                        selectBucket(atX: value.location.x, in: layout)
                    }
                    .onEnded { value in
                        guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                        onDragEnded()
                    }
            )
    }

    private func selectBucket(atX x: CGFloat, in layout: PublishedPostsChartLayout) {
        guard let index = layout.nearestBucketIndex(toX: x, bucketCount: snapshot.buckets.count) else { return }

        withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
            selectedBucketIndex = index
            hasInteractedWithChart = true
        }
        onSelectionChanged()
    }

    private func shouldShowXAxisLabel(for bucket: PublishedPostsChartBucket) -> Bool {
        bucket.id == 0
            || bucket.id == snapshot.buckets.count - 1
            || bucket.id == effectiveSelectedBucketIndex
            || bucket.id.isMultiple(of: 3)
            || bucket.isToday
    }

    private func lineOpacity(for series: PublishedPostsChartSeries) -> Double {
        guard hasInteractedWithChart,
              let effectiveSelectedBucket
        else { return 0.96 }

        return effectiveSelectedBucket.cumulativeCount(for: series) > 0 ? 0.98 : 0.38
    }

    private func barOpacity(for bucket: PublishedPostsChartBucket, series: PublishedPostsChartSeries) -> Double {
        guard hasInteractedWithChart,
              let effectiveSelectedBucketIndex
        else { return 0.76 }

        return bucket.id == effectiveSelectedBucketIndex && bucket.count(for: series) > 0 ? 0.94 : 0.30
    }

    private func linePoints(for series: PublishedPostsChartSeries) -> [PublishedPostsChartPoint] {
        snapshot.buckets.map { bucket in
            PublishedPostsChartPoint(bucketIndex: bucket.id, value: bucket.cumulativeCount(for: series))
        }
    }

    private func smoothPath(
        for points: [PublishedPostsChartPoint],
        in rect: CGRect,
        layout: PublishedPostsChartLayout,
        domainMax: Double
    ) -> Path {
        let cgPoints = points.map {
            CGPoint(
                x: layout.xPosition(forBucketIndex: $0.bucketIndex),
                y: layout.yPosition(for: Double($0.value), domainMax: domainMax, in: rect)
            )
        }

        guard let first = cgPoints.first else { return Path() }

        var path = Path()
        path.move(to: first)

        guard cgPoints.count > 1 else { return path }

        for index in 0..<(cgPoints.count - 1) {
            let previous = index > 0 ? cgPoints[index - 1] : cgPoints[index]
            let current = cgPoints[index]
            let next = cgPoints[index + 1]
            let following = index + 2 < cgPoints.count ? cgPoints[index + 2] : next

            let control1 = clampedControlPoint(
                CGPoint(
                    x: current.x + (next.x - previous.x) / 6,
                    y: current.y + (next.y - previous.y) / 6
                ),
                between: current,
                and: next
            )
            let control2 = clampedControlPoint(
                CGPoint(
                    x: next.x - (following.x - current.x) / 6,
                    y: next.y - (following.y - current.y) / 6
                ),
                between: current,
                and: next
            )

            path.addCurve(to: next, control1: control1, control2: control2)
        }

        return path
    }

    private func clampedControlPoint(_ point: CGPoint, between start: CGPoint, and end: CGPoint) -> CGPoint {
        let minY = min(start.y, end.y)
        let maxY = max(start.y, end.y)
        return CGPoint(x: point.x, y: min(max(point.y, minY), maxY))
    }

    private var accessibilityValue: String {
        guard let effectiveSelectedBucket else {
            return "\(snapshot.dateRangeLabel), \(postType.countText(snapshot.totalCount))"
        }

        return "\(effectiveSelectedBucket.accessibilityDateLabel), \(postType.countText(effectiveSelectedBucket.totalCount))"
    }
}

private enum PublishedPostsChartType: String, CaseIterable, Identifiable {
    case sent
    case posted
    case drafts
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sent: "Sent"
        case .posted: "Posted"
        case .drafts: "Drafts"
        case .failed: "Failed"
        }
    }

    var menuTitle: String {
        switch self {
        case .sent: "Sent"
        case .posted: "Posted"
        case .drafts: "Drafts"
        case .failed: "Failed"
        }
    }

    var systemImage: String {
        switch self {
        case .sent: "paperplane"
        case .posted: "checkmark.seal"
        case .drafts: "doc.text"
        case .failed: "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .sent: FlickStyle.appTint
        case .posted: .green
        case .drafts: .orange
        case .failed: .red
        }
    }

    var singularNoun: String {
        switch self {
        case .sent: "sent post"
        case .posted: "post"
        case .drafts: "draft"
        case .failed: "failed post"
        }
    }

    var pluralNoun: String {
        switch self {
        case .sent: "sent posts"
        case .posted: "posts"
        case .drafts: "drafts"
        case .failed: "failed posts"
        }
    }

    var emptyTitle: String {
        switch self {
        case .sent: "No sent posts"
        case .posted: "No posted posts"
        case .drafts: "No drafts"
        case .failed: "No failed posts"
        }
    }

    var emptyMessage: String {
        switch self {
        case .sent:
            "Posted posts and draft uploads will appear here after Flick sends them to a platform."
        case .posted:
            "Posted posts will appear here after Flick records successful publishes."
        case .drafts:
            "Draft uploads waiting for account-side completion will appear here."
        case .failed:
            "Failed publish jobs will appear here with their platform error details."
        }
    }

    func countText(_ count: Int) -> String {
        count == 1 ? "1 \(singularNoun)" : "\(count.formatted()) \(pluralNoun)"
    }

    func events(posts: [PublishedPost], publishingJobs: [PublishingJob]) -> [PublishedPostsChartEvent] {
        switch self {
        case .sent:
            postEvents(posts) + draftEvents(publishingJobs)
        case .posted:
            postEvents(posts)
        case .drafts:
            draftEvents(publishingJobs)
        case .failed:
            failedEvents(publishingJobs)
        }
    }

    private func postEvents(_ posts: [PublishedPost]) -> [PublishedPostsChartEvent] {
        posts.map { post in
            PublishedPostsChartEvent(
                id: "post:\(post.id.uuidString)",
                platform: post.platform,
                accountID: post.accountID,
                date: post.publishedAt
            )
        }
    }

    private func draftEvents(_ jobs: [PublishingJob]) -> [PublishedPostsChartEvent] {
        jobs
            .filter { $0.status == .awaitingUserCompletion }
            .map { job in
                PublishedPostsChartEvent(
                    id: "job:\(job.id.uuidString)",
                    platform: job.platform,
                    accountID: job.accountID,
                    date: job.updatedAt
                )
            }
    }

    private func failedEvents(_ jobs: [PublishingJob]) -> [PublishedPostsChartEvent] {
        jobs
            .filter { $0.status == .failed }
            .map { job in
                PublishedPostsChartEvent(
                    id: "job:\(job.id.uuidString)",
                    platform: job.platform,
                    accountID: job.accountID,
                    date: job.lastAttemptAt ?? job.updatedAt
                )
            }
    }
}

private struct PublishedPostsChartEvent: Identifiable, Hashable {
    var id: String
    var platform: SocialPlatform
    var accountID: UUID
    var date: Date
}

private struct PublishedPostsChartSnapshot {
    var buckets: [PublishedPostsChartBucket]
    var series: [PublishedPostsChartSeries]
    var totalCount: Int
    var startDate: Date
    var endDate: Date

    var hasPosts: Bool {
        totalCount > 0
    }

    var lineValues: [Int] {
        buckets.flatMap { bucket in
            series.map { bucket.cumulativeCount(for: $0) }
        }
    }

    var barValues: [Int] {
        buckets.flatMap { bucket in
            series.map { bucket.count(for: $0) }
        }
    }

    var dateRangeLabel: String {
        if Calendar.autoupdatingCurrent.isDate(startDate, inSameDayAs: endDate) {
            return startDate.formatted(.dateTime.month(.abbreviated).day())
        }

        return "\(startDate.formatted(.dateTime.month(.abbreviated).day())) to \(endDate.formatted(.dateTime.month(.abbreviated).day()))"
    }

    var animationID: String {
        [
            series.map(\.id).joined(separator: "|"),
            String(totalCount),
            String(Int(startDate.timeIntervalSinceReferenceDate)),
            String(Int(endDate.timeIntervalSinceReferenceDate))
        ].joined(separator: "-")
    }

    static func make(
        events: [PublishedPostsChartEvent],
        selectedPlatform: SocialPlatform?,
        selectedAccountID: UUID?,
        accountOptions: [PublishedPostsAccountOption],
        accountColorByID: [UUID: Color],
        calendar: Calendar = .autoupdatingCurrent
    ) -> PublishedPostsChartSnapshot {
        let bucketCount = 14
        let today = calendar.startOfDay(for: Date())
        let latestEventDay = events
            .map { calendar.startOfDay(for: $0.date) }
            .max()
        let endDate = Self.endDate(today: today, latestEventDay: latestEventDay, calendar: calendar)
        let startDate = calendar.date(byAdding: .day, value: -(bucketCount - 1), to: endDate) ?? endDate
        let series = makeSeries(
            events: events,
            selectedPlatform: selectedPlatform,
            selectedAccountID: selectedAccountID,
            accountOptions: accountOptions,
            accountColorByID: accountColorByID
        )
        let visibleEvents = events.filter { event in
            let eventDay = calendar.startOfDay(for: event.date)
            return eventDay >= startDate && eventDay <= endDate
        }
        let eventsByDay = Dictionary(grouping: visibleEvents) { event in
            calendar.startOfDay(for: event.date)
        }
        let seriesIDs = Set(series.map(\.id))
        var cumulativeCounts: [String: Int] = Dictionary(uniqueKeysWithValues: series.map { ($0.id, 0) })

        let buckets = (0..<bucketCount).map { index in
            let date = calendar.date(byAdding: .day, value: index, to: startDate) ?? startDate
            let dayEvents = eventsByDay[date] ?? []
            var counts: [String: Int] = [:]

            for event in dayEvents {
                let id = seriesID(
                    for: event,
                    selectedPlatform: selectedPlatform,
                    selectedAccountID: selectedAccountID
                )
                guard seriesIDs.contains(id) else { continue }
                counts[id, default: 0] += 1
            }

            for (id, count) in counts {
                cumulativeCounts[id, default: 0] += count
            }

            return PublishedPostsChartBucket(
                id: index,
                date: date,
                counts: counts,
                cumulativeCounts: cumulativeCounts,
                calendar: calendar
            )
        }

        return PublishedPostsChartSnapshot(
            buckets: buckets,
            series: series,
            totalCount: buckets.reduce(0) { $0 + $1.totalCount },
            startDate: startDate,
            endDate: endDate
        )
    }

    private static func makeSeries(
        events: [PublishedPostsChartEvent],
        selectedPlatform: SocialPlatform?,
        selectedAccountID: UUID?,
        accountOptions: [PublishedPostsAccountOption],
        accountColorByID: [UUID: Color]
    ) -> [PublishedPostsChartSeries] {
        if selectedPlatform == nil {
            return SocialPlatform.allCases
                .filter { platform in events.contains { $0.platform == platform } }
                .enumerated()
                .map { index, platform in
                    PublishedPostsChartSeries(
                        id: "platform:\(platform.rawValue)",
                        title: platform.displayName,
                        tint: platform.tint,
                        index: index
                    )
                }
        }

        if let selectedPlatform, selectedAccountID == nil {
            return [
                PublishedPostsChartSeries(
                    id: "platform:\(selectedPlatform.rawValue)",
                    title: selectedPlatform.displayName,
                    tint: selectedPlatform.tint,
                    index: 0
                )
            ]
        }

        return accountOptions
            .filter { option in
                if let selectedAccountID {
                    return option.id == selectedAccountID
                }
                return events.contains { $0.accountID == option.id }
            }
            .enumerated()
            .map { index, option in
                PublishedPostsChartSeries(
                    id: "account:\(option.id.uuidString)",
                    title: option.displayName,
                    tint: accountColorByID[option.id] ?? FlickStyle.appTint,
                    index: index
                )
            }
    }

    private static func seriesID(
        for event: PublishedPostsChartEvent,
        selectedPlatform: SocialPlatform?,
        selectedAccountID: UUID?
    ) -> String {
        if selectedPlatform == nil || selectedAccountID == nil {
            return "platform:\(event.platform.rawValue)"
        }

        return "account:\(event.accountID.uuidString)"
    }

    private static func endDate(today: Date, latestEventDay: Date?, calendar: Calendar) -> Date {
        guard let latestEventDay else { return today }

        let daysFromLatestEventToToday = calendar.dateComponents([.day], from: latestEventDay, to: today).day ?? 0
        if (0...13).contains(daysFromLatestEventToToday) {
            return today
        }

        return latestEventDay
    }
}

private struct PublishedPostsChartSeries: Identifiable {
    var id: String
    var title: String
    var tint: Color
    var index: Int
}

private struct PublishedPostsChartBucket: Identifiable {
    var id: Int
    var date: Date
    var counts: [String: Int]
    var cumulativeCounts: [String: Int]
    var calendar: Calendar

    var totalCount: Int {
        counts.values.reduce(0, +)
    }

    var isToday: Bool {
        calendar.isDateInToday(date)
    }

    var axisLabel: String {
        if isToday {
            return "Today"
        }

        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    var accessibilityDateLabel: String {
        if isToday {
            return "Today"
        }

        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    func count(for series: PublishedPostsChartSeries) -> Int {
        counts[series.id] ?? 0
    }

    func cumulativeCount(for series: PublishedPostsChartSeries) -> Int {
        cumulativeCounts[series.id] ?? 0
    }

    func segmentSummary(series: [PublishedPostsChartSeries], fallback: String) -> String {
        let parts = series.compactMap { item -> String? in
            let value = count(for: item)
            guard value > 0 else { return nil }
            return "\(item.title) \(value.formatted())"
        }

        return parts.isEmpty ? fallback : parts.joined(separator: ", ")
    }
}

private struct PublishedPostsChartPoint {
    var bucketIndex: Int
    var value: Int
}

private struct PublishedPostsAccountOption: Identifiable {
    var id: UUID
    var displayName: String
    var platformUserID: String?
    var postCount: Int
}

private struct PublishedPostsFilterOption: Identifiable {
    static let allID = "all"

    var id: String
    var title: String
    var platform: SocialPlatform?
    var systemImage: String?
    var tint: Color

    init(
        id: String,
        title: String,
        platform: SocialPlatform? = nil,
        systemImage: String? = nil,
        tint: Color
    ) {
        self.id = id
        self.title = title
        self.platform = platform
        self.systemImage = systemImage
        self.tint = tint
    }
}

private struct PublishedPostsTypeMenu: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selection: PublishedPostsChartType

    var body: some View {
        Menu {
            ForEach(PublishedPostsChartType.allCases) { type in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        selection = type
                    }
                } label: {
                    Label(type.menuTitle, systemImage: selection == type ? "checkmark" : type.systemImage)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selection.systemImage)
                    .font(.caption.weight(.semibold))

                Text(selection.menuTitle)
                    .lineLimit(1)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(foregroundColor.opacity(0.76))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .fixedSize(horizontal: true, vertical: false)
            .contentShape(.capsule)
            .glassEffect(.regular.tint(Color.primary), in: .capsule)
        }
        .buttonStyle(.plain)
        .layoutPriority(1)
        .accessibilityLabel("Post type")
        .accessibilityValue(selection.menuTitle)
    }

    private var foregroundColor: Color {
        colorScheme == .dark ? .black : .white
    }
}

private struct PublishedPostsFilterChipBar: View {
    var options: [PublishedPostsFilterOption]
    var selectedID: String
    var onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(options) { option in
                    Button {
                        onSelect(option.id)
                    } label: {
                        PublishedPostsFilterChip(
                            option: option,
                            isSelected: selectedID == option.id
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            }
        }
        .scrollClipDisabled()
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: selectedID)
    }
}

private struct PublishedPostsFilterChip: View {
    @Environment(\.colorScheme) private var colorScheme

    var option: PublishedPostsFilterOption
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let platform = option.platform {
                PlatformIcon(platform: platform, size: 15, frameSize: 18)
            } else if let systemImage = option.systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
            }

            Text(option.title)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 12)
        .frame(height: 40)
        .contentShape(.capsule)
        .glassEffect(glass, in: .capsule)
        .accessibilityElement(children: .combine)
    }

    private var glass: Glass {
        isSelected ? Glass.regular.tint(Color.primary) : Glass.regular
    }

    private var foregroundColor: Color {
        if colorScheme == .dark {
            return isSelected ? .black : .white
        }

        return isSelected ? .white : .primary
    }
}

private struct PublishedPostsChartDomain {
    var maxValue: Double
    var ticks: [Int]

    init(values: [Int], desiredTickCount: Int) {
        let highestValue = max(values.max() ?? 0, 1)
        let step = Self.niceStep(for: Double(highestValue) / Double(desiredTickCount))
        maxValue = Double(step * desiredTickCount)
        ticks = (1...desiredTickCount).map { step * $0 }
    }

    private static func niceStep(for rawStep: Double) -> Int {
        guard rawStep > 1, rawStep.isFinite else { return 1 }

        let exponent = floor(log10(rawStep))
        let scale = pow(10, exponent)
        let fraction = rawStep / scale

        let niceFraction: Double
        switch fraction {
        case ...1:
            niceFraction = 1
        case ...2:
            niceFraction = 2
        case ...5:
            niceFraction = 5
        default:
            niceFraction = 10
        }

        return max(1, Int(niceFraction * scale))
    }
}

private struct PublishedPostsChartLayout {
    var size: CGSize
    var bucketCount: Int
    var axisWidth: CGFloat

    let chartGap: CGFloat
    let lineHeight: CGFloat
    let barHeight: CGFloat
    let sideInset: CGFloat

    private let topInset: CGFloat = 4
    private let xAxisHeight: CGFloat = 32

    init(size: CGSize, bucketCount: Int, axisWidth: CGFloat) {
        self.size = size
        self.bucketCount = bucketCount
        self.axisWidth = axisWidth

        let gap = min(28, max(18, size.height * 0.07))
        let availableHeight = max(1, size.height - topInset - xAxisHeight - gap)
        let resolvedLineHeight = min(150, max(110, availableHeight * 0.52))
        let plotWidth = max(1, size.width - axisWidth)
        let rawStep = bucketCount > 1 ? plotWidth / CGFloat(bucketCount - 1) : plotWidth

        chartGap = gap
        lineHeight = resolvedLineHeight
        barHeight = max(72, availableHeight - resolvedLineHeight)
        sideInset = min(28, max(10, rawStep * 0.36))
    }

    var plotWidth: CGFloat {
        max(1, size.width - axisWidth)
    }

    var plotXRange: ClosedRange<CGFloat> {
        0...plotWidth
    }

    var linePlot: CGRect {
        CGRect(x: 0, y: topInset, width: plotWidth, height: lineHeight)
    }

    var barPlot: CGRect {
        CGRect(x: 0, y: linePlot.maxY + chartGap, width: plotWidth, height: barHeight)
    }

    var axisLabelCenterX: CGFloat {
        plotWidth + axisWidth / 2 - 2
    }

    var xAxisLabelY: CGFloat {
        barPlot.maxY + 22
    }

    var interactiveHeight: CGFloat {
        min(size.height, xAxisLabelY + 12)
    }

    var bucketStep: CGFloat {
        guard bucketCount > 1 else { return 0 }
        return max(1, (plotWidth - sideInset * 2) / CGFloat(bucketCount - 1))
    }

    var xAxisLabelWidth: CGFloat {
        max(28, bucketStep * 1.7)
    }

    func barWidth(seriesCount: Int) -> CGFloat {
        guard seriesCount > 1 else {
            return max(9, min(22, bucketStep * 0.62))
        }

        let slotWidth = min(52, max(20, bucketStep * 0.92))
        return max(7, min(18, slotWidth / CGFloat(seriesCount) * 1.35))
    }

    func barCornerRadius(width: CGFloat, height: CGFloat) -> CGFloat {
        min(3, width * 0.22, height * 0.32)
    }

    func barXOffset(seriesIndex: Int, seriesCount: Int) -> CGFloat {
        guard seriesCount > 1 else { return 0 }

        let width = barWidth(seriesCount: seriesCount)
        let step = width * 0.58
        return (CGFloat(seriesIndex) - CGFloat(seriesCount - 1) / 2) * step
    }

    func xPosition(forBucketIndex index: Int) -> CGFloat {
        guard bucketCount > 1 else { return plotWidth / 2 }
        return sideInset + CGFloat(index) * bucketStep
    }

    func nearestBucketIndex(toX x: CGFloat, bucketCount: Int) -> Int? {
        guard bucketCount > 0 else { return nil }
        guard bucketCount > 1 else { return 0 }

        let clampedX = min(max(x, sideInset), plotWidth - sideInset)
        let rawIndex = ((clampedX - sideInset) / bucketStep).rounded()
        return min(max(Int(rawIndex), 0), bucketCount - 1)
    }

    func yPosition(for value: Double, domainMax: Double, in rect: CGRect) -> CGFloat {
        guard domainMax > 0 else { return rect.maxY }
        let ratio = min(max(value / domainMax, 0), 1)
        return rect.maxY - CGFloat(ratio) * rect.height
    }

    func barHeight(for value: Int, domainMax: Double) -> CGFloat {
        guard value > 0 else { return 0 }
        let top = yPosition(for: Double(value), domainMax: domainMax, in: barPlot)
        return max(3, barPlot.maxY - top)
    }

    func barYCenter(for value: Int, domainMax: Double) -> CGFloat {
        barPlot.maxY - barHeight(for: value, domainMax: domainMax) / 2
    }
}

private struct DashboardChartHorizontalLine: Shape {
    var xRange: ClosedRange<CGFloat>
    var y: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: xRange.lowerBound, y: y))
        path.addLine(to: CGPoint(x: xRange.upperBound, y: y))
        return path
    }
}

private struct DashboardChartVerticalLine: Shape {
    var x: CGFloat
    var yRange: ClosedRange<CGFloat>

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: x, y: yRange.lowerBound))
        path.addLine(to: CGPoint(x: x, y: yRange.upperBound))
        return path
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
#endif
