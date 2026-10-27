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
        browser.writeSession(now: true)
        return tab
    }

    /// A web tab that is not a pin yet, with an address to pin.
    private func plain(_ browser: Browser, _ n: Int) -> Tab {
        let tab = Tab(configuration: Web.configuration(space: browser.spaceID))
        tab.setAddressOptimistically(URL(string: "https://p\(n).example/")!)
        browser.prepare(tab)
        browser.insert(tab, at: browser.tabs.count)
        return tab
    }

    /// Pinned rows on, for what the sidebar shows of them.
    private func rowsOn(_ browser: Browser) {
        let was = (browser.prefs.listsPins, browser.prefs.sidebar)
        (browser.prefs.listsPins, browser.prefs.sidebar) = (true, true)
        addTeardownBlock { @MainActor in (browser.prefs.listsPins, browser.prefs.sidebar) = was }
    }

    private func full(_ browser: Browser) {
        for n in 0..<Browser.essentialCap { _ = pin(browser, n) }
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

    func testEveryWayOfMakingASquareStopsAtTheCap() {
        let browser = window()
        full(browser)
        XCTAssertEqual(browser.essentialCount, Browser.essentialCap)
        // pin(): a row, never a refusal.
        let a = plain(browser, 1)
        browser.pin(a)
        XCTAssertNotNil(a.pin)
        XCTAssertTrue(a.listed)
        // Drag onto the squares.
        let b = plain(browser, 2)
        XCTAssertTrue(browser.pinDropped(b, listed: false, at: 0))
        XCTAssertTrue(b.listed)
        // setListed(false) on a row stays a row.
        browser.setListed(a, false)
        XCTAssertTrue(a.listed)
        XCTAssertEqual(browser.essentialCount, Browser.essentialCap)
    }

    func testCountComesFromSavedPinsNotThisWindowsTabs() {
        let a = window(), b = window()
        b.spaceID = a.spaceID
        full(a)
        // b holds no tabs for them yet still sees the cap.
        XCTAssertEqual(b.essentialCount, Browser.essentialCap)
        let late = plain(b, 7)
        b.pin(late)
        XCTAssertTrue(late.listed)
        // Shared pins count whether or not they show.
        let was = b.prefs.sharesPins
        b.prefs.sharesPins = false
        addTeardownBlock { @MainActor in b.prefs.sharesPins = was }
        XCTAssertEqual(b.essentialCount, Browser.essentialCap)
    }

    func testSharingAnEssentialIntoAFullSpaceMakesItARow() {
        let browser = window()
        let other = Space(id: UUID(), name: "Other", colour: 0, icon: "", sharesSignIns: true)
        Spaces.write(Spaces.read() + [other])
        addTeardownBlock { Spaces.write(Spaces.read().filter { $0.id != other.id }); Pins.forget(other.id) }
        Pins.set(other.id, (0..<Browser.essentialCap).map { PinDef(id: UUID(), letter: "O", home: "https://o\($0)/", title: "o") }, from: browser)
        let tab = pin(browser, 1)
        let was = (browser.prefs.sharesPins, browser.prefs.usesSpaces)
        (browser.prefs.sharesPins, browser.prefs.usesSpaces) = (true, true)
        addTeardownBlock { @MainActor in (browser.prefs.sharesPins, browser.prefs.usesSpaces) = was }
        browser.shareEverywhere(tab)
        XCTAssertTrue(tab.listed)
        Pins.setShared([], from: browser)
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

    func testRestoredPinKeepsNoFolderThatIsGone() {
        let browser = window()
        _ = pin(browser, 1)
        var def = Pins.defs(browser.spaceID)[0]
        def.group = UUID()
        Pins.set(browser.spaceID, [def], from: browser)
        browser.pinsChanged(in: browser.spaceID)
        XCTAssertNil(browser.tabs.first { $0.pinID == def.id }?.pinGroup)
    }

    func testRemovingAFolderRewritesSavedPins() {
        let browser = window()
        let tab = pin(browser, 1)
        let top = group(), mid = group(top.id)
        browser.tabGroups = [top, mid]
        browser.setPinGroup(tab, mid.id)
        XCTAssertEqual(Pins.defs(browser.spaceID).first?.group, mid.id)
        browser.removeTabGroup(mid.id)
        XCTAssertEqual(Pins.defs(browser.spaceID).first?.group, top.id)
    }

    func testUnpinRemovesItsNowEmptyFolder() {
        let browser = window()
        let tab = pin(browser, 1)
        let top = group(), mid = group(top.id)
        browser.tabGroups = [top, mid]
        browser.setPinGroup(tab, mid.id)
        browser.unpin(tab)
        XCTAssertTrue(browser.tabGroups.isEmpty)
    }

    func testBadParentsAreDroppedOnLoad() {
        let one = group(), two = group(one.id), three = group(two.id), four = group(three.id)
        var lost = group(UUID()), loopA = group(), loopB = group()
        loopA.parent = loopB.id
        loopB.parent = loopA.id
        lost.parent = UUID()
        let out = TabGroup.sane([one, two, three, four, lost, loopA, loopB])
        XCTAssertEqual(out.map(\.parent), [nil, one.id, two.id, nil, nil, nil, nil])
    }

    func testPinDefHasOneRepresentationOfRow() throws {
        let viaEssential = PinDef(id: UUID(), letter: "A", home: "h", title: "t", essential: false)
        var viaListed = viaEssential
        viaListed.listed = true
        XCTAssertEqual(viaEssential, viaListed)
        let old = #"{"id":"\#(UUID().uuidString)","letter":"A","home":"h","title":"t","essential":false}"#
        let def = try JSONDecoder().decode(PinDef.self, from: Data(old.utf8))
        XCTAssertTrue(def.isListed)
        XCTAssertEqual(def.listed, true)
        XCTAssertNil(def.essential)
    }

    // MARK: folders in the sidebar

    func testFolderRowsNestByDepthAndFoldedHidesDescendants() {
        let browser = window()
        rowsOn(browser)
        let tab = pin(browser, 1, listed: true)
        var top = group(), mid = group(top.id)
        let other = group()
        browser.tabGroups = [top, mid, other]
        browser.setPinGroup(tab, mid.id)
        var rows = browser.folderRows(tabsOn: false, pinsOn: true)
        XCTAssertEqual(rows.map(\.group.id), [top.id, mid.id])
        XCTAssertEqual(rows.map(\.depth), [1, 2])
        // The empty folder shows only where groups are on.
        XCTAssertEqual(browser.folderRows(tabsOn: true, pinsOn: true).map(\.group.id), [top.id, mid.id, other.id])
        top.collapsed = true
        browser.tabGroups = [top, mid, other]
        rows = browser.folderRows(tabsOn: false, pinsOn: true)
        XCTAssertEqual(rows.map(\.group.id), [top.id])
        mid.collapsed = false
        XCTAssertEqual(browser.folderPins(mid.id).map(\.id), [tab.id])
        XCTAssertTrue(browser.rowPins.isEmpty)
    }

    func testDroppingOnAFolderPinsAsARowThereAndOutOfItAMovesItUp() {
        let browser = window()
        let folder = group()
        browser.tabGroups = [folder]
        let loose = plain(browser, 1)
        XCTAssertTrue(browser.pinDropped(loose, into: folder.id))
        XCTAssertTrue(loose.listed)
        XCTAssertEqual(loose.pinGroup, folder.id)
        XCTAssertEqual(Pins.defs(browser.spaceID).first?.group, folder.id)
        // Dropped among the rows: out of the folder, which goes with its last pin.
        XCTAssertTrue(browser.pinDropped(loose, listed: true, at: 0))
        XCTAssertNil(loose.pinGroup)
        XCTAssertTrue(browser.tabGroups.isEmpty)
        // An essential dropped on a folder becomes a row in it.
        let square = pin(browser, 2)
        let again = group()
        browser.tabGroups = [again]
        XCTAssertTrue(browser.pinDropped(square, into: again.id))
        XCTAssertTrue(square.listed)
        XCTAssertEqual(square.pinGroup, again.id)
    }

    func testPinnedRowSlotIgnoresRowsInFolders() {
        let browser = window()
        rowsOn(browser)
        let folder = group()
        browser.tabGroups = [folder]
        let inside = pin(browser, 1, listed: true)
        let first = pin(browser, 2, listed: true), second = pin(browser, 3, listed: true)
        browser.setPinGroup(inside, folder.id)
        let drop = plain(browser, 4)
        XCTAssertTrue(browser.pinDropped(drop, listed: true, at: 1))
        let order = browser.rowPins.map(\.id)
        XCTAssertEqual(order, [first.id, drop.id, second.id])
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
