//
//  AddressInput.swift
//  Wayfinder
//

import Foundation

nonisolated enum SearchEngine: String, CaseIterable, Identifiable, Codable {
    case duckDuckGo
    case google
    case bing
    case ecosia

    var id: String { rawValue }

    var name: String {
        switch self {
        case .duckDuckGo: "DuckDuckGo"
        case .google: "Google"
        case .bing: "Bing"
        case .ecosia: "Ecosia"
        }
    }

    private var baseURL: String {
        switch self {
        case .duckDuckGo: "https://duckduckgo.com/"
        case .google: "https://www.google.com/search"
        case .bing: "https://www.bing.com/search"
        case .ecosia: "https://www.ecosia.org/search"
        }
    }

    func searchURL(for query: String) -> URL {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url!
    }
}

/// Turns whatever the user typed into the address bar into something loadable.
nonisolated enum AddressInput {
    static func url(for input: String, searchEngine: SearchEngine) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return directURL(for: text) ?? searchEngine.searchURL(for: text)
    }

    /// Returns a URL if the text looks like an address, or nil if it should be searched for.
    static func directURL(for text: String) -> URL? {
        guard !text.contains(where: \.isWhitespace) else { return nil }
        let lowercased = text.lowercased()

        if lowercased.hasPrefix("about:") || lowercased.hasPrefix("data:") {
            return URL(string: text)
        }

        if lowercased.contains("://") {
            guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
                  ["http", "https", "file"].contains(scheme) else { return nil }
            return url
        }

        guard let url = URL(string: "https://" + text), let host = url.host()?.lowercased() else { return nil }

        if host == "localhost" || isIPv4Address(host) {
            return URL(string: "http://" + text)
        }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }),
              let topLevelDomain = labels.last, topLevelDomain.count >= 2,
              topLevelDomain.allSatisfy(\.isLetter) else { return nil }
        return url
    }

    /// A short form of the URL for display when the address bar is not being edited.
    static func displayString(for url: URL) -> String {
        guard let host = url.host(), url.scheme == "http" || url.scheme == "https" else {
            return url.absoluteString
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func isIPv4Address(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            guard let value = Int(part), part.count <= 3 else { return false }
            return (0...255).contains(value)
        }
    }
}
