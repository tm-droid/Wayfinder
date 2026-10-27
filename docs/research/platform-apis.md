# Platform API research (Liquid Glass, privacy report, WKContentRuleList)

Date: 2026-10-27. Target: macOS 14+ deployment, macOS 26 SDK, runs on macOS 27.
Verification legend: [V] verified against primary source this session; [U] unverified / from memory or secondary sources.

---

## 1. Liquid Glass on macOS 26+

### 1.1 SwiftUI API [V signature via Apple docs summary; details U]

```swift
func glassEffect<S: Shape>(_ glass: Glass = .regular, in shape: S = DefaultGlassEffectShape()) -> some View
```
- `Glass` variants: `.regular` (default), `.clear` (more transparent; use over media-rich content, needs dimming layer), `.identity` [U].
- Modifiers on `Glass` (chainable): `.tint(_ color: Color?)`, `.interactive(_ isEnabled: Bool = true)`.
  Interactive = scale/bounce/shimmer on press; intended for controls, not static chrome.
- Button styles: `.buttonStyle(.glass)` and `.buttonStyle(.glassProminent)`.
- `GlassEffectContainer(spacing:) { ... }`: groups glass shapes so they render in one pass and can blend/morph. Glass cannot sample other glass, so siblings of glass must live in one container.
- `glassEffectID(_:in:)` with `@Namespace`: morphing transitions between glass views inside a container when inserted/removed with animation.
- `glassEffectUnion(id:namespace:)`: merges several views into one glass shape [U].
- `.backgroundExtensionEffect()`: mirrors+blurs content under sidebar/inspector edges so content appears to extend beneath glass (use on hero/content views behind a floating sidebar).
- `.scrollEdgeEffectStyle(.soft/.hard, for:)`, `.safeAreaBar` [U] for scroll-edge treatment under toolbars.

```swift
struct Chrome: View {
    @Namespace private var ns
    @State private var expanded = false
    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button("Back", systemImage: "chevron.left") {}
                    .glassEffect(.regular.interactive(), in: .circle)
                    .glassEffectID("back", in: ns)
                if expanded {
                    Button("Reader", systemImage: "doc.text") {}
                        .glassEffect(.regular.tint(.blue.opacity(0.4)).interactive())
                        .glassEffectID("reader", in: ns)
                }
            }
        }
        .animation(.bouncy, value: expanded)
    }
}
```

### 1.2 AppKit API [mostly V via secondary sources; `style` U]

