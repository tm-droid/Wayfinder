import XCTest
@testable import Search

final class CommandRankerTests: XCTestCase {
    private typealias C = CommandCandidate<String>

    private func rank(_ query: String, _ candidates: [C], limit: Int = CommandRanker.maxResults) -> [String] {
        CommandRanker.rank(query: query, candidates: candidates, now: Date(timeIntervalSince1970: 1_000_000), limit: limit).map(\.candidate.id)
    }

    private func page(_ id: String, _ title: String, _ url: String, _ kind: CommandKind = .history, used: Date? = nil) -> C {
        C(id: id, title: title, url: url, kind: kind, lastUsed: used)
    }

    private let actions = [
        C(id: "newSpace", title: "New Space", kind: .action),
        C(id: "pin", title: "Pin Current Tab", kind: .action),
        C(id: "toggleSidebar", title: "Toggle Sidebar", kind: .action, keywords: ["hide sidebar"]),
    ]

    func testFuzzyScoringOrder() throws {
        let prefix = try XCTUnwrap(CommandRanker.score("git", in: "GitHub"))
        let wordStart = try XCTUnwrap(CommandRanker.score("git", in: "My GitHub"))
        let inside = try XCTUnwrap(CommandRanker.score("git", in: "Digit"))
        let scattered = try XCTUnwrap(CommandRanker.score("ghb", in: "GitHub"))
        XCTAssertGreaterThan(prefix, wordStart)
        XCTAssertGreaterThan(wordStart, inside)
        XCTAssertGreaterThan(inside, scattered)
        XCTAssertNil(CommandRanker.score("xyz", in: "GitHub"))
        XCTAssertNotNil(CommandRanker.score("GH", in: "github"))
    }

    func testHostMatchBeatsPathMatch() {
        let result = rank("apple", [page("path", "Docs", "https://example.com/apple"), page("host", "Docs", "https://apple.com/docs")])
        XCTAssertEqual(result.first, "host")
    }

    func testDedupePrefersTabOverBookmarkOverHistory() {
        let candidates = [
            page("tab", "Example", "https://example.com/", .openTab),
            page("bm", "Example", "https://www.example.com", .bookmark),
            page("bm2", "Other Example", "https://example.com/other", .bookmark),
            page("h", "Example", "http://example.com"),
            page("h2", "Other Example", "https://example.com/other"),
            page("h3", "Example 3", "https://example.com/three"),
        ]
        XCTAssertEqual(Set(rank("example", candidates)), ["tab", "bm2", "h3"])
    }

    func testTwoTabsOnOneURLBothStay() {
        let tabs = [page("a", "Mail", "https://mail.example.com", .openTab), page("b", "Mail", "https://mail.example.com", .openTab)]
        XCTAssertEqual(rank("mail", tabs).count, 2)
    }

    func testKindBonusAndRecency() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(rank("site", [page("h", "Site", "https://a.com"), page("t", "Site", "https://b.com", .openTab)]).first, "t")
        let fresh = page("new", "Site", "https://a.com", used: now)
        let stale = page("old", "Site", "https://b.com", used: now.addingTimeInterval(-90 * 86_400))
        XCTAssertEqual(rank("site", [stale, fresh]), ["new", "old"])
    }

    func testEqualScoresKeepInputOrder() {
        XCTAssertEqual(rank("site", [page("1", "Site", "https://a.com"), page("2", "Site", "https://b.com")]), ["1", "2"])
    }

    func testLimit() {
        let many = (0..<20).map { page("\($0)", "Site \($0)", "https://site\($0).com") }
        XCTAssertEqual(rank("site", many).count, CommandRanker.maxResults)
        XCTAssertEqual(rank("site", many, limit: 3).count, 3)
    }

    func testActionMatchingAndKeywords() {
        XCTAssertEqual(rank("new sp", actions).first, "newSpace")
        XCTAssertEqual(rank("hide", actions), ["toggleSidebar"])
    }

    func testGreaterThanPrefixIsActionsOnly() {
        let mixed = actions + [page("t", "New tab page", "https://new.example.com", .openTab)]
        XCTAssertEqual(Set(rank("new", mixed)), ["newSpace", "t"])
        XCTAssertEqual(rank(">new", mixed), ["newSpace"])
        XCTAssertEqual(rank("> new", mixed), ["newSpace"])
        XCTAssertEqual(rank(">", mixed), ["newSpace", "pin", "toggleSidebar"])
    }

    func testEmptyQueryShowsPagesNotActions() {
        XCTAssertEqual(rank("", actions + [page("h", "Site", "https://a.com")]), ["h"])
    }
}
