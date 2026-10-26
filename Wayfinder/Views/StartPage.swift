//
//  StartPage.swift
//  Wayfinder
//

import AppKit
import SwiftUI

/// Shown in tabs that have not loaded anything yet.
struct StartPage: View {
    let model: BrowserWindowModel

    @Environment(BookmarkStore.self) private var bookmarks
    @Environment(HistoryStore.self) private var history

    private let columns = [GridItem(.adaptive(minimum: 92, maximum: 110), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                header

                if !bookmarks.bookmarks.isEmpty {
                    section("Favorites") {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                            ForEach(bookmarks.bookmarks) { bookmark in
                                FavoriteTile(url: bookmark.url, title: bookmark.displayTitle) {
                                    model.open(bookmark.url, inNewTab: NSEvent.modifierFlags.contains(.command))
                                }
                            }
                        }
                    }
                }

                let recent = history.recentSites(limit: 8)
                if !recent.isEmpty {
                    section("Recently Visited") {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                            ForEach(recent) { entry in
                                FavoriteTile(url: entry.url, title: entry.displayTitle) {
                                    model.open(entry.url, inNewTab: NSEvent.modifierFlags.contains(.command))
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 56)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.10), Color(nsColor: .windowBackgroundColor)],
                startPoint: .top, endPoint: .center
            )
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("Where to next?")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Type in the address bar to search or enter a website.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.semibold))
            content()
        }
    }
}

private struct FavoriteTile: View {
    let url: URL
    let title: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                SiteIcon(url: url, size: 36)
                    .frame(width: 68, height: 68)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.separator.opacity(0.6))
                    }
                    .shadow(color: .black.opacity(isHovering ? 0.12 : 0.05), radius: isHovering ? 8 : 3, y: 2)
                    .scaleEffect(isHovering ? 1.05 : 1)
                Text(title)
                    .font(.callout)
                    .lineLimit(1)
                    .frame(maxWidth: 92)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.snappy(duration: 0.15)) { isHovering = hovering }
        }
        .help(url.absoluteString)
    }
}

struct ErrorPage: View {
    let error: BrowserTab.LoadError
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("Wayfinder can’t open this page")
                .font(.title2.weight(.semibold))
            Text(error.message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let url = error.url {
                Text(url.absoluteString)
                    .font(.callout.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