- `NSGlassEffectView : NSView` (macOS 26). Properties:
  - `contentView: NSView?` — put your content here; the view embeds it and sizes glass around it. Do NOT add subviews directly (glass won't lay out/vibrancy breaks).
  - `cornerRadius: CGFloat`
  - `tintColor: NSColor?`
  - `style: NSGlassEffectView.Style` (`.regular`, `.clear`) — exists in later 26.x SDK per my memory; search results did not confirm it. [U] Check header in your SDK: `grep -n style $(xcrun --show-sdk-path)/System/Library/Frameworks/AppKit.framework/Headers/NSGlassEffectView.h`.
- `NSGlassEffectContainerView : NSView` — `contentView`, `spacing: CGFloat` (merge distance; sibling glass views within this distance visually merge). Put multiple `NSGlassEffectView`s inside its content view.
- Hosting SwiftUI glass in AppKit: `NSHostingView` works; SwiftUI `.glassEffect` inside it composites correctly. Mixed trees: prefer one technology per glass cluster (container must contain all siblings).

```swift
@available(macOS 26, *)
func makeGlassBar(content: NSView) -> NSView {
    let glass = NSGlassEffectView()
    glass.cornerRadius = 14
    glass.tintColor = NSColor.controlAccentColor.withAlphaComponent(0.15)
    glass.contentView = content
    return glass
}

@available(macOS 26, *)
func makeCluster(_ views: [NSView]) -> NSView {
    let container = NSGlassEffectContainerView()
    container.spacing = 20
    let stack = NSStackView(views: views.map { v in
        let g = NSGlassEffectView(); g.contentView = v; g.cornerRadius = 12; return g
    })
    container.contentView = stack
    return container
}
```

### 1.3 Where to use glass (HIG-aligned)
- Glass = navigation/control layer floating ABOVE content: toolbars, tab/sidebar chrome, popovers, floating controls (e.g. URL bar capsule, find bar, command bar).
- Never put glass on content itself (web page, lists of rows), and don't stack glass on glass (use container; no glass-in-glass).
- Use `.regular` by default; `.clear` only over rich imagery/video with a dimming layer; tint only to convey primary action/state, not decoration.
- Keep content legible: prefer system colors/vibrancy on glass; avoid custom opaque backgrounds on toolbar items (they fight the effect).

### 1.4 Sidebars and toolbars
- Standard path: `NSSplitViewController` + `NSSplitViewItem(sidebarWithViewController:)`. On macOS 26 the sidebar item automatically renders as floating glass inset from the window edge; content extends beneath it. Don't paint an opaque background behind it.
- For content beneath sidebar edges: `NSSplitViewItem` content gets automatic extension; for custom content use `.backgroundExtensionEffect()` (SwiftUI) or the AppKit equivalent `NSBackgroundExtensionView` [U name — verify in SDK].
- Toolbars: `NSToolbar` items get glass grouping automatically; `NSToolbarItemGroup`/`NSSharingServicePickerToolbarItem` group visually; use `NSToolbarItem.isBordered`, and `NSToolbarItem.style = .prominent` [U] for tinted primary.
- Scroll edge effect: `NSScrollView.topEdgeEffectStyle` / `NSScrollPocket` [U] — AppKit adds soft edge blur under toolbar automatically for scroll views under the titlebar.
- Custom titlebar/frameless window designs lose most of this; if the browser draws its own chrome, wrap it in `NSGlassEffectView` manually.
- Behaviour on macOS 27 builds linked against the 26 SDK: Apple allowed opting out of the new look via `UIDesignRequiresCompatibility` in Info.plist on 26; whether macOS 27 still honours it is [U] — don't rely on it.

### 1.5 Accessibility: Reduce Transparency / Increase Contrast
- System handles most of it: glass becomes frostier/more opaque automatically under Reduce Transparency, and adds borders under Increase Contrast. Don't re-implement unless you draw custom translucent surfaces.
- For custom surfaces:
  - AppKit: `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency`, `.accessibilityDisplayShouldIncreaseContrast`, `.accessibilityDisplayShouldReduceMotion`; observe `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` (post on `NSWorkspace.shared.notificationCenter`).
  - SwiftUI: `@Environment(\.accessibilityReduceTransparency)`, `\.accessibilityReduceMotion`, `\.colorSchemeContrast` (`.increased`). [V names are stable public API]

```swift
struct AdaptiveGlass<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceT
    let shape: S
    func body(content: Content) -> some View {
        if #available(macOS 26, *), !reduceT {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)   // opaque-ish fallback
        }
    }
}
```

### 1.6 Availability gating (deployment target 14)
- Wrap every glass symbol; SwiftUI modifiers can't be conditionally applied inline, so use a `ViewModifier` or `@ViewBuilder` extension:

```swift
extension View {
    @ViewBuilder func wfGlass<S: Shape>(_ shape: S, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}
```
- AppKit: `if #available(macOS 26, *) { NSGlassEffectView } else { NSVisualEffectView(material: .sidebar/.headerView) }`. Keep a single factory function returning `NSView`.
- `@available(macOS 26, *)` on types that hold `NSGlassEffectView` stored properties.

### 1.7 Pitfalls / performance
- Each glass layer samples+blurs what's behind it in real time; many separate glass views = many offscreen passes. Use `GlassEffectContainer` / `NSGlassEffectContainerView` to batch.
- Glass over a live `WKWebView` (video, scrolling) forces continuous re-render behind the glass; keep glass areas small and out of full-window overlays. Test with Instruments (Core Animation / Metal System Trace).
- Don't animate `cornerRadius`/frame of glass views every frame; use `glassEffectID` morphs.
- `.interactive()` on non-tappable surfaces gives misleading affordance.
- Adding subviews directly to `NSGlassEffectView` instead of `contentView` produces wrong clipping/vibrancy.
- `.clear` glass over light web pages has poor contrast; add dimming.
- Tinting stacked on dark/light mode: re-check both appearances.
- Sidebar overlay and `.backgroundExtensionEffect` can read as "double content"; apply only to decorative/hero content, not text.
- Window corner radii in 26 are larger and concentric; use `NSView`/SwiftUI `ConcentricRectangle` [U] or `.containerRelativeShape` for nested shapes.

Sources:
- https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)
- https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- https://developer.apple.com/documentation/appkit/nsglasseffectview
- https://developer.apple.com/documentation/appkit/nsglasseffectcontainerview
- https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- WWDC25 "Build an AppKit app with the new design" (session 310), "Meet Liquid Glass" (219), "Build a SwiftUI app with the new design" (323)

