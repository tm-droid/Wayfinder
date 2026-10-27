import Foundation

/// A named section of ordinary tabs in one space's tab layout.
/// Its tabs remain ordinary tabs; their own group IDs describe membership.
struct TabGroup: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var collapsed: Bool
    /// The folder this one sits in. Nil: top level, and for a file from
    /// before nesting.
    var parent: UUID? = nil
}

extension TabGroup {
    private enum Keys: String, CodingKey { case id, name, collapsed, parent }

    /// A group saved without its folded state is an open one.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        collapsed = (try? c.decodeIfPresent(Bool.self, forKey: .collapsed)) ?? false
        parent = try? c.decodeIfPresent(UUID.self, forKey: .parent)
    }
}

/// Folders inside folders, three deep at most. Pure, so the rules are tested
/// without a window; Browser applies them.
extension TabGroup {
    static let maxDepth = 3

    /// 1 for a top-level folder. A parent chain that loops (a hand-edited
    /// file) stops past the cap rather than spinning.
    static func depth(of id: UUID, in groups: [TabGroup]) -> Int {
        var n = 1, at = groups.first { $0.id == id }?.parent
        while let up = at, n <= maxDepth + 1 {
            n += 1
            at = groups.first { $0.id == up }?.parent
        }
        return n
    }

    /// 1 for a folder with no folders in it; else one more than its deepest.
    static func height(of id: UUID, in groups: [TabGroup], seen: Set<UUID> = []) -> Int {
        guard !seen.contains(id) else { return 1 }
        let kids = groups.filter { $0.parent == id }.map { height(of: $0.id, in: groups, seen: seen.union([id])) }
        return 1 + (kids.max() ?? 0)
    }

    /// Whether `child` can go inside `parent` (nil: to the top level) without
    /// going into itself or past the depth cap with everything below it.
    static func canNest(_ child: UUID, under parent: UUID?, in groups: [TabGroup]) -> Bool {
        guard let parent else { return true }
        guard child != parent, groups.contains(where: { $0.id == child }) else { return false }
        var at: UUID? = parent
        while let up = at {
            if up == child { return false }
            at = groups.first { $0.id == up }?.parent
        }
        return depth(of: parent, in: groups) + height(of: child, in: groups) <= maxDepth
    }

    /// A folder taken away: what was in it moves up a level, to its parent,
    /// and is not deleted with it.
    static func removing(_ id: UUID, from groups: [TabGroup], pins: [PinDef] = []) -> (groups: [TabGroup], pins: [PinDef]) {
        let up = groups.first { $0.id == id }?.parent
        var out = groups.filter { $0.id != id }
        for i in out.indices where out[i].parent == id { out[i].parent = up }
        var held = pins
        for i in held.indices where held[i].group == id { held[i].group = up }
        return (out, held)
    }

    /// Hidden by a folded folder above it, however deep.
    static func hidden(_ id: UUID, in groups: [TabGroup]) -> Bool {
        var at = groups.first { $0.id == id }?.parent, steps = 0
        while let up = at, steps <= maxDepth {
            guard let g = groups.first(where: { $0.id == up }) else { return false }
            if g.collapsed { return true }
            at = g.parent
            steps += 1
        }
        return false
    }

    /// The folders that hold something (`held`: a tab's or a pin's folder),
    /// and the ones above them, which hold those.
    static func keeping(_ groups: [TabGroup], held: Set<UUID>) -> [TabGroup] {
        var keep = held
        for id in held {
            var at = groups.first { $0.id == id }?.parent, steps = 0
            while let up = at, steps <= maxDepth { keep.insert(up); at = groups.first { $0.id == up }?.parent; steps += 1 }
        }
        return groups.filter { keep.contains($0.id) }
    }
}

extension TabGroup {
    /// The number an extension knows the group by, as Chrome numbers its
    /// groups. Taken from the identifier, so it stays the same for as long
    /// as the group lasts, across launches too, with nothing to keep.
    static func number(_ id: UUID) -> Int {
        let u = id.uuid
        let n = Int(u.0 & 0x7F) << 24 | Int(u.1) << 16 | Int(u.2) << 8 | Int(u.3)
        return n == 0 ? 1 : n
    }
}
