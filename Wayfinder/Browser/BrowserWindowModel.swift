//
//  BrowserWindowModel.swift
//  Wayfinder
//

import AppKit
import Observation
import os
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

    @ObservationIgnored private static let logger = Logger(subsystem: "com.tanush.Wayfinder", category: "Spaces")

    @ObservationIgnored let store: SpaceStore
    /// Every open web view in this window, across all spaces.
    private var loadedTabs: [BrowserTab] = []
    private(set) var selectedSpaceID: Space.ID
    var selectedTabID: BrowserTab.ID? {
        didSet {
            guard let selectedTabID, let record = store.record(selectedTabID) else { return }
            lastSelectedTabIDs[record.spaceID] = selectedTabID
            store.touch(selectedTabID)
        }
    }
    /// The tab to bring back when returning to a space.
    @ObservationIgnored private var lastSelectedTabIDs: [Space.ID: BrowserTab.ID] = [:]

    let address = AddressFieldState()
    let commandBar = CommandBarState()
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
            closeObserver.map(NotificationCenter.default.removeObserver)
            closeObserver = nil
            guard let window else { return }
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.store.flush() }
            }
            keyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { Self.lastActive = self }
            }
            if window.isKeyWindow { Self.lastActive = self }
        }
    }

    @ObservationIgnored private var keyObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var closeObserver: (any NSObjectProtocol)?

    init(store: SpaceStore = .shared, restoresSession: Bool = true) {
        self.store = store
        selectedSpaceID = store.spaces[0].id
        Self.liveWindows.add(self)
        Self.lastActive = self

        let urls = Self.pendingURLs
        Self.pendingURLs = []
        if restoresSession, !Self.didRestoreSession {
            Self.didRestoreSession = true
            store.discardTodayRecords(keepingRestorable: Preferences.restoresTabs, except: Self.loadedRecordIDs(in: store))
            for record in store.records where record.kind == .today && Self.owner(of: record.id, in: store) == nil {
                load(record, select: false)
                lastSelectedTabIDs[record.spaceID] = record.id
            }
        }

        for url in urls {
            newTab(url: url, select: false)
        }
        if tabs.isEmpty {
            newTab()
        } else {
            selectedTabID = lastSelectedTabIDs[selectedSpaceID] ?? tabs.last?.id
        }
    }

    var currentSpace: Space {
        store.space(selectedSpaceID) ?? store.spaces[0]
    }

    /// Open tabs of the current space: essentials, then pinned, then today.
    var tabs: [BrowserTab] {
        tabs(in: selectedSpaceID)
    }

    private func tabs(in spaceID: Space.ID) -> [BrowserTab] {
        let loaded = Dictionary(loadedTabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return store.records(in: spaceID).compactMap { loaded[$0.id] }
    }

    var todayTabs: [BrowserTab] {
        let today = Set(store.records(in: selectedSpaceID, kind: .today).map(\.id))
        return tabs.filter { today.contains($0.id) }
    }

    /// What the tab strip shows: every essential and pinned tab (loaded or not), plus open today tabs.
    var visibleRecords: [TabRecord] {
        let loaded = Set(loadedTabs.map(\.id))
        return store.records(in: selectedSpaceID).filter { $0.kind != .today || loaded.contains($0.id) }
    }

    func tab(for record: TabRecord) -> BrowserTab? {
        loadedTabs.first { $0.id == record.id }
    }

    var selectedTab: BrowserTab? {
        loadedTabs.first { $0.id == selectedTabID }
    }

    /// The window that has this record's web view open, if any. A record is open in at most one window.
    private static func owner(of recordID: TabRecord.ID, in store: SpaceStore) -> BrowserWindowModel? {
        let windows: [BrowserWindowModel] = liveWindows.allObjects
        return windows.first { $0.store === store && $0.loadedTabs.contains { $0.id == recordID } }
    }

    private static func loadedRecordIDs(in store: SpaceStore) -> Set<TabRecord.ID> {
        let windows: [BrowserWindowModel] = liveWindows.allObjects
        return Set(windows.filter { $0.store === store }.flatMap { $0.loadedTabs.map(\.id) })
    }

    static var frontmost: BrowserWindowModel? {
        lastActive ?? liveWindows.allObjects.first
    }

    // MARK: Tabs

    @discardableResult
    func newTab(url: URL? = nil, select: Bool = true, after anchor: BrowserTab? = nil) -> BrowserTab {
        newTab(url: url, in: selectedSpaceID, select: select, after: anchor)
    }

    @discardableResult
    private func newTab(url: URL?, in spaceID: Space.ID, select: Bool, after anchor: BrowserTab?) -> BrowserTab {
        let space = store.space(spaceID) ?? currentSpace
        let record = TabRecord(spaceID: space.id, kind: .today)
        let tab = BrowserTab(id: record.id, dataStore: space.dataStore)
        insert(tab, record: record, after: anchor, select: select && space.id == selectedSpaceID)
        if let url = url ?? Preferences.homepage {
            tab.load(url)
        } else if select {
            focusAddressBar()
        }
        return tab
    }

    func openTab(with url: URL, after anchor: BrowserTab?, select: Bool) {
        newTab(url: url, in: anchor.flatMap { store.record($0.id)?.spaceID } ?? selectedSpaceID, select: select, after: anchor)
    }

    /// A tab for `window.open` or `target=_blank`. WebKit loads it after we return the web view.
    /// Returns nil when the opener's space is unknown, since the popup would share its profile.
    func openPopup(configuration: WKWebViewConfiguration, after anchor: BrowserTab) -> BrowserTab? {
        guard let spaceID = store.record(anchor.id)?.spaceID else { return nil }
        let record = TabRecord(spaceID: spaceID, kind: .today)
        let tab = BrowserTab(id: record.id, configuration: configuration)
        insert(tab, record: record, after: anchor, select: spaceID == selectedSpaceID)
        return tab
    }

    func duplicate(_ tab: BrowserTab) {
        newTab(url: tab.url, in: store.record(tab.id)?.spaceID ?? selectedSpaceID, select: true, after: tab)
    }

    func close(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        // Closing a pinned or essential tab unloads it but keeps the record, reset to its home URL.
        let wasToday = store.record(tab.id)?.kind == .today
        if wasToday {
            if let url = tab.url {
                ClosedTabs.shared.push(url)
            }
            store.removeRecord(tab.id)
        } else {
            store.resetToSavedURL(tab.id)
        }
        tab.tearDown()
        loadedTabs.removeAll { $0.id == tab.id }

        let remaining = tabs
        if remaining.isEmpty {
            selectedTabID = nil
            if wasToday {
                if loadedTabs.isEmpty {
                    window?.performClose(nil)
                } else {
                    newTab()
                }
            }
        } else if selectedTabID == tab.id {
            selectedTabID = remaining[min(index, remaining.count - 1)].id
        }
        saveSession()
    }

    func closeSelectedTab() {
        if let selectedTab { close(selectedTab) }
    }

    /// Closes every today tab of the current space (Arc's "Clear").
    func clearTodayTabs() {
        let doomed = todayTabs
        guard !doomed.isEmpty else { return }
        // Keep the window usable: a space with nothing open gets a fresh tab.
        if doomed.count == tabs.count { newTab() }
        doomed.forEach(close)
    }

    /// Reopens the page as a today tab in another space and closes it here.
    func moveToSpace(_ tab: BrowserTab, _ spaceID: Space.ID) {
        guard store.record(tab.id)?.spaceID != spaceID, store.space(spaceID) != nil else { return }
        newTab(url: tab.url, in: spaceID, select: false, after: nil)
        close(tab)
    }

    /// Moves a tab to a section and position; see `SpaceStore.place`.
    @discardableResult
    func place(_ id: TabRecord.ID, kind: TabRecord.Kind, folderID: Folder.ID? = nil, before anchor: TabRecord.ID? = nil) -> Bool {
        if let tab = loadedTabs.first(where: { $0.id == id }) { sync(tab) }
        return store.place(id, kind: kind, folderID: folderID, before: anchor)
    }

    func closeOtherTabs(except tab: BrowserTab) {
        for other in todayTabs where other.id != tab.id {
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

    /// Selects a tab, loading it first if it is an unloaded pinned or essential tab.
    func activate(_ record: TabRecord) {
        if let tab = tab(for: record) {
            selectedSpaceID = record.spaceID
            select(tab)
        } else if let other = Self.owner(of: record.id, in: store), let tab = other.tab(for: record) {
            // A record is open in one window at a time, so go to the window that has it.
            other.selectSpace(record.spaceID)
            other.select(tab)
            other.window?.makeKeyAndOrderFront(nil)
        } else {
            selectedSpaceID = record.spaceID
            load(record, select: true)
        }
    }

    /// ⌘1 to ⌘8 pick a tab by position. ⌘9 picks the last tab, as in Safari.
    func selectTab(number: Int) {
        let records = visibleRecords
        guard !records.isEmpty else { return }
        let index = number == 9 ? records.count - 1 : number - 1
        if records.indices.contains(index) { activate(records[index]) }
    }

    func selectAdjacentTab(offset: Int) {
        let records = visibleRecords
        guard let current = records.firstIndex(where: { $0.id == selectedTabID }) else { return }
        activate(records[(current + offset + records.count) % records.count])
    }

    /// Reorders today tabs; offsets are positions in `todayTabs`.
    func moveTabs(fromOffsets source: IndexSet, toOffset destination: Int) {
        store.moveRecords(todayTabs.map(\.id), fromOffsets: source, toOffset: destination)
    }

    // MARK: Spaces

    /// Switches space and brings back the tab that was selected there last.
    func selectSpace(_ id: Space.ID) {
        guard id != selectedSpaceID, store.space(id) != nil else { return }
        selectedSpaceID = id
        if let remembered = lastSelectedTabIDs[id], tabs.contains(where: { $0.id == remembered }) {
            selectedTabID = remembered
        } else if let first = tabs.first {
            selectedTabID = first.id
        } else {
            selectedTabID = nil
            newTab()
        }
    }

    /// ⌃1 to ⌃9 pick a space by position.
    func selectSpace(number: Int) {
        guard store.spaces.indices.contains(number - 1) else { return }
        selectSpace(store.spaces[number - 1].id)
    }

    /// Wraps around at both ends.
    func selectAdjacentSpace(offset: Int) {
        let spaces = store.spaces
        guard spaces.count > 1, let current = spaces.firstIndex(where: { $0.id == selectedSpaceID }) else { return }
        selectSpace(spaces[(current + offset + spaces.count) % spaces.count].id)
    }

    @discardableResult
    func addSpace(name: String, icon: String = "square.grid.2x2", color: SpaceColor = .blue) -> Space {
        let space = store.addSpace(name: name, icon: icon, color: color)
        selectSpace(space.id)
        return space
    }

    /// Removes a space, its tabs and its stored website data in every window. The last space cannot be removed.
    func removeSpace(_ id: Space.ID) {
        guard let space = store.space(id), store.spaces.count > 1 else { return }
        let windows: [BrowserWindowModel] = Self.liveWindows.allObjects
        for window in windows where window.store === store {
            window.leaveSpace(id)
        }
        store.removeSpace(id)
        guard !space.usesDefaultDataStore else { return }
        Task {
            // WebKit refuses while a web view still uses the store, and the views release a moment after teardown.
            for attempt in 1...3 {
                await Task.yield()
                do {
                    try await WKWebsiteDataStore.remove(forIdentifier: space.dataStoreID)
                    return
                } catch {
                    Self.logger.error("Could not remove data store (attempt \(attempt)): \(error)")
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }
    }

    /// Tears down this window's tabs in a space that is being removed and moves off it.
    private func leaveSpace(_ id: Space.ID) {
        let doomed = loadedTabs.filter { store.record($0.id)?.spaceID == id }
        doomed.forEach { $0.tearDown() }
        loadedTabs.removeAll { tab in doomed.contains { $0.id == tab.id } }
        lastSelectedTabIDs[id] = nil
        if selectedSpaceID == id, let next = store.spaces.first(where: { $0.id != id }) {
            selectSpace(next.id)
        }
    }

    // MARK: Pinning

    func pin(_ tab: BrowserTab) {
        sync(tab)
        store.pin(tab.id)
    }

    /// Returns false when the space already has the maximum number of essentials.
    @discardableResult
    func makeEssential(_ tab: BrowserTab) -> Bool {
        sync(tab)
        return store.makeEssential(tab.id)
    }

    func unpin(_ tab: BrowserTab) {
        store.unpin(tab.id)
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
        for window in windows {
            window.loadedTabs.forEach(window.sync)
        }
    }

    // MARK: Private

    private func sync(_ tab: BrowserTab) {
        store.update(tab.id, url: tab.url, title: tab.title)
        let state = tab.webView.interactionState.flatMap {
            try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: false)
        }
        store.setInteractionState(tab.id, state)
    }

    /// Creates the web view for a stored record.
    @discardableResult
    private func load(_ record: TabRecord, select: Bool) -> BrowserTab {
        let tab = BrowserTab(id: record.id, dataStore: store.space(record.spaceID)?.dataStore ?? .default())
        tab.owner = self
        loadedTabs.append(tab)
        if let data = record.interactionState,
           let state = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSObject.self], from: data) {
            tab.webView.interactionState = state
        } else if let url = record.url ?? record.savedURL {
            tab.load(url)
        }
        if select { selectedTabID = tab.id }
        return tab
    }

    private func insert(_ tab: BrowserTab, record: TabRecord, after anchor: BrowserTab?, select: Bool) {
        tab.owner = self
        let visible = tabs(in: record.spaceID)
        if let anchor, let index = visible.firstIndex(where: { $0.id == anchor.id }) {
            // Keep a run of tabs opened from the same page in order, like Safari.
            var insertionIndex = index + 1
            while insertionIndex < visible.count, visible[insertionIndex].openerID == anchor.id {
                insertionIndex += 1
            }
            tab.openerID = anchor.id
            store.addRecord(record, after: visible[insertionIndex - 1].id)
        } else {
            store.addRecord(record)
        }
        loadedTabs.append(tab)
        if select || (selectedTabID == nil && record.spaceID == selectedSpaceID) {
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
