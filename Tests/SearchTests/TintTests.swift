import XCTest
@testable import Search

final class TintTests: XCTestCase {
    func testSpaceDecodesWithAndWithoutLook() throws {
        let id = UUID().uuidString
        let old = try JSONDecoder().decode(Space.self, from: Data(#"{"id":"\#(id)","name":"A","colour":0}"#.utf8))
        XCTAssertNil(old.look)
        let new = try JSONDecoder().decode(Space.self, from: Data(#"{"id":"\#(id)","name":"A","colour":0,"look":{"grain":0.4,"scheme":"dark","future":1}}"#.utf8))
        XCTAssertEqual(new.look?.grain, 0.4)
        XCTAssertEqual(new.look?.scheme, .dark)
    }

    func testLookRoundTripsThroughSpace() throws {
        var space = Space.first()
        space.look = LookPreset.all[1].look
        space.look?.transparency = 0.6
        let back = try JSONDecoder().decode(Space.self, from: JSONEncoder().encode(space))
        XCTAssertEqual(back, space)
        XCTAssertEqual(back.look?.transparency, 0.6)
    }

    func testTintFollowsTheActiveSpace() {
        var a = Space.first(), b = Space(id: UUID(), name: "B", colour: 0)
        a.look = SpaceLook(gradient: ["#112233", "#445566"], grain: 0.5)
        b.look = SpaceLook(scheme: .light, cornerRadius: 4)
        let spaces = [a, b]
        XCTAssertTrue(Tint.of(spaces, active: a.id).hasGround)
        XCTAssertEqual(Tint.of(spaces, active: a.id).look.grain, 0.5)
        XCTAssertFalse(Tint.of(spaces, active: b.id).hasGround)
        XCTAssertEqual(Tint.of(spaces, active: b.id).scheme, .light)
        XCTAssertEqual(Tint.of(spaces, active: b.id).look.cornerRadius, 4)
        // Mods sit under the space's own look.
        let mod = Mod(id: "a.m", name: "M", look: SpaceLook(grain: 0.9, cornerRadius: 20))
        XCTAssertEqual(Tint.of(spaces, active: b.id, mods: [mod]).look.cornerRadius, 4)
        XCTAssertEqual(Tint.of(spaces, active: b.id, mods: [mod]).look.grain, 0.9)
        XCTAssertEqual(Tint.of([], active: UUID()), Tint.none)
    }

    func testPresetsAreValid() {
        XCTAssertTrue((6...8).contains(LookPreset.all.count))
        XCTAssertEqual(Set(LookPreset.all.map(\.name)).count, LookPreset.all.count)
        for p in LookPreset.all {
            let stops = p.look.gradient ?? []
            XCTAssertTrue((2...3).contains(stops.count), p.name)
            XCTAssertEqual(SpaceLook.resolve([p.look]).gradient, stops.compactMap(SpaceLook.normalizedHex), p.name)
            XCTAssertNotNil(p.look.accent.flatMap(SpaceLook.normalizedHex), p.name)
            XCTAssertTrue(stops.allSatisfy { Tint.color($0) != nil }, p.name)
        }
    }

    func testResetGoesBackToDefaults() {
        var look = SpaceLook(grain: 0.8, transparency: 0.9)
        XCTAssertEqual(SpaceLook.resolve([look]).grain, 0.8)
        look.grain = nil
        look.transparency = nil
        XCTAssertEqual(SpaceLook.resolve([look]).grain, SpaceLook.defaults.grain)
        XCTAssertEqual(SpaceLook.resolve([look]).transparency, SpaceLook.defaults.transparency)
        XCTAssertTrue(look.isEmpty)
    }

    func testDotMathRoundTrips() {
        let hex = LookEdit.hex(hue: 0.6, amount: 0.5)
        let back = LookEdit.place(hex)
        XCTAssertEqual(back?.hue ?? 0, 0.6, accuracy: 0.01)
        XCTAssertEqual(back?.amount ?? 0, 0.5, accuracy: 0.02)
        let p = LookEdit.point(hue: 0.25, amount: 1, in: 100)
        XCTAssertEqual(p.x, 100, accuracy: 0.001)
        XCTAssertEqual(p.y, 50, accuracy: 0.001)
        let at = LookEdit.place(at: CGPoint(x: 100, y: 50), in: 100)
        XCTAssertEqual(at.hue, 0.25, accuracy: 0.001)
        XCTAssertEqual(LookEdit.place(at: CGPoint(x: 500, y: 50), in: 100).amount, 1)
    }

    func testFineDragAndStopCount() {
        XCTAssertEqual(LookEdit.dragged(0.5, by: 0.2, fine: false), 0.7, accuracy: 1e-9)
        XCTAssertEqual(LookEdit.dragged(0.5, by: 0.2, fine: true), 0.52, accuracy: 1e-9)
        XCTAssertEqual(LookEdit.dragged(0.9, by: 0.5, fine: false), 1)
        XCTAssertNil(LookEdit.adding("#000000", to: ["#111111", "#222222", "#333333"]))
        XCTAssertEqual(LookEdit.adding("#000000", to: ["#111111", "#222222"])?.count, 3)
        XCTAssertNil(LookEdit.removing(0, from: ["#111111", "#222222"]))
        XCTAssertEqual(LookEdit.removing(1, from: ["#111111", "#222222", "#333333"]), ["#111111", "#333333"])
    }
}
