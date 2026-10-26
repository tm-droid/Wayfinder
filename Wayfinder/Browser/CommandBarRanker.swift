//
//  CommandBarRanker.swift
//  Wayfinder
//

import Foundation

nonisolated enum CommandBarAction: String, CaseIterable, Hashable {
    case newSpace, nextSpace, previousSpace, toggleSidebar, copyURL
    case pinCurrentTab, unpinCurrentTab, addToEssentials, duplicateTab
    case reopenClosedTab, clearTodayTabs, openHistory, openSettings

    var title: String {
        switch self {
        case .newSpace: "New Space"
        case .nextSpace: "Next Space"
        case .previousSpace: "Previous Space"
        case .toggleSidebar: "Toggle Sidebar"
        case .copyURL: "Copy URL"
        case .pinCurrentTab: "Pin Current Tab"
        case .unpinCurrentTab: "Unpin Current Tab"
        case .addToEssentials: "Add to Essentials"
        case .duplicateTab: "Duplicate Tab"
        case .reopenClosedTab: "Reopen Closed Tab"
        case .clearTodayTabs: "Clear Today Tabs"
        case .openHistory: "Open History"
        case .openSettings: "Open Settings"
        }
    }

    var symbol: String {
        switch self {
        case .newSpace: "plus.square.on.square"
        case .nextSpace: "chevron.right.square"
        case .previousSpace: "chevron.left.square"
        case .toggleSidebar: "sidebar.left"
        case .copyURL: "link"
        case .pinCurrentTab: "pin"
        case .unpinCurrentTab: "pin.slash"
        case .addToEssentials: "star"
        case .duplicateTab: "plus.square.on.square"
        case .reopenClosedTab: "arrow.uturn.backward"
        case .clearTodayTabs: "xmark.bin"
        case .openHistory: "clock"
        case .openSettings: "gearshape"
        }
    }

    /// Extra words that find the action.
    var keywords: [String] {
        switch self {
        case .toggleSidebar: ["hide sidebar", "show sidebar"]
        case .copyURL: ["copy link", "copy address"]
        case .clearTodayTabs: ["close all tabs"]
        case .openSettings: ["preferences"]
        default: []
        }
    }
}

nonisolated struct CommandBarItem: Identifiable, Hashable {
    enum Group: Int, Comparable {
        case topHit, tab, bookmark, history, action

        static func < (lhs: Group, rhs: Group) -> Bool { lhs.rawValue < rhs.rawValue }

        var heading: String? {
            switch self {
            case .topHit: nil
            case .tab: "Switch to Tab"
            case .bookmark: "Bookmarks"
            case .history: "History"
            case .action: "Actions"
            }
        }
    }

    enum Target: Hashable {
        case navigate(URL)
        case switchTab(UUID)
        case action(CommandBarAction)
    }

    let group: Group
    let title: String
    let subtitle: String
    let target: Target
    var url: URL?
    var symbol: String?
    /// The tab's space, set only when it is not the current one.
    var spaceIcon: String?

    var id: String { "\(group)-\(target)" }
}

