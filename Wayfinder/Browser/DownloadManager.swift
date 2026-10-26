//
//  DownloadManager.swift
//  Wayfinder
//

import AppKit
import Observation
import WebKit

@Observable
final class DownloadItem: Identifiable {
    enum State: Equatable {
        case downloading
        case finished
        case failed(String)
        case cancelled
    }

    let id = UUID()
    fileprivate(set) var filename: String
    fileprivate(set) var destination: URL?
    fileprivate(set) var state = State.downloading
    fileprivate(set) var fractionCompleted = 0.0
    fileprivate(set) var completedBytes: Int64 = 0
    fileprivate(set) var totalBytes: Int64 = 0

    @ObservationIgnored fileprivate let download: WKDownload
    @ObservationIgnored fileprivate var progressObservations: [NSKeyValueObservation] = []

    fileprivate init(download: WKDownload) {
        self.download = download
        filename = download.originalRequest?.url?.lastPathComponent ?? "Download"
    }

    var statusText: String {
        switch state {
        case .downloading:
            let completed = ByteCountFormatter.string(fromByteCount: completedBytes, countStyle: .file)
            guard totalBytes > 0 else { return completed }
            return "\(completed) of \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))"
        case .finished:
            return ByteCountFormatter.string(fromByteCount: max(completedBytes, totalBytes), countStyle: .file)
        case .failed(let message):
            return message
        case .cancelled:
            return "Cancelled"
        }
    }
}

@Observable
final class DownloadManager: NSObject, WKDownloadDelegate {
    static let shared = DownloadManager()

    /// Newest first.
    private(set) var items: [DownloadItem] = []

    var activeItems: [DownloadItem] {
        items.filter { $0.state == .downloading }
    }

    /// Combined progress of active downloads, or nil when none are running.
    var overallProgress: Double? {
        let active = activeItems
        guard !active.isEmpty else { return nil }
        return active.map(\.fractionCompleted).reduce(0, +) / Double(active.count)
    }

    func track(_ download: WKDownload) {
        download.delegate = self
        let item = DownloadItem(download: download)
        let progress = download.progress
        item.progressObservations = [
            progress.observe(\.fractionCompleted) { [weak item] progress, _ in
                let fraction = progress.fractionCompleted
                let completed = progress.completedUnitCount
                let total = progress.totalUnitCount
                Task { @MainActor [weak item] in
                    item?.fractionCompleted = fraction
                    item?.completedBytes = completed
                    item?.totalBytes = total
                }
            },
        ]
        items.insert(item, at: 0)
    }

    func cancel(_ item: DownloadItem) {
        item.download.cancel { _ in }
        item.state = .cancelled
        item.progressObservations = []
    }

    func reveal(_ item: DownloadItem) {
        guard let destination = item.destination else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    func open(_ item: DownloadItem) {
        guard item.state == .finished, let destination = item.destination else { return }
        NSWorkspace.shared.open(destination)
    }

    func clearInactive() {
        items.removeAll { $0.state != .downloading }
    }

    // MARK: WKDownloadDelegate

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        guard let item = item(for: download) else { return nil }
        let destination = Self.uniqueDestination(for: suggestedFilename)
        item.filename = destination.lastPathComponent
        item.destination = destination
        if response.expectedContentLength > 0 {
            item.totalBytes = response.expectedContentLength
        }
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let item = item(for: download) else { return }
        item.state = .finished
        item.fractionCompleted = 1
        item.progressObservations = []
        if let destination = item.destination {
            // Bounces the Downloads stack in the Dock, as Safari does.
            DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: destination.path)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
        guard let item = item(for: download), item.state != .cancelled else { return }
        item.state = .failed(error.localizedDescription)
        item.progressObservations = []
    }

    private func item(for download: WKDownload) -> DownloadItem? {
        items.first { $0.download === download }
    }

    private static func uniqueDestination(for suggestedFilename: String) -> URL {
        let directory = URL.downloadsDirectory
        let filename = suggestedFilename.isEmpty ? "Download" : suggestedFilename
        let base = (filename as NSString).deletingPathExtension
        let pathExtension = (filename as NSString).pathExtension

        var candidate = directory.appending(path: filename)
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = pathExtension.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(pathExtension)"
            candidate = directory.appending(path: name)
            counter += 1
        }
        return candidate
    }
}