---

## 2. Privacy report estimation without hit counts

### 2.1 Is there a public per-rule action callback? NO.
- Public `WKNavigationDelegate.h` (WebKit main, checked via raw GitHub) contains zero occurrences of `contentRuleList`. [V]
- The callbacks exist only as SPI in `WKNavigationDelegatePrivate.h` [V, current main]:
  ```objc
  - (void)_webView:(WKWebView *)webView URL:(NSURL *)url contentRuleListIdentifiers:(NSArray<NSString *> *)identifiers notifications:(NSArray<NSString *> *)notifications; // macos 10.13.4
  - (void)_webView:(WKWebView *)webView contentRuleListWithIdentifier:(NSString *)identifier performedAction:(_WKContentRuleListAction *)action forURL:(NSURL *)url; // macos 10.15
  ```
- `_WKContentRuleListAction` exposes `blockedLoad`, `blockedCookies`, `madeHTTPS`, `redirected`, `modifiedHeaders`, `notifications` (from WebKit source/tests). Used by Tools/TestWebKitAPI (TestNavigationDelegate).
- Using SPI: private-selector delegate methods are discovered via `respondsToSelector:` on your navigation delegate, so implementing `@objc(_webView:contentRuleListWithIdentifier:performedAction:forURL:)` works at runtime. Consequences: App Store rejection risk (this browser is presumably direct-distributed; confirm), may break between OS releases, needs `NSObject`-typed action param (`Any`/`NSObject`) and KVC/`perform` to read `blockedLoad`. Zero public-API alternative produces counts.
- Related public-ish mechanism: a rule action `{"type":"notify"}`... in WebKit "notify" is surfaced only through the SPI `notifications` array above. Not public.
- `WKContentRuleList` / `WKContentRuleListStore` public API has no counters, no events. [V via Apple docs search]

### 2.2 Public alternatives and limits
1. **User script + PerformanceObserver / `performance.getEntriesByType('resource')`**
   - Blocked requests never produce resource-timing entries (the load is cancelled before network), so you can only see what was NOT blocked. Cross-origin entries expose limited timing but DO list the URL (`name`), so you can match remaining trackers that slipped through (useful for "trackers still contacted").
   - Does not cover requests in sub-frames from other origins (inject with `forMainFrameOnly: false`), service/shared workers, `sendBeacon` (appears), or CSS-initiated loads (appear). Page's own CSP/no timing-allow-origin does not hide `name`.
2. **Detect blocking from the page side**: wrap `fetch`/`XMLHttpRequest`/`Image.onerror`/`script.onerror` and count errors for hosts on a tracker list. A content-rule block fails with a network error (`TypeError: Load failed`), indistinguishable from a real failure, but combined with "host in tracker list" it's a good estimate. Must inject at `.atDocumentStart` in all frames; page can tamper; DOM-inserted `<script>/<img>` elements need a MutationObserver + `error` listener (capture phase on `window` catches element error events).
3. **Offline estimate from your own rule list**: at navigation commit, don't count; instead use `WKNavigationDelegate`'s `decidePolicyFor navigationAction` for main/subframe navigations (public) only — covers frames, not subresources.
4. **`WKURLSchemeHandler`**: only for custom schemes, not http(s). Not useful.
5. **Local proxy / `NEFilter`/`NEAppProxy`**: heavy, not appropriate.
6. **`WKWebView` `_WKWebsiteDataStore` resource-load statistics** (SPI): ITP data (`_getResourceLoadStatisticsDataSummary`-style) – private, same risk as 2.1.