/// Orders and merges command bar results. Pure, so it can be tested without any store.
nonisolated enum CommandBarRanker {
    struct TabEntry {
        var id: UUID
        var title: String
        var url: URL?
        var spaceIcon: String?
    }

    struct PageEntry {
        var title: String
        var url: URL
    }

    static let maxResults = 8
    static let maxPerGroup = 3

    static func rank(
        query rawQuery: String,
        searchEngine: SearchEngine,
        tabs: [TabEntry],
        bookmarks: [PageEntry],
        history: [PageEntry],
        actions: [CommandBarAction] = CommandBarAction.allCases
    ) -> [CommandBarItem] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        var result: [CommandBarItem] = []
        var seen = Set<String>()

        if let top = topHit(for: query, searchEngine: searchEngine) { result.append(top) }

        let tabItems: [(Int, CommandBarItem)] = tabs.compactMap { tab in
            guard let rank = pageScore(query, title: tab.title, url: tab.url) else { return nil }
            let host = tab.url.map(AddressInput.displayString(for:))
            return (rank, CommandBarItem(group: .tab, title: tab.title.isEmpty ? (host ?? "Untitled") : tab.title,
                                         subtitle: "Switch to tab", target: .switchTab(tab.id), url: tab.url, spaceIcon: tab.spaceIcon))
        }
        let pickedTabs = top(tabItems)
        result += pickedTabs
        pickedTabs.compactMap(\.url).forEach { seen.insert(key(for: $0)) }
        // A tab's URL hides its bookmark and history rows, but two tabs on one URL both stay.
        result += pages(bookmarks, group: .bookmark, query: query, seen: &seen)
        result += pages(history, group: .history, query: query, seen: &seen)

        let actionItems: [(Int, CommandBarItem)] = actions.compactMap { action in
            let candidates = [score(query, in: action.title)] + action.keywords.map { score(query, in: $0).map { $0 * 4 / 5 } }
            guard let rank = candidates.compactMap({ $0 }).max() else { return nil }
            return (rank, CommandBarItem(group: .action, title: action.title, subtitle: "Action", target: .action(action), symbol: action.symbol))
        }
        result += top(actionItems)

        return Array(result.prefix(maxResults))
    }

    /// What Enter does with the text as typed: open it if it is an address, otherwise search for it.
    static func topHit(for query: String, searchEngine: SearchEngine) -> CommandBarItem? {
        guard !query.isEmpty else { return nil }
        if let url = AddressInput.directURL(for: query) {
            return CommandBarItem(group: .topHit, title: "Open \(AddressInput.displayString(for: url))", subtitle: url.absoluteString,
                                  target: .navigate(url), url: url)
        }
        return CommandBarItem(group: .topHit, title: "Search \(searchEngine.name) for \u{201C}\(query)\u{201D}", subtitle: "",
                              target: .navigate(searchEngine.searchURL(for: query)), symbol: "magnifyingglass")
    }

    /// Case-insensitive subsequence score, or nil if `query` is not a subsequence of `text`.
    /// Substrings beat scattered matches; prefixes and word starts beat the middle of a word.
    static func score(_ query: String, in text: String) -> Int? {
        let q = Array(query.trimmingCharacters(in: .whitespaces).lowercased())
        let t = Array(text.lowercased())
        guard !q.isEmpty else { return 0 }
        guard q.count <= t.count else { return nil }

        var substringStart: Int?
        for start in 0...(t.count - q.count) where Array(t[start..<(start + q.count)]) == q {
            if substringStart == nil { substringStart = start }
            if isWordStart(t, start) {
                substringStart = start
                break
            }
        }
        if let start = substringStart {
            let position = start == 0 ? 50 : isWordStart(t, start) ? 30 : 0
            return 100 + q.count * 4 + position - min(t.count - q.count, 40) / 4
        }

        var total = 0
        var previous = -2
        var next = 0
        for character in q {
            guard let index = (next..<t.count).first(where: { t[$0] == character }) else { return nil }
            total += 1
            if index == previous + 1 { total += 5 }
            if isWordStart(t, index) { total += 4 }
            total -= min(index - next, 3)
            previous = index
            next = index + 1
        }
        return max(1, min(total, 90))
    }

    // MARK: Private

    /// Best of the title, the host (weighted up) and the full URL (weighted down).
    private static func pageScore(_ query: String, title: String, url: URL?) -> Int? {
        let candidates = [
            score(query, in: title),
            url.flatMap { score(query, in: AddressInput.displayString(for: $0)) }.map { $0 * 6 / 5 },
            url.flatMap { score(query, in: $0.absoluteString) }.map { $0 / 2 },
        ]
        return candidates.compactMap { $0 }.max()
    }

    private static func pages(_ entries: [PageEntry], group: CommandBarItem.Group, query: String, seen: inout Set<String>) -> [CommandBarItem] {
        let scored: [(Int, CommandBarItem)] = entries.compactMap { entry in
            guard !seen.contains(key(for: entry.url)), let rank = pageScore(query, title: entry.title, url: entry.url) else { return nil }
            let host = AddressInput.displayString(for: entry.url)
            return (rank, CommandBarItem(group: group, title: entry.title.isEmpty ? host : entry.title, subtitle: host,
                                         target: .navigate(entry.url), url: entry.url))
        }
        var picked: [CommandBarItem] = []
        for item in top(scored, limit: .max) where picked.count < maxPerGroup {
            guard let url = item.url, seen.insert(key(for: url)).inserted else { continue }
            picked.append(item)
        }
        return picked
    }

    /// Highest score first; equal scores keep their input order.
    private static func top(_ scored: [(Int, CommandBarItem)], limit: Int = maxPerGroup) -> [CommandBarItem] {
        let ordered = scored.enumerated().sorted { lhs, rhs in
            lhs.element.0 != rhs.element.0 ? lhs.element.0 > rhs.element.0 : lhs.offset < rhs.offset
        }
        return ordered.prefix(limit).map(\.element.1)
    }

    private static func key(for url: URL) -> String {
        var text = url.absoluteString.lowercased()
        for prefix in ["https://", "http://", "www."] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
        }
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    private static func isWordStart(_ text: [Character], _ index: Int) -> Bool {
        index == 0 || !text[index - 1].isLetter && !text[index - 1].isNumber
    }
}
