# Wayfinder browser feature research (2026-10-26)

Evidence caveat: Reddit returned HTTP 403 to all scripted access (old.reddit, www, .json), so Part A relies on Hacker News (Algolia API) plus prior knowledge. Reddit-derived claims are marked UNVERIFIED. Technical claims (Part C) are checked against WebKit headers/GitHub unless marked.

## Summary (plan-changing findings)
1. No public API reports WKContentRuleList block hits. Only private `_WKContentRuleListAction` exists; WebKit bug 205720 asks for it. Privacy report must use fallbacks (see U11). Do not promise per-request counts.
2. Licensing: EasyList/EasyPrivacy are dual GPLv3-or-later / CC BY-SA 3.0; AdGuard SafariConverterLib is GPL-3.0; Ora (reference) is GPL-3.0. Copying Ora code or linking SafariConverterLib forces Wayfinder to be GPL-3.0 (or needs a custom converter). Readability.js is Apache-2.0 (safe).
3. WKWebExtension (macOS 15.4+) loads unpacked directories AND zips via `WKWebExtension.extension(withResourceBaseURL:)`, so U14 is feasible, but the host app must implement the tab/window protocols and prompt/popup delegates. Chrome Web Store install is not provided by WebKit; app must download/unzip CRX itself (UNVERIFIED how Yab does it; Yab says "Chrome Web Store").
4. Yab (closed source, WebKit) markets: spaces, split view, built-in ad blocker, Chrome Web Store extensions, MCP/CLI, iPhone sync. Competitive bar = those plus AI agent. Source: https://yetanotherbrowser.com/compare/yab-vs-chrome
5. Arc is in maintenance (HN 50198810: "feature development stopped over a year ago"), so import (U15) and Arc-parity are an adoption wedge.

