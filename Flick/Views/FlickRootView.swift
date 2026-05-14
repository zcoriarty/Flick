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

            Tab(FlickSection.product.title, systemImage: FlickSection.product.systemImage, value: FlickSection.product) {
                ProductView()
            }

            Tab(FlickSection.create.title, systemImage: FlickSection.create.systemImage, value: FlickSection.create) {
                CreateView()
            }

            Tab(FlickSection.templates.title, systemImage: FlickSection.templates.systemImage, value: FlickSection.templates) {
                TemplatesView()
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
        .tint(FlickStyle.appTint)
        .preferredColorScheme(.dark)
        .task {
            await appModel.refresh()
        }
        .onOpenURL { url in
            _ = TikTokOpenSDKURLHandler.handle(url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            _ = TikTokOpenSDKURLHandler.handle(activity.webpageURL)
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
