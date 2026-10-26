//
//  WayfinderApp.swift
//  Wayfinder
//
//  Created by Tanush Malhotra (School) on 5/28/26.
//

import SwiftUI

@main
struct WayfinderApp: App {
    static let browserWindowID = "browser"
    static let historyWindowID = "history"

    var body: some Scene {
        WindowGroup(id: Self.browserWindowID) {
            BrowserWindow()
                .withSharedStores()
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            BrowserCommands()
        }

        Window("History", id: Self.historyWindowID) {
            HistoryView()
                .withSharedStores()
        }
        .defaultSize(width: 720, height: 560)

        Settings {
            SettingsView()
                .withSharedStores()
        }
    }
}

private extension View {
    func withSharedStores() -> some View {
        environment(HistoryStore.shared)
            .environment(BookmarkStore.shared)
            .environment(DownloadManager.shared)
            .environment(FaviconLoader.shared)
    }
}
