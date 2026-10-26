//
//  ChromeImporter.swift
//  Wayfinder
//
//  Chrome / Edge / Brave / Chromium `Bookmarks` JSON.
//

import Foundation

enum ChromeImporter {
    static func looksLikeChrome(_ json: Any) -> Bool {
        guard let root = json as? [String: Any], let roots = root["roots"] as? [String: Any] else { return false }
        return roots["bookmark_bar"] != nil || roots["other"] != nil
    }

    static func parse(data: Data) throws -> ImportedData {
        guard let json = try? JSONSerialization.jsonObject(with: data), looksLikeChrome(json) else {
            throw ImportError.unrecognizedFormat
        }
        return parse(json: json)
    }

    static func parse(json: Any) -> ImportedData {
        guard let roots = (json as? [String: Any])?["roots"] as? [String: Any] else { return ImportedData() }
        var result: [ImportedNode] = []
        for key in ["bookmark_bar", "other", "synced"] {
            guard let root = roots[key] as? [String: Any] else { continue }
            let children = nodes(in: root)
            guard !children.isEmpty else { continue }
            if key == "bookmark_bar" {
                result += children
            } else {
                let name = (root["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? key
                result.append(.folder(title: name, children: children))
            }
        }
        return ImportedData(bookmarks: result)
    }

    private static func nodes(in folder: [String: Any]) -> [ImportedNode] {
        guard let children = folder["children"] as? [[String: Any]] else { return [] }
        return children.compactMap { child in
            let title = child["name"] as? String ?? ""
            switch child["type"] as? String {
            case "url":
                guard let raw = child["url"] as? String, let url = ImportedURL.web(raw) else { return nil }
                return .link(title: title, url: url)
            case "folder":
                return .folder(title: title, children: nodes(in: child))
            default:
                return nil
            }
        }
    }
}