## A. Community opinion (what people value)
- Tab model: "3 Groups: Pinned Tabs, Favorites Tabs, 'Regular' Tabs; pinned never go away; favorites are sticky to original URL" (HN https://news.ycombinator.com/item?id=40213834). Users say they returned to Arc because of tab management.
- "best browser UX... vertical tabs, auto archiving, spaces/collections, sync" but hates growth hacks/AI overlay on pages, forced sign-in (HN https://news.ycombinator.com/item?id=41601332). Lesson: no account required, no page overlays, no upsell.
- Spaces w/ profiles: "named persistent spaces... some pinned, some ephemeral; spaces can have different profiles; side-by-side tabs give iPad-like split screen" (HN https://news.ycombinator.com/item?id=38627019).
- Peek/Little Arc: "peek into a webpage or Little Arc... handy for SSO popups without changing full focus" (HN https://news.ycombinator.com/item?id=36868913).
- Command bar: "floating command bar that does more than just open this URL" (HN https://news.ycombinator.com/item?id=41966471); auto-hiding sidebar, pins, split tabs praised (https://news.ycombinator.com/item?id=50198810).
- Boosts: HN users use them for site CSS tweaks, e.g. HN skin (https://news.ycombinator.com/item?id=36857199).
- Split view: "not as smooth" in Arc (https://news.ycombinator.com/item?id=41268954); users want spaces+split without cloud bits (https://news.ycombinator.com/item?id=41603904). Wayfinder: local-first.
- Zen: pinned vs ephemeral distinction "more natural than bookmarks or traditional tabs" (https://news.ycombinator.com/item?id=46530737); folders for research threads (https://news.ycombinator.com/item?id=43836613); asks for Arc-style Auto Archive in Zen (https://news.ycombinator.com/item?id=41336421). Zen perf/battery concern on Firefox base (https://news.ycombinator.com/item?id=50206869): WebKit is Wayfinder's battery edge.
- Safari reader/profiles/tab groups/privacy report, Reddit specifics: UNVERIFIED (no data retrieved).

## B. Source patterns
### zen-browser/desktop (MPL-2.0, safe to read; Gecko/JS so copy behaviours, not code)
- Prefs defaults (https://github.com/zen-browser/desktop/tree/dev/prefs/zen):
  - glance.yaml: activation key `alt` (ctrl/alt/shift), animation 350 ms, enabled true.
  - workspaces.yaml: `separate-essentials` true (essentials per space/container optional), swipe actions on, switch animation 250 ms, wrap-around navigation true, `close-shortcut-behavior: reset-unload-switch` for pinned tabs, `restore-pinned-tabs-to-pinned-url` false.
  - split-view.yaml: drag-over-split delay 500 ms, threshold 40 px, rearrange hover 24 px, min resize 7.
  - view.yaml: sidebar max width 500, single toolbar, `drag-window-from-content`, show-clear-tabs-button.
  - compact mode (src/zen/compact-mode/ZenCompactMode.mjs): prefs `hide-tabbar`, `hide-toolbar`, `show-sidebar-and-toolbar-on-hover`, `hover-hack-delay`, `sidebar-keep-hover.duration`, `toolbar-hide-after-hover.duration`, `toolbar-flash-popup`, `show-background-tab-toast`, `outside-window-edge-offset.*`.
- Files: src/zen/glance/ZenGlanceManager.mjs, src/zen/split-view/ZenViewSplitter.mjs, src/zen/folders/ZenFolders.mjs (max subfolder tests), src/zen/live-folders (RSS/GitHub live folders: idea worth stealing).
### the-ora/browser (GPL-3.0; macOS 15+, SwiftUI+AppKit+WebKit) https://github.com/the-ora/browser
- Models (SwiftData): `Features/Tabs/Models/TabContainer.swift` (id, name, emoji, createdAt, lastAccessedAt, cascade tabs+folders+history), `Tab.swift` (TabType pinned/fav/normal, order, savedURL, lastAccessedAt, @Transient browserPage), `Folder.swift` (name, isOpened).
- Per-space data store: `Core/BrowserEngine/BrowserEngineProfile.swift` uses `WKWebsiteDataStore(forIdentifier: UUID)` (persistent) or `.nonPersistent()` (private). Pattern to copy: one data store per space, keyed by space UUID.
- Sleeping: `Features/Tabs/State/TabManager.swift` `cleanupOldTabs()` calls `tab.destroyWebView()` when not active, not playing media, type == .normal, past `tabAliveTimeout`; `removeOldTabs()` = auto-archive (closes normal tabs past `tabRemovalTimeout`); `autoClearContainerTabs()` = per-space autoClear. Ora does NOT save interactionState (UNVERIFIED by full read; grep found none).
- Other: Launcher/* (command bar), Sidebar/Views/TabList/{FavTabsList,PinnedTabsList,NormalTabsList}.swift, FloatingSidebar.swift, Tabs/Switcher/FloatingTabSwitcher.swift, Shared/Layout/SplitView/*, Features/Privacy/* (ContentBlockerCompileService shards rules by halving on discard; uses AdGuard converter), Importer/Services/Importer.swift.

## C. Technical verification
1. Block hits: no public API. WebKit bug https://bugs.webkit.org/show_bug.cgi?id=205720 (open as of search; status UNVERIFIED); private SPI `_WKContentRuleListAction` (https://opensource.apple.com/source/WebKit2/WebKit2-7609.3.5.0.2/UIProcess/API/Cocoa/_WKContentRuleListAction.mm.auto.html); forum https://developer.apple.com/forums/thread/654298.
2. EasyList licence: dual GPLv3+ / CC BY-SA 3.0+, attribute "The EasyList authors" (https://easylist.to/pages/licence.html). AdGuard SafariConverterLib: GPL-3.0, Swift, SPM/CocoaPods, `ContentBlockerConverter().convertArray(...)`, advanced rules need separate extension (https://github.com/AdguardTeam/SafariConverterLib). Safari limit 150,000 active rules per content blocker (same README); use several lists/identifiers for more (WKWebView limit per list assumed same: UNVERIFIED).
3. WKWebExtension: macOS 15.4+. `extension(withResourceBaseURL:)` accepts directory or ZIP with manifest.json; `supportsManifestVersion(_:)`. Delegate (WKWebExtensionControllerDelegate) methods: openWindowsFor, focusedWindowFor, openNewWindow, openNewTab, openOptionsPage, promptForPermissions, promptForPermissionToAccessURLs, promptForPermissionMatchPatterns, didUpdateAction, presentPopupForAction, sendMessage/connectUsing (native messaging). Context has `grantedPermissions`, `setPermissionStatus(...)`, `unsupportedAPIs`, `webViewConfiguration`. App must expose tabs/windows via WKWebExtensionTab/Window protocols. Source: https://raw.githubusercontent.com/WebKit/WebKit/main/Source/WebKit/UIProcess/API/Cocoa/WKWebExtension.h and ...WKWebExtensionControllerDelegate.h. API gaps per Chrome API (e.g. which MV3 APIs missing): UNVERIFIED.
4. Sleeping: `WKWebView.interactionState` (macOS 12+) saves back/forward list, scroll, form data; assign to new web view (https://developer.apple.com/documentation/webkit/wkwebview/interactionstate). No WKWebView-specific memory-pressure API; use `DispatchSource.makeMemoryPressureEventSource` (UNVERIFIED for WK; generic GCD) and discard background views. Firefox iOS ADR: offload background webviews, never selected tab (https://searchfox.org/mozilla-mobile/source/firefox-ios/adr/0010-offload-background-webviews-on-memory-warning.md).
5. Arc StorableSidebar.json (from ivnvxd/arc-export main.py, https://github.com/ivnvxd/arc-export): `sidebar.containers[]`; the container having key `"global"` (index of it +1 in their code: the container AFTER the marker is read) holds `spaces[]` and `items[]`. Space: `title`, `newContainerIDs` = alternating [ {"pinned":...} or {"unpinned":...}, containerId, ...]. Item: `id`, `parentID` (tree), `title`, `data.tab.savedURL`, `data.tab.savedTitle`; folders are items with a list data (exact key UNVERIFIED), `childrenIds`. Format undocumented; may change. Version-pin and parse defensively. Also see https://github.com/Physton/arc-bookmarks.
6. Readability.js: Apache-2.0 (https://github.com/mozilla/readability). Needs a DOM: run inside WKWebView via WKUserScript/evaluateJavaScript on `document.cloneNode(true)` (parse() mutates the DOM); `isProbablyReaderable(document)` gates the button; sanitize output (DOMPurify recommended by README) and render in a separate WKWebView with strict CSP, JS disabled for content.

## Unit tweaks
- U2 data model: Space{id,name,emoji,color,dataStoreUUID,profile}. Tab types: essential (global or per-space, Zen `separate-essentials` default true), pinned (has savedURL; "reset-unload-switch" close behaviour), today/normal. Folders nested (Zen supports subfolders). One `WKWebsiteDataStore(forIdentifier:)` per space/profile; private = nonPersistent. Persist with SwiftData as Ora does, plus `interactionState` Data blob per tab. Keep `lastAccessedAt`.
- U3 sidebar: vertical, width max ~500, resizable; pinned above divider, today below; swipe/scroll to switch spaces (wrap-around, 250 ms); drag window from toolbar. No sign-in, no ads/upsells (HN 41601332).
- U4 command bar: floating, searches tabs/history/bookmarks/commands, opens URL in current or new tab; port Ora Launcher/* structure.
- U5 compact mode: hover-reveal sidebar with delay + keep-hover duration (Zen prefs); flash toolbar on navigation; tint chrome using page colour; Liquid Glass via `NSGlassEffectView`/SwiftUI `.glassEffect` (macOS 26 API; check availability, UNVERIFIED in this research). Ora `FloatingSidebar.swift` reference.
- U6 split view: drag tab onto content edge (500 ms delay, 40 px threshold from Zen), min pane width, resizable divider, up to 4 panes (assumption). Ref Ora Shared/Layout/SplitView.
- U7 peek/glance: modifier+click (default Alt like Zen, configurable), 350 ms animation, expand-to-tab, close, open-in-split; also used for external links from essentials. Zen has tests for glance+split interaction.
- U8 auto-archive + sleeping: sleep after N min idle (save interactionState, nil webview; skip active/media/audible); archive normal tabs after configurable time (Arc default 12h; setting offering Never/24h/7d/30d; UNVERIFIED Arc defaults) into searchable Archive, never archive pinned/essential; undo toast. Ref Ora TabManager.cleanupOldTabs/removeOldTabs.
- U9 Little Arc: small floating window for external links/SSO, with "move to space" action; keep default-browser link handoff here.
- U10 content blocker: ship own converted lists under GPL-3.0, or write permissive converter. Compile via WKContentRuleListStore, shard under limit (Ora halving approach), update lists in background, attribute EasyList authors.
- U11 privacy report: no hit counts. Fallbacks: (a) count third-party trackers via lists matched in a WKUserScript observing PerformanceObserver resource entries against domain list (loaded-but-not-blocked only); (b) WKNavigationDelegate decidePolicyFor main-frame blocks you do yourself; (c) show "rules active" and cookies per site via WKHTTPCookieStore. State clearly counts are estimates.
- U12 reader: Readability.js bundled (Apache-2.0 notice), isProbablyReaderable gating, themes/fonts, Safari-like toolbar button.
- U13 boosts: per-site CSS/JS via WKUserScript + WKUserStyleSheet keyed by host; editable in-app; export/share as JSON. Content-world isolation (WKContentWorld).
- U14 extensions: WKWebExtensionController per profile (WKWebExtensionController(configuration:) with dataStore for the space), load folder/zip, implement tab/window protocol adapters and the permission/popup delegates; persist granted permissions. Test uBlock Origin Lite/Bitwarden first. CRX downloader for Web Store is own work, legally grey (UNVERIFIED).
- U15 import: Arc StorableSidebar.json (see C5), plus Safari bookmarks plist / Chrome Bookmarks JSON; parse read-only, map spaces->spaces, pinned container->pinned, unpinned->today, `parentID` to folders; show preview and skip unknown nodes.

Sources:
- https://hn.algolia.com/api/v1/search (items cited above)
- https://yetanotherbrowser.com/compare/yab-vs-chrome
- https://github.com/zen-browser/desktop , https://github.com/the-ora/browser
- https://bugs.webkit.org/show_bug.cgi?id=205720 , https://developer.apple.com/forums/thread/654298
- https://easylist.to/pages/licence.html , https://github.com/AdguardTeam/SafariConverterLib , https://github.com/mozilla/readability
- https://github.com/WebKit/WebKit/tree/main/Source/WebKit/UIProcess/API/Cocoa , https://developer.apple.com/documentation/webkit/wkwebview/interactionstate
- https://github.com/ivnvxd/arc-export
