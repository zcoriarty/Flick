//
//  FlickRootView.swift
//  Flick
//

import SwiftUI

struct FlickRootView: View {
    @Environment(FlickAppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var appModel = appModel

        TabView(selection: $appModel.selectedSection) {
            Tab(FlickSection.dashboard.title, systemImage: FlickSection.dashboard.systemImage, value: FlickSection.dashboard) {
                NavigationStack {
                    DashboardView()
                }
            }

            #if os(macOS) || targetEnvironment(macCatalyst)
            Tab(FlickSection.product.title, systemImage: FlickSection.product.systemImage, value: FlickSection.product) {
                NavigationStack {
                    ProductView()
                }
            }
            #else
            Tab(FlickSection.media.title, systemImage: FlickSection.media.systemImage, value: FlickSection.media) {
                NavigationStack {
                    MediaView()
                }
            }
            #endif

            Tab(FlickSection.models.title, systemImage: FlickSection.models.systemImage, value: FlickSection.models) {
                NavigationStack {
                    ModelsView()
                }
            }

            Tab(FlickSection.create.title, systemImage: FlickSection.create.systemImage, value: FlickSection.create) {
                NavigationStack {
                    CreateView()
                }
            }

            #if os(macOS) || targetEnvironment(macCatalyst)
            Tab(FlickSection.templates.title, systemImage: FlickSection.templates.systemImage, value: FlickSection.templates) {
                NavigationStack {
                    TemplatesView()
                }
            }

            Tab(FlickSection.accounts.title, systemImage: FlickSection.accounts.systemImage, value: FlickSection.accounts) {
                NavigationStack {
                    AccountsView()
                }
            }

            Tab(FlickSection.settings.title, systemImage: FlickSection.settings.systemImage, value: FlickSection.settings) {
                NavigationStack {
                    SettingsView()
                }
            }
            #endif
        }
        #if os(macOS) || targetEnvironment(macCatalyst)
        .tabViewStyle(.sidebarAdaptable)
        #else
        .tint(FlickStyle.appTint)
        #endif
        .flickAppBackground()
        .task {
            await appModel.refresh()
        }
        .task {
            await appModel.refreshOnCloudKitStoreChanges()
        }
        #if os(iOS) && !targetEnvironment(macCatalyst)
        .task {
            await PublishedPostNotificationRegistrationService.shared.configure()
        }
        #endif
        .task {
            await appModel.runTikTokPublishStatusRefreshLoop()
        }
        #if os(macOS) || targetEnvironment(macCatalyst)
        .task {
            await appModel.runMacRunnerHeartbeatLoop()
        }
        .task {
            await appModel.runAutomationWorkerLoop()
        }
        #endif
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await appModel.refresh()
            }
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
