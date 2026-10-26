//
//  ImporterTests.swift
//  WayfinderTests
//

import XCTest
@testable import Wayfinder

final class ImporterTests: XCTestCase {
    private func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures").appendingPathComponent(name)
    }

    private func link(_ title: String, _ url: String) -> ImportedNode {
        .link(title: title, url: URL(string: url)!)
    }

    func testArc() throws {
        let data = try BrowserImporter.detectAndParse(fileURL: fixture("arc-StorableSidebar.json"))
        XCTAssertEqual(data.spaces.count, 2)
        let work = data.spaces[0]
        XCTAssertEqual(work.name, "Work")
        XCTAssertEqual(work.emoji, "💼")
        XCTAssertEqual(work.colorHex, "#FF8000")
        XCTAssertEqual(work.pinned, [
            link("GitHub", "https://github.com"),
            .folder(title: "Docs", children: [
                link("Apple Developer", "https://developer.apple.com"),
                link("Swift", "https://swift.org"),
            ]),
        ])
        XCTAssertEqual(work.essentials, [link("Gmail", "https://mail.google.com")])
        XCTAssertEqual(data.spaces[1].name, "Space 1")
        XCTAssertEqual(data.spaces[1].pinned, [link("Hacker News", "https://news.ycombinator.com")])
        XCTAssertTrue(data.bookmarks.isEmpty)
    }

    func testArcDefensive() throws {
        let junk = #"{"sidebar":{"containers":[1,"x",{"spaces":[5,{"newContainerIDs":[{"pinned":1}]}],"items":[null,{"id":3}]}]}}"#
        let data = try ArcImporter.parse(data: Data(junk.utf8))
        XCTAssertEqual(data.spaces, [ImportedSpace(name: "Space 1")])
    }

    func testChrome() throws {
        let data = try BrowserImporter.detectAndParse(fileURL: fixture("chrome-Bookmarks.json"))
        XCTAssertTrue(data.spaces.isEmpty)
        XCTAssertEqual(data.bookmarks, [
            link("Example", "https://example.com/"),
            .folder(title: "Dev", children: [link("MDN", "https://developer.mozilla.org/")]),
            .folder(title: "Other bookmarks", children: [link("Wikipedia", "https://en.wikipedia.org/")]),
        ])
    }

    func testSafariHTML() throws {
        let data = try BrowserImporter.detectAndParse(fileURL: fixture("safari-bookmarks.html"))
        XCTAssertEqual(data.bookmarks, [
            .folder(title: "Favorites", children: [
                link("Apple & Friends", "https://www.apple.com/"),
                .folder(title: "Reading", children: [
                    link("Tom's \"Quote\" \u{263A}", "https://example.com/?a=1&b=2"),
                ]),
            ]),
            link("Unclosed link", "https://unclosed.example/"),
            link("Bold title", "https://last.example/"),
        ])
    }

    func testNotABrowserFile() {
        XCTAssertThrowsError(try BrowserImporter.detectAndParse(data: Data(#"{"hello":1}"#.utf8))) {
            XCTAssertEqual($0 as? ImportError, .unrecognizedFormat)
        }
        XCTAssertThrowsError(try BrowserImporter.detectAndParse(data: Data("plain text".utf8)))
        XCTAssertThrowsError(try BrowserImporter.detectAndParse(fileURL: fixture("missing.json"))) {
            XCTAssertEqual($0 as? ImportError, .unreadable)
        }
    }
}
