import WebKit
import XCTest
@testable import Search

/// Boosts: which sites, what is kept, what comes in, and where scripts run.
@MainActor
final class BoostTests: XCTestCase {
    private func store() -> (Boosts, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("boosts-\(UUID().uuidString).json")
        return (Boosts(file: url), url)
    }

    func testMatchesHostAndSubdomainsOnLabelBoundary() {
        var b = Boost(name: "x", hosts: ["Example.com."])
        XCTAssertTrue(b.matches("example.com"))
        XCTAssertTrue(b.matches("WWW.Example.COM."))
        XCTAssertTrue(b.matches("a.b.example.com"))
        XCTAssertFalse(b.matches("evilexample.com"))
        XCTAssertFalse(b.matches("example.com.evil.org"))
        XCTAssertFalse(b.matches("example.co"))
        XCTAssertFalse(b.matches(nil))
        b.subdomains = false
        XCTAssertTrue(b.matches("example.com"))
        XCTAssertFalse(b.matches("a.example.com"))
    }

    func testStoreRoundTripAndOldFileTolerance() throws {
        let (boosts, url) = store()
        var b = Boost(name: "Mine", hosts: ["example.com"])
        b.css = "body{color:red}"
        b.js = "1"
        XCTAssertTrue(boosts.save(b))
        Disk.drain()
        let again = Boosts(file: url)
        XCTAssertEqual(again.all.count, 1)
        XCTAssertEqual(again.all.first?.js, "1")
        XCTAssertEqual(again.all.first?.css, b.css)

        // Old or hand-written: a bare array with only some keys.
        try Data(#"[{"name":"Old","hosts":["a.com"],"future":1},{"hosts":[]}]"#.utf8).write(to: url)
        let old = Boosts(file: url)
        XCTAssertEqual(old.all.map(\.name), ["Old"])
        XCTAssertTrue(old.all[0].enabled)
        try Data("garbage".utf8).write(to: url)
        XCTAssertTrue(Boosts(file: url).all.isEmpty)
    }

    func testImportStripsScriptUntilAllowedAndStartsOff() throws {
        let (source, _) = store()
        var b = Boost(name: "S", hosts: ["example.com"])
        b.js = "alert(1)"
        b.css = "a{}"
        source.save(b)
        let data = try XCTUnwrap(source.exportData())
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("alert(1)"), "export carries scripts")

        let found = Boosts.parseImport(data)
        XCTAssertEqual(found.count, 1)
        XCTAssertNil(found[0].boost.js)
        XCTAssertEqual(found[0].script, "alert(1)")
        XCTAssertFalse(found[0].boost.enabled)
        XCTAssertTrue(found[0].boost.imported)

        let (target, _) = store()
        let none = target.commitImport(found, allowing: [])
        XCTAssertNil(none[0].js)
        XCTAssertNil(target.all[0].js)
        XCTAssertEqual(target.injections(host: "example.com", shy: false).count, 0, "off until kept")

        let (other, _) = store()
        other.commitImport(found, allowing: [found[0].id])
        XCTAssertEqual(other.all[0].js, "alert(1)")
        XCTAssertFalse(other.all[0].enabled)
    }

    func testCaps() throws {
        let (boosts, _) = store()
        var b = Boost(name: "Big", hosts: ["example.com"])
        b.css = String(repeating: "a", count: Boosts.maxCSS + 1)
        XCTAssertFalse(boosts.save(b))
        let big = try JSONEncoder().encode([b])
        XCTAssertTrue(Boosts.parseImport(big).isEmpty)
        b.css = ""
        b.js = String(repeating: "a", count: Boosts.maxJS + 1)
        XCTAssertFalse(boosts.save(b))
        b.js = nil
        b.hosts = (0...Boosts.maxHosts).map { "h\($0).com" }
        XCTAssertFalse(boosts.save(b))
        b.hosts = ["*.com"]
        XCTAssertFalse(boosts.save(b))
        b.hosts = ["ok.com"]
        XCTAssertTrue(boosts.save(b))
    }

    func testPrivateTabsGetNothingUnlessAllowed() {
        let (boosts, _) = store()
        var b = Boost(name: "S", hosts: ["example.com"])
        b.css = "a{}"
        b.js = "1"
        boosts.save(b)
        XCTAssertEqual(boosts.injections(host: "example.com", shy: true, allowsPrivate: false).count, 0)
        XCTAssertEqual(boosts.injections(host: "example.com", shy: true, allowsPrivate: true).count, 2)
        XCTAssertEqual(boosts.injections(host: "example.com", shy: false).count, 2)
        XCTAssertEqual(boosts.injections(host: "other.com", shy: false).count, 0)
    }

    func testScriptWorldIsNeitherSearchsNorThePages() {
        let (boosts, _) = store()
        var b = Boost(name: "S", hosts: ["example.com"])
        b.css = "a{}"
        b.js = "1"
        boosts.save(b)
        let list = boosts.injections(host: "example.com", shy: false)
        let script = list.first { $0.isScript }
        XCTAssertNotNil(script)
        XCTAssertTrue(script?.world !== Web.world)
        XCTAssertTrue(script?.world !== WKContentWorld.page)
        XCTAssertTrue(list.first { !$0.isScript }?.world === Web.world)
    }

    func testTrialAppliesToOneTabOnly() {
        let (boosts, _) = store()
        var b = Boost(name: "S", hosts: ["example.com"])
        b.css = "a{}"
        b.enabled = false
        boosts.save(b)
        let tab = UUID()
        boosts.tryOn(b.id, tab: tab)
        XCTAssertEqual(boosts.injections(host: "example.com", tab: tab, shy: false).count, 1)
        XCTAssertEqual(boosts.injections(host: "example.com", tab: UUID(), shy: false).count, 0)
        boosts.keep(b.id)
        XCTAssertEqual(boosts.injections(host: "example.com", tab: UUID(), shy: false).count, 1)
    }
}
