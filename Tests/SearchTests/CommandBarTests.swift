import AppKit
import WebKit
import XCTest
@testable import Search

/// Return, ⌘Return, ⇧⌘Return and Esc on every kind of row the command bar
/// has (the old bar crashed on Return), driven through the browser's model
/// rather than a window. Tabs of another space switch the space first.
@MainActor
final class CommandBarTests: XCTestCase {
    private var browser: Browser!
    private var oldSpaces = false
    private var oldSplit = false
    private var home: Tab!
    private var docs: Tab!
    private var roadmap: Tab!
    private var work: Space!

    override class func setUp() {
        setenv("SEARCH_PROBE", "command-bar-\(getpid())", 1)
        super.setUp()
    }

    override class func tearDown() {
        Disk.drain()
        unsetenv("SEARCH_PROBE")
        super.tearDown()
    }

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        browser = Browser(record: WindowRecord())
        oldSpaces = browser.prefs.usesSpaces
        oldSplit = browser.prefs.splitView
        browser.prefs.usesSpaces = true
        browser.prefs.splitView = false
        browser.closeAll()
        home = tab("Home", "https://home.example/")
        docs = tab("Docs", "https://docs.example/guide")
        roadmap = tab("Roadmap", "https://roadmap.example/q3")
        browser.showRow([home, docs], active: home.id)
        work = Space(id: UUID(), name: "Work", colour: 0)
        browser.spaces.append(work)
        browser.parked[work.id] = Parked(tabs: [roadmap], active: roadmap.id)
    }

    override func tearDown() {
        // The bookmark and visits live in files the other suites read.
        if let kept = browser.bookmarks.bookmark(for: URL(string: "https://bookmark.example/reading")!) { browser.bookmarks.remove(kept.id) }
        browser.history.forget()
        browser.parked = [:]
        browser.closeAll()
        browser.prefs.usesSpaces = oldSpaces
        browser.prefs.splitView = oldSplit
        Disk.drain()
        browser = nil
        super.tearDown()
    }

    private func tab(_ title: String, _ url: String) -> Tab {
        let tab = Tab(configuration: Web.configuration(space: browser.spaceID))
        tab.restore(url: URL(string: url)!, title: title)
        return tab
    }

    /// ⌘K with words typed.
    private func summon(_ words: String) {
        browser.summon()
        browser.typed = words
    }

    /// ⌘T's field: the page in front is blank.
    private func newTabField(_ words: String) {
        let blank = Tab(configuration: Web.configuration(space: browser.spaceID))
        browser.showRow([blank, home, docs], active: blank.id)
        browser.editing = true
        browser.typed = words
    }

    private func pick(_ matches: (Suggestion) -> Bool, file: StaticString = #filePath, line: UInt = #line) throws -> Suggestion {
        let index = try XCTUnwrap(browser.offers.firstIndex(where: matches), "no such row in \(browser.offers.map(\.key))", file: file, line: line)
        browser.picked = index
        return browser.offers[index]
    }

    // MARK: Tabs

    func testSummonListsTabsOfEverySpaceWithTheirSpaceName() {
        browser.summon()
        let offers = browser.offers
        XCTAssertNil(offers.first { $0.key == "Docs" }?.badge)
        XCTAssertNotNil(offers.first { $0.key == "Docs" })
        XCTAssertEqual(offers.first { $0.key == "Roadmap" }?.badge, "Work")
        XCTAssertNil(offers.first { $0.key == "Home" }, "the page in front is not offered")
    }

    func testReturnOnTabInThisSpaceSwitchesToIt() {
        summon("docs")
        browser.submit()
        XCTAssertEqual(browser.activeID, docs.id)
        XCTAssertEqual(browser.tabs.count, 2)
        XCTAssertFalse(browser.editing)
        XCTAssertEqual(browser.typed, "")
    }

    func testReturnOnTabInAnotherSpaceEntersTheSpaceThenSelects() {
        summon("road")
        browser.submit()
        XCTAssertEqual(browser.spaceID, work.id)
        XCTAssertEqual(browser.activeID, roadmap.id)
        XCTAssertFalse(browser.editing)
    }

    func testTopOpenTabWinsReturnInANewTabFieldToo() {
        newTabField("docs")
        XCTAssertEqual(browser.offers.first?.tab, docs.id)
        browser.submit()
        XCTAssertEqual(browser.activeID, docs.id)
    }

    func testCommandReturnOpensABackgroundTabAndStaysPut() throws {
        for words in ["docs", "road"] {
            summon(words)
            let before = browser.tabs.count
            browser.submit(aside: true)
            XCTAssertEqual(browser.tabs.count, before + 1, words)
            XCTAssertEqual(browser.activeID, home.id, words)
            XCTAssertEqual(browser.spaceID, Space.firstID, words)
            XCTAssertFalse(browser.editing)
        }
    }

    func testShiftCommandReturnOpensANewForegroundTab() {
        summon("road")
        let before = browser.tabs.count
        browser.submit(aside: true, front: true)
        XCTAssertEqual(browser.tabs.count, before + 1)
        XCTAssertNotEqual(browser.activeID, home.id)
        XCTAssertEqual(browser.active?.address?.host, "roadmap.example")
        XCTAssertEqual(browser.spaceID, Space.firstID)
    }

    func testEscapeLeavesEverythingAsItWas() {
        summon("road")
        browser.dismiss()
        XCTAssertFalse(browser.editing)
        XCTAssertFalse(browser.summoning)
        XCTAssertEqual(browser.typed, "")
        XCTAssertEqual(browser.activeID, home.id)
        XCTAssertEqual(browser.spaceID, Space.firstID)
    }

    // MARK: Bookmarks and history

    private func remember() {
        browser.history.record(URL(string: "https://history.example/recipes")!, title: "Soup recipes")
        _ = browser.bookmarks.add(URL(string: "https://bookmark.example/reading")!, title: "Reading list")
    }

    func testReturnOnHistoryAndBookmarkRowsOpensThemHere() throws {
        remember()
        for (words, host, kind) in [("history.example", "history.example", Suggestion.Kind.visited), ("bookmark.example", "bookmark.example", .bookmark)] {
            newTabField(words)
            _ = try pick { $0.kind == kind }
            let before = browser.tabs.count
            browser.submit()
            XCTAssertEqual(browser.active?.address?.host, host)
            XCTAssertEqual(browser.tabs.count, before)
            XCTAssertFalse(browser.editing)
        }
    }

    func testCommandReturnOnHistoryAndBookmarkRowsOpensBehind() throws {
        remember()
        for (words, kind, front) in [("history.example", Suggestion.Kind.visited, false), ("bookmark.example", .bookmark, true)] {
            newTabField(words)
            let blank = browser.activeID
            _ = try pick { $0.kind == kind }
            let before = browser.tabs.count
            browser.submit(aside: true, front: front)
            XCTAssertEqual(browser.tabs.count, before + 1, words)
            XCTAssertEqual(browser.activeID == blank, !front, words)
        }
    }

    func testEscapeOnHistoryRowPutsTheOldAddressBack() {
        remember()
        browser.edit()
        browser.typed = "history.example"
        XCTAssertFalse(browser.offers.isEmpty)
        browser.dismiss()
        XCTAssertFalse(browser.editing)
        XCTAssertEqual(browser.typed, "")
        XCTAssertEqual(browser.active?.address?.host, "home.example")
    }

    // MARK: Actions and Settings

    func testActionsPrefixListsActionsAndSettingsOnly() {
        newTabField("> sidebar")
        XCTAssertFalse(browser.offers.isEmpty)
        XCTAssertEqual(browser.picked, 0)
        for offer in browser.offers {
            switch offer.kind {
            case .action, .setting: break
            default: XCTFail("\(offer.kind) in an actions list")
            }
        }
        // Without the prefix, a page you have open still beats them.
        newTabField("docs")
        XCTAssertEqual(browser.offers.first?.kind, .open)
    }

    func testCompactSidebarActionRunsOnReturnAndCommandReturn() throws {
        for aside in [false, true] {
            summon("")
            browser.typed = "> compact sidebar"
            let top = try XCTUnwrap(browser.offers.first)
            XCTAssertEqual(top.kind, .action("view.fold"))
            XCTAssertEqual(top.key, "Toggle Compact Sidebar")
            let folded = browser.folded
            browser.submit(aside: aside)
            XCTAssertEqual(browser.folded, !folded, "aside \(aside)")
            XCTAssertFalse(browser.editing)
            XCTAssertEqual(browser.typed, "")
        }
    }

    func testActionRowRunsShiftCommandReturnAndEscapeDoesNothing() throws {
        newTabField("> new space")
        _ = try pick { $0.kind == .action("bar.newSpace") }
        browser.dismiss()
        XCTAssertFalse(browser.makingSpace)
        newTabField("> new space")
        _ = try pick { $0.kind == .action("bar.newSpace") }
        browser.submit(aside: true, front: true)
        XCTAssertTrue(browser.makingSpace)
        browser.makingSpace = false
    }

    func testActionsFollowTheFeatureSwitches() {
        browser.prefs.usesSpaces = false
        XCTAssertFalse(CommandBar.actions(in: browser).contains { $0.section == .spaces })
        XCTAssertFalse(CommandBar.actions(in: browser).contains { $0.id == "tabs.search" })
        browser.prefs.usesSpaces = true
        XCTAssertTrue(CommandBar.actions(in: browser).contains { $0.id == "bar.newSpace" })
    }

    func testSettingsRowOpensItsPageOnReturnAndCommandReturn() throws {
        let item = try XCTUnwrap(SettingsIndex.items.first { $0.kind != .note && $0.page == .appearance })
        for aside in [false, true] {
            browser.tuning = false
            newTabField("> " + item.title)
            _ = try pick { $0.kind == .setting(item.id) }
            browser.submit(aside: aside)
            XCTAssertTrue(browser.tuning, "aside \(aside)")
            XCTAssertEqual(browser.settingsPage, .appearance)
        }
    }

    func testEscapeOnSettingsRowLeavesSettingsClosed() throws {
        let item = try XCTUnwrap(SettingsIndex.items.first { $0.kind != .note })
        newTabField("> " + item.title)
        browser.dismiss()
        XCTAssertFalse(browser.tuning)
    }

    // MARK: Speed

    func testBigHistoryRanksQuickly() {
        let history = History(file: "command-bar-perf-\(getpid()).json")
        defer { history.retire() }
        for index in 0..<50_000 {
            history.record(URL(string: "https://site\(index % 977).example/page/\(index)")!, title: "Page \(index) about topic \(index % 31)")
        }
        var scan = 0.0
        var ranking = 0.0
        var rows = 0
        for words in ["page/4", "site12", "example/page/77"] {
            var mark = Date()
            // Only the best few places for the words reach the ranker, by frecency.
            let found = history.suggestions(for: words, limit: CommandBar.places)
            scan += Date().timeIntervalSince(mark)
            XCTAssertLessThanOrEqual(found.count, CommandBar.places)
            let candidates = found.enumerated().map { index, row in
                CommandCandidate(id: index, title: row.title, url: row.url.absoluteString, kind: .history)
            }
            mark = Date()
            rows += CommandRanker.rank(query: words, candidates: candidates).count
            ranking += Date().timeIntervalSince(mark)
        }
        XCTAssertGreaterThan(rows, 0)
        XCTAssertLessThan(ranking / 3, 0.05, "ranking a key")
        // The scan of 50k places is History's own (as fast as it was before the bar
        // ranked); this is a debug build, so the bound is a ceiling, not a target.
        XCTAssertLessThan(scan / 3, 2, "scanning 50k places for a key")
    }
}
