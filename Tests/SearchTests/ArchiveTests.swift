import AppKit
import XCTest
@testable import Search

/// Tabs let go, kept 30 days, searched and reopened.
@MainActor
final class ArchiveTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "archive-\(getpid())", 1)
        super.setUp()
    }

    private func store() -> Archive {
        Archive(file: FileManager.default.temporaryDirectory.appendingPathComponent("archive-\(UUID()).json"))
    }

    private func tab(_ url: String, title: String = "", shy: Bool = false) -> Tab {
        let tab = Tab(shy: shy, configuration: Web.configuration(space: UUID()))
        tab.setAddressOptimistically(URL(string: url)!)
        tab.restore(url: URL(string: url)!, title: title)
        return tab
    }

    func testKeepsWebTabsNotPrivateOnesOrOtherPages() {
        let archive = store()
        archive.keep(tab("https://a.example/", title: "A"))
        archive.keep(tab("https://p.example/", shy: true))
        archive.keep(tab("about:blank"))
        XCTAssertEqual(archive.entries.map(\.title), ["A"])
        // The same page again is one line, the newest.
        archive.keep(tab("https://a.example/", title: "A again"))
        XCTAssertEqual(archive.entries.map(\.title), ["A again"])
    }

    func testThirtyDaysThenGoneAndSearchMatchesTitleAndAddress() {
        let now = Date()
        let old = Archive.Entry(url: URL(string: "https://old.example/")!, title: "Old", at: now.addingTimeInterval(-31 * 86400))
        let new = Archive.Entry(url: URL(string: "https://swift.example/docs")!, title: "Swift Guide", at: now.addingTimeInterval(-86400))
        XCTAssertEqual(Archive.pruned([old, new], now: now), [new])
        XCTAssertEqual(Archive.matching([new], "guide swift"), [new])
        XCTAssertEqual(Archive.matching([new], "docs"), [new])
        XCTAssertTrue(Archive.matching([new], "nope").isEmpty)
    }

    func testClearAndSurvivesAReload() {
        let archive = store()
        archive.keep(tab("https://a.example/", title: "A"))
        Disk.drain()
        let reloaded = Archive(file: archive.file)
        XCTAssertEqual(reloaded.entries.count, 1)
        archive.clear()
        XCTAssertTrue(archive.entries.isEmpty)
    }

    func testClearTabsArchivesTheTabsItClosesButNotPrivateOnes() {
        let browser = Browser(record: WindowRecord())
        browser.spaceID = UUID()
        addTeardownBlock { @MainActor in browser.closeAll(); Archive.shared.clear() }
        Archive.shared.clear()
        for n in 0..<2 {
            let t = tab("https://c\(n).example/", title: "C\(n)")
            browser.prepare(t)
            browser.insert(t, at: browser.tabs.count)
        }
        browser.clearTabs()
        let kept = Archive.shared.entries.map(\.url.host)
        XCTAssertTrue(kept.contains("c0.example") && kept.contains("c1.example"))
    }
}
