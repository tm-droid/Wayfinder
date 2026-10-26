//
//  CommandBarView.swift
//  Wayfinder
//

import SwiftUI

/// The floating ⌘T / ⌘L bar, drawn over the whole window.
struct CommandBarView: View {
    let model: BrowserWindowModel

    @Environment(\.openWindow) private var openWindow
    @FocusState private var isFieldFocused: Bool

    private var bar: CommandBarState { model.commandBar }

    var body: some View {
        ZStack {
            if bar.isPresented {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { bar.dismiss() }
                    .transition(.opacity)

                panel
                    .frame(width: 640)
                    .transition(.scale(scale: 0.97).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.15), value: bar.isPresented)
    }

    private var panel: some View {
        @Bindable var bar = bar
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: bar.mode == .newTab ? "plus.magnifyingglass" : "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                TextField("Search or enter address", text: $bar.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22))
                    .focused($isFieldFocused)
                    .onSubmit { commit(inBackground: false) }
                    .onKeyPress(.upArrow) { bar.moveHighlight(by: -1); return .handled }
                    .onKeyPress(.downArrow) { bar.moveHighlight(by: 1); return .handled }
                    .onKeyPress(.tab) { bar.autocomplete(); return .handled }
                    .onKeyPress(.escape) { bar.dismiss(); return .handled }
                    .onKeyPress(.return) {
                        // Plain Return falls through to onSubmit.
                        guard NSEvent.modifierFlags.contains(.command) else { return .ignored }
                        commit(inBackground: true)
                        return .handled
                    }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            if !bar.items.isEmpty {
                Divider()
                results
                    .padding(8)
            }
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .onChange(of: bar.text) { model.refreshCommandBar() }
        .onChange(of: bar.presentCount, initial: true) {
            guard bar.isPresented else { return }
            isFieldFocused = true
            // Select the prefilled URL once the field has focus.
            DispatchQueue.main.async { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(bar.items.enumerated()), id: \.element.id) { index, item in
                if item.group.heading != nil, index == 0 || bar.items[index - 1].group != item.group {
                    Text(item.group.heading ?? "")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.top, index == 0 ? 2 : 8)
                        .padding(.bottom, 2)
                }
                CommandBarRow(item: item, isHighlighted: index == bar.highlightedIndex)
                    .onHover { if $0 { bar.highlightedIndex = index } }
                    .onTapGesture { run(item, inBackground: false) }
            }
        }
    }

    private func commit(inBackground: Bool) {
        if let item = bar.highlightedItem { run(item, inBackground: inBackground) }
    }

    private func run(_ item: CommandBarItem, inBackground: Bool) {
        model.commitCommandBar(item, inBackground: inBackground) {
            openWindow(id: WayfinderApp.historyWindowID)
        }
    }
}

private struct CommandBarRow: View {
    let item: CommandBarItem
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 22)
            Text(item.title)
                .lineLimit(1)
            if !item.subtitle.isEmpty {
                Text(item.subtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if let spaceIcon = item.spaceIcon {
                SpaceIcon(icon: spaceIcon, size: 14)
                    .foregroundStyle(.secondary)
            } else if isHighlighted {
                Text("\u{21A9}\u{FE0E}")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isHighlighted ? AnyShapeStyle(.selection.opacity(0.35)) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var icon: some View {
        if let url = item.url {
            SiteIcon(url: url, size: 18)
        } else {
            Image(systemName: item.symbol ?? "globe")
                .foregroundStyle(.secondary)
        }
    }
}
