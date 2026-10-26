//
//  BrowserWindowModel.swift
//  Wayfinder
//

import AppKit
import Observation
import SwiftUI
import WebKit

/// The tabs and transient UI state of one browser window.
@Observable
final class BrowserWindowModel {
    /// Open windows, used to save the session and to route links from other windows.
    @ObservationIgnored private static let liveWindows = NSHashTable<BrowserWindowModel>.weakObjects()
    @ObservationIgnored private static var didRestoreSession = false
    /// URLs waiting for the next browser window to open, for example from the History window.
    @ObservationIgnored static var pendingURLs: [URL] = []
    @ObservationIgnored private(set) static weak var lastActive: BrowserWindowModel?

    private(set) var tabs: [BrowserTab] = []
    var selectedTabID: BrowserTab.ID?

    let address = AddressFieldState()
    var isFindBarVisible = false
    var findText = ""
    private(set) var findHasNoMatches = false
    var isDownloadsPresented = false
    /// Incremented to ask the address bar to take focus.
    private(set) var addressFocusRequest = 0
    /// Incremented to ask the find bar to take focus.
    private(set) var findFocusRequest = 0

    @ObservationIgnored weak var window: NSWindow? {
        didSet {
            guard window !== oldValue else { return }
            keyObserver.map(NotificationCenter.default.removeObserver)
            keyObserver = nil
            guard let window else { return }
            keyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { Self.lastActive = self }
            }
            if window.isKeyWindow { Self.lastActive = self }
        }
    }

    @ObservationIgnored private var keyObserver: (any NSObjectProtocol)?

    init() {
        Self.liveWindows.add(self)
        Self.lastActive = self

        var urls = Self.pendingURLs
        Self.pendingURLs = []
        if !Self.didRestoreSession {
            Self.didRestoreSession = true
            if Preferences.restoresTabs {
                urls = Self.savedSessionURLs() + urls
            }
        }

        for url in urls {
            newTab(url: url, select: false)
        }
        if tabs.isEmpty {
            newTab()
        } else {
            selectedTabID = tabs.last?.id
        }
    }

    var selectedTab: BrowserTab? {
        tabs.first { $0.id == selectedTabID }
    }

    static var frontmost: BrowserWindowModel? {
        lastActive ?? liveWindows.allObjects.first
    }

    // MARK: Tabs

    @discardableResult
    func newTab(url: URL? = nil, select: Bool = true, after anchor: BrowserTab? = nil) -> BrowserTab {
        let tab = BrowserTab()
        insert(tab, after: anchor, select: select)
        if let url = url ?? Preferences.homepage {
            tab.load(url)
        } else if select {
            focusAddressBar()
        }
        return tab
    }

    func openTab(with url: URL, after anchor: BrowserTab?, select: Bool) {
        newTab(url: url, select: select, after: anchor)
    }

    /// A tab for `window.open` or `target=_blank`. WebKit loads it after we return the web view.
    func openPopup(configuration: WKWebViewConfiguration, after anchor: BrowserTab) -> BrowserTab {
        let tab = BrowserTab(configuration: configuration)
        insert(tab, after: anchor, select: true)
        return tab
    }

    func duplicate(_ tab: BrowserTab) {
        newTab(url: tab.url, after: tab)
    }

    func close(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        if let url = tab.url {
            ClosedTabs.shared.push(url)
        }
        tab.tearDown()
        tabs.remove(at: index)

        if tabs.isEmpty {
            selectedTabID = nil
            window?.performClose(nil)
        } else if selectedTabID == tab.id {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
        }
        saveSession()
    }

    func closeSelectedTab() {
        if let selectedTab { close(selectedTab) }
    }

    func closeOtherTabs(except tab: BrowserTab) {
        for other in tabs where other.id != tab.id {
            close(other)
        }
    }

    func reopenClosedTab() {
        guard let url = ClosedTabs.shared.pop() else { return }
        newTab(url: url)
    }

    func select(_ tab: BrowserTab) {
        selectedTabID = tab.id
    }

    /// ⌘1 to ⌘8 pick a tab by position. ⌘9 picks the last tab, as in Safari.
    func selectTab(number: Int) {
        guard !tabs.isEmpty else { return }
        let index = number == 9 ? tabs.count - 1 : number - 1
        if tabs.indices.contains(index) { selectedTabID = tabs[index].id }
    }

    func selectAdjacentTab(offset: Int) {
        guard let current = tabs.firstIndex(where: { $0.id == selectedTabID }), !tabs.isEmpty else { return }
        let index = (current + offset + tabs.count) % tabs.count
        selectedTabID = tabs[index].id
    }

    func moveTabs(fromOffsets source: IndexSet, toOffset destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
        saveSession()
    }

    // MARK: Navigation

    /// Loads what the user typed into the current tab, or a new one if there is none.
    func submit(_ input: String) {
        guard let url = AddressInput.url(for: input, searchEngine: Preferences.searchEngine) else { return }
        open(url)
    }

    /// Called when the user presses Return in the address bar or picks a suggestion.
    func commitAddress(_ input: String) {
        address.endEditing()
        submit(input)
        focusWebView()
    }

    func focusWebView() {
        guard let webView = selectedTab?.webView else { return }
        webView.window?.makeFirstResponder(webView)
    }

    func open(_ url: URL, inNewTab: Bool = false) {
        if inNewTab || selectedTab == nil {
            newTab(url: url)
        } else {
            selectedTab?.load(url)
        }
    }

    func goHome() {
        if let homepage = Preferences.homepage {
            open(homepage)
        } else {
            newTab()
        }
    }

    // MARK: UI requests

    func focusAddressBar() {
        addressFocusRequest += 1
    }

    func showFindBar() {
        isFindBarVisible = true
        findFocusRequest += 1
    }

    func hideFindBar() {
        isFindBarVisible = false
        findHasNoMatches = false
        focusWebView()
    }

    func findNext(backwards: Bool = false) {
        guard let tab = selectedTab else { return }
        let text = findText
        guard !text.isEmpty else {
            findHasNoMatches = false
            return
        }
        Task {
            let found = await tab.find(text, backwards: backwards)
            if text == findText { findHasNoMatches = !found }
        }
    }

    func showDownloads() {
        isDownloadsPresented = true
    }

    // MARK: Session

    func saveSession() {
        let windows: [BrowserWindowModel] = Self.liveWindows.allObjects
        let urls: [URL] = windows.flatMap { window in window.tabs.compactMap { $0.url } }
        let strings = urls.filter { $0.scheme == "http" || $0.scheme == "https" }.map(\.absoluteString)
        UserDefaults.standard.set(strings, forKey: PreferenceKey.savedTabs)
    }

    private static func savedSessionURLs() -> [URL] {
        let strings = UserDefaults.standard.stringArray(forKey: PreferenceKey.savedTabs) ?? []
        return strings.compactMap(URL.init(string:))
    }

    // MARK: Private

    private func insert(_ tab: BrowserTab, after anchor: BrowserTab?, select: Bool) {
        tab.owner = self
        if let anchor, let index = tabs.firstIndex(where: { $0.id == anchor.id }) {
            // Keep a run of tabs opened from the same page in order, like Safari.
            var insertionIndex = index + 1
            while insertionIndex < tabs.count, tabs[insertionIndex].openerID == anchor.id {
                insertionIndex += 1
            }
            tab.openerID = anchor.id
            tabs.insert(tab, at: insertionIndex)
        } else {
            tabs.append(tab)
        }
        if select || selectedTabID == nil {
            selectedTabID = tab.id
        }
    }
}

/// Recently closed tabs across all windows, so ⌘⇧T works even after a window closes.
@Observable
final class ClosedTabs {
    static let shared = ClosedTabs()

    private(set) var urls: [URL] = []

    var isEmpty: Bool { urls.isEmpty }

    func push(_ url: URL) {
        urls.append(url)
        if urls.count > 50 { urls.removeFirst() }
    }

    func pop() -> URL? {
        urls.popLast()
    }
}
