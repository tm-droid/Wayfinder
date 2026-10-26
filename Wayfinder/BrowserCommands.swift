//
//  BrowserCommands.swift
//  Wayfinder
//

import AppKit
import SwiftUI

struct BrowserCommands: Commands {
    @FocusedValue(BrowserWindowModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    private var tab: BrowserTab? { model?.selectedTab }
    private var bookmarks: BookmarkStore { .shared }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Tab") {
                if let model { model.newTab() } else { openWindow(id: WayfinderApp.browserWindowID) }
            }
            .keyboardShortcut("t")

            Button("Reopen Closed Tab") {
                if let model {
                    model.reopenClosedTab()
                } else if let url = ClosedTabs.shared.pop() {
                    BrowserWindowModel.pendingURLs = [url]
                    openWindow(id: WayfinderApp.browserWindowID)
                }
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(ClosedTabs.shared.isEmpty)

            Button("Open Location…") { model?.focusAddressBar() }
                .keyboardShortcut("l")
                .disabled(model == nil)

            Divider()

            // Stays enabled so ⌘W still closes other windows, like History.
            Button("Close Tab") {
                if let model { model.closeSelectedTab() } else { NSApp.keyWindow?.performClose(nil) }
            }
            .keyboardShortcut("w")
        }

        CommandGroup(replacing: .printItem) {
            Button("Export as PDF…") { Task { await tab?.exportPDF() } }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(tab?.url == nil)
            Button("Print…") { tab?.print() }
                .keyboardShortcut("p")
                .disabled(tab?.url == nil)
        }

        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find…") { model?.showFindBar() }
                .keyboardShortcut("f")
                .disabled(tab?.url == nil)
            Button("Find Next") { model?.findNext() }
                .keyboardShortcut("g")
                .disabled(model?.findText.isEmpty != false)
            Button("Find Previous") { model?.findNext(backwards: true) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(model?.findText.isEmpty != false)
        }

        CommandGroup(before: .sidebar) {
            Button("Reload Page") { tab?.reload() }
                .keyboardShortcut("r")
                .disabled(tab?.url == nil && tab?.loadError == nil)
            Button("Stop") { tab?.stopLoading() }
                .keyboardShortcut(".")
                .disabled(tab?.isLoading != true)

            Divider()

            Button("Actual Size") { tab?.resetZoom() }
                .keyboardShortcut("0")
                .disabled(tab == nil || tab?.zoom == 1)
            Button("Zoom In") { tab?.zoomIn() }
                .keyboardShortcut("=")
                .disabled(tab?.canZoomIn != true)
            Button("Zoom Out") { tab?.zoomOut() }
                .keyboardShortcut("-")
                .disabled(tab?.canZoomOut != true)

            Divider()

            Button("Show Downloads") { model?.showDownloads() }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(model == nil)

            Divider()
        }

        CommandMenu("History") {
            Button("Back") { tab?.goBack() }
                .keyboardShortcut("[")
                .disabled(tab?.canGoBack != true)
            Button("Forward") { tab?.goForward() }
                .keyboardShortcut("]")
                .disabled(tab?.canGoForward != true)
            Button("Home") { model?.goHome() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(model == nil)

            Divider()

            Button("Show All History") { openWindow(id: WayfinderApp.historyWindowID) }
                .keyboardShortcut("y")
        }

        CommandMenu("Bookmarks") {
            Button(bookmarks.contains(tab?.url) ? "Remove Bookmark" : "Add Bookmark") {
                if let tab, let url = tab.url { bookmarks.toggle(url: url, title: tab.title) }
            }
            .keyboardShortcut("d")
            .disabled(tab?.url == nil)

            if !bookmarks.bookmarks.isEmpty {
                Divider()
                ForEach(bookmarks.bookmarks) { bookmark in
                    Button(bookmark.displayTitle) { model?.open(bookmark.url) }
                        .disabled(model == nil)
                }
            }
        }

        CommandGroup(before: .windowList) {
            Button("Show Previous Tab") { model?.selectAdjacentTab(offset: -1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled((model?.tabs.count ?? 0) < 2)
            Button("Show Next Tab") { model?.selectAdjacentTab(offset: 1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled((model?.tabs.count ?? 0) < 2)

            Divider()

            ForEach(1...9, id: \.self) { number in
                Button(number == 9 ? "Select Last Tab" : "Select Tab \(number)") { model?.selectTab(number: number) }
                    .keyboardShortcut(KeyEquivalent(Character(String(number))))
                    .disabled(model == nil)
            }

            Divider()
        }
    }
}