### 2.3 Tracker lists and licensing
- DuckDuckGo Tracker Radar (https://github.com/duckduckgo/tracker-radar): data licensed CC BY-NC-SA 4.0 (non-commercial, share-alike). Code is Apache-2.0. Commercial/redistributed use needs care. [U — confirm in repo LICENSE]
- Disconnect `services.json` (https://github.com/disconnectme/disconnect-tracking-protection): GPL-3.0 for the lists in repo; Disconnect also offers separate commercial licensing. [U — confirm]
- EasyList/EasyPrivacy: dual-licensed GPLv3+ / CC BY-SA 3.0. Using as rules in a bundled product → comply with attribution/share-alike. [U]
- WebKit's own `ResourceLoadStatistics` use no public list; Safari 's list comes from on-device learning.

### 2.4 How Safari's Privacy Report counts [from Apple Support docs; U on internals]
- Two numbers: "websites that contacted trackers" (sites visited in last 30 days where a known tracker was contacted) and "trackers prevented from profiling you" (trackers ITP identified that were contacted and had their ability limited—cookies/storage partitioned/blocked, IP hidden when enabled).
- It is driven by ITP's on-device `ResourceLoadStatistics` classification (prevalent cross-site resources + Apple's tracker list), NOT by content-blocker hit counts. Content blockers' blocks are not reported in the Privacy Report.
- Hence "trackers contacted" is a per-site-per-tracker-domain set, not per-request counts.

### 2.5 Recommendation (most accurate public approach)
Combine, in order of accuracy:
1. **Primary: page-side instrumentation** (user script at document start, all frames) that records per-request outcome for every subresource using `PerformanceObserver` (successes, with URL) AND `error` capture listener + fetch/XHR wrappers (failures), classifying each URL's registrable domain (eTLD+1) against a bundled tracker-domain map (Tracker Radar category data or your own rules). Count "blocked" = failed requests to listed tracker domains; "contacted" = succeeded ones. Post via `WKScriptMessageHandler` (`WKContentWorld` isolated world can't see the page's `fetch`, so wrap in `.page` world, or use `error` capture listener in the isolated world which does receive DOM events).
2. Fallback/validation: static analysis of the page's initial DOM scripts against the list.
3. Treat as an **estimate**; label UI "Trackers blocked (est.)". Dedupe per (page, tracker domain), the same unit Safari uses, and this avoids retry inflation.
4. If you accept private API in a non-App-Store build: use `_webView:contentRuleListWithIdentifier:performedAction:forURL:` behind `respondsToSelector` + runtime checks, with the JS estimator as fallback if the selector disappears. Highest accuracy (exact, per URL, per list identifier).

Sources:
- https://raw.githubusercontent.com/WebKit/WebKit/main/Source/WebKit/UIProcess/API/Cocoa/WKNavigationDelegatePrivate.h (lines 99-100)
- https://raw.githubusercontent.com/WebKit/WebKit/main/Source/WebKit/UIProcess/API/Cocoa/WKNavigationDelegate.h (no contentRuleList)
- https://webkit.googlesource.com/WebKit/+/refs/heads/master/Tools/TestWebKitAPI/cocoa/TestNavigationDelegate.h
- https://opensource.apple.com/source/WebKit2/WebKit2-7609.3.5.0.2/UIProcess/API/Cocoa/_WKContentRuleListAction.mm.auto.html
- https://developer.apple.com/documentation/webkit/wkcontentrulelist
- https://support.apple.com/guide/safari/view-a-privacy-report-ibrw1074/mac
- https://github.com/duckduckgo/tracker-radar , https://github.com/disconnectme/disconnect-tracking-protection

---

## 3. WKContentRuleList limits on macOS

### 3.1 Max rules per list: 150,000 [V]
- WebKit source `Source/WebCore/contentextensions/ContentExtensionParser.cpp`: `constexpr size_t maxRuleCount = 150000;` -> error "Too many rules in JSON array" (surfaces as `WKErrorContentRuleListStoreCompileFailed`).
- Apple Frameworks Engineer on forums (July 2023) confirms 150,000. Historic limit was 50k (WebKit bug 205719, "Increase maximum size of WKContentRuleList"). Not in public docs; can change between OS versions, so keep lists well under (e.g. <=50k) for safety on macOS 14.
- Not a per-store limit; you can compile many lists. Limit is per list.

### 3.2 Compile time and memory [U — no official figures; engineering reports]
- Compilation builds a DFA (bytecode) off-main-thread in the UI-process-spawned compile on a background queue; completion handler runs on main. Large regex-heavy lists (`url-filter` with many wildcards, `.*` prefixes) blow up NFA->DFA states; compile can take seconds to tens of seconds for ~100k rules and use hundreds of MB transiently. Measure on your own list; expect it to be dominated by regex complexity, not count.
- WebKit maintainer comment (bug 205719): limit depends on compile speed, memory of the compiled list, and memory during compile.
- Compiled lists are mmapped bytecode on disk; runtime memory per web content process loading them is lower but scales with list size. Many big lists on every tab cost.
- Tips: prefer `if-domain`/`unless-domain` and anchored `^https?://([^/]+\.)?host` url-filters over free-form regex; dedupe; convert simple host rules to the domain-anchored form; avoid `.*` leading.

### 3.3 Splitting and caching best practice
- Split by category (ads, trackers, social, cosmetic) and by size (<=~30-50k/list). Gives incremental compile, per-category toggles, and failure isolation (one bad rule fails only that list).
- Cache via `WKContentRuleListStore.default()`:
  - `lookUpContentRuleList(forIdentifier:)` first; on success use the compiled list; on failure (`WKErrorContentRuleListStoreLookUpFailed`) compile.
  - `WKErrorContentRuleListStoreVersionMismatch` after OS/WebKit update -> recompile.
  - Embed a content hash/version in the identifier (e.g. `"ads-v12-<sha8>"`) so list updates produce a new identifier; then `removeContentRuleList(forIdentifier:)` the stale ones (`getAvailableContentRuleListIdentifiers` to enumerate).
  - Compile at launch in background, add lists to `WKUserContentController` as each finishes; the first navigation may precede compile — either delay first load until the cached lists are found, or reload.
- Use a custom store (`WKContentRuleListStore(url:)`) if you want the data in app-controlled dir (cleanup/diagnostics).
- Apple's docs: the store does not apply rules automatically; add to each `WKUserContentController` via `add(_:)`. Lists are keyed by identifier, and the same identifier is passed to the SPI action callback.

```swift
func load(id: String, json: String, into ucc: WKUserContentController) async {
    let store = WKContentRuleListStore.default()!
    do {
        let list = try await store.contentRuleList(forIdentifier: id)   // lookUp
        if let list { ucc.add(list); return }
    } catch { /* lookUp failed / version mismatch -> compile */ }
    if let list = try? await store.compileContentRuleList(forIdentifier: id, encodedContentRuleList: json) {
        ucc.add(list)
    }
}
```

### 3.4 `ignore-previous-rules` scope: per list only [V from source]
- In `ContentExtensionsBackend.cpp`, actions are gathered per content rule list (`actionsFromContentRuleList`, iterated by list identifier). The reverse scan that handles `IgnorePreviousRulesAction` runs inside one list's matched-action vector and sets `sawIgnorePreviousRules` for that list only (also gates that list's css-display-none sheet).
- So an `ignore-previous-rules` (e.g. allowlist exception) in list B does NOT cancel a `block` in list A. Different lists are independent; each can independently block.
- Implications: (a) allowlists/exceptions must be in the SAME list as the rules they override, placed AFTER them; (b) per-site "disable blocking" cannot be a separate exception list — instead remove the list from that tab's `WKUserContentController` (or `WKWebpagePreferences`/per-config) or compile exceptions into every list; (c) when splitting lists, keep each exception with its rules. `if-domain` / `unless-domain` on the exception rule is the standard way to implement per-site off-switches within a list (rebuild on change).
- Order inside a list matters: later `ignore-previous-rules` cancels earlier matching rules in that list.

Sources:
- https://developer.apple.com/forums/thread/734111
- https://bugs.webkit.org/show_bug.cgi?id=205719
- https://raw.githubusercontent.com/WebKit/WebKit/main/Source/WebCore/contentextensions/ContentExtensionParser.cpp (line ~333)
- https://raw.githubusercontent.com/WebKit/WebKit/main/Source/WebCore/contentextensions/ContentExtensionsBackend.cpp (lines ~155-167, 355)
- https://developer.apple.com/documentation/webkit/wkcontentruleliststore
- https://developer.apple.com/documentation/webkit/wkcontentrulelist
- https://developer.apple.com/documentation/safariservices/creating-a-content-blocker
