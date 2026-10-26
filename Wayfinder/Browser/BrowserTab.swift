//
//  BrowserTab.swift
//  Wayfinder
//

import AppKit
import Observation
import UniformTypeIdentifiers
import WebKit

/// One tab: a WKWebView plus the observable state the UI shows for it.
@Observable
final class BrowserTab: NSObject, Identifiable {
    struct LoadError: Equatable {
        let url: URL?
        let message: String
    }

    static let zoomLevels: [Double] = [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    let id = UUID()
    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored weak var owner: BrowserWindowModel?
    /// The tab this one was opened from, used to place new tabs next to their opener.
    @ObservationIgnored var openerID: BrowserTab.ID?

    private(set) var title = ""
    private(set) var url: URL?
    private(set) var isLoading = false
    private(set) var estimatedProgress = 0.0
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var hasOnlySecureContent = false
    private(set) var themeColor: NSColor?
    private(set) var zoom = 1.0
    private(set) var loadError: LoadError?

    /// Set for tabs opened by a page script, which load right after creation.
    @ObservationIgnored private var isAwaitingOpenerLoad: Bool
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init(configuration: WKWebViewConfiguration? = nil) {
        isAwaitingOpenerLoad = configuration != nil
        webView = WKWebView(frame: .zero, configuration: configuration ?? Self.makeConfiguration())
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.isInspectable = true
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        observeWebView()
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        if let url { return AddressInput.displayString(for: url) }
        return "New Tab"
    }

    var showsStartPage: Bool {
        url == nil && !isLoading && !isAwaitingOpenerLoad
    }

    var isSecure: Bool {
        url?.scheme == "https" && hasOnlySecureContent
    }

    // MARK: Navigation

    func load(_ url: URL) {
        loadError = nil
        webView.load(URLRequest(url: url))
    }

    func reload() {
        if let failedURL = loadError?.url {
            load(failedURL)
        } else {
            webView.reload()
        }
    }

    func stopLoading() {
        webView.stopLoading()
    }

    func goBack() {
        loadError = nil
        webView.goBack()
    }

    func goForward() {
        loadError = nil
        webView.goForward()
    }

    func go(to item: WKBackForwardListItem) {
        loadError = nil
        webView.go(to: item)
    }

    // MARK: Zoom

    var canZoomIn: Bool { zoom < Self.zoomLevels.last! }
    var canZoomOut: Bool { zoom > Self.zoomLevels.first! }

    func zoomIn() {
        setZoom(Self.zoomLevels.first { $0 > zoom + 0.001 } ?? zoom)
    }

    func zoomOut() {
        setZoom(Self.zoomLevels.last { $0 < zoom - 0.001 } ?? zoom)
    }

    func resetZoom() {
        setZoom(1)
    }

    private func setZoom(_ value: Double) {
        zoom = value
        webView.pageZoom = value
    }

    // MARK: Find

    /// Selects and scrolls to the next match. Returns false when nothing matches.
    func find(_ text: String, backwards: Bool = false) async -> Bool {
        guard !text.isEmpty else { return true }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        let result = try? await webView.find(text, configuration: configuration)
        return result?.matchFound ?? false
    }

    // MARK: Export and print

    func exportPDF() async {
        guard let window = webView.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (title.isEmpty ? "Page" : Self.sanitizedFilename(title)) + ".pdf"
        guard await panel.beginSheetModal(for: window) == .OK, let destination = panel.url else { return }
        do {
            let data = try await webView.pdf()
            try data.write(to: destination, options: .atomic)
        } catch {
            await presentAlert(message: "The PDF could not be saved.", informativeText: error.localizedDescription)
        }
    }

    func print() {
        guard let window = webView.window else { return }
        let operation = webView.printOperation(with: NSPrintInfo.shared)
        operation.view?.frame = webView.bounds
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    /// Stops media and loads before the tab is thrown away.
    func tearDown() {
        observations.removeAll()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
        Task { [webView] in
            await webView.closeAllMediaPresentations()
            await webView.pauseAllMediaPlayback()
        }
    }

    // MARK: Private

    private static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        // Sites serve their best experience to Safari-compatible user agents.
        configuration.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.preferences.isFraudulentWebsiteWarningEnabled = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        return configuration
    }

    private func observeWebView() {
        observations = [
            webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
                guard let self else { return }
                title = webView.title ?? ""
                if let url = webView.url {
                    HistoryStore.shared.updateTitle(title, for: url)
                }
            },
            webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
                self?.url = webView.url
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
                guard let self else { return }
                isLoading = webView.isLoading
                if isLoading { isAwaitingOpenerLoad = false }
            },
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
                self?.estimatedProgress = webView.estimatedProgress
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
                self?.canGoBack = webView.canGoBack
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
                self?.canGoForward = webView.canGoForward
            },
            webView.observe(\.hasOnlySecureContent, options: [.initial, .new]) { [weak self] webView, _ in
                self?.hasOnlySecureContent = webView.hasOnlySecureContent
            },
            webView.observe(\.themeColor, options: [.initial, .new]) { [weak self] webView, _ in
                self?.themeColor = webView.themeColor
            },
        ]
    }

    private func loadFavicon() async {
        guard let pageURL = webView.url, pageURL.scheme == "http" || pageURL.scheme == "https" else { return }
        let script = """
            const links = [...document.querySelectorAll('link[rel~="icon"], link[rel="apple-touch-icon"]')];
            const size = link => Math.max(0, ...(link.sizes ? [...link.sizes].map(s => parseInt(s) || 0) : [0]));
            return links
                .filter(link => link.href && !link.href.endsWith('.svg'))
                .sort((a, b) => size(b) - size(a))
                .map(link => link.href);
            """
        let hrefs = (try? await webView.callAsyncJavaScript(script, contentWorld: .defaultClient)) as? [String] ?? []
        await FaviconLoader.shared.load(for: pageURL, candidates: hrefs.compactMap(URL.init(string:)))
    }

    @discardableResult
    private func presentAlert(message: String, informativeText: String? = nil, configure: (NSAlert) -> Void = { _ in }) async -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = message
        if let informativeText { alert.informativeText = informativeText }
        configure(alert)
        if let owner, owner.selectedTabID != id {
            owner.select(self)
        }
        if let window = webView.window ?? owner?.window {
            return await alert.beginSheetModal(for: window)
        }
        return alert.runModal()
    }

    private static func alertTitle(for frame: WKFrameInfo) -> String {
        let host = frame.securityOrigin.host
        return host.isEmpty ? "This page says:" : "“\(host)” says:"
    }

    private static func sanitizedFilename(_ name: String) -> String {
        String(name.map { "/:\\".contains($0) ? "-" : $0 }.prefix(120))
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        let error = error as NSError
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return true }
        // Frame load interrupted by policy change: the navigation became a download.
        if error.domain == "WebKitErrorDomain" && error.code == 102 { return true }
        return false
    }
}

