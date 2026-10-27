import Foundation

// The command bar's ranking: pure, so it tests without any store. Candidates
// are open tabs, bookmarks, history and actions; the caller supplies them and
// maps the winners back by `id`. A query starting with ">" looks at actions only.

enum CommandKind: Int, Codable, CaseIterable, Comparable {
    case openTab, bookmark, history, action

    static func < (a: CommandKind, b: CommandKind) -> Bool { a.rawValue < b.rawValue }

    /// A tab you have open beats the same page in a bookmark or the history.
    fileprivate var bonus: Int {
        switch self {
        case .openTab: 20
        case .bookmark: 10
        case .history, .action: 0
        }
    }
}

struct CommandCandidate<ID: Hashable>: Hashable {
    var id: ID
    var title: String
    /// The address or host it is found by; nil for an action.
    var url: String?
    var kind: CommandKind
    /// When it was last used or visited; nil counts as long ago.
    var lastUsed: Date?
    /// Extra words that find an action.
    var keywords: [String]

    init(id: ID, title: String, url: String? = nil, kind: CommandKind, lastUsed: Date? = nil, keywords: [String] = []) {
        self.id = id
        self.title = title
        self.url = url
        self.kind = kind
        self.lastUsed = lastUsed
        self.keywords = keywords
    }
}

struct CommandRanked<ID: Hashable> {
    var candidate: CommandCandidate<ID>
    var score: Int
}

enum CommandRanker {
    static let maxResults = 8
    /// Recent use adds up to this many points, fading to nothing over `recencyDays`.
    static let recencyBonus = 15
    static let recencyDays = 30.0

    /// Best matches first. Equal scores keep their input order. A page open in a
    /// tab hides its bookmark and history rows; actions are never merged.
    static func rank<ID: Hashable>(
        query rawQuery: String,
        candidates: [CommandCandidate<ID>],
        now: Date = Date(),
        limit: Int = maxResults
    ) -> [CommandRanked<ID>] {
        var query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let actionsOnly = query.hasPrefix(">")
        if actionsOnly { query = String(query.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines) }

        var scored: [(Int, Int, CommandCandidate<ID>)] = []   // score, input order, candidate
        for (offset, c) in candidates.enumerated() {
            // ">" shows actions alone; an empty query shows pages, not every action.
            if actionsOnly ? c.kind != .action : (c.kind == .action && query.isEmpty) { continue }
            guard let match = matchScore(query, c) else { continue }
            scored.append((match + c.kind.bonus + recency(c.lastUsed, now: now), offset, c))
        }
        scored.sort { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }

        var seen = Set<String>()
        var result: [CommandRanked<ID>] = []
        // Tabs claim their address first, whatever their score.
        for c in scored.map(\.2) where c.kind == .openTab { if let u = c.url { seen.insert(key(u)) } }
        for (score, _, c) in scored {
            if c.kind != .openTab, c.kind != .action, let u = c.url, !seen.insert(key(u)).inserted { continue }
            result.append(CommandRanked(candidate: c, score: score))
            if result.count == limit { break }
        }
        return result
    }

    /// Case-insensitive subsequence score, or nil if `query` is not a subsequence of `text`.
    /// Substrings beat scattered matches; prefixes and word starts beat the middle of a word.
    static func score(_ query: String, in text: String) -> Int? {
        let q = Array(query.trimmingCharacters(in: .whitespaces).lowercased())
        let t = Array(text.lowercased())
        guard !q.isEmpty else { return 0 }
        guard q.count <= t.count else { return nil }

        var substringStart: Int?
        for start in 0...(t.count - q.count) where Array(t[start..<(start + q.count)]) == q {
            if substringStart == nil { substringStart = start }
            if isWordStart(t, start) {
                substringStart = start
                break
            }
        }
        if let start = substringStart {
            let position = start == 0 ? 50 : isWordStart(t, start) ? 30 : 0
            return 100 + q.count * 4 + position - min(t.count - q.count, 40) / 4
        }

        var total = 0
        var previous = -2
        var next = 0
        for character in q {
            guard let index = (next..<t.count).first(where: { t[$0] == character }) else { return nil }
            total += 1
            if index == previous + 1 { total += 5 }
            if isWordStart(t, index) { total += 4 }
            total -= min(index - next, 3)
            previous = index
            next = index + 1
        }
        return max(1, min(total, 90))
    }

    // MARK: Private

    /// Title, the address (weighted up when it is only a host, so shorter) and, for actions, keywords (weighted down).
    private static func matchScore<ID>(_ query: String, _ c: CommandCandidate<ID>) -> Int? {
        if query.isEmpty { return 0 }
        var options = [score(query, in: c.title)]
        if let url = c.url {
            let host = displayString(url)
            options.append(score(query, in: host).map { $0 * 6 / 5 })
            options.append(score(query, in: url).map { $0 / 2 })
        }
        options += c.keywords.map { score(query, in: $0).map { $0 * 4 / 5 } }
        return options.compactMap { $0 }.max()
    }

    private static func recency(_ date: Date?, now: Date) -> Int {
        guard let date else { return 0 }
        let age = max(0, now.timeIntervalSince(date)) / 86_400
        return Int((Double(recencyBonus) * max(0, 1 - age / recencyDays)).rounded())
    }

    private static func key(_ url: String) -> String {
        var text = url.lowercased()
        for prefix in ["https://", "http://", "www."] where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    /// The host of an address, or the text as is.
    private static func displayString(_ url: String) -> String {
        var text = key(url)
        if let slash = text.firstIndex(of: "/") { text = String(text[..<slash]) }
        return text
    }

    private static func isWordStart(_ text: [Character], _ index: Int) -> Bool {
        index == 0 || !text[index - 1].isLetter && !text[index - 1].isNumber
    }
}
