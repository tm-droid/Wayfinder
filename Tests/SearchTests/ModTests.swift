import XCTest
@testable import Search

final class ModTests: XCTestCase {
    private func load(_ json: String) -> Result<Mod, Mod.LoadFailure> { Mod.load(Data(json.utf8)) }

    private func errors(_ json: String) -> [ModError] {
        if case .failure(.invalid(let e)) = load(json) { return e }
        return []
    }

    func testGoodManifestLoads() throws {
        let json = #"{"id":"com.example.calm","name":"Calm","author":"Me","version":"1.2","look":{"grain":0.2},"flags":{"hoverOnlyClose":true,"dimUnloadedTabs":0.4},"css":"body{color:red}"}"#
        let mod = try load(json).get()
        XCTAssertEqual(mod.look?.grain, 0.2)
        XCTAssertEqual(mod.flags?.dimUnloadedTabs, 0.4)
        XCTAssertEqual(try JSONDecoder().decode(Mod.self, from: JSONEncoder().encode(mod)), mod)
    }

    func testIDs() {
        for good in ["com.example.calm", "app.wayfinder.mods.hover-close", "a.b", "org.x9.y-z"] {
            XCTAssertTrue(Mod.isValidID(good), good)
        }
        for bad in ["", "calm", "Com.Example", "com..example", ".com.x", "com.x.", "com.-x", "com.x-", "com.exa mple", "com.exämple", "a.", String(repeating: "a.", count: 60) + "b"] {
            XCTAssertFalse(Mod.isValidID(bad), bad)
        }
        XCTAssertEqual(errors(#"{"id":"nodots","name":"X"}"#), [.badID])
    }

    func testVersionAndNames() {
        XCTAssertEqual(errors(#"{"id":"a.b","name":"X","version":"1.x"}"#), [.badVersion])
        XCTAssertEqual(errors(#"{"id":"a.b","name":"  "}"#), [.emptyName])
        XCTAssertEqual(errors(#"{"id":"a.b","name":"\#(String(repeating: "n", count: 61))"}"#), [.nameTooLong])
    }

    func testOversizeCSS() {
        let big = String(repeating: "a{}", count: Mod.maxCSSBytes / 3 + 10)
        XCTAssertEqual(Mod(id: "a.b", name: "X", css: big).validate(), [.cssTooLarge(bytes: big.utf8.count)])
        XCTAssertTrue(Mod(id: "a.b", name: "X", css: String(repeating: "a", count: Mod.maxCSSBytes)).validate().isEmpty)
    }

    func testRemoteCSSRejected() {
        func check(_ css: String, _ expected: ModError, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertTrue(Mod(id: "a.b", name: "X", css: css).validate().contains(expected), css, file: file, line: line)
        }
        check("@import 'x.css';", .cssImport)
        check("@IMPORT url(x.css);", .cssImport)
        check("a{background:url(https://evil.test/x.png)}", .cssRemoteURL)
        check("a{background:URL( 'HTTP://evil.test/x' )}", .cssRemoteURL)
        check("a{background:url(//evil.test/x.png)}", .cssRemoteURL)
        check("a{background:url(\"//evil.test/x.png\")}", .cssRemoteURL)
        check("a{content:\"\\75rl(x)\"}", .cssEscape)
        XCTAssertTrue(Mod(id: "a.b", name: "X", css: "a{background:url(data:image/png;base64,AAAA)} /* // ok */").validate().isEmpty)
    }

    func testFlagRanges() {
        XCTAssertEqual(errors(#"{"id":"a.b","name":"X","flags":{"dimUnloadedTabs":2}}"#), [.flagOutOfRange(.dimUnloadedTabs)])
        XCTAssertEqual(errors(#"{"id":"a.b","name":"X","flags":{"tabTextSize":40}}"#), [.flagOutOfRange(.tabTextSize)])
    }

    func testUnknownFlagAndKeyRejected() {
        XCTAssertEqual(load(#"{"id":"a.b","name":"X","flags":{"runScript":true}}"#), .failure(.unreadable("unknown flag runScript")))
        XCTAssertEqual(load(#"{"id":"a.b","name":"X","js":"alert(1)"}"#), .failure(.unreadable("unknown key js")))
        XCTAssertEqual(load(#"{"id":"a.b","name":"X","flags":{"sleekBorder":"yes"}}"#).isFailure, true)
        XCTAssertEqual(load("nope").isFailure, true)
    }

    func testFlagMergeOrder() {
        let a = Mod(id: "a.a", name: "A", flags: ModFlags(hoverOnlyClose: true, dimUnloadedTabs: 0.2, tabTextSize: 12))
        let b = Mod(id: "a.b", name: "B", flags: ModFlags(hoverOnlyClose: false, dimUnloadedTabs: 0.6))
        let c = Mod(id: "a.c", name: "C", look: SpaceLook(grain: 0.1))
        let merged = ModFlags.merge([a, b, c])
        XCTAssertEqual(merged.hoverOnlyClose, false)
        XCTAssertEqual(merged.dimUnloadedTabs, 0.6)
        XCTAssertEqual(merged.tabTextSize, 12)
        XCTAssertNil(merged.biggerMute)
        XCTAssertEqual(ModFlags.merge([b, a]).hoverOnlyClose, true)
        XCTAssertEqual(ModFlags.merge([]), ModFlags())
    }

    func testLookLayersModsThenSpace() {
        let a = Mod(id: "a.a", name: "A", look: SpaceLook(grain: 0.2, cornerRadius: 4))
        let b = Mod(id: "a.b", name: "B", look: SpaceLook(grain: 0.5))
        let r = SpaceLook.resolve(mods: [a, b], own: SpaceLook(cornerRadius: 9))
        XCTAssertEqual(r.grain, 0.5)
        XCTAssertEqual(r.cornerRadius, 9)
        XCTAssertEqual(SpaceLook.resolve(mods: [a], own: nil).cornerRadius, 4)
    }

    func testBuiltInsAllValid() {
        XCTAssertEqual(Mod.builtIns.count, 8)
        XCTAssertEqual(Set(Mod.builtIns.map(\.id)).count, 8)
        for mod in Mod.builtIns { XCTAssertEqual(mod.validate(), [], mod.id) }
        // One per flag, and together they set every flag.
        let all = ModFlags.merge(Mod.builtIns)
        XCTAssertEqual(all.hoverOnlyClose, true)
        XCTAssertEqual(all.biggerMute, true)
        XCTAssertNotNil(all.dimUnloadedTabs)
        XCTAssertNotNil(all.tabTextSize)
        XCTAssertEqual(all.sleekBorder, true)
        XCTAssertEqual(all.compactFindBar, true)
        XCTAssertEqual(all.hidePinnedReset, true)
        XCTAssertEqual(all.resetOnHoverOnly, true)
        XCTAssertEqual(ModFlag.allCases.count, 8)
    }
}

private extension Result {
    var isFailure: Bool { if case .failure = self { return true } else { return false } }
}
