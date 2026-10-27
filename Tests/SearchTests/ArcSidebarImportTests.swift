import AppKit
import XCTest
@testable import Search

/// Arc's sidebar into Wayfinder's: favourites as essentials, folders as
/// nested folders, pinned pages as pins in them, Today as tabs.
@MainActor
final class ArcSidebarImportTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "arcsidebar-\(getpid())", 1)
        super.setUp()
    }

    private func tab(_ id: String, _ url: String) -> [String: Any] {
        ["id": id, "title": id, "data": ["tab": ["savedURL": url, "savedTitle": id]]]
    }

    private func folder(_ id: String, _ kids: [String]) -> [String: Any] {
        ["id": id, "title": id, "data": ["list": [String: Any]()], "childrenIds": kids]
    }

    /// 14 favourites; pinned: a loose page, A { a1, B { b1, C { c1, D { d1 } } } };
    /// Today: two pages.
    private func fixture() throws -> ArcSidebar {
        let favourites = (0..<14).map { tab("fav\($0)", "https://fav\($0).example/") }
        let items: [[String: Any]] = favourites + [
            ["id": "favs", "childrenIds": (0..<14).map { "fav\($0)" }],
            ["id": "pins", "childrenIds": ["loose", "A"]],
            tab("loose", "https://loose.example/"),
            folder("A", ["a1", "B"]), tab("a1", "https://a1.example/"),
            folder("B", ["b1", "C"]), tab("b1", "https://b1.example/"),
            folder("C", ["c1", "D"]), tab("c1", "https://c1.example/"),
            folder("D", ["d1"]), tab("d1", "https://d1.example/"),
            ["id": "today", "childrenIds": ["t1", "t2"]],
            tab("t1", "https://today1.example/"), tab("t2", "https://today2.example/"),
        ]
        let main: [String: Any] = [
            "items": items,
            "spaces": [["title": "Work", "profile": ["default": [String: Any]()],
                        "newContainerIDs": ["pinned", "pins", "unpinned", "today"]]],
            "topAppsContainerIDs": [["default": [String: Any]()], "favs"],
        ]
        let data = try JSONSerialization.data(withJSONObject: ["sidebar": ["containers": [main]]])
        return try XCTUnwrap(Arc.parse(data, profile: nil))
    }

    func testEverythingComesInWhereWayfinderKeepsIt() throws {
        let browser = Browser(record: WindowRecord())
        browser.spaceID = UUID()
        let rows = browser.prefs.listsPins, spaces = browser.prefs.usesSpaces
        browser.prefs.listsPins = true
        browser.prefs.usesSpaces = false
        addTeardownBlock { @MainActor in
            browser.prefs.listsPins = rows
            browser.prefs.usesSpaces = spaces
            browser.closeAll()
            Pins.forget(browser.spaceID)
        }
        let sidebar = try fixture()
        XCTAssertEqual(sidebar.spaces[0].today.map(\.title), ["t1", "t2"])
        browser.takeArc(sidebar)

        let defs = Pins.defs(browser.spaceID)
        let favourites = defs.filter { $0.home.contains("fav") }
        XCTAssertEqual(favourites.filter(\.isEssential).count, Browser.essentialCap)
        XCTAssertEqual(favourites.filter(\.isListed).count, 2, "past the cap a favourite is a row")

        let named = { (name: String) in browser.tabGroups.first { $0.name == name } }
        let a = try XCTUnwrap(named("A")), b = try XCTUnwrap(named("B")), c = try XCTUnwrap(named("C"))
        XCTAssertNil(a.parent)
        XCTAssertEqual(b.parent, a.id)
        XCTAssertEqual(c.parent, b.id)
        XCTAssertNil(named("D"), "deeper than three is flattened into the third")
        let group = { (host: String) in defs.first { $0.home.contains(host) }?.group }
        XCTAssertNil(group("loose"))
        XCTAssertEqual(group("a1"), a.id)
        XCTAssertEqual(group("b1"), b.id)
        XCTAssertEqual(group("c1"), c.id)
        XCTAssertEqual(group("d1"), c.id)
        XCTAssertTrue(defs.first { $0.home.contains("loose") }?.isListed ?? false)
        XCTAssertTrue(defs.filter { !$0.home.contains("fav") }.allSatisfy(\.isListed))

        // The pins hold their folders in this window too.
        XCTAssertEqual(browser.tabs.first { $0.home?.host() == "b1.example" }?.pinGroup, b.id)

        // Today: tabs, asleep.
        let today = browser.tabs.filter { $0.pin == nil && ($0.pending ?? $0.address)?.host()?.hasPrefix("today") == true }
        XCTAssertEqual(today.count, 2)
        XCTAssertTrue(today.allSatisfy(\.asleep))

        // Nothing twice.
        let again = browser.takeArc(sidebar)
        XCTAssertEqual(again.pins, 0)
        XCTAssertEqual(again.tabs, 0)
        XCTAssertEqual(browser.tabGroups.count, 3)
    }
}