// MARK: - WKNavigationDelegate

extension BrowserTab: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if navigationAction.shouldPerformDownload {
            return .download
        }

        let isLinkClick = navigationAction.navigationType == .linkActivated
        let wantsNewTab = navigationAction.modifierFlags.contains(.command) || navigationAction.buttonNumber == 2
        if isLinkClick, wantsNewTab, let url = navigationAction.request.url {
            owner?.openTab(with: url, after: self, select: navigationAction.modifierFlags.contains(.shift))
            return .cancel
        }

        if let url = navigationAction.request.url, let scheme = url.scheme?.lowercased(),
           !["http", "https", "about", "data", "blob", "file", "javascript"].contains(scheme) {
            // mailto:, tel:, facetime: and friends belong to other apps. Only follow them on a click.
            if isLinkClick || navigationAction.navigationType == .formSubmitted {
                NSWorkspace.shared.open(url)
            }
            return .cancel
        }

        return .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if !navigationResponse.canShowMIMEType {
            return .download
        }
        if navigationResponse.isForMainFrame, let response = navigationResponse.response as? HTTPURLResponse,
           let disposition = response.value(forHTTPHeaderField: "Content-Disposition"),
           disposition.lowercased().hasPrefix("attachment") {
            return .download
        }
        return .allow
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        DownloadManager.shared.track(download)
        owner?.showDownloads()
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        DownloadManager.shared.track(download)
        owner?.showDownloads()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadError = nil
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        loadError = nil
        zoom = webView.pageZoom
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url {
            HistoryStore.shared.recordVisit(url: url, title: webView.title ?? "")
        }
        owner?.saveSession()
        Task { await loadFavicon() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        guard !Self.isCancellation(error) else { return }
        let failedURL = (error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL
        loadError = LoadError(url: failedURL ?? webView.url, message: error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        guard !Self.isCancellation(error) else { return }
        loadError = LoadError(url: webView.url, message: error.localizedDescription)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

// MARK: - WKUIDelegate

extension BrowserTab: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        owner?.openPopup(configuration: configuration, after: self).webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        owner?.close(self)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        await presentAlert(message: Self.alertTitle(for: frame), informativeText: message)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        let response = await presentAlert(message: Self.alertTitle(for: frame), informativeText: message) { alert in
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
        }
        return response == .alertFirstButtonReturn
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo
    ) async -> String? {
        let field = NSTextField(string: defaultText ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        let response = await presentAlert(message: Self.alertTitle(for: frame), informativeText: prompt) { alert in
            alert.accessoryView = field
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            alert.window.initialFirstResponder = field
        }
        return response == .alertFirstButtonReturn ? field.stringValue : nil
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        if let window = webView.window {
            return await panel.beginSheetModal(for: window) == .OK ? panel.urls : nil
        }
        return panel.runModal() == .OK ? panel.urls : nil
    }
}
