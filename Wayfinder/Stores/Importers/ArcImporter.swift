//
//  ArcImporter.swift
//  Wayfinder
//
//  Arc `StorableSidebar.json`. Format is undocumented and may change, so
//  everything is read defensively; unknown or missing keys are skipped.
//  Key paths follow ivnvxd/arc-export: sidebar.containers[] -> container with
//  `spaces` + `items`; items is a flat array mixing id strings and objects
//  (objects have id, parentID, title, data.tab.savedURL/savedTitle or data.list);
//  space.newContainerIDs = [{"pinned":..}, id, {"unpinned":..}, id].
//  UNVERIFIED guesses: container `topAppsContainerIDs` for essentials,
//  space `customInfo.iconType.emoji_v2` and `windowTheme.primaryColorPalette`.
//

import Foundation

enum ArcImporter {
    static func looksLikeArc(_ json: Any) -> Bool {
        guard let root = json as? [String: Any], let sidebar = root["sidebar"] as? [String: Any] else { return false }
        return sidebar["containers"] is [Any]
    }

    static func parse(data: Data) throws -> ImportedData {
        guard let json = try? JSONSerialization.jsonObject(with: data), looksLikeArc(json) else {
            throw ImportError.unrecognizedFormat
        }
        return parse(json: json)
    }

    static func parse(json: Any) -> ImportedData {
        guard let sidebar = (json as? [String: Any])?["sidebar"] as? [String: Any],
              let containers = sidebar["containers"] as? [Any] else { return ImportedData() }

        var spaces: [ImportedSpace] = []
        for case let container as [String: Any] in containers {
            guard let rawSpaces = container["spaces"] as? [Any] else { continue }
            let items = (container["items"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
            let tree = Tree(items: items)
            let essentialIDs = (container["topAppsContainerIDs"] as? [Any] ?? []).compactMap { $0 as? String }
            let essentials = essentialIDs.flatMap { tree.nodes(under: $0) }

            let first = spaces.count
            var unnamed = 0
            for case let raw as [String: Any] in rawSpaces {
                var name = raw["title"] as? String ?? ""
                if name.isEmpty { unnamed += 1; name = "Space \(unnamed)" }
                var space = ImportedSpace(name: name)
                space.emoji = ((raw["customInfo"] as? [String: Any])?["iconType"] as? [String: Any])?["emoji_v2"] as? String
                space.colorHex = colorHex(raw)
                let ids = containerIDs(raw["newContainerIDs"] as? [Any] ?? [], marker: "pinned")
                space.pinned = ids.flatMap { tree.nodes(under: $0) }
                spaces.append(space)
            }
            if spaces.count > first, !essentials.isEmpty { spaces[first].essentials = essentials }
        }
        return ImportedData(spaces: spaces)
    }

    /// IDs following a `{marker: ...}` entry in an alternating [marker, id, ...] array.
    private static func containerIDs(_ array: [Any], marker: String) -> [String] {
        var ids: [String] = []
        for (i, entry) in array.enumerated() {
            guard let dict = entry as? [String: Any], dict[marker] != nil,
                  i + 1 < array.count, let id = array[i + 1] as? String else { continue }
            ids.append(id)
        }
        return ids
    }

    private static func colorHex(_ space: [String: Any]) -> String? {
        let theme = (space["customInfo"] as? [String: Any])?["windowTheme"] as? [String: Any]
        let palette = theme?["primaryColorPalette"] as? [String: Any]
        guard let mid = palette?["midTone"] as? [String: Any],
              let r = (mid["red"] as? NSNumber)?.doubleValue,
              let g = (mid["green"] as? NSNumber)?.doubleValue,
              let b = (mid["blue"] as? NSNumber)?.doubleValue else { return nil }
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    private struct Tree {
        var byID: [String: [String: Any]] = [:]
        var childrenOf: [String: [String]] = [:]

        init(items: [[String: Any]]) {
            for item in items {
                guard let id = item["id"] as? String else { continue }
                byID[id] = item
            }
            for item in items {
                guard let id = item["id"] as? String, let parent = item["parentID"] as? String else { continue }
                childrenOf[parent, default: []].append(id)
            }
            // Prefer the parent's explicit ordering when it has one.
            for (parent, kids) in childrenOf {
                guard let order = byID[parent]?["childrenIds"] as? [String] else { continue }
                var rank: [String: Int] = [:]
                for (i, id) in order.enumerated() where rank[id] == nil { rank[id] = i }
                childrenOf[parent] = kids.enumerated()
                    .sorted { (rank[$0.element] ?? Int.max, $0.offset) < (rank[$1.element] ?? Int.max, $1.offset) }
                    .map(\.element)
            }
        }

        func nodes(under parent: String, visited: Set<String> = []) -> [ImportedNode] {
            guard !visited.contains(parent) else { return [] }
            let seen = visited.union([parent])
            return (childrenOf[parent] ?? []).compactMap { id in
                guard let item = byID[id] else { return nil }
                let data = item["data"] as? [String: Any]
                if let tab = data?["tab"] as? [String: Any] {
                    guard let raw = tab["savedURL"] as? String, let url = ImportedURL.web(raw) else { return nil }
                    let custom = item["title"] as? String
                    let title = (custom?.isEmpty == false ? custom : tab["savedTitle"] as? String) ?? ""
                    return .link(title: title, url: url)
                }
                if data?["list"] != nil {
                    return .folder(title: item["title"] as? String ?? "", children: nodes(under: id, visited: seen))
                }
                return nil
            }
        }
    }
}
