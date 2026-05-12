//
//  FlickRootView.swift
//  Flick
//

import SwiftUI

struct FlickRootView: View {
    @Environment(FlickAppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        TabView(selection: $appModel.selectedSection) {
            Tab(FlickSection.dashboard.title, systemImage: FlickSection.dashboard.systemImage, value: FlickSection.dashboard) {
                DashboardView()
            }

            Tab(FlickSection.create.title, systemImage: FlickSection.create.systemImage, value: FlickSection.create) {
                CreateView()
            }

            Tab(FlickSection.queue.title, systemImage: FlickSection.queue.systemImage, value: FlickSection.queue) {
                QueueView()
            }

            Tab(FlickSection.trends.title, systemImage: FlickSection.trends.systemImage, value: FlickSection.trends) {
                TrendsView()
            }

            Tab(FlickSection.analytics.title, systemImage: FlickSection.analytics.systemImage, value: FlickSection.analytics) {
                AnalyticsView()
            }

            Tab(FlickSection.accounts.title, systemImage: FlickSection.accounts.systemImage, value: FlickSection.accounts) {
                AccountsView()
            }

            Tab(FlickSection.settings.title, systemImage: FlickSection.settings.systemImage, value: FlickSection.settings) {
                SettingsView()
            }
        }
        .tint(.indigo)
        .task {
            await appModel.refresh()
        }
        .onOpenURL { url in
            Task {
                await appModel.handleOAuthCallback(url)
            }
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL else { return }
            Task {
                await appModel.handleOAuthCallback(url)
            }
        }
        #if os(iOS)
        .tabBarMinimizeBehavior(.onScrollDown)
        #endif
    }
}

#Preview {
    @Previewable @State var appModel = FlickAppModel.live()
    FlickRootView()
        .environment(appModel)
}
