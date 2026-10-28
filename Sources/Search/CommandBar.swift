import Foundation

// What the command bar offers for what was typed: the pool of open tabs (of
// every space), bookmarks, history, menu commands and Settings rows, ranked by
// CommandRanker. The pool is cheap to build however big the history is: only
// the best few places for the typed words are taken from it (History's own
// frecency scan), and the ranker never sees the rest.

@MainActor
enum CommandBar {
    /// The least a command or Settings row scores to show without ">": a
    /// substring of its name or words, not a scattering of letters.
    static let actionFloor = 80

    /// How many bookmarks and history places go in the pool.
    static let places = 30

    /// Commands that mean nothing from the bar: it is already open, or the key
    /// alone is what they are for, or they destroy without asking.
    private static let skipped: Set<String> = ["tabs.search", "file.openAddress", Command.recentTabs, "history.clear"]

    /// The names the bar gives a command, and the words that find it.
    private static let renamed: [String: (title: String, words: [String])] = [
        "view.fold": ("Toggle Compact Sidebar", ["fold", "hide sidebar", "compact", "tab bar"]),
        "view.sidebar": ("Toggle Sidebar or Tab Bar", ["sidebar", "tabs on top", "horizontal"]),
    ]

    /// Commands the bar has that no menu does.
    private static let extra: [Command] = [
        Command("bar.newSpace", "New Space", .spaces, nil) { $0.makingSpace = true },
    ]

    static func command(_ id: String) -> Command? { extra.first { $0.id == id } ?? Command.named(id) }

    /// The commands that make sense in this window as it is now.
    static func actions(in browser: Browser) -> [Command] {
        (Command.all + extra).filter { command in
            if skipped.contains(command.id) { return false }
            if command.section == .spaces, !browser.prefs.usesSpaces { return false }
            if Command.split.contains(command.id) { return browser.prefs.splitView }
            if Command.ai.contains(command.id) { return browser.prefs.ai }
            if Command.dusk.contains(command.id) { return browser.prefs.darkensPages }
            return true
        }
    }

    static func title(of command: Command) -> String {
        renamed[command.id]?.title ?? command.title.replacingOccurrences(of: "…", with: "")
    }

    static func words(of command: Command) -> [String] { [command.section.rawValue] + (renamed[command.id]?.words ?? []) }

    static func suggestion(for command: Command) -> Suggestion {
        Suggestion(key: title(of: command), title: command.section.rawValue, url: about, kind: .action(command.id))
    }

    static func suggestion(for item: SettingsItem) -> Suggestion {
        Suggestion(key: item.title, title: "Settings › " + item.page.title, url: about, kind: .setting(item.id))
    }

    /// An action goes nowhere, but the row still carries *a* URL; `take` and
    /// `submit` read the kind first and never follow it.
    static let about = URL(string: "about:blank")!
}

extension Browser {
    /// The rows for what was typed, best first. An empty field gives the tabs
    /// you have open, most recent first; "> " alone is the actions.
    func barOffers(for typed: String, now: Date = Date()) -> [Suggestion] {
        let query = typed.trimmingCharacters(in: .whitespaces)
        let actionsOnly = query.hasPrefix(">")
        var pool: [Suggestion] = []
        var candidates: [CommandCandidate<Int>] = []
        func add(_ row: Suggestion, _ title: String, url: String? = nil, _ kind: CommandKind,
                 used: Date? = nil, words: [String] = []) {
            candidates.append(CommandCandidate(id: pool.count, title: title, url: url, kind: kind, lastUsed: used, keywords: words))
            pool.append(row)
        }

        if !actionsOnly {
            // Every space's tabs: the others' are parked, and Return there
            // enters the space first.
            var open = tabs.map { ($0, Space?.none) }
            for space in spaces where space.id != spaceID {
                open += (parked[space.id]?.tabs ?? []).map { ($0, space) }
            }
            for (tab, space) in open.filter({ $0.0.id != activeID && !$0.0.isBlank }).sorted(by: { $0.0.touched > $1.0.touched }) {
                guard let url = tab.address else { continue }
                var row = Suggestion(key: tab.label, title: Address.pretty(url), url: url, kind: .open, tab: tab.id)
                row.space = space?.id
                row.badge = space?.name
                add(row, tab.label, url: url.absoluteString, .openTab, used: tab.touched)
            }
            if !query.isEmpty {
                for row in bookmarks.places(for: query, limit: CommandBar.places) {
                    add(row, row.title.isEmpty ? row.key : row.title, url: row.url.absoluteString, .bookmark)
                }
                // Already ordered by frecency, which the ranker keeps for equal scores.
                for row in history.suggestions(for: query, limit: CommandBar.places) {
                    add(row, row.title.isEmpty ? row.key : row.title, url: row.url.absoluteString, .history)
                }
            }
        }
        if !query.isEmpty {
            for command in CommandBar.actions(in: self) {
                let title = CommandBar.title(of: command)
                add(CommandBar.suggestion(for: command), title, .action,
                    words: CommandBar.words(of: command))
            }
            for item in SettingsIndex.items where item.kind != .note && SettingsIndex.applies(item, prefs) {
                add(CommandBar.suggestion(for: item), item.title, .action, words: item.words + [item.page.title])
            }
        }
        // A scatter of letters finds an action only after ">": otherwise "soup"
        // would offer a Settings row for "Open sized pop-ups" under every search.
        let ranked = CommandRanker.rank(query: typed, candidates: candidates, now: now, limit: CommandRanker.maxResults * 3)
            .filter { actionsOnly || $0.candidate.kind != .action || $0.score >= CommandBar.actionFloor }
        return ranked.prefix(CommandRanker.maxResults).map { pool[$0.candidate.id] }
    }

    /// An action or Settings row, run. The field is put away first: some
    /// actions raise it again (New Tab). False for any other row.
    func perform(_ offer: Suggestion) -> Bool {
        switch offer.kind {
        case .action(let id):
            guard let command = CommandBar.command(id) else { return false }
            putFieldAway()
            command.run(self)
        case .setting(let id):
            guard let item = SettingsIndex.item(id) else { return false }
            putFieldAway()
            show(InternalPage(.settings, item.page.rawValue))
        default:
            return false
        }
        return true
    }

    /// A row for a tab of this window, switched to: its space is entered first
    /// when it is another's.
    @discardableResult
    func switchTo(_ offer: Suggestion) -> Bool {
        guard let id = offer.tab else { return false }
        putFieldAway()
        if let space = offer.space, space != spaceID { enter(space) }
        guard let tab = tabs.first(where: { $0.id == id }) else { return false }
        select(tab)
        return true
    }

    private func putFieldAway() {
        summoning = false
        editing = false
        typed = ""
        picked = nil
    }
}
