//
//  DownloadsPopover.swift
//  Wayfinder
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DownloadsButton: View {
    @Bindable var model: BrowserWindowModel

    @Environment(DownloadManager.self) private var downloads

    var body: some View {
        Button {
            model.isDownloadsPresented.toggle()
        } label: {
            if let progress = downloads.overallProgress {
                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .frame(width: 16, height: 16)
            } else {
                Label("Downloads", systemImage: "arrow.down.circle")
            }
        }
        .help("Show Downloads")
        .popover(isPresented: $model.isDownloadsPresented, arrowEdge: .bottom) {
            DownloadsList()
        }
    }
}

private struct DownloadsList: View {
    @Environment(DownloadManager.self) private var downloads

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Downloads")
                    .font(.headline)
                Spacer()
                Button("Clear") { downloads.clearInactive() }
                    .controlSize(.small)
                    .disabled(downloads.items.allSatisfy { $0.state == .downloading })
            }
            .padding(12)

            Divider()

            if downloads.items.isEmpty {
                Text("No downloads")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(downloads.items) { item in
                            DownloadRow(item: item)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
        }
        .frame(width: 360)
    }
}

private struct DownloadRow: View {
    let item: DownloadItem

    @Environment(DownloadManager.self) private var downloads

    var body: some View {
        HStack(spacing: 10) {
            fileIcon
                .resizable()
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.filename)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if item.state == .downloading {
                    ProgressView(value: item.fractionCompleted)
                        .controlSize(.small)
                }
                Text(item.statusText)
                    .font(.caption)
                    .foregroundStyle(isFailure ? Color.red : Color.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if item.state == .downloading {
                Button {
                    downloads.cancel(item)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Cancel")
            } else if item.state == .finished {
                Button {
                    downloads.reveal(item)
                } label: {
                    Image(systemName: "magnifyingglass.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Show in Finder")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { downloads.open(item) }
    }

    private var fileIcon: Image {
        if item.state == .finished, let destination = item.destination {
            return Image(nsImage: NSWorkspace.shared.icon(forFile: destination.path))
        }
        let type = UTType(filenameExtension: (item.filename as NSString).pathExtension) ?? .data
        return Image(nsImage: NSWorkspace.shared.icon(for: type))
    }

    private var isFailure: Bool {
        if case .failed = item.state { return true }
        return false
    }
}
