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
                NavigationStack {
                    DashboardView()
                }
            }

            Tab(FlickSection.product.title, systemImage: FlickSection.product.systemImage, value: FlickSection.product) {
                NavigationStack {
                    ProductView()
                }
            }

            Tab(FlickSection.create.title, systemImage: FlickSection.create.systemImage, value: FlickSection.create) {
                NavigationStack {
                    CreateView()
                }
            }

            Tab(FlickSection.templates.title, systemImage: FlickSection.templates.systemImage, value: FlickSection.templates) {
                NavigationStack {
                    TemplatesView()
                }
            }

            Tab(FlickSection.accounts.title, systemImage: FlickSection.accounts.systemImage, value: FlickSection.accounts) {
                AccountsView()
            }

            Tab(FlickSection.settings.title, systemImage: FlickSection.settings.systemImage, value: FlickSection.settings) {
                SettingsView()
            }
        }
        #if os(macOS) || targetEnvironment(macCatalyst)
        .tabViewStyle(.sidebarAdaptable)
        #else
        .tint(FlickStyle.appTint)
        #endif
        .preferredColorScheme(.dark)
        .flickAppBackground()
        .task {
            await appModel.refresh()
        }
        .onOpenURL { url in
            _ = TikTokOpenSDKURLHandler.handle(url, source: "SwiftUI.onOpenURL")
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            _ = TikTokOpenSDKURLHandler.handle(activity.webpageURL, source: "SwiftUI.onContinueUserActivity")
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
