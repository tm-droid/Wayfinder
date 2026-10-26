//
//  SpaceModelTests.swift
//  WayfinderTests
//

import WebKit
import XCTest
@testable import Wayfinder

final class SpaceModelTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = UUID().uuidString
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeStore() -> SpaceStore {
        SpaceStore(file: JSONFile(url: directory.appending(path: "Spaces.json")), defaults: defaults)
    }

    private func addTab(_ store: SpaceStore, _ spaceID: Space.ID, _ url: String = "https://example.com") -> TabRecord.ID {
        let record = TabRecord(spaceID: spaceID, url: URL(string: url), kind: .today)
        store.addRecord(record)
        return record.id
    }

    func testMigratesSavedTabsIntoDefaultStoreSpace() {
        defaults.set(["https://apple.com", "https://webkit.org"], forKey: PreferenceKey.savedTabs)
        let store = makeStore()

        XCTAssertEqual(store.spaces.count, 1)
        XCTAssertEqual(store.spaces[0].name, "Personal")
        XCTAssertTrue(store.spaces[0].usesDefaultDataStore)
        XCTAssertEqual(store.records.map(\.kind), [.today, .today])
        XCTAssertEqual(store.records.compactMap(\.url?.absoluteString), ["https://apple.com", "https://webkit.org"])
        XCTAssertNil(defaults.object(forKey: PreferenceKey.savedTabs))

        // The migration is written, so a second launch loads the file and does not import again.
        defaults.set(["https://example.com"], forKey: PreferenceKey.savedTabs)
        XCTAssertEqual(makeStore().records.count, 2)
    }

    func testStorePersistsAcrossLaunches() {
        let store = makeStore()
        let space = store.addSpace(name: "Work")
        let id = addTab(store, space.id)
        store.pin(id)
        store.flush()

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.spaces.map(\.name), ["Personal", "Work"])
        XCTAssertEqual(reloaded.record(id)?.kind, .pinned)
    }

    func testEssentialsCapIsPerSpace() {
        let store = makeStore()
        let personal = store.spaces[0].id
        let work = store.addSpace(name: "Work").id
        for _ in 0..<SpaceStore.essentialsLimit {
            XCTAssertTrue(store.makeEssential(addTab(store, personal)))
        }
        let extra = addTab(store, personal)
        XCTAssertFalse(store.makeEssential(extra))
        XCTAssertEqual(store.record(extra)?.kind, .today)
        XCTAssertTrue(store.makeEssential(addTab(store, work)))
    }

    func testPinAndUnpin() {
        let store = makeStore()
        let id = addTab(store, store.spaces[0].id, "https://apple.com")
        store.pin(id)
        XCTAssertEqual(store.record(id)?.kind, .pinned)
        XCTAssertEqual(store.record(id)?.savedURL?.absoluteString, "https://apple.com")

        store.update(id, url: URL(string: "https://apple.com/mac"), title: "Mac")
        store.resetToSavedURL(id)
        XCTAssertEqual(store.record(id)?.url?.absoluteString, "https://apple.com")

        store.unpin(id)
        XCTAssertEqual(store.record(id)?.kind, .today)
        XCTAssertNil(store.record(id)?.savedURL)
    }

    func testFolderMoveAndDelete() {
        let store = makeStore()
        let spaceID = store.spaces[0].id
        let other = store.addSpace(name: "Other").id
        let outer = store.addFolder(name: "Outer", in: spaceID)
        let inner = store.addFolder(name: "Inner", in: spaceID, parentID: outer.id)
        let id = addTab(store, spaceID)

        XCTAssertFalse(store.moveRecord(id, toFolder: store.addFolder(name: "Elsewhere", in: other).id))
        XCTAssertTrue(store.moveRecord(id, toFolder: inner.id))
        XCTAssertEqual(store.record(id)?.kind, .pinned)
        XCTAssertEqual(store.record(id)?.folderID, inner.id)

        // Deleting the middle of a nest keeps the inner folder and its tabs.
        store.removeFolder(outer.id)
        XCTAssertNil(store.folders.first { $0.id == inner.id }?.parentID)
        XCTAssertEqual(store.record(id)?.folderID, inner.id)

        store.removeFolder(inner.id)
        XCTAssertNil(store.record(id)?.folderID)
        XCTAssertEqual(store.record(id)?.kind, .pinned)
    }

    func testReorderWithinSection() {
        let store = makeStore()
        let spaceID = store.spaces[0].id
        let a = addTab(store, spaceID)
        let pinned = addTab(store, spaceID)
        let b = addTab(store, spaceID)
        let c = addTab(store, spaceID)
        store.pin(pinned)

        store.moveRecords([a, b, c], fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(store.records(in: spaceID, kind: .today).map(\.id), [c, a, b])
        XCTAssertEqual(store.records(in: spaceID, kind: .pinned).map(\.id), [pinned])
    }

    func testRemoveSpaceKeepsLastOne() {
        let store = makeStore()
        XCTAssertFalse(store.removeSpace(store.spaces[0].id))
        let work = store.addSpace(name: "Work")
        let id = addTab(store, work.id)
        XCTAssertTrue(store.removeSpace(work.id))
        XCTAssertNil(store.record(id))
    }

    func testSwitchingSpaceRestoresSelection() {
        let store = makeStore()
        let model = BrowserWindowModel(store: store, restoresSession: false)
        let personal = model.selectedSpaceID
        let first = model.selectedTabID
        let second = model.newTab(url: nil)
        XCTAssertEqual(model.selectedTabID, second.id)
        model.select(model.tabs.first { $0.id == first }!)
        model.select(second)

        let work = model.addSpace(name: "Work")
        XCTAssertEqual(model.selectedSpaceID, work.id)
        XCTAssertEqual(model.tabs.count, 1)
        let workTab = model.selectedTabID

        model.selectSpace(personal)
        XCTAssertEqual(model.tabs.count, 2)
        XCTAssertEqual(model.selectedTabID, second.id)

        model.selectSpace(work.id)
        XCTAssertEqual(model.selectedTabID, workTab)
    }

    func testSelectByNumberStaysInCurrentSpace() {
        let store = makeStore()
        let model = BrowserWindowModel(store: store, restoresSession: false)
        model.newTab()
        let work = model.addSpace(name: "Work")
        model.selectTab(number: 1)
        XCTAssertEqual(store.record(model.selectedTabID!)?.spaceID, work.id)
        model.selectSpace(store.spaces[0].id)
        model.selectTab(number: 9)
        XCTAssertEqual(model.selectedTabID, model.tabs.last?.id)
    }

    func testClosingPinnedTabKeepsRecord() {
        let store = makeStore()
        let model = BrowserWindowModel(store: store, restoresSession: false)
        let tab = model.newTab()
        model.pin(tab)
        model.newTab()
        model.close(tab)
        XCTAssertNotNil(store.record(tab.id))
        XCTAssertFalse(model.tabs.contains { $0.id == tab.id })
        XCTAssertTrue(model.visibleRecords.contains { $0.id == tab.id })
    }

    func testCorruptFileIsMovedAsideNotOverwritten() throws {
        let url = directory.appending(path: "Spaces.json")
        try Data("not json".utf8).write(to: url)
        defaults.set(["https://stale.example"], forKey: PreferenceKey.savedTabs)

        let store = makeStore()
        XCTAssertEqual(store.spaces.count, 1)
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertNotNil(defaults.object(forKey: PreferenceKey.savedTabs))
        let kept = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix("Spaces.corrupt-") }
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(try Data(contentsOf: directory.appending(path: kept[0])), Data("not json".utf8))
    }

    func testMigrationKeyKeptWhenWriteFails() throws {
        defaults.set(["https://apple.com"], forKey: PreferenceKey.savedTabs)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }

        _ = makeStore()
        XCTAssertNotNil(defaults.object(forKey: PreferenceKey.savedTabs))
    }

    func testPopupFromOtherSpaceStaysThereUnselected() {
        let store = makeStore()
        let model = BrowserWindowModel(store: store, restoresSession: false)
        let anchor = model.selectedTab!
        let personal = model.selectedSpaceID
        let work = model.addSpace(name: "Work")
        let selected = model.selectedTabID

        let popup = model.openPopup(configuration: WKWebViewConfiguration(), after: anchor)
        XCTAssertEqual(store.record(popup!.id)?.spaceID, personal)
        XCTAssertEqual(model.selectedSpaceID, work.id)
        XCTAssertEqual(model.selectedTabID, selected)
    }

    func testTabOpenedFromAnchorUsesAnchorSpace() {
        let store = makeStore()
        let model = BrowserWindowModel(store: store, restoresSession: false)
        let anchor = model.selectedTab!
        let personal = model.selectedSpaceID
        let work = model.addSpace(name: "Work")
        let selected = model.selectedTabID

        model.openTab(with: URL(string: "https://example.com")!, after: anchor, select: true)
        model.duplicate(anchor)
        let added = store.records(in: personal).filter { $0.id != anchor.id }
        XCTAssertEqual(added.count, 2)
        XCTAssertEqual(store.records(in: work.id).count, 1)
        XCTAssertEqual(model.selectedTabID, selected)
    }

    func testRecordIsLoadedInOnlyOneWindow() {
        let store = makeStore()
        let first = BrowserWindowModel(store: store, restoresSession: false)
        let tab = first.selectedTab!
        first.pin(tab)
        let second = BrowserWindowModel(store: store, restoresSession: false)
        first.newTab()

        second.activate(store.record(tab.id)!)
        XCTAssertNil(second.tab(for: store.record(tab.id)!))
        XCTAssertEqual(first.selectedTabID, tab.id)
    }

    func testClosingLastPinnedTabCreatesNoTodayTab() {
        let store = makeStore()
        let model = BrowserWindowModel(store: store, restoresSession: false)
        let tab = model.selectedTab!
        model.pin(tab)
        model.close(tab)
        XCTAssertNil(model.selectedTabID)
        XCTAssertTrue(model.tabs.isEmpty)
        XCTAssertTrue(store.records(in: model.selectedSpaceID, kind: .today).isEmpty)
        XCTAssertNotNil(store.record(tab.id))
    }
}

