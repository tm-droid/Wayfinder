//
//  BookmarkStore.swift
//  Wayfinder
//

import Foundation
import Observation
import SwiftUI

struct Bookmark: Codable, Identifiable, Hashable {
    var id = UUID()
    var url: URL
    var title: String
    var dateAdded = Date.now

    var displayTitle: String {
        title.isEmpty ? AddressInput.displayString(for: url) : title
    }
}

@Observable
final class BookmarkStore {
    static let shared = BookmarkStore()

    private(set) var bookmarks: [Bookmark]

    @ObservationIgnored private let file = JSONFile<[Bookmark]>(name: "Bookmarks.json")
    @ObservationIgnored private let saver = SaveScheduler(delay: .milliseconds(200))

    init() {
        bookmarks = file.load() ?? Self.defaultBookmarks
    }

    func contains(_ url: URL?) -> Bool {
        guard let url else { return false }
        return bookmarks.contains { $0.url == url }
    }

    func toggle(url: URL, title: String) {
        if contains(url) {
            bookmarks.removeAll { $0.url == url }
        } else {
            bookmarks.append(Bookmark(url: url, title: title))
        }
        scheduleSave()
    }

    func remove(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        scheduleSave()
    }

    func rename(_ bookmark: Bookmark, to title: String) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        bookmarks[index].title = title
        scheduleSave()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        bookmarks.move(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }

    func matches(for query: String, limit: Int) -> [Bookmark] {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        return Array(bookmarks.filter {
            $0.url.absoluteString.lowercased().contains(query) || $0.title.lowercased().contains(query)
        }.prefix(limit))
    }

    private func scheduleSave() {
        saver.schedule { [weak self] in
            guard let self else { return }
            file.save(bookmarks)
        }
    }

    private static let defaultBookmarks = [
        Bookmark(url: URL(string: "https://webkit.org")!, title: "WebKit"),
        Bookmark(url: URL(string: "https://developer.apple.com")!, title: "Apple Developer"),
        Bookmark(url: URL(string: "https://en.wikipedia.org")!, title: "Wikipedia"),
        Bookmark(url: URL(string: "https://github.com")!, title: "GitHub"),
    ]
}
