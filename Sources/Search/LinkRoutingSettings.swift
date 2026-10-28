import SwiftUI

/// Settings › Spaces & Pins › Link Routing: where a link from another app
/// goes, by site. The first rule that fits wins; the order is the list's.
struct LinkRoutingSettings: View {
    @ObservedObject var browser: Browser
    @State private var rules: [LinkRule] = []
    @State private var pattern = ""

    private var profile: UUID { browser.profileID }

    var body: some View {
        GroupBlock(title: "Link Routing", icon: "arrow.triangle.branch") {
            Card {
                ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                    if index > 0 { Rule() }
                    row(index, rule)
                }
                if !rules.isEmpty { Rule() }
                HStack(spacing: 8) {
                    TextField("github.com or *.github.com", text: $pattern)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .onSubmit(add)
                    Pill("Add Rule", action: add)
                        .disabled(LinkRouter.normalize(host: pattern.replacingOccurrences(of: "*.", with: "")) == nil)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            Text("A link from another app goes by the first rule that fits its site. A rule for a Space that is gone opens in the current one.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
                .padding(.leading, 2)
        }
        .onAppear { rules = LinkRules.read(profile: profile) }
    }

    private func row(_ index: Int, _ rule: LinkRule) -> some View {
        HStack(spacing: 8) {
            Text(rule.pattern)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            Picker("", selection: Binding(get: { rule.target }, set: { set($0, at: index) })) {
                Text("Current Space").tag(LinkTarget.current)
                Text("Little window").tag(LinkTarget.little)
                ForEach(browser.spaces) { space in Text(space.name).tag(LinkTarget.space(space.id)) }
                // A target that is gone stays pickable as what it falls back to.
                if case .space(let id) = rule.target, !browser.spaces.contains(where: { $0.id == id }) {
                    Text("Deleted Space (current)").tag(rule.target)
                }
            }
            .labelsHidden()
            .fixedSize()
            Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                .disabled(index == 0)
            Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                .disabled(index == rules.count - 1)
            Button { remove(index) } label: { Image(systemName: "minus.circle") }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func add() {
        let text = pattern.trimmingCharacters(in: .whitespaces)
        let base = text.hasPrefix("*.") ? String(text.dropFirst(2)) : text
        guard let host = LinkRouter.normalize(host: base) else { return }
        rules.append(LinkRule(pattern: text.hasPrefix("*.") ? "*." + host : host, target: .current))
        pattern = ""
        save()
    }

    private func set(_ target: LinkTarget, at index: Int) {
        guard rules.indices.contains(index) else { return }
        rules[index].target = target
        save()
    }

    private func move(_ index: Int, by step: Int) {
        let to = index + step
        guard rules.indices.contains(index), rules.indices.contains(to) else { return }
        rules.swapAt(index, to)
        save()
    }

    private func remove(_ index: Int) {
        guard rules.indices.contains(index) else { return }
        rules.remove(at: index)
        save()
    }

    private func save() { LinkRules.write(rules, profile: profile) }
}
