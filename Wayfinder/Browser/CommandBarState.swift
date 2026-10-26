//
//  CommandBarState.swift
//  Wayfinder
//

import AppKit
import Observation

/// Editing state of a window's command bar.
@Observable
final class CommandBarState {
    enum Mode {
        /// ⌘T: Enter opens the result in a new tab.
        case newTab
        /// ⌘L: Enter navigates the current tab.
        case current
    }

    private(set) var isPresented = false
    private(set) var mode = Mode.newTab
    var text = ""
    private(set) var items: [CommandBarItem] = []
    var highlightedIndex = 0
    /// Incremented each time the bar opens, so the field can take focus and select its text.
    private(set) var presentCount = 0

    var highlightedItem: CommandBarItem? {
        items.indices.contains(highlightedIndex) ? items[highlightedIndex] : nil
    }

    func present(_ mode: Mode, prefill: String) {
        self.mode = mode
        text = prefill
        highlightedIndex = 0
        isPresented = true
        presentCount += 1
    }

    func dismiss() {
        isPresented = false
        text = ""
        items = []
    }

    func setItems(_ newItems: [CommandBarItem]) {
        items = newItems
        highlightedIndex = 0
    }

    func moveHighlight(by offset: Int) {
        guard !items.isEmpty else { return }
        highlightedIndex = (highlightedIndex + offset + items.count) % items.count
    }

    /// Tab key: fill in the first result that is a page.
    func autocomplete() {
        guard let url = items.first(where: { $0.group != .topHit && $0.group != .action && $0.url != nil })?.url else { return }
        text = AddressInput.displayString(for: url)
    }
}

extension BrowserWindowModel {
    func showCommandBar(_ mode: CommandBarState.Mode) {
        let prefill = mode == .current ? selectedTab?.url?.absoluteString ?? "" : ""
        commandBar.present(mode, prefill: prefill)
        refreshCommandBar()
    }

    func refreshCommandBar() {
        let query = commandBar.text
        let tabs: [CommandBarRanker.TabEntry] = store.records.compactMap { record in
            guard record.id != selectedTabID else { return nil }
            let loaded = tab(for: record)
            let space = record.spaceID == selectedSpaceID ? nil : store.space(record.spaceID)?.icon
            return .init(id: record.id, title: loaded?.title ?? record.title, url: loaded?.url ?? record.url ?? record.savedURL, spaceIcon: space)
        }
        let bookmarks = BookmarkStore.shared.matches(for: query, limit: 20).map { CommandBarRanker.PageEntry(title: $0.displayTitle, url: $0.url) }
        let history = HistoryStore.shared.matches(for: query, limit: 20).map { CommandBarRanker.PageEntry(title: $0.displayTitle, url: $0.url) }
        commandBar.setItems(CommandBarRanker.rank(
            query: query, searchEngine: Preferences.searchEngine,
            tabs: tabs, bookmarks: bookmarks, history: history, actions: availableCommandBarActions
        ))
    }

    private var availableCommandBarActions: [CommandBarAction] {
        var actions: [CommandBarAction] = [.newSpace, .toggleSidebar, .openHistory, .openSettings]
        if store.spaces.count > 1 { actions += [.nextSpace, .previousSpace] }
        if let selectedTab, let record = store.record(selectedTab.id) {
            if selectedTab.url != nil { actions += [.copyURL, .duplicateTab] }
            actions.append(record.kind == .today ? .pinCurrentTab : .unpinCurrentTab)
            if record.kind != .essential { actions.append(.addToEssentials) }
        }
        if !ClosedTabs.shared.isEmpty { actions.append(.reopenClosedTab) }
        if !todayTabs.isEmpty { actions.append(.clearTodayTabs) }
        return actions
    }

    /// Runs a result. `inBackground` (⌘Enter) opens pages in a new tab without switching to it.
    func commitCommandBar(_ item: CommandBarItem, inBackground: Bool, openHistory: () -> Void) {
        let mode = commandBar.mode
        commandBar.dismiss()
        switch item.target {
        case .navigate(let url):
            if inBackground {
                newTab(url: url, select: false)
            } else {
                open(url, inNewTab: mode == .newTab)
            }
        case .switchTab(let id):
            if let record = store.record(id) { activate(record) }
        case .action(let action):
            perform(action, openHistory: openHistory)
        }
        if case .action = item.target {} else if !inBackground { focusWebView() }
    }

    private func perform(_ action: CommandBarAction, openHistory: () -> Void) {
        switch action {
        case .newSpace: addSpace(name: "Space \(store.spaces.count + 1)")
        case .nextSpace: selectAdjacentSpace(offset: 1)
        case .previousSpace: selectAdjacentSpace(offset: -1)
        case .toggleSidebar: NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
        case .copyURL:
            if let url = selectedTab?.url {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
        case .pinCurrentTab: selectedTab.map(pin)
        case .unpinCurrentTab: selectedTab.map(unpin)
        case .addToEssentials: selectedTab.map { _ = makeEssential($0) }
        case .duplicateTab: selectedTab.map(duplicate)
        case .reopenClosedTab: reopenClosedTab()
        case .clearTodayTabs: clearTodayTabs()
        case .openHistory: openHistory()
        case .openSettings: NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }
}
