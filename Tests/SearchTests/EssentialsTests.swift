import AppKit
import XCTest
@testable import Search

/// Essentials (the icon grid), folders inside folders, and a pin that has
/// wandered from its home. Files decode as they always did; windows agree.
@MainActor
final class EssentialsTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "essentials-\(getpid())", 1)
        super.setUp()
    }

    private func group(_ parent: UUID? = nil, collapsed: Bool = false) -> TabGroup {
        TabGroup(id: UUID(), name: "G", collapsed: collapsed, parent: parent)
    }

    /// A window in a space of its own: pins.json is shared by the whole run.
    private func window() -> Browser {
        let browser = Browser(record: WindowRecord())
        browser.spaceID = UUID()
        addTeardownBlock { @MainActor in browser.closeAll(); Pins.forget(browser.spaceID) }
        return browser
    }

    private func pin(_ browser: Browser, _ n: Int, listed: Bool = false) -> Tab {
        let url = URL(string: "https://e\(n).example/")!
        let tab = Tab(configuration: Web.configuration(space: browser.spaceID))
        tab.setAddressOptimistically(url)
        tab.pin = "E"
        tab.pinID = UUID()
        tab.home = url
        tab.listed = listed
        browser.prepare(tab)
        browser.insert(tab, at: browser.tabs.count)
        return tab
    }

    // MARK: files from before

    func testOldPinsFileDecodesWithSquaresAsEssentials() throws {
        let id = UUID()
        let json = """
        {"\(id.uuidString)":[{"id":"\(UUID().uuidString)","letter":"A","home":"https://a/","title":"A"},
        {"id":"\(UUID().uuidString)","letter":"B","home":"https://b/","title":"B","listed":true}]}
        """
        let defs = try XCTUnwrap(Pins.decode(Data(json.utf8))?.bySpace[id])
        XCTAssertTrue(defs[0].isEssential)
        XCTAssertNil(defs[0].group)
        XCTAssertFalse(defs[1].isEssential)
    }

    func testOldSessionGroupDecodesAtTheTopLevel() throws {
        let json = #"{"id":"\#(UUID().uuidString)","name":"Work"}"#
        let g = try JSONDecoder().decode(TabGroup.self, from: Data(json.utf8))
        XCTAssertNil(g.parent)
        XCTAssertFalse(g.collapsed)
    }

    func testNewFieldsSurviveARoundTripAndStayOutOfPlainPins() throws {
        let g = group(UUID())
        XCTAssertEqual(try JSONDecoder().decode(TabGroup.self, from: JSONEncoder().encode(g)), g)
        let plain = try JSONEncoder().encode(PinDef(id: UUID(), letter: "A", home: "h", title: "t", name: nil))
        let text = String(decoding: plain, as: UTF8.self)
        XCTAssertFalse(text.contains("essential") || text.contains("group"))
    }

    // MARK: essentials

    func testThirteenthEssentialIsRefused() {
        let browser = window()
        for n in 0..<Browser.essentialCap { _ = pin(browser, n) }
        let row = pin(browser, 99, listed: true)
        XCTAssertFalse(browser.canMakeEssential(row))
        XCTAssertFalse(browser.setEssential(row, true))
        XCTAssertTrue(row.listed)
        // Taking one out makes room.
        let first = browser.tabs.first { $0.pin != nil && !$0.listed }!
        XCTAssertTrue(browser.setEssential(first, false))
        XCTAssertTrue(browser.setEssential(row, true))
        XCTAssertFalse(row.listed)
    }

    func testTwoWindowsKeepOnePinWhenOneTogglesEssential() {
        let a = window(), b = window()
        b.spaceID = a.spaceID
        let tab = pin(a, 1)
        a.writeSession(now: true)
        XCTAssertEqual(b.tabs.filter { $0.pin != nil }.count, 1)
        a.setEssential(tab, false)
        let there = b.tabs.filter { $0.pin != nil }
        XCTAssertEqual(there.count, 1)
        XCTAssertTrue(there[0].listed)
        XCTAssertEqual(a.tabs.filter { $0.pin != nil }.count, 1)
        a.setEssential(tab, true)
        XCTAssertFalse(b.tabs.first { $0.pin != nil }!.listed)
    }

    // MARK: folders

    func testNestingStopsAtThreeLevels() {
        let one = group(), two = group(one.id), three = group(two.id), loose = group()
        let all = [one, two, three, loose]
        XCTAssertEqual(TabGroup.depth(of: three.id, in: all), 3)
        XCTAssertFalse(TabGroup.canNest(loose.id, under: three.id, in: all))
        XCTAssertTrue(TabGroup.canNest(loose.id, under: two.id, in: all))
        // A branch with a folder in it counts its own depth.
        XCTAssertFalse(TabGroup.canNest(one.id, under: loose.id, in: all + [group(loose.id)]))
        XCTAssertFalse(TabGroup.canNest(one.id, under: three.id, in: all))
        XCTAssertFalse(TabGroup.canNest(one.id, under: one.id, in: all))
    }

    func testDeletingAFolderMovesItsChildrenUp() {
        let top = group(), mid = group(top.id), leaf = group(mid.id)
        var pinned = PinDef(id: UUID(), letter: "A", home: "h", title: "t", name: nil)
        pinned.group = mid.id
        let out = TabGroup.removing(mid.id, from: [top, mid, leaf], pins: [pinned])
        XCTAssertEqual(out.groups.map(\.id), [top.id, leaf.id])
        XCTAssertEqual(out.groups[1].parent, top.id)
        XCTAssertEqual(out.pins[0].group, top.id)
    }

    func testFoldedParentHidesDescendants() {
        let top = group(collapsed: true), mid = group(top.id), leaf = group(mid.id)
        XCTAssertTrue(TabGroup.hidden(leaf.id, in: [top, mid, leaf]))
        XCTAssertFalse(TabGroup.hidden(top.id, in: [top, mid, leaf]))
    }

    func testAFolderHoldingOnlyAPinOrAFolderIsKept() {
        let top = group(), mid = group(top.id), empty = group()
        let kept = TabGroup.keeping([top, mid, empty], held: [mid.id])
        XCTAssertEqual(kept.map(\.id), [top.id, mid.id])
    }

    func testPinFolderAndRemovalOnABrowser() {
        let browser = window()
        let tab = pin(browser, 1)
        let top = group(), mid = group(top.id)
        browser.tabGroups = [top, mid]
        browser.setPinGroup(tab, mid.id)
        XCTAssertEqual(tab.pinGroup, mid.id)
        browser.removeTabGroup(mid.id)
        XCTAssertEqual(tab.pinGroup, top.id)
        XCTAssertEqual(browser.tabGroups.map(\.id), [top.id])
    }

    // MARK: drift

    func testDriftShowsPinTitleAndCurrentPageUntilBackHome() {
        let browser = window()
        let tab = pin(browser, 1)
        tab.name = "Mail"
        tab.restore(url: URL(string: "https://e1.example/")!, title: "Inbox", name: "Mail")
        XCTAssertNil(browser.drift(of: tab))
        tab.restore(url: URL(string: "https://e1.example/other")!, title: "Inbox", name: "Mail")
        XCTAssertEqual(browser.drift(of: tab), "Mail / Inbox")
        tab.restore(url: URL(string: "https://e1.example")!, title: "Inbox", name: "Mail")
        XCTAssertNil(browser.drift(of: tab))
    }
}