final class SidebarModelTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = UUID().uuidString
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeStore() -> SpaceStore {
        SpaceStore(file: JSONFile(url: directory.appending(path: "Spaces.json")), defaults: defaults)
    }

    private func add(_ store: SpaceStore, _ spaceID: Space.ID, _ url: String) -> TabRecord.ID {
        let record = TabRecord(spaceID: spaceID, url: URL(string: url), kind: .today)
        store.addRecord(record)
        return record.id
    }

    func testPlaceChangesKindAndFolder() {
        let store = makeStore()
        let space = store.spaces[0].id
        let a = add(store, space, "https://a.com")
        let folder = store.addFolder(name: "F", in: space)
        XCTAssertTrue(store.place(a, kind: .pinned, folderID: folder.id))
        XCTAssertEqual(store.record(a)?.kind, .pinned)
        XCTAssertEqual(store.record(a)?.folderID, folder.id)
        XCTAssertEqual(store.record(a)?.savedURL, URL(string: "https://a.com"))
        XCTAssertTrue(store.place(a, kind: .essential))
        XCTAssertNil(store.record(a)?.folderID)
        XCTAssertTrue(store.place(a, kind: .pinned))
        XCTAssertEqual(store.record(a)?.kind, .pinned)
        XCTAssertTrue(store.place(a, kind: .today))
        XCTAssertEqual(store.record(a)?.kind, .today)
        XCTAssertNil(store.record(a)?.savedURL)
    }

    func testPlaceOrdersBeforeAnchor() {
        let store = makeStore()
        let space = store.spaces[0].id
        let a = add(store, space, "https://a.com")
        let b = add(store, space, "https://b.com")
        let c = add(store, space, "https://c.com")
        XCTAssertTrue(store.place(c, kind: .today, before: a))
        XCTAssertEqual(store.records(in: space, kind: .today).map(\.id), [c, a, b])
        XCTAssertTrue(store.place(c, kind: .today))
        XCTAssertEqual(store.records(in: space, kind: .today).map(\.id), [a, b, c])
    }

    func testPlaceRespectsEssentialsCapAndFolderSpace() {
        let store = makeStore()
        let space = store.spaces[0].id
        for i in 0..<SpaceStore.essentialsLimit {
            XCTAssertTrue(store.place(add(store, space, "https://e\(i).com"), kind: .essential))
        }
        let extra = add(store, space, "https://x.com")
        XCTAssertFalse(store.place(extra, kind: .essential))
        XCTAssertEqual(store.record(extra)?.kind, .today)
        let other = store.addSpace(name: "Other")
        let foreign = store.addFolder(name: "F", in: other.id)
        XCTAssertFalse(store.place(extra, kind: .pinned, folderID: foreign.id))
        XCTAssertEqual(store.record(extra)?.kind, .today)
    }

    func testUpdateSpace() {
        let store = makeStore()
        let id = store.spaces[0].id
        store.updateSpace(id, name: "Home", icon: "🏠", color: .green)
        XCTAssertEqual(store.space(id)?.name, "Home")
        XCTAssertEqual(store.space(id)?.icon, "🏠")
        XCTAssertEqual(store.space(id)?.color, .green)
    }

    func testSpaceSwitchingWrapsAndSelectsByNumber() {
        let store = makeStore()
        let model = BrowserWindowModel(store: store, restoresSession: false)
        let first = model.selectedSpaceID
        let second = model.addSpace(name: "B").id
        let third = model.addSpace(name: "C").id
        model.selectAdjacentSpace(offset: 1)
        XCTAssertEqual(model.selectedSpaceID, first)
        model.selectAdjacentSpace(offset: -1)
        XCTAssertEqual(model.selectedSpaceID, third)
        model.selectSpace(number: 2)
        XCTAssertEqual(model.selectedSpaceID, second)
        model.selectSpace(number: 9)
        XCTAssertEqual(model.selectedSpaceID, second)
    }

    func testClearTodayKeepsPinnedAndLeavesATab() {
        let store = makeStore()
        let model = BrowserWindowModel(store: store, restoresSession: false)
        let pinned = model.newTab()
        model.pin(pinned)
        model.newTab()
        model.newTab()
        model.clearTodayTabs()
        XCTAssertTrue(model.tabs.contains { $0.id == pinned.id })
        XCTAssertEqual(model.todayTabs.count, 0)
        model.pin(pinned)
        model.unpin(pinned)
        model.clearTodayTabs()
        XCTAssertEqual(model.tabs.count, 1)
    }

    func testMoveToSpace() {
        let store = makeStore()
        let model = BrowserWindowModel(store: store, restoresSession: false)
        let home = model.selectedSpaceID
        let work = store.addSpace(name: "Work").id
        let tab = model.newTab()
        model.moveToSpace(tab, work)
        XCTAssertNil(store.record(tab.id))
        XCTAssertEqual(store.records(in: work, kind: .today).count, 1)
        XCTAssertEqual(model.selectedSpaceID, home)
    }
}
