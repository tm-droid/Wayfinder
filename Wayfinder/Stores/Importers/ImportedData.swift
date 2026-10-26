//
//  ImportedData.swift
//  Wayfinder
//
//  Browser-neutral result of parsing another browser's export. Not tied to
//  BookmarkStore or the space models; mapping happens in a later step.
//

import Foundation

indirect enum ImportedNode: Equatable {
    case link(title: String, url: URL)
    case folder(title: String, children: [ImportedNode])
}

struct ImportedSpace: Equatable {
    var name: String
    var emoji: String?
    var colorHex: String?
    var pinned: [ImportedNode] = []
    var essentials: [ImportedNode] = []
}

struct ImportedData: Equatable {
    var spaces: [ImportedSpace] = []
    var bookmarks: [ImportedNode] = []

    var isEmpty: Bool { spaces.isEmpty && bookmarks.isEmpty }
}

enum ImportError: Error, Equatable {
    case unreadable
    case unrecognizedFormat
}

enum ImportedURL {
    /// Only http(s) URLs are importable (drops javascript:, data:, file:, ...).
    static func web(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { return nil }
        return url
    }
}
