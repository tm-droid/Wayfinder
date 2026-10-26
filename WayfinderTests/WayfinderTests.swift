//
//  WayfinderTests.swift
//  WayfinderTests
//
//  Created by Tanush Malhotra (School) on 5/28/26.
//

import XCTest
@testable import Wayfinder

final class AddressInputTests: XCTestCase {
    private func resolve(_ input: String) -> String? {
        AddressInput.url(for: input, searchEngine: .duckDuckGo)?.absoluteString
    }

    func testFullURLIsKept() {
        XCTAssertEqual(resolve("https://apple.com/mac"), "https://apple.com/mac")
        XCTAssertEqual(resolve("http://example.com"), "http://example.com")
    }

    func testBareHostGetsHTTPS() {
        XCTAssertEqual(resolve("webkit.org"), "https://webkit.org")
        XCTAssertEqual(resolve("  en.wikipedia.org/wiki/WebKit  "), "https://en.wikipedia.org/wiki/WebKit")
        XCTAssertEqual(resolve("example.com/search?q=1"), "https://example.com/search?q=1")
    }

    func testLocalAddressesUseHTTP() {
        XCTAssertEqual(resolve("localhost"), "http://localhost")
        XCTAssertEqual(resolve("localhost:3000"), "http://localhost:3000")
        XCTAssertEqual(resolve("192.168.1.1"), "http://192.168.1.1")
        XCTAssertEqual(resolve("127.0.0.1:8080/status"), "http://127.0.0.1:8080/status")
    }

    func testSpecialSchemes() {
        XCTAssertEqual(resolve("about:blank"), "about:blank")
    }

    func testWordsAreSearched() {
        XCTAssertEqual(resolve("swift"), "https://duckduckgo.com/?q=swift")
        XCTAssertEqual(resolve("how to build webkit"), "https://duckduckgo.com/?q=how%20to%20build%20webkit")
        XCTAssertEqual(resolve("1.5"), "https://duckduckgo.com/?q=1.5")
        XCTAssertEqual(resolve("999.1.1.1"), "https://duckduckgo.com/?q=999.1.1.1")
    }

    func testUnsupportedSchemesAreSearched() {
        XCTAssertEqual(resolve("javascript:alert(1)"), "https://duckduckgo.com/?q=javascript:alert(1)")
    }

    func testEmptyInputLoadsNothing() {
        XCTAssertNil(resolve(""))
        XCTAssertNil(resolve("   "))
    }

    func testSearchEngines() {
        XCTAssertEqual(SearchEngine.google.searchURL(for: "a b").absoluteString, "https://www.google.com/search?q=a%20b")
        XCTAssertEqual(SearchEngine.bing.searchURL(for: "x").absoluteString, "https://www.bing.com/search?q=x")
        XCTAssertEqual(SearchEngine.ecosia.searchURL(for: "x").absoluteString, "https://www.ecosia.org/search?q=x")
    }

    func testDisplayStringDropsSchemeAndWWW() {
        XCTAssertEqual(AddressInput.displayString(for: URL(string: "https://www.apple.com/mac/")!), "apple.com")
        XCTAssertEqual(AddressInput.displayString(for: URL(string: "http://localhost:8765/")!), "localhost")
        XCTAssertEqual(AddressInput.displayString(for: URL(string: "about:blank")!), "about:blank")
    }
}
