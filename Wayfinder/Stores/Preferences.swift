//
//  Preferences.swift
//  Wayfinder
//

import Foundation

/// UserDefaults keys shared by `@AppStorage` in views and plain reads in models.
enum PreferenceKey {
    static let homepage = "homepage"
    static let searchEngine = "searchEngine"
    static let restoresTabs = "restoresTabs"
    static let savedTabs = "savedTabs"
}

enum Preferences {
    static var searchEngine: SearchEngine {
        UserDefaults.standard.string(forKey: PreferenceKey.searchEngine).flatMap(SearchEngine.init(rawValue:)) ?? .duckDuckGo
    }

    /// The page new tabs open with, or nil for the start page.
    static var homepage: URL? {
        guard let text = UserDefaults.standard.string(forKey: PreferenceKey.homepage) else { return nil }
        return AddressInput.directURL(for: text.trimmingCharacters(in: .whitespaces))
    }

    static var restoresTabs: Bool {
        UserDefaults.standard.object(forKey: PreferenceKey.restoresTabs) as? Bool ?? true
    }
}
