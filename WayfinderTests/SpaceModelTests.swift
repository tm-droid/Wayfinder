//
//  SpaceModelTests.swift
//  WayfinderTests
//

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
}
