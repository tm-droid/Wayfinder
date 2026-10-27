# Safari research for Wayfinder (macOS WKWebView browser)

Date: 2026-10-27. Scope: Safari 18 (macOS 15), Safari 26 (macOS 26 Tahoe, incl. 26.4), Safari 27 (macOS 27 "Golden Gate", shipped ~Sep 2026).
Legend: Y = reproducible with public API; P = partial (API named); N = Safari-private / OS-private.
Priority: MUST / NICE / SKIP for Wayfinder.
Confidence tags: [V] verified in a primary source this session; [K] from prior knowledge, not re-verified; [?] unverified/conflicting.

## TL;DR

1. Engine parity is free. Every WebKit engine feature in Safari 26/27 (HDR images, Grid Lanes, Customizable Select, Digital Credentials, ITP/fingerprint hardening) comes from the same WebKit; WKWebView apps get engine work. What is NOT free is the browser shell: sync, Passwords/passkeys UX, Private Relay, Apple Pay, Reader engine, Highlights, Translate UI.
2. Biggest hard gaps for a third-party WKWebView browser: passkeys (needs the Web Browser public-key-credential entitlement, Apple-approved), iCloud Tabs/Passwords sync, Private Relay, Hide My Email in fields, Apple Pay on the web, one-time-code AutoFill from Messages.
3. WKWebExtension (macOS 15.4+) is the single most valuable public API: lets Wayfinder load real Safari/Chrome-style MV3 web extensions (uBlock-class, password managers). App must build all extension UI (toolbar actions, popups, permission prompts, tab/window bridge).
4. Safari 27 expands WKWebView public API materially (WKSerializedNode, WKJSHandle, WKContentWorldConfiguration, WKWebpagePreferences.alternateRequest/overrideReferrerForAllRequests, WKNavigationDelegate willSubmitForm, WKHTTPCookieStore.cookies(for:)) [V]. These make link-tracking stripping, per-site referrer policy, form-submit hooks, and tab/node transfer between views practical.
5. Safari's users' biggest unmet needs are exactly Arc/Zen's selling points: vertical sidebar, Spaces, command bar, split view, better tab management, richer extension ecosystem, per-site customisation (Boosts / Distraction Control analog). Safari 26 removed then (26.4) restored the compact tab bar after user outcry [V].

---

## 1. Feature inventory

