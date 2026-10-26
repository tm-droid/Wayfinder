//
//  WebContainer.swift
//  Wayfinder
//

import AppKit
import SwiftUI
import WebKit

/// Hosts the selected tab's web view. Swapping tabs moves web views in and out,
/// so every tab keeps its page, scroll position and running scripts.
struct WebContainer: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard webView.superview !== container else { return }
        attach(to: container)
    }

    private func attach(to container: NSView) {
        container.subviews.forEach { $0.removeFromSuperview() }
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
        if webView.url != nil {
            container.window?.makeFirstResponder(webView)
        }
    }
}

/// Reports the NSWindow a view lives in.
struct WindowAccessor: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> ReportingView {
        let view = ReportingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ReportingView, context: Context) {
        view.onChange = onChange
    }

    final class ReportingView: NSView {
        var onChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onChange?(window)
        }
    }
}
