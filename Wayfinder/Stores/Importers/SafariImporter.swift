//
//  SafariImporter.swift
//  Wayfinder
//
//  Netscape bookmark HTML: Safari "Export Bookmarks", plus Firefox/Chrome/Edge
//  HTML exports. A small tolerant tag scanner, not a full HTML parser.
//

import Foundation

enum SafariImporter {
    static func looksLikeNetscape(_ text: String) -> Bool {
        let head = text.prefix(4096).lowercased()
        return head.contains("netscape-bookmark-file") || (head.contains("<dl") && head.contains("<dt"))
    }

    static func parse(data: Data) throws -> ImportedData {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              looksLikeNetscape(text) else {
            throw ImportError.unrecognizedFormat
        }
        return parse(html: text)
    }

    static func parse(html: String) -> ImportedData {
        var scanner = Scanner(chars: Array(html))
        return ImportedData(bookmarks: scanner.run())
    }

    private struct Level {
        var title: String?
        var children: [ImportedNode] = []
    }

    private struct Scanner {
        let chars: [Character]
        var pos = 0

        init(chars: [Character]) { self.chars = chars }

        mutating func run() -> [ImportedNode] {
            var stack = [Level(title: nil)]
            var pendingTitle: String?

            while let tag = nextTag() {
                switch tag.name {
                case "h3":
                    pendingTitle = readText()
                case "dl":
                    stack.append(Level(title: pendingTitle))
                    pendingTitle = nil
                case "/dl":
                    collapse(&stack)
                case "a":
                    let text = readText()
                    if let href = tag.attributes["href"], let url = ImportedURL.web(Entities.decode(href)) {
                        stack[stack.count - 1].children.append(.link(title: text, url: url))
                    }
                default:
                    break
                }
            }
            while stack.count > 1 { collapse(&stack) }
            return stack[0].children
        }

        private func collapse(_ stack: inout [Level]) {
            guard stack.count > 1 else { return }
            let done = stack.removeLast()
            if let title = done.title {
                stack[stack.count - 1].children.append(.folder(title: title, children: done.children))
            } else {
                stack[stack.count - 1].children += done.children
            }
        }

        struct Tag {
            var name: String
            var attributes: [String: String]
        }

        /// Advance to the next `<...>` tag; skips comments and `<!DOCTYPE>`.
        mutating func nextTag() -> Tag? {
            while pos < chars.count {
                guard chars[pos] == "<" else { pos += 1; continue }
                let start = pos + 1
                guard start < chars.count else { return nil }
                if chars[start] == "!" || chars[start] == "?" {
                    skip(to: ">")
                    continue
                }
                guard let end = firstIndex(of: ">", from: start) else { return nil }
                pos = end + 1
                return parseTag(Array(chars[start..<end]))
            }
            return nil
        }

        /// Text up to the next closing or structural tag, with inline tags stripped and entities decoded.
        mutating func readText() -> String {
            var raw = ""
            while pos < chars.count {
                if chars[pos] == "<" {
                    guard let end = firstIndex(of: ">", from: pos + 1) else { pos = chars.count; break }
                    let tag = parseTag(Array(chars[(pos + 1)..<end]))
                    if ["/a", "/h3", "a", "h3", "dt", "dd", "dl", "/dl"].contains(tag.name) {
                        // Consume a matching closer; leave structural tags for the main loop.
                        if tag.name == "/a" || tag.name == "/h3" { pos = end + 1 }
                        break
                    }
                    pos = end + 1
                } else {
                    raw.append(chars[pos])
                    pos += 1
                }
            }
            return Entities.decode(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private mutating func skip(to terminator: Character) {
            if let end = firstIndex(of: terminator, from: pos) { pos = end + 1 } else { pos = chars.count }
        }

        private func firstIndex(of c: Character, from: Int) -> Int? {
            var i = from
            while i < chars.count { if chars[i] == c { return i }; i += 1 }
            return nil
        }

        private func parseTag(_ body: [Character]) -> Tag {
            var i = 0
            var name = ""
            while i < body.count, !body[i].isWhitespace { name.append(body[i]); i += 1 }
            var attrs: [String: String] = [:]
            while i < body.count {
                while i < body.count, body[i].isWhitespace || body[i] == "/" { i += 1 }
                var key = ""
                while i < body.count, !body[i].isWhitespace, body[i] != "=" { key.append(body[i]); i += 1 }
                while i < body.count, body[i].isWhitespace { i += 1 }
                var value = ""
                if i < body.count, body[i] == "=" {
                    i += 1
                    while i < body.count, body[i].isWhitespace { i += 1 }
                    if i < body.count, body[i] == "\"" || body[i] == "'" {
                        let quote = body[i]
                        i += 1
                        while i < body.count, body[i] != quote { value.append(body[i]); i += 1 }
                        i += 1
                    } else {
                        while i < body.count, !body[i].isWhitespace { value.append(body[i]); i += 1 }
                    }
                }
                if !key.isEmpty { attrs[key.lowercased()] = value }
            }
            return Tag(name: name.lowercased(), attributes: attrs)
        }
    }
}

enum Entities {
    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "ndash": "\u{2013}", "mdash": "\u{2014}", "hellip": "\u{2026}", "copy": "\u{00A9}",
    ]

    static func decode(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "&", let semi = s[i...].prefix(12).firstIndex(of: ";") {
                let name = String(s[s.index(after: i)..<semi])
                if let decoded = resolve(name) {
                    out += decoded
                    i = s.index(after: semi)
                    continue
                }
            }
            out.append(c)
            i = s.index(after: i)
        }
        return out
    }

    private static func resolve(_ name: String) -> String? {
        if name.hasPrefix("#") {
            let digits = name.dropFirst()
            let value = digits.first == "x" || digits.first == "X"
                ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits, radix: 10)
            return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        return named[name]
    }
}
