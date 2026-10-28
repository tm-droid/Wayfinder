import XCTest
@testable import Search

final class ModStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("mods-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private var file: URL { dir.appendingPathComponent("mods.json") }

    private func load(_ json: String) -> Result<Mod, Mod.LoadFailure> { Mod.load(Data(json.utf8)) }

    private func mod(_ json: String) throws -> Mod { try load(json).get() }

    private func problems(_ json: String) -> [ModError] {
        if case .failure(.invalid(let e)) = load(json) { return e }
        return []
    }

    private func prefs(_ p: String, flags: String = "") -> String {
        #"{"id":"com.example.p","name":"P","prefs":[\#(p)]\#(flags)}"#
    }

    // MARK: manifest prefs

    func testGoodPrefsLoad() throws {
        let m = try mod(prefs(#"""
        {"id":"close","label":"Bigger mute","type":"checkbox","default":true,"flag":"biggerMute"},
        {"id":"dim","label":"Dim","type":"dropdown","default":"0.3","flag":"dimUnloadedTabs",
         "options":[{"value":"0.3","label":"A little"},{"value":"0.6","label":"A lot"}]},
        {"id":"note","label":"Note","type":"string","maxLength":10,"default":"hi"}
        """#))
        XCTAssertEqual(m.prefs.map(\.kind), [.checkbox, .dropdown, .string])
        XCTAssertEqual(try JSONDecoder().decode(Mod.self, from: JSONEncoder().encode(m)), m)
    }

    func testUnknownKeysAndTypesAreRefused() {
        for p in [#"{"id":"a","label":"A","type":"checkbox","script":"x"}"#,
                  #"{"id":"a","label":"A","type":"color"}"#,
                  #"{"id":"a","label":"A","type":"checkbox","flag":"runCode"}"#,
                  #"{"id":"a","label":"A","type":"checkbox","default":"yes"}"#] {
            let r = load(prefs(p))
            if case .failure(.unreadable) = r { continue }
            if case .failure(.invalid) = r { continue }
            XCTFail("accepted \(p)")
        }
        if case .failure(.unreadable(let why)) = load(prefs(#"{"id":"a","label":"A","type":"color"}"#)) {
            XCTAssertTrue(why.contains("color"), why)
        } else { XCTFail() }
        if case .success = load(#"{"id":"com.example.p","name":"P","css":"a{}"}"#) { XCTFail("css accepted") }
    }

    func testPrefCaps() {
        let many = (0..<9).map { #"{"id":"p\#($0)","label":"L","type":"checkbox"}"# }.joined(separator: ",")
        XCTAssertTrue(problems(prefs(many)).contains(.tooManyPrefs))

        XCTAssertEqual(problems(prefs(#"{"id":"a","label":"A","type":"checkbox"},{"id":"a","label":"B","type":"checkbox"}"#)),
                       [.pref("a", .duplicateID)])
        XCTAssertEqual(problems(prefs(#"{"id":"Bad Id","label":"A","type":"checkbox"}"#)), [.pref("Bad Id", .badID)])
        let longLabel = String(repeating: "x", count: 61)
        XCTAssertEqual(problems(prefs(#"{"id":"a","label":"\#(longLabel)","type":"checkbox"}"#)), [.pref("a", .labelTooLong)])
        XCTAssertEqual(problems(prefs(#"{"id":"a","label":"A","type":"string","maxLength":201}"#)), [.pref("a", .maxLengthOutOfRange)])
        XCTAssertEqual(problems(prefs(#"{"id":"a","label":"A","type":"string","maxLength":5,"default":"toolong"}"#)), [.pref("a", .badDefault)])
        XCTAssertEqual(problems(prefs(#"{"id":"a","label":"A","type":"checkbox","maxLength":5}"#)), [.pref("a", .maxLengthNotAllowed)])

        let opts = (0..<13).map { #"{"value":"\#($0)","label":"o"}"# }.joined(separator: ",")
        XCTAssertEqual(problems(prefs(#"{"id":"a","label":"A","type":"dropdown","options":[\#(opts)]}"#)), [.pref("a", .tooManyOptions)])
        XCTAssertEqual(problems(prefs(#"{"id":"a","label":"A","type":"dropdown","options":[{"value":"1","label":"o"}]}"#)), [.pref("a", .tooFewOptions)])
        XCTAssertEqual(problems(prefs(#"{"id":"a","label":"A","type":"dropdown","options":[{"value":"1","label":"o"},{"value":"1","label":"p"}]}"#)),
                       [.pref("a", .duplicateOption)])
        XCTAssertEqual(problems(prefs(#"{"id":"a","label":"A","type":"checkbox","options":[{"value":"1","label":"o"}]}"#)), [.pref("a", .optionsNotAllowed)])
    }

    func testBindingsAreChecked() {
        XCTAssertEqual(problems(prefs(#"{"id":"a","label":"A","type":"string","flag":"biggerMute"}"#)), [.pref("a", .flagNotAllowed)])
        XCTAssertEqual(problems(prefs(#"{"id":"a","label":"A","type":"checkbox","flag":"tabTextSize"}"#)), [.pref("a", .flagNeedsToggle)])
        let two = #"[{"value":"15","label":"a"},{"value":"40","label":"b"}]"#
        XCTAssertEqual(problems(prefs(#"{"id":"a","label":"A","type":"dropdown","flag":"tabTextSize","options":\#(two)}"#)), [.pref("a", .optionOutOfRange)])
        let words = #"[{"value":"big","label":"a"},{"value":"small","label":"b"}]"#
        XCTAssertEqual(problems(prefs(#"{"id":"a","label":"A","type":"dropdown","flag":"tabTextSize","options":\#(words)}"#)), [.pref("a", .flagNeedsNumbers)])
        XCTAssertEqual(problems(prefs(#"{"id":"a","label":"A","type":"dropdown","flag":"biggerMute","options":\#(words)}"#)), [.pref("a", .flagNeedsNumbers)])
    }

    func testManifestSizeCap() {
        let pad = String(repeating: "a", count: Mod.maxManifestBytes)
        if case .failure(.unreadable(let why)) = load(#"{"id":"com.example.p","name":"P","author":"\#(pad)"}"#) {
            XCTAssertTrue(why.contains("64 KB"), why)
        } else { XCTFail("big manifest accepted") }
        XCTAssertFalse(ModError.badID.message.isEmpty)
    }

    func testReadManifestFromFileCapsTheRead() throws {
        let big = dir.appendingPathComponent("big.json")
        try Data(repeating: 0x20, count: 200_000).write(to: big)
        if case .success = ModStore.readManifest(at: big) { XCTFail() }
        let ok = dir.appendingPathComponent("ok.json")
        try Data(#"{"id":"com.example.ok","name":"Ok"}"#.utf8).write(to: ok)
        XCTAssertEqual(try ModStore.readManifest(at: ok).get().name, "Ok")
        if case .success = ModStore.readManifest(at: dir.appendingPathComponent("nope.json")) { XCTFail() }
    }

    // MARK: preferences into flags

    func testPrefsSetFlags() throws {
        let m = try mod(prefs(#"""
        {"id":"mute","label":"M","type":"checkbox","flag":"biggerMute"},
        {"id":"dim","label":"D","type":"dropdown","flag":"dimUnloadedTabs","default":"0.3",
         "options":[{"value":"0.3","label":"a"},{"value":"0.6","label":"b"}]}
        """#, flags: #","flags":{"biggerMute":true}"#))
        XCTAssertNil(m.flags(with: [:]).biggerMute, "an unticked box says nothing, even over the manifest's flag")
        XCTAssertEqual(m.flags(with: [:]).dimUnloadedTabs, 0.3)
        let f = m.flags(with: ["mute": .on(true), "dim": .text("0.6")])
        XCTAssertEqual(f.biggerMute, true)
        XCTAssertEqual(f.dimUnloadedTabs, 0.6)
        XCTAssertEqual(m.flags(with: ["dim": .text("9")]).dimUnloadedTabs, 0.3, "a value the pref does not offer is ignored")
    }

    // MARK: merge order

    func testLaterModsWinAndTheSpaceWinsOverAll() {
        let a = Mod(id: "a.one", name: "A", look: SpaceLook(cornerRadius: 4, tabTextSize: 11), flags: ModFlags(biggerMute: true, tabTextSize: 15))
        let b = Mod(id: "a.two", name: "B", look: SpaceLook(cornerRadius: 20), flags: ModFlags(tabTextSize: 17))
        XCTAssertEqual(SpaceLook.resolve(mods: [a, b], own: nil).cornerRadius, 20)
        XCTAssertEqual(SpaceLook.resolve(mods: [b, a], own: nil).cornerRadius, 4)
        XCTAssertEqual(SpaceLook.resolve(mods: [a, b], own: nil).tabTextSize, 17, "the flag is a look token for the tab text size")
        XCTAssertEqual(SpaceLook.resolve(mods: [b, a], own: nil).tabTextSize, 15)
        XCTAssertEqual(SpaceLook.resolve(mods: [a, b], own: SpaceLook(cornerRadius: 2, tabTextSize: 12)).cornerRadius, 2)
        XCTAssertEqual(SpaceLook.resolve(mods: [a, b], own: SpaceLook(tabTextSize: 12)).tabTextSize, 12)
        XCTAssertEqual(ModFlags.merge([a, b]).biggerMute, true, "a flag a later mod leaves alone stays")
        XCTAssertEqual(ModFlags.merge([a, b]).tabTextSize, 17)
    }

    func testSleekBorderFlagIsALookLayerTheSpaceCanOverride() {
        let sleek = Mod(id: "a.sleek", name: "S", flags: ModFlags(sleekBorder: true))
        XCTAssertEqual(SpaceLook.resolve(mods: [sleek], own: nil).webBorder, 1)
        XCTAssertEqual(SpaceLook.resolve(mods: [sleek], own: SpaceLook(webBorder: 0)).webBorder, 0)
        XCTAssertEqual(SpaceLook.resolve(mods: [sleek, Mod(id: "a.round", name: "R", look: SpaceLook(cornerRadius: 3))], own: nil).cornerRadius, 3)
    }

    func testTintCarriesTheMergedFlags() {
        let a = Mod(id: "a.one", name: "A", flags: ModFlags(compactFindBar: true))
        let b = Mod(id: "a.two", name: "B", flags: ModFlags(dimUnloadedTabs: 0.4, compactFindBar: false))
        let tint = Tint.of([Space.first()], active: Space.firstID, mods: [a, b])
        XCTAssertEqual(tint.flags.compactFindBar, false)
        XCTAssertEqual(tint.dims(asleep: true, live: false), 0.6, accuracy: 1e-9)
        XCTAssertEqual(tint.dims(asleep: true, live: true), 1)
        XCTAssertEqual(tint.dims(asleep: false, live: false), 1)
        XCTAssertEqual(Tint.none.dims(asleep: true, live: false), 1)
    }

    // MARK: the state

    func testBuiltInsStartOffAndCannotBeRemoved() {
        var s = ModState()
        XCTAssertEqual(s.all.map(\.id), Mod.builtIns.map(\.id))
        XCTAssertTrue(s.enabledMods.isEmpty)
        XCTAssertFalse(s.remove(Mod.builtIns[0].id))
        s.setEnabled(Mod.builtIns[2].id, true)
        XCTAssertEqual(s.enabledMods.map(\.id), [Mod.builtIns[2].id])
        XCTAssertEqual(s.enabledMods[0].flags?.dimUnloadedTabs, 0.5)
    }

    func testInstallReplaceMoveRemove() throws {
        var s = ModState()
        let m = try mod(prefs(#"{"id":"x","label":"X","type":"string"}"#))
        XCTAssertNil(s.install(m))
        XCTAssertTrue(s.isEnabled(m.id))
        XCTAssertEqual(s.all.last?.id, m.id)
        XCTAssertTrue(s.setValue(.text("hello"), pref: "x", of: m.id))
        XCTAssertFalse(s.setValue(.on(true), pref: "x", of: m.id))
        XCTAssertFalse(s.setValue(.text("a"), pref: "nope", of: m.id))
        // Reinstalling keeps place, state and valid values.
        s.move(m.id, by: -3)
        var again = m
        again.name = "P2"
        XCTAssertNil(s.install(again))
        XCTAssertEqual(s.all.firstIndex { $0.id == m.id }, Mod.builtIns.count - 3)
        XCTAssertEqual(s.mod(m.id)?.name, "P2")
        XCTAssertEqual(s.value(of: m.prefs[0], in: m), .text("hello"))
        s.move(m.id, by: -100)
        XCTAssertEqual(s.all.first?.id, m.id)
        XCTAssertTrue(s.remove(m.id))
        XCTAssertNil(s.mod(m.id))
        XCTAssertEqual(s.all.count, Mod.builtIns.count)

        let clash = Mod(id: Mod.builtIns[0].id, name: "Clash")
        XCTAssertEqual(s.install(clash), .builtInID)
        XCTAssertEqual(s.install(Mod(id: "bad", name: "Bad")), .invalid(.invalid([.badID])))
        for i in 0..<ModState.maxInstalled { XCTAssertNil(s.install(Mod(id: "a.m\(i)", name: "M"))) }
        XCTAssertEqual(s.install(Mod(id: "a.extra", name: "M")), .tooMany)
    }

    func testEnabledOrderFollowsTheUsersOrder() throws {
        var s = ModState()
        let a = Mod.builtIns[0].id, b = Mod.builtIns[1].id
        s.setEnabled(a, true)
        s.setEnabled(b, true)
        XCTAssertEqual(s.enabledMods.map(\.id), [a, b])
        s.move(b, by: -1)
        XCTAssertEqual(s.enabledMods.map(\.id), [b, a])
    }

    // MARK: the file

    func testRoundTrip() throws {
        var s = ModState()
        let m = try mod(prefs(#"{"id":"mute","label":"M","type":"checkbox","flag":"biggerMute"},{"id":"t","label":"T","type":"string"}"#))
        XCTAssertNil(s.install(m))
        s.setEnabled(Mod.builtIns[3].id, true)
        s.setEnabled(m.id, false)
        s.setValue(.on(true), pref: "mute", of: m.id)
        s.setValue(.text("note"), pref: "t", of: m.id)
        s.move(m.id, by: -2)
        XCTAssertTrue(s.write(to: file))
        XCTAssertEqual(ModState.read(from: file), s)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["mods.json"], "no temp file is left")
    }

    func testMissingFileIsEmpty() {
        XCTAssertEqual(ModState.read(from: file), ModState())
    }

    func testCorruptFileIsSetAsideAndNothingCrashes() throws {
        try Data("{ not json".utf8).write(to: file)
        XCTAssertEqual(ModState.read(from: file), ModState())
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let aside = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(aside.count, 1)
        XCTAssertTrue(aside[0].contains("unreadable"))
        XCTAssertTrue(ModState().write(to: file), "a new file can be written afterwards")
        for junk in ["[1,2]", "42", "null", ""] {
            try Data(junk.utf8).write(to: file)
            XCTAssertEqual(ModState.read(from: file), ModState(), junk)
        }
    }

    func testBadPartsAreDroppedAndTheRestKept() throws {
        var s = ModState()
        let good = try mod(prefs(#"{"id":"t","label":"T","type":"string","maxLength":5}"#))
        XCTAssertNil(s.install(good))
        s.setEnabled(Mod.builtIns[1].id, true)
        s.setValue(.text("ok"), pref: "t", of: good.id)
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(s.encoded())) as? [String: Any])
        var installed = root["installed"] as! [Any]
        installed.append(["id": "a.css", "name": "Css", "css": "a{}"])
        installed.append(["id": "nodots", "name": "Bad"])
        installed.append("junk")
        installed.append(["id": Mod.builtIns[0].id, "name": "Impostor"])
        root["installed"] = installed
        root["order"] = ["ghost.mod", good.id, good.id]
        root["enabled"] = ["ghost.mod", good.id, 7]
        root["values"] = [good.id: ["t": "waytoolong", "other": true], "ghost.mod": ["t": "x"]]
        try JSONSerialization.data(withJSONObject: root).write(to: file)

        let back = ModState.read(from: file)
        XCTAssertEqual(back.installed.map(\.id), [good.id])
        XCTAssertEqual(back.all.map(\.id), [good.id] + Mod.builtIns.map(\.id), "saved order kept, ghosts and repeats dropped, the rest appended")
        XCTAssertEqual(back.enabledMods.map(\.id), [good.id])
        XCTAssertEqual(back.value(of: good.prefs[0], in: good), .text(""), "a value the pref refuses falls back to its default")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "a readable file is not set aside")
    }

    func testStoreSavesEveryChange() throws {
        let store = MainActor.assumeIsolated { ModStore(file: file) }
        let id = Mod.builtIns[0].id
        MainActor.assumeIsolated { store.change { $0.setEnabled(id, true) } }
        XCTAssertTrue(ModState.read(from: file).isEnabled(id))
        let m = dir.appendingPathComponent("m.json")
        try Data(#"{"id":"com.example.m","name":"M"}"#.utf8).write(to: m)
        XCTAssertNil(MainActor.assumeIsolated { store.install(from: m) })
        XCTAssertNotNil(MainActor.assumeIsolated { store.install(from: dir.appendingPathComponent("gone.json")) })
        XCTAssertNotNil(ModState.read(from: file).mod("com.example.m"))
    }

    func testProfilesKeepSeparateFiles() {
        let other = UUID()
        XCTAssertEqual(ModStore.file(for: Profile.personalID).lastPathComponent, "mods.json")
        XCTAssertEqual(ModStore.file(for: other).lastPathComponent, "mods-\(other.uuidString).json")
    }

    func testSettingsFindsTheMods() {
        XCTAssertTrue(SettingsIndex.find("zen mods").contains { $0.page == .mods })
        XCTAssertTrue(SettingsPanel.Page.blocks.joined().contains(.mods))
    }
}
