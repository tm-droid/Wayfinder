//
//  CommandBarTests.swift
//  WayfinderTests
//

import XCTest
@testable import Wayfinder

final class CommandBarTests: XCTestCase {
    private func url(_ string: String) -> URL { URL(string: string)! }

    private func rank(
        _ query: String,
        tabs: [CommandBarRanker.TabEntry] = [],
        bookmarks: [CommandBarRanker.PageEntry] = [],
        history: [CommandBarRanker.PageEntry] = []
    ) -> [CommandBarItem] {
        CommandBarRanker.rank(query: query, searchEngine: .duckDuckGo, tabs: tabs, bookmarks: bookmarks, history: history)
    }

    private func page(_ title: String, _ link: String) -> CommandBarRanker.PageEntry {
        .init(title: title, url: url(link))
    }

    func testFuzzyScoringOrder() throws {
        let prefix = try XCTUnwrap(CommandBarRanker.score("git", in: "GitHub"))
        let wordStart = try XCTUnwrap(CommandBarRanker.score("git", in: "My GitHub"))
        let inside = try XCTUnwrap(CommandBarRanker.score("git", in: "Digit"))
        let scattered = try XCTUnwrap(CommandBarRanker.score("ghb", in: "GitHub"))
        XCTAssertGreaterThan(prefix, wordStart)
        XCTAssertGreaterThan(wordStart, inside)
        XCTAssertGreaterThan(inside, scattered)
        XCTAssertNil(CommandBarRanker.score("xyz", in: "GitHub"))
        XCTAssertNotNil(CommandBarRanker.score("GH", in: "github"))
    }

    func testHostMatchBeatsPathMatch() {
        let result = rank("apple", history: [page("Docs", "https://example.com/apple"), page("Docs", "https://apple.com/docs")])
        let history = result.filter { $0.group == .history }
        XCTAssertEqual(history.first?.url, url("https://apple.com/docs"))
    }

    func testDedupePrefersTabOverBookmarkOverHistory() {
        let id = UUID()
        let tabs = [CommandBarRanker.TabEntry(id: id, title: "Example", url: url("https://example.com/"))]
        let bookmarks = [page("Example", "https://www.example.com"), page("Other Example", "https://example.com/other")]
        let history = [page("Example", "http://example.com"), page("Other Example", "https://example.com/other"), page("Example 3", "https://example.com/three")]
        let result = rank("example", tabs: tabs, bookmarks: bookmarks, history: history)

        XCTAssertEqual(result.filter { $0.group == .tab }.count, 1)
        XCTAssertEqual(result.filter { $0.group == .bookmark }.map(\.url), [url("https://example.com/other")])
        XCTAssertEqual(result.filter { $0.group == .history }.map(\.url), [url("https://example.com/three")])
    }

    func testGroupCapsAndTotalCap() {
        let tabs = (0..<6).map { CommandBarRanker.TabEntry(id: UUID(), title: "Site \($0)", url: url("https://site\($0).com")) }
        let result = rank("site", tabs: tabs)
        XCTAssertEqual(result.filter { $0.group == .tab }.count, 3)

        let pages = (0..<6).map { page("Site \($0)", "https://site\($0).org") }
        let busy = rank("site", tabs: tabs, bookmarks: pages, history: pages.map { page($0.title + "x", $0.url.absoluteString + "/h") })
        XCTAssertLessThanOrEqual(busy.count, CommandBarRanker.maxResults)
        XCTAssertEqual(busy.filter { $0.group == .topHit }.count, 1)
        XCTAssertLessThanOrEqual(busy.filter { $0.group == .bookmark }.count, 3)
    }

    func testActionMatching() {
        let newSpace = rank("new sp").filter { $0.group == .action }
        XCTAssertEqual(newSpace.first?.target, .action(.newSpace))

        let pin = rank("pin").filter { $0.group == .action }
        XCTAssertEqual(pin.first?.target, .action(.pinCurrentTab))
    }

    func testTopHitForURLAndSearch() {
        let address = rank("example.com").first
        XCTAssertEqual(address?.group, .topHit)
        XCTAssertEqual(address?.target, .navigate(url("https://example.com")))
        XCTAssertTrue(address?.title.hasPrefix("Open") == true)

        let search = rank("swift concurrency").first
        XCTAssertEqual(search?.group, .topHit)
        XCTAssertEqual(search?.target, .navigate(SearchEngine.duckDuckGo.searchURL(for: "swift concurrency")))
        XCTAssertTrue(search?.title.contains("Search DuckDuckGo") == true)

        XCTAssertTrue(rank("   ").allSatisfy { $0.group != .topHit })
    }

    func testTabKeepsSpaceIcon() {
        let tabs = [CommandBarRanker.TabEntry(id: UUID(), title: "Mail", url: url("https://mail.example.com"), spaceIcon: "📬")]
        XCTAssertEqual(rank("mail", tabs: tabs).first { $0.group == .tab }?.spaceIcon, "📬")
    }
}
