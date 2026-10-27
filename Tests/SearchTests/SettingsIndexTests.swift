import XCTest
@testable import Search

/// Settings' rows (SettingsIndex): merged controls write the keys the two
/// switches did, new defaults reach only keys never touched, and an
/// explicit off on a switch that left Settings stays off.
@MainActor
final class SettingsIndexTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "settings-index-\(getpid())", 1)
        super.setUp()
    }

    private let touched = ["pins.list", "sidebar", "sidebar.position", "tabs.sleep", SleepPace.key, "float.leave", "float.away",
                           "pins.home", "pins.peek", "links.peek", "links.peekClick", "pages.120", "pages.120.mode",
                           "swipe.history", "tabs.address", "links.show", "float.flicks", "spaces", "pins.list",
                           "newtab.floating"]

    private func fresh(_ body: () -> Void) {
        let saved = touched.map { ($0, Store.settings.object(forKey: $0)) }
        defer { for (key, value) in saved { Store.settings.set(value, forKey: key) } }
        touched.forEach(Store.settings.removeObject(forKey:))
        body()
    }

    func testIdsAreUniqueAndEveryGroupIsReal() {
        XCTAssertEqual(Set(SettingsIndex.items.map(\.id)).count, SettingsIndex.items.count)
        for item in SettingsIndex.items {
            XCTAssertNotNil(SettingsIndex.group(item.group), item.id)
            XCTAssertLessThanOrEqual(item.detail.count, 90, item.id)
            if let parent = item.parent { XCTAssertNotNil(SettingsIndex.item(parent), item.id) }
        }
    }

    func testOldSectionNames() {
        XCTAssertEqual(SettingsPanel.Page.named("shortcuts"), .keyboard)
        XCTAssertEqual(SettingsPanel.Page.named("downloads"), .general)
        XCTAssertEqual(SettingsPanel.Page.named("privacy"), .privacy)
    }

    func testDefaultsForUntouchedKeys() {
        fresh {
            let prefs = Preferences()
            XCTAssertTrue(prefs.pinsKeepSite)
            XCTAssertTrue(prefs.listsPins)
            Store.settings.set(false, forKey: "pins.list")
            XCTAssertFalse(Preferences().listsPins, "a stored choice of squares is kept")
            Store.settings.removeObject(forKey: "pins.list")
            XCTAssertEqual(prefs.fastPages, .onPower)
            XCTAssertTrue(prefs.holdsHistory)
            XCTAssertTrue(prefs.showsAddress)
            XCTAssertEqual(prefs.sleepChoice, .normal)
            XCTAssertEqual(prefs.floatOwn, .tabs)
            XCTAssertEqual(prefs.peekChoice, .shift)
            // Nothing written just for reading them.
            for key in ["pins.list", "pins.home", "pins.peek", "pages.120.mode", "swipe.history", "tabs.address"] {
                XCTAssertNil(Store.settings.object(forKey: key), key)
            }
        }
    }

    func testExplicitChoicesStand() {
        fresh {
            Store.settings.set(false, forKey: "pages.120")
            Store.settings.set(false, forKey: "swipe.history")
            Store.settings.set(false, forKey: "tabs.address")
            Store.settings.set(false, forKey: "links.show")
            Store.settings.set(false, forKey: "float.flicks")
            Store.settings.set(false, forKey: "pins.home")
            let prefs = Preferences()
            XCTAssertEqual(prefs.fastPages, .never)
            XCTAssertFalse(prefs.holdsHistory)
            XCTAssertFalse(prefs.showsAddress)
            XCTAssertFalse(prefs.showsLinks)
            XCTAssertFalse(prefs.floatFlicks)
            XCTAssertFalse(prefs.pinsKeepSite, "one off, the other never set: off")
            Store.settings.set(true, forKey: "pins.peek")
            XCTAssertTrue(Preferences().pinsKeepSite, "either on: on")
            Store.settings.set(true, forKey: "pages.120")
            XCTAssertEqual(Preferences().fastPages, .always)
        }
    }

    func testMergedControlsWriteTheOldKeys() {
        fresh {
            let prefs = Preferences()
            prefs.tabsLayout = .right
            XCTAssertEqual(Store.settings.object(forKey: "sidebar") as? Bool, true)
            XCTAssertEqual(Store.settings.string(forKey: "sidebar.position"), "right")
            prefs.tabsLayout = .top
            XCTAssertEqual(Store.settings.object(forKey: "sidebar") as? Bool, false)
            prefs.sleepChoice = .never
            XCTAssertEqual(Store.settings.object(forKey: "tabs.sleep") as? Bool, false)
            prefs.sleepChoice = .sooner
            XCTAssertEqual(Store.settings.object(forKey: "tabs.sleep") as? Bool, true)
            XCTAssertEqual(Store.settings.string(forKey: SleepPace.key), "sooner")
            prefs.floatOwn = .tabsOrApps
            XCTAssertEqual(Store.settings.object(forKey: "float.leave") as? Bool, true)
            XCTAssertEqual(Store.settings.object(forKey: "float.away") as? Bool, true)
            prefs.floatOwn = .never
            XCTAssertEqual(Store.settings.object(forKey: "float.leave") as? Bool, false)
            XCTAssertEqual(Store.settings.object(forKey: "float.away") as? Bool, false)
            prefs.pinsKeepSite = false
            XCTAssertEqual(Store.settings.object(forKey: "pins.home") as? Bool, false)
            XCTAssertEqual(Store.settings.object(forKey: "pins.peek") as? Bool, false)
            prefs.peekChoice = .off
            XCTAssertEqual(Store.settings.object(forKey: "links.peek") as? Bool, false)
            prefs.peekChoice = .optionCommand
            XCTAssertEqual(Store.settings.object(forKey: "links.peek") as? Bool, true)
            XCTAssertEqual(Store.settings.string(forKey: "links.peekClick"), "optionCommand")
        }
    }

    func testSetUpLikeArcAndUndo() {
        fresh {
            let prefs = Preferences()
            XCTAssertTrue(prefs.listsPins, "pinned rows are on by default")
            prefs.pinsKeepSite = false
            prefs.listsPins = false
            let before = prefs.arcSnapshot
            XCTAssertFalse(prefs.looksLikeArc)
            XCTAssertEqual(prefs.setUpLikeArc().count, 5)
            XCTAssertTrue(prefs.looksLikeArc)
            prefs.restore(before)
            XCTAssertEqual(prefs.tabsLayout, before.layout)
            XCTAssertFalse(prefs.usesSpaces || prefs.listsPins || prefs.pinsKeepSite || prefs.floatingNewTab)
        }
    }

    func testFindByWords() {
        XCTAssertTrue(SettingsIndex.find("vertical tabs").contains { $0.id == "tabs.layout" })
        XCTAssertTrue(SettingsIndex.find("pip").contains { $0.id == "float.own" })
        XCTAssertTrue(SettingsIndex.find("autoplay").contains { $0.id == "media.click" })
        XCTAssertTrue(SettingsIndex.find("spelling").contains { $0.id == "autocorrect" })
        XCTAssertTrue(SettingsIndex.find("split").contains { $0.id == "note.split" })
        XCTAssertTrue(SettingsIndex.find("").isEmpty)
        XCTAssertTrue(SettingsIndex.find("zzzz nothing").isEmpty)
    }
}