| Feature | What it does (Safari) | Reproducible in WKWebView app? + API | Pri |
|---|---|---|---|
| Profiles (Safari 17+) | Separate history, cookies, tab groups, extensions, favourites, per-profile start page; per-profile website data | Y. `WKWebsiteDataStore(forIdentifier: UUID)` (macOS 14+) gives isolated cookies/storage per profile; own model for history/bookmarks/extension sets. One `WKWebExtensionController` per profile. [K] | MUST |
| Tab Groups (Safari 15+; Shared Tab Groups 16+) | Named groups of tabs in sidebar, sync via iCloud, shareable with collaborators (Messages), collaboration | P. Local model: Y. Cross-device sync: own CloudKit container (not Safari's). Sharing: `CKShare` / `NSItemProvider` + SharedWithYou-style UX is custom. | MUST |
| Start Page customisation | Favourites, Frequently Visited, Siri Suggestions, Reading List, iCloud Tabs, Privacy Report, background image, per-profile | Y. Serve own page via `WKURLSchemeHandler` custom scheme (`wayfinder://start`). Data sources are your own. Siri Suggestions/iCloud Tabs: N. | NICE |
| Reader | Declutters article; font/theme; auto-open per site | P. No public Reader API. Inject Mozilla Readability.js (`WKUserScript`/`callAsyncJavaScript`) and render in a styled WKWebView. Per-site auto-reader = own settings. | NICE |
| Listen to Page | Spoken page via TTS (Reader/Listen) | Y. `AVSpeechSynthesizer` + extracted Readability text; no Siri voices parity guarantee. [K that Safari has it; date unverified] | NICE |
| Summaries (Reader, Apple Intelligence) | On-device summary of article, macOS 15.1+ | P. Foundation Models framework (macOS 26, on-device LLM) is public; build own "Summarize" over Readability text. Requires Apple Intelligence-eligible hardware. [K] | NICE |
| Highlights (Safari 18) | ML surfaces relevant info on page (addresses, summaries, links, reviews) as a banner | N for the system model. P: re-implement narrow cases (address -> MapKit, summary -> Foundation Models). | SKIP |
| Distraction Control (Safari 18) | User picks elements to hide, persists per site; cannot hide cookie banners/login prompts reliably | Y. Element-picker via injected JS + persisted CSS/selector per host (`WKUserScript` at documentEnd, or `WKContentRuleList` css-display-none). Arc Boosts analog; strong differentiator when combined with user CSS/JS. | MUST |
| Web Apps / Add to Dock (macOS 14+) | Site -> standalone Dock app with own cookie jar, minimal chrome | P. No API to register Safari web apps. Wayfinder can generate its own `.app` shell per site (helper app bundle w/ WKWebView, shared or isolated data store) or a "pop-out" window mode. Heavy; shell packaging, signing, updates. | NICE |
| Privacy Report | Shows trackers blocked per site/last 30 days | P. No ITP telemetry API. Build own counters via `WKContentRuleList` match notifications (not exposed) -> instead use `WKNavigationDelegate` + `WKURLSchemeHandler`/own blocklist engine to count. | NICE |
| Intelligent Tracking Prevention (ITP) | Cross-site cookie blocking, 7-day script-written storage cap, bounce tracking mitigation, partitioned storage | Y/P. ITP/storage partitioning is in the WebKit engine and applied to WKWebView by default (apps may see third-party cookie blocking) [?: confirm per-config flags]. No Safari-private toggle. | MUST (verify defaults) |
| Advanced Tracking & Fingerprinting Protection (AFP) | Safari 26: on for ALL browsing (not just Private); blocks known fingerprinting scripts from screen dims, hardwareConcurrency, speech voices, Apple Pay capability, web-audio readback, 2D canvas; limits script-set storage; strips nav-tracking query params / `document.referrer` from those scripts [V WebKit blog] | P. Settings UI is Safari-owned; engine-side behaviour in WKWebView is [?]. Test with fingerprint test pages in your WKWebView. Add own content-rule lists (EasyPrivacy-style) via `WKContentRuleListStore`. | MUST |
| Link Tracking Protection | Strips known tracking query params (gclid, fbclid, mc_eid, etc.) in Private Browsing, Mail, Messages; AFP 'all browsing' does not (per third-party sources) [?] | Y. `WKNavigationDelegate.decidePolicyFor` -> cancel + reload cleaned URL; or Safari 27 `WKWebpagePreferences.alternateRequest` to rewrite main-resource request in-flight [V Safari 27 notes]. Maintain param list (AdGuard/Brave lists). | MUST |
| Private Relay (iCloud+) | Two-hop relay hides IP in Safari, DNS, unencrypted HTTP | N. OS/network-layer service tied to Safari; no app opt-in API. Alternative: DoH via `NWParameters.PrivacyContext` / `NEDNSSettingsManager` (system extension) or user VPN. | SKIP |
| Hide My Email | Generates iCloud+ alias from Passwords/AutoFill in email fields; Sign in with Apple relay | N for in-field generation. P: "Sign in with Apple" via `ASAuthorizationAppleIDProvider` yields relay email for native sign-in only. | SKIP |
| Passwords app / AutoFill | Passwords, TOTP, passkeys, Wi-Fi; Safari auto-fills passwords/cards/addresses | P. Third-party browsers do not get system Safari AutoFill for free in WKWebView. Public paths: (a) Credential Provider Extensions (`ASCredentialProviderViewController`) serve 1Password/Bitwarden; (b) `ASAuthorizationController` for native flows; (c) own Vault in Keychain (repo already has Vault.swift/ApplePasswords*.swift). A forum comment says macOS 26 may autofill from Passwords in web views [?]. | MUST (credential story) |
| Passkeys / WebAuthn in WKWebView | Safari shows picker (Passwords / security key / nearby device) | P. WebKit gates WebAuthn behind `com.apple.developer.web-browser.public-key-credential` entitlement (macOS; requested from Apple) or associated-domains for your own RP. Forum reports mixed on iOS; confirm via Apple Developer support. [?] Without it: fallback to `ASWebAuthenticationSession` or open in Safari. | MUST (apply early) |
| One-time codes (Messages/Mail) | `autocomplete="one-time-code"` offers code from Messages/Mail; auto-deletes after use (opt-in) | N/? Safari uses private Messages/Mail data. Public: iOS QuickType/`textContentType = .oneTimeCode`; macOS web view equivalence unverified. Provide fallback: user paste, or Passwords TOTP via Credential Provider. | NICE |
| Apple Pay on the web | `ApplePaySession`/Payment Request, Touch ID | N/? Historically unavailable in WKWebView; requires Apple Pay JS entitlement (Safari/SFSafariVC only). Fallback: "Open in Safari" for checkout. [?] | SKIP (fallback) |
| Picture-in-Picture | Native PiP for HTML5 video; Video viewer | Y. `WKWebViewConfiguration.allowsPictureInPictureMediaPlayback` (default true) + `video.webkitSetPresentationMode`. Custom PiP (repo has NativePiP.swift). Document PiP API for non-video: Safari does not support it as of 26 [?]. | MUST |
| Translate | On-page translation via Apple Translation | P. `Translation` framework public (macOS 15+: `TranslationSession`, `.translationPresentation`). Extract DOM text via JS, translate, replace. Safari's language-detect banner = own. | NICE |
| Live Text | Select/copy/search text in images; translate/lookup | P. WKWebView supports image text analysis through system (VisionKit `ImageAnalyzer`) on macOS 13+ [?]; otherwise `VNRecognizeTextRequest`. | NICE |
| Handoff | Continue tab on iPhone/iPad | P. `NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)` with `webpageURL` works for Handoff of any browser app that has an iOS counterpart; needs same-team apps. | NICE |
| iCloud Tabs | Open tabs on other devices | N for Safari's container. Own CloudKit sync of tab state. | SKIP |
| Shared with You | Links shared in Messages shown in Start Page / by-sender | P. `SharedWithYou` framework (`SWHighlightCenter`, `SWHighlight`) public, macOS 13+. Pick for start page. | NICE |
| Web Extensions (Safari) | MV2/MV3 JS extensions via App Store; Safari Web Extension Converter; Describe an Extension (Safari 27, AI) | P. `WKWebExtension`, `WKWebExtensionContext`, `WKWebExtensionController` public from macOS 15.4/iOS 18.4/visionOS 2.4 [V availability]. App implements `WKWebExtensionControllerDelegate` (tab/window model, permission prompts, popup presentation, openNewTab). Reports MV3, content scripts, service workers, action popups work (Nook browser notes) [?]. Not exposed: App Store distribution, Safari's Extensions pane, Describe-an-Extension. | MUST |
| Smart Search Field | Unified field: Safari Suggestions, quick website search, bookmarks/history, Siri Knowledge | P. Own implementation (repo has command bar). Search engine suggestion APIs public; Safari Suggestions N. | MUST |
| Tab bar layouts | Compact (single bar) vs Separate; 26 removed Compact, 26.4 restored it [V 9to5Mac] | Y. All UI is app-owned. Offer sidebar + compact + horizontal; this is where Safari is weakest. | MUST |
| Per-site settings | Zoom, Reader, Content Blockers, Camera/Mic/Location, Auto-play, Pop-ups, Downloads, Notifications | Y/P. Zoom: `WKWebView.pageZoom`; autoplay: `mediaTypesRequiringUserActionForPlayback`; camera/mic: `WKUIDelegate.requestMediaCapturePermissionFor`; location: `CLLocationManager` + `WKUIDelegate`; pop-ups: `createWebViewWith`; JS: `WKWebpagePreferences.allowsContentJavaScript`; content blockers: `WKContentRuleList`. Notifications/Web Push: N/? (limited to apps w/ push entitlement) [?]. Store per-host in own DB; Safari 27 adds referrer override. | MUST |
| Downloads | Download manager popover, resume, Open safe files | Y. `WKDownload` (macOS 11.3+), `WKDownloadDelegate`; quarantine attribute (`com.apple.quarantine`) applied by app; resume = `resumeData`. | MUST |
| Web Inspector / Responsive Design Mode | Develop menu; RDM with device presets | P. `WKWebView.isInspectable = true` (macOS 13.3+) -> inspect from Safari's Develop menu. RDM is private; emulate via window-size presets + `customUserAgent`. Safari 27 inspector gains: contrast checker, redirect chain in Network tab, subgrid/Grid-Lanes badges [V]. | NICE |
| Energy efficiency | Tab suspension, WebContent process management, efficient media playback | P. Engine efficiency inherited. No public tab-suspend API; approximate by discarding WKWebViews for background tabs (keep snapshot via `takeSnapshot`, restore with `interactionState`). Media: `pauseAllMediaPlayback()`, `setAllMediaPlaybackSuspended`. | MUST (Arc/Zen weakness) |
| Spatial / HDR | HDR images (Safari 26), `<model>`, immersive video visionOS | Y (engine). HDR images/dynamic-range-limit CSS in WKWebView on macOS 26 [V engine feature]. `<model>` reaches macOS in Safari 27 [V]. visionOS-only items N. | NICE |
| Listen to Page | see above | | |
| Full-screen / Video viewer | Native video full-screen | Y. `WKWebView` full-screen element API (`isFullScreenSupported`) | MUST |
| Content Blockers | Safari content-blocker extensions | Y. `WKContentRuleListStore`; same JSON format; lists limited to 150k rules per list [K] | MUST |
| Web Push / Notify Me | Notify Me (Safari 27): monitor a page and alert on change | Y (own). Page-diff watcher + `UNUserNotificationCenter`; Apple's version uses Apple Intelligence [V existence]. | NICE |
| Auto tab grouping (Safari 27) | Apple Intelligence clusters tabs by topic | P. Foundation Models (macOS 26) for topic clustering over titles/URLs; opt-in. | NICE |
| Lockdown Mode | Reduced attack surface | N. Systemwide; WKWebView respects Lockdown Mode if enabled on OS. | SKIP |
| Digital Credentials API | ID from Wallet in browser (Safari 26) | N/? Engine API in WebKit; app-level availability in WKWebView [?]. Needs Apple support for ISO mdoc. | SKIP |

---

## 2. New in 2025-2026 (what to build on)

### 2.1 Safari 26 (macOS Tahoe 26, Sep 2025) [V WebKit blog Jun 9 2025]
- WebKit for SwiftUI: new `WebView` (SwiftUI View) and `WebPage` (Observable model). WebView supports `webViewScrollPosition`, `webViewMagnificationGestures`, `findNavigator`; WebPage supports custom scheme handling, customised navigations (back/forward list), `DialogPresenting` for JS dialogs, JavaScript calls. Minimum OS 26. Verdict for Wayfinder: existing AppKit WKWebView still the back-deploy and most flexible path; WebPage useful for Observable-friendly tab models if min target is 26. [Evidence: WebKit blog; tutorials]
- WKWebView API additions: Screen Time support, local/session storage restoration APIs, `backdrop-filter` over transparent web views [V].
- Privacy: AFP in all browsing; fingerprinting script mitigation extended; reduced reading of query params/referrer for known fingerprinting scripts [V].
- Engine: HDR images, dynamic-range-limit CSS, SVG icons, WebGPU, Digital Credentials API, Web Inspector improvements, WebCodecs audio, MSE detachable, Lockdown updates.
- Web Extensions: web-based Safari Web Extension Packager (App Store Connect), command shortcuts in menu bar with user customisation on macOS [V]. Not helpful for third-party WKWebExtension hosts beyond command surface.
- Web apps: every site can be a web app on iOS/iPadOS [V]; macOS web apps existed since 14.
- UI: Liquid Glass; compact tab bar removed in first Tahoe builds, restored in 26.4 [V 9to5Mac Mar 26 2026]. MacRumors' Tahoe review criticised Liquid Glass fit [V].
- Safari 26.4: CSS Grid Lanes (masonry) shipped [V].

### 2.2 Safari 27 (macOS 27 / iOS 27, announced WWDC26 Jun 8 2026; shipped ~Sep 2026) [V blog; Macworld date unverified]
- WebKit blog: 58 new features, 525 fixes, 4 deprecations; WebKit team claims 1,100+ quality fixes (session 204). Gruber: release is mostly correctness [V].
- User features: Notify Me (monitor page, alert on change), automatic AI tab groups (opt-in, Apple Intelligence), Describe an Extension (natural language -> extension, suggests existing apps), auto-change flagged weak/compromised passwords [V via MacRumors/9to5Mac/T2Online; AI items require Apple Intelligence].
- WKWebView public API expansion [V]:
  - `WKSerializedNode`: clone DOM nodes (incl. shadow roots) between WKWebViews.
  - `WKJSHandle`: native references to JS objects.
  - `WKContentWorldConfiguration`: set autofill scripting, shadow-root access, inspectability per content world.
  - `WKWebpagePreferences.alternateRequest` / `overrideReferrerForAllRequests`.
  - `WKNavigationDelegate` `willSubmitForm` + `WKFormInfo` (hook for save-password prompts).
  - `mainFrameNavigation` on `WKNavigationAction` / `WKNavigationResponse`.
  - `WKWebView.load(url:)`; `WKHTTPCookieStore.cookies(for:)`.
  Impact: `willSubmitForm` finally enables a "Save password?" prompt without brittle JS; `WKContentWorldConfiguration` autofill scripting helps credential managers; `alternateRequest` enables Link Tracking Protection and header tweaks; `WKJSHandle`/`WKSerializedNode` help Distraction Control, Reader, and tab pop-out.
- Web Extensions (Safari): `runtime.getDocumentId()`, error reporting for uncaught exceptions/rejections in extension scripts, user-gesture propagation across `sendMessage`/`connect`/`postMessage`/`executeScript` [V].
- Web platform: Customizable Select (`appearance: base-select`), `<model>` on macOS/iOS/iPadOS, Immersive environments (visionOS 27), MapKit JS, img `sizes=auto`, `stretch`. Inspector: contrast in colour picker, redirect chains, subgrid badges [V].

### 2.3 Open items to confirm before committing roadmap
- Which Safari 27 WKWebExtension API deltas exist (WWDC26 session "Create web extensions for Safari" not read).
- WebAuthn/passkey behaviour in WKWebView on macOS 26/27 without the public-key-credential entitlement.
- Whether macOS 26/27 autofills Passwords-app credentials in third-party WKWebViews.
- Whether AFP and Link Tracking Protection apply in WKWebView by default.
- ApplePaySession availability in WKWebView.

---

## 3. Public API cheat sheet for Wayfinder

| Need | API (min OS) |
|---|---|
| Profile isolation | `WKWebsiteDataStore(forIdentifier:)` (macOS 14) |
| Private window | `WKWebsiteDataStore.nonPersistent()` |
| Extensions | `WKWebExtension`, `WKWebExtensionContext`, `WKWebExtensionController`, `WKWebExtensionControllerDelegate` (macOS 15.4) |
| Content blocking | `WKContentRuleListStore` (macOS 10.13+) |
| Per-site JS toggle | `WKWebpagePreferences.allowsContentJavaScript` |
| Request rewrite | `WKNavigationDelegate decidePolicyFor`; Safari 27 `alternateRequest` |
| Form submit hook | `willSubmitForm` (Safari 27 SDK) |
| Downloads | `WKDownload` (macOS 11.3) |
| Inspect | `isInspectable` (macOS 13.3) |
| Snapshot/tab restore | `takeSnapshot`, `interactionState` (macOS 12) |
| Media permissions | `WKUIDelegate requestMediaCapturePermissionFor` (macOS 12) |
| Zoom | `pageZoom` (macOS 11) |
| Find | `findNavigator` (SwiftUI WebView) / `find(_:)` (macOS 11) |
| SwiftUI | `WebView`, `WebPage` (macOS 26) |
| Translation | `Translation` framework (macOS 15) |
| On-device LLM | Foundation Models (macOS 26, Apple Intelligence devices) |
| Handoff | `NSUserActivity` browsing-web |
| Shared with You | `SharedWithYou` framework |
| Credential provider | `AuthenticationServices` credential provider extension |
| Default browser | `com.apple.developer.web-browser` entitlement (Apple-approved) |
| Passkeys in web views | `com.apple.developer.web-browser.public-key-credential` [?] |

---

## 4. What Safari users love [mix of V and K]

- Efficiency: best battery life among Mac browsers; light on RAM (G2/Capterra reviews, comparison sites) [V anecdotal].
- Native feel: system menus, gestures, text rendering, Touch ID, Passwords.
- Ecosystem: iCloud sync of tabs/tab groups/history/reading list, Handoff, iPhone/Mac Continuity, Shared with You.
- Privacy defaults: ITP, Private Relay, AFP-all-browsing (26), Privacy Report, no ad-driven business [K].
- Profiles + Tab Groups: low-friction work/personal separation.
- Reader, PiP, video quality (HDR/Dolby), Translate, Live Text.
- Passkeys and Passwords app, one-time-code auto-fill.
- Web Inspector quality (esp. WebKit-specific debugging) among devs; respectable but not top.

## 5. Top complaints

- Extensions: smaller ecosystem than Chrome; App Store distribution/packaging friction; users cite "limited extension support" repeatedly in reviews [V anecdotal]. MV3 coverage lags in places. Safari 27 adds Describe an Extension as an AI response [V existence].
- Tab management: no vertical/sidebar tabs by default, no Spaces, weak tab search, hidden menu bar/tab controls while scrolling (reviewers) [V anecdotal]; users complain past ~20 tabs [V per Reddit summary, anecdotal]. Safari 26 Tahoe removed compact tab bar then restored it in 26.4 [V].
- Liquid Glass UI: readability/consistency critiques (MacRumors Tahoe review) [V].
- Site compatibility: "works best in Chrome" sites, WebKit-specific bugs; Apple responded with 1,100+ fixes in Safari 27 [V].
- DevTools: Web Inspector lags Chrome DevTools in features and extension support (RDM limited) [K].
- Bookmarks/history organisation primitive; no workspace/folders hierarchy in sidebar; search field lacks command-style actions [K].
- Update coupling: Safari tied to macOS release cadence (though 26.x point releases ship features) [K].
- Privacy changes hit sites (analytics/measurement breakage): AFP all-browsing affects marketers [V via ppc.land/taggrs coverage].

## 6. Why power users leave Safari for Arc / Zen / others, and what they miss

Why leave:
- Arc: vertical sidebar, Spaces (profile-per-context), pinned/essential tabs, split view, command bar, Boosts, Little Arc, Easels; Arc entered maintenance mode May 27 2025 [V comparison article], pushing users to Zen, Dia, Vivaldi, Orion, Safari. (The Browser Company acquired by Atlassian Sept 2025 [K, unverified].)
- Zen: Firefox/Gecko with Arc-style sidebar, Workspaces, split view, Glance; complaints: high RAM, occasional crashes, less polish than Arc [V comparison sources, SEO-style].
- Vivaldi: deep customisation, tab stacking/tiling, native vertical tabs [V comparison].
- Extension breadth (uBlock Origin full, Bitwarden, Vimium, Tampermonkey).
- Per-profile + per-space workflows more flexible than Safari Profiles.
- Cross-platform sync (Windows/Linux/Android) and uniform dev tools.

What they miss after leaving Safari:
- Battery/thermal efficiency, smooth scrolling/animation [V anecdotal].
- Passwords app + passkeys + Touch ID autofill; Apple Pay.
- Handoff, iCloud Tabs, Messages shared links, Private Relay, Hide My Email.
- PiP/video quality, HDR, system translate, Live Text, Reader.
- Native macOS integration (menu, services, Shortcuts, Spotlight).
- Lockdown Mode, Stage Manager/Spaces integration.

## 7. Implications for Wayfinder (build order)

MUST (differentiators using Safari's strengths + Arc/Zen's):
1. Profiles via `WKWebsiteDataStore(forIdentifier:)` + per-profile extension controller.
2. WKWebExtension host with full UI bridge (toolbar, popup, permissions, commands).
3. Sidebar tabs, Spaces, Tab Groups, compact/horizontal modes (Safari's gap).
4. Content blocking + Link Tracking Protection + AFP-class tests; Privacy Report counters.
5. Distraction Control + per-site CSS/JS (Boosts + Safari fusion).
6. Per-site settings store (zoom, permissions, autoplay, referrer policy, JS).
7. Passkey/AutoFill story: apply for web-browser public-key-credential entitlement now; Credential Provider extension support; `willSubmitForm` for save-password.
8. Energy: background tab discard/snapshot, media suspend.

NICE: Reader via Readability + Listen + Foundation Models summaries; Translate via Translation framework; PiP; Notify Me clone; AI tab grouping; web-app shells; Handoff; Shared with You; Responsive emulation.

SKIP: Private Relay, Hide My Email, iCloud Tabs (use own CloudKit sync if needed), Apple Pay, Digital Credentials, Lockdown, visionOS features, Highlights.

## Sources

- WebKit blog, News from WWDC25: WebKit in Safari 26 beta: https://webkit.org/blog/16993/news-from-wwdc25-web-technology-coming-this-fall-in-safari-26-beta/
- WebKit blog, News from WWDC26: WebKit in Safari 27 beta: https://webkit.org/blog/17967/news-from-wwdc26-webkit-in-safari-27-beta/
- WWDC26 session 204, What's new in WebKit for Safari 27: https://developer.apple.com/videos/play/wwdc2026/204/
- Safari 27 beta release notes: https://developer.apple.com/documentation/safari-release-notes/safari-27-release-notes
- Michael Tsai, Safari 27 Announced (quotes MacRumors/WebKit): https://mjtsai.com/blog/2026/06/12/safari-27-announced/
- MacRumors, Safari monitor webpage: https://www.macrumors.com/2026/06/08/safari-monitor-webpage-notify-updates/
- Gruber on WebKit Safari 27: https://daringfireball.net/linked/2026/06/24/webkit-safari-27
- 9to5Mac, compact tab bar returns in 26.4: https://9to5mac.com/2026/03/26/macos-tahoe-26-4-and-ipados-26-4-add-compact-tab-bar-in-safari/
- MacRumors, macOS Tahoe review: https://www.macrumors.com/2025/08/01/macos-tahoe-review
- Macworld, macOS 27 Safari: https://macworld.com/article/3159801/my-fingers-already-love-this-macos-27-safari-feature.html
- MacRumors forums, iOS 27 Safari features: https://forums.macrumors.com/threads/ios-27-all-the-new-safari-features.2483916/
- Apple docs, WKWebExtensionController(+Delegate): https://developer.apple.com/documentation/webkit/wkwebextensioncontroller
- Nook browser extensions system notes (third-party): https://deepwiki.com/nook-browser/Nook/5.6-browser-extensions-system
- Apple Developer Forums on WKWebView passkeys: https://developer.apple.com/forums/thread/837755 , https://developer.apple.com/forums/thread/798042 , https://developer.apple.com/forums/thread/802914 ; WebKit bug https://bugs.webkit.org/show_bug.cgi?id=250912
- Apple Developer Forums, WKWebView password autofill: https://developer.apple.com/forums/thread/654338
- AFP coverage: https://www.macobserver.com/?p=404559 , https://ppc.land/safari-26-tracking-changes-to-impact-marketing-measurement/
- Comparisons: https://supasidebar.com/blog/best-mac-browser-reddit-2026 , https://efficient.app/compare/arc-browser-vs-safari , https://talk.macpowerusers.com/t/alternatives-to-the-arc-browser/41013
- Reviews (anecdotal): https://g2.com/products/apple-safari/reviews , https://www.capterra.com/p/229123/Safari/reviews/
