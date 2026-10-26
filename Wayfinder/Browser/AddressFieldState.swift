//
//  AddressFieldState.swift
//  Wayfinder
//

import Foundation
import Observation

struct Suggestion: Identifiable, Hashable {
    enum Kind {
        case search
        case website
        case bookmark
        case history
    }

    let kind: Kind
    let title: String
    let subtitle: String
    /// What loads when the suggestion is picked: typed text or a URL string.
    let completion: String
    var url: URL?

    var id: String { "\(kind)-\(completion)" }
}

/// Editing state of a window's address bar, shared by the field and its suggestion list.
@Observable
final class AddressFieldState {
    var text = ""
    /// The field is first responder.
    var isFocused = false
    /// The user has typed since focusing, so suggestions apply.
    private(set) var isEditing = false
    private(set) var suggestions: [Suggestion] = []
    var highlightedIndex: Int?

    var showsSuggestions: Bool {
        isFocused && isEditing && !suggestions.isEmpty
    }

    var highlightedSuggestion: Suggestion? {
        highlightedIndex.flatMap { suggestions.indices.contains($0) ? suggestions[$0] : nil }
    }

    func userDidType(_ newText: String) {
        text = newText
        isEditing = true
        highlightedIndex = nil
        suggestions = Self.suggestions(for: newText)
    }

    func moveHighlight(by offset: Int) {
        guard !suggestions.isEmpty else { return }
        let current = highlightedIndex ?? (offset > 0 ? -1 : suggestions.count)
        highlightedIndex = min(max(current + offset, 0), suggestions.count - 1)
    }

    func endEditing() {
        isEditing = false
        highlightedIndex = nil
        suggestions = []
    }

    private static func suggestions(for text: String) -> [Suggestion] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        var result: [Suggestion] = []
        if let url = AddressInput.directURL(for: query) {
            result.append(Suggestion(kind: .website, title: url.absoluteString, subtitle: "Go to site", completion: url.absoluteString, url: url))
        } else {
            let engine = Preferences.searchEngine
            result.append(Suggestion(kind: .search, title: query, subtitle: "Search \(engine.name)", completion: query))
        }

        var seen = Set<URL>()
        for bookmark in BookmarkStore.shared.matches(for: query, limit: 3) where seen.insert(bookmark.url).inserted {
            result.append(Suggestion(kind: .bookmark, title: bookmark.displayTitle, subtitle: AddressInput.displayString(for: bookmark.url),
                                     completion: bookmark.url.absoluteString, url: bookmark.url))
        }
        for entry in HistoryStore.shared.matches(for: query, limit: 6) where seen.insert(entry.url).inserted {
            result.append(Suggestion(kind: .history, title: entry.displayTitle, subtitle: AddressInput.displayString(for: entry.url),
                                     completion: entry.url.absoluteString, url: entry.url))
        }
        return Array(result.prefix(8))
    }
}
