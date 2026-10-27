import AppKit
import WebKit
import XCTest
@testable import Search

/// A boost script in a real web view, on a page whose CSP forbids all but its
/// own scripts: it runs where its boost names, not elsewhere, and cannot
/// close its wrapper to get out of the check.
@MainActor
final class BoostPageTests: XCTestCase {
    private var server: LocalPageServer!

    override func setUp() async throws {
        try await super.setUp()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        server = try LocalPageServer([
            "/csp": .init(type: "text/html", headers: ["Content-Security-Policy: script-src 'self'"],
                          body: "<!doctype html><title>csp</title><p>hello</p>"),
        ])
    }

    override func tearDown() async throws {
        server.stop()
        server = nil
        try await super.tearDown()
    }

    private final class Done: NSObject, WKNavigationDelegate {
        var finish: (() -> Void)?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish?(); finish = nil }
    }

    /// What `attribute` of the root is after `boost` is applied to `url`.
    private func attribute(_ name: String, of boost: Boost, at url: URL) async throws -> String? {
        let boosts = Boosts(file: nil)
        XCTAssertTrue(boosts.save(boost))
        let config = WKWebViewConfiguration()
        for injection in boosts.injections(host: url.host(), shy: false) { config.userContentController.addUserScript(injection.userScript) }
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 300, height: 200), configuration: config)
        let done = Done()
        web.navigationDelegate = done
        await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in
            done.finish = { k.resume() }
            web.load(URLRequest(url: url))
        }
        return try await web.evaluateJavaScript("document.documentElement.getAttribute('\(name)')") as? String
    }

    private func boost(_ js: String, host: String) -> Boost {
        var b = Boost(name: "T", hosts: [host])
        b.subdomains = false
        b.js = js
        return b
    }

    func testScriptRunsOnACSPPageAtItsHostAndNotElsewhere() async throws {
        let js = "document.documentElement.setAttribute('data-boost', 'ran');"
        let here = server.url("/csp")
        XCTAssertEqual(here.host(), "127.0.0.1")
        let ran = try await attribute("data-boost", of: boost(js, host: "127.0.0.1"), at: here)
        XCTAssertEqual(ran, "ran", "a boost script works under script-src 'self'")

        // The same boost, named for a host the page is not on, is not run:
        // the page-side check refuses even where it was injected.
        let other = boost(js, host: "example.com")
        let injected = Boosts(file: nil)
        injected.save(other)
        let source = try XCTUnwrap(injected.injections(host: "example.com", shy: false).first { $0.isScript }?.source)
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: Boosts.world))
        let web = WKWebView(frame: .zero, configuration: config)
        let done = Done()
        web.navigationDelegate = done
        await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in
            done.finish = { k.resume() }
            web.load(URLRequest(url: here))
        }
        let none = try await web.evaluateJavaScript("document.documentElement.getAttribute('data-boost')") as? String
        XCTAssertNil(none, "a script for another host does not run here")
    }

    func testScriptCannotCloseTheWrapperToSkipTheHostCheck() async throws {
        let breakout = "} catch (e) {} })(); document.documentElement.setAttribute('data-escaped', '1'); (function () { try {"
        let injected = Boosts(file: nil)
        injected.save(boost(breakout, host: "example.com"))
        let source = try XCTUnwrap(injected.injections(host: "example.com", shy: false).first { $0.isScript }?.source)
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: Boosts.world))
        let web = WKWebView(frame: .zero, configuration: config)
        let done = Done()
        web.navigationDelegate = done
        await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in
            done.finish = { k.resume() }
            web.load(URLRequest(url: server.url("/csp")))
        }
        let escaped = try await web.evaluateJavaScript("document.documentElement.getAttribute('data-escaped')") as? String
        XCTAssertNil(escaped)
    }
}
