import XCTest
@testable import Search

final class SpaceLookTests: XCTestCase {
    private func look(_ json: String) throws -> SpaceLook {
        try JSONDecoder().decode(SpaceLook.self, from: Data(json.utf8))
    }

    func testEmptyAndPartialJSONDecode() throws {
        XCTAssertTrue(try look("{}").isEmpty)
        let partial = try look(#"{"grain": 0.3, "font": "serif"}"#)
        XCTAssertEqual(partial.grain, 0.3)
        XCTAssertEqual(partial.font, .serif)
        XCTAssertNil(partial.gradient)
    }

    func testUnknownKeysAndBadValuesAreIgnored() throws {
        let l = try look(#"{"font": "comic", "grain": "lots", "futureThing": 3, "density": "roomy"}"#)
        XCTAssertNil(l.font)
        XCTAssertNil(l.grain)
        XCTAssertEqual(l.density, .roomy)
    }

    func testRoundTrip() throws {
        let l = SpaceLook(gradient: ["#112233", "#445566"], angle: 90, grain: 0.5, accent: "#FF0000", cornerRadius: 8,
                          density: .compact, tabTextSize: 12, font: .mono, webInset: 4, webBorder: 1)
        let back = try JSONDecoder().decode(SpaceLook.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(back, l)
    }

    func testResolveEmptyIsDefaults() {
        XCTAssertEqual(SpaceLook.resolve([]), SpaceLook.defaults)
        XCTAssertEqual(SpaceLook.resolve([SpaceLook()]), SpaceLook.defaults)
    }

    func testClamping() {
        let r = SpaceLook.resolve([SpaceLook(angle: 900, grain: 7, cornerRadius: -3, tabTextSize: 99, webInset: 100, webBorder: -1)])
        XCTAssertEqual(r.angle, 360)
        XCTAssertEqual(r.grain, 1)
        XCTAssertEqual(r.cornerRadius, 0)
        XCTAssertEqual(r.tabTextSize, 20)
        XCTAssertEqual(r.webInset, 24)
        XCTAssertEqual(r.webBorder, 0)
        XCTAssertEqual(SpaceLook.resolve([SpaceLook(grain: .nan)]).grain, SpaceLook.defaults.grain)
    }

    func testGradientCleaning() {
        let r = SpaceLook.resolve([SpaceLook(gradient: ["#abc", "123456", "#00000080", "#FFFFFF"])])
        XCTAssertEqual(r.gradient, ["#AABBCC", "#123456", "#00000080"])
        // One readable stop is not a gradient: the layer below stands.
        let kept = SpaceLook.resolve([SpaceLook(gradient: ["#111111", "#222222"]), SpaceLook(gradient: ["#333333", "nope"])])
        XCTAssertEqual(kept.gradient, ["#111111", "#222222"])
        XCTAssertEqual(SpaceLook.resolve([SpaceLook(accent: "blue")]).accent, nil)
        XCTAssertEqual(SpaceLook.resolve([SpaceLook(accent: " #ff8800 ")]).accent, "#FF8800")
    }

    func testMergeOrderLaterWinsFieldByField() {
        let modA = SpaceLook(grain: 0.2, cornerRadius: 4, font: .serif)
        let modB = SpaceLook(grain: 0.4, density: .roomy)
        let own = SpaceLook(cornerRadius: 12)
        let r = SpaceLook.resolve([modA, modB, own])
        XCTAssertEqual(r.grain, 0.4)           // modB over modA
        XCTAssertEqual(r.cornerRadius, 12)     // own over modA
        XCTAssertEqual(r.font, .serif)         // only modA set it
        XCTAssertEqual(r.density, .roomy)
        XCTAssertEqual(r.tabTextSize, SpaceLook.defaults.tabTextSize)
        XCTAssertEqual(SpaceLook.resolve([own, modA]).cornerRadius, 4)
    }
}
