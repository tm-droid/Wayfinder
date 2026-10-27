# Zen Browser deep dive (for Wayfinder: macOS WebKit browser; Arc + Zen + Yab + Safari)

Research date: 2026-10-27. Zen is Firefox (Gecko) fork, MPL-2.0, repo zen-browser/desktop (45.4k stars, ~796 open issues, created 2024-03-28).
Latest release at time of writing: 1.23.4b (2026-10-21). Based on Firefox 157 (1.23b).
Tags: MUST-HAVE / NICE / SKIP are for a WebKit macOS browser. Design ideas only, no code copied.
Gaps flagged "UNVERIFIED". Another agent covers narrow specs (essentials, command bar, boosts, gradient picker, glance/split); those are only summarised here.

## 1. Release cadence and history

- Cadence: weekly-ish "b" (beta/stable) builds, typically 1 minor per ~3-5 weeks + 2-4 patch builds. Oct 2026: 1.23b (10-02), 1.23.1b (10-06), 1.23.2b (10-09), 1.23.3b (10-16), 1.23.4b (10-20). ~196 releases since 0.0.0-a.2 (2024-07-07).
- Each release tracks a Firefox major (143 at 1.16b, 148 at 1.19b, 151 at 1.20b, 155 at 1.22b, 157 at 1.23b). Security-fix notes link MFSA advisories.
- Feature timeline from release notes (first mention):
  - 1.10b (2025-03-19): Glance, split view, mods, window sync, PiP, tab unloading, pinned tabs in notes.
  - 1.10.1b: workspace gradients/sidebar work. 1.10.2b: folders + compact tweaks.
  - 1.16b (2025-09-22): command bar actions (toggle Compact Mode from URL bar), open extensions by typing name, new split-view creation UI, cmd+alt+= split shortcut.
  - 1.17b (2025-10-21): unified site-controls panel (permissions, security, add-ons, quick actions), compact-mode toolbar button, copy-URL button, macOS Tahoe look-and-feel, OS accent colour when no theme.
  - 1.19b (2026-02-28): Live Folders (auto-fill folders from GitHub issues/PRs or RSS), drag tab on another for 1s to offer split, native macOS popovers. 1.19.4b: grain. 1.19.12b: space-swipe perf, local translation.
  - 1.20b (2026-05-24): Boosts (tint colours, fonts, zap elements, auto dark mode per site), stronger fingerprint protection.
  - 1.22b (2026-09-05): sync of Spaces/Folders/Tabs via Mozilla account (Settings > Sync), squircle chrome, onboarding flow, faster space creation, reorderable containers.
  - 1.23b (2026-10-02): "Library" (history, media, downloads, spaces in one place), resize sidebar while hidden (auto-hides when too small), hardware AV1 WebRTC decode.
- Takeaway: Zen shipped boosts and cross-device sync only ~2.5 years in; before that "window sync" meant same-device multi-window sync, which caused the biggest regression class (see section 5).

## 2. Feature inventory (with Wayfinder tag)

### 2.1 Spaces / workspaces
- Workspace = named group of tabs with own icon (emoji), name, theme (gradient + grain + opacity), optional default Firefox container. Icons shown at bottom of sidebar; swipe (trackpad) or shortcut to change. Docs: "workspaces bring flexibility of multiple windows into one".
- Containers per workspace: workspace can have default container (Personal/Work/Banking/Shopping + custom; 9 colours, 13 icons) -> separate cookie jars per space. Regular tabs = "No Container".
- Shortcuts: backward/forward workspace Alt+Ctrl+Q / Alt+Ctrl+E; "Switch to workspace 1-10" unbound by default; "Create new space" added to settings in 1.19.12b.
- Workspace-specific bookmarks exist. Open request: rules to route URL to a workspace (disc #786, 29 up), archive unused spaces (#13192), per-container download folder (#15149), CMD+N default space (#16188), filter URL-bar history by space (#16193).
- Per-workspace colour was a top ask (disc #819, 30 up) then shipped as gradient themes.
- Tag: **MUST-HAVE** (spaces with per-space theme + cookie isolation). Wayfinder already has Spaces model; WebKit equivalent of containers = separate `WKWebsiteDataStore(forIdentifier:)` per space (macOS 14+). That is a strong differentiator vs Zen's Firefox containers (which are bolted on).

### 2.2 Essentials
- Favicon grid at top of sidebar, shared across all workspaces (global) or per-workspace (setting); clicking an essential keeps its URL; close button "unloads"; has reset-to-original-URL behaviour. Glance auto-triggers on off-site link clicks in Essentials/pinned (no Alt needed).
- Bugs: moving essential to new window removes it from essentials (#8309), reopening closed tab duplicates essentials (#10302), closing tab opened from essential -> blank window (#6968 closed), loading dot missing (#9403).
- Tag: **MUST-HAVE** (Arc "Favorites" parity). Keep invariants simple: essential tab object never destroyed on close.

### 2.3 Pinned tabs and folders
- Pinned tabs per workspace, below essentials; have "reset" button to go back to pinned URL (mods exist to hide/restyle it: "Hidden Reset Button", "Only Reset On Hover", "No pinned tab reset btn" -> UX of reset button is contentious).
- Folders in sidebar (since ~1.10.2b), nestable, drag/drop; tab groups; "Hierarchical Tab Groups" was a 44-up request (#525, closed).
- Live Folders (1.19b): GitHub issues/PRs/RSS auto-populate folders. HN submission got interest ("RSS and GitHub PRs first-class").
- Tag: pinned+folders **MUST-HAVE**; live folders **NICE** (RSS folder cheap to build with URLSession + Atom parsing; GitHub variant needs API auth).

### 2.4 Compact mode
- Toggle via right-click toolbar, toolbar button (1.17b), command bar, or shortcut (docs list Ctrl+S in text, Alt+Ctrl+C in shortcut table: docs inconsistent). Floating sidebar toggle Alt+Ctrl+S, floating toolbar Alt+Ctrl+T.
- Variants (multi/collapsed toolbar modes): Hide sidebar / Hide toolbar / Hide both. In Single Toolbar mode compact = hide sidebar; reveal by hovering the edge (left, or right if "tabs on the right").
- Options: briefly pop toolbar when switching/opening tabs in compact mode (Settings > Look and Feel > Theme Settings); hover-area width requested (disc #7843); "Smaller Compact Mode" mod shrinks height.
- Compact backgrounds transition smoothly across spaces (1.16b). Fullscreen does not auto-enable compact (disc #801, 30 up).
- Bugs (macOS heavy): compact mode resets on startup (#8606, 54 up, closed), sidebar stuck open when compact enabled (#8643, 33 up), macOS sidebar freezing/auto-hide (#13504).
- Tag: **MUST-HAVE**. Persist as a single source-of-truth setting; do not derive from window state at launch (root cause of #8606 class).

### 2.5 Split view
- Create: drag tab to left/right edge of another; right-click link > "Split link in new tab"; select multiple tabs in sidebar then toggle layout; cmd+alt+= (1.16b); hold-drag tab on tab 1s (1.19b).
- Layouts: horizontal (Alt+Ctrl+H), vertical (Alt+Ctrl+V), grid (Alt+Ctrl+G); unsplit all Alt+Ctrl+U. Per-pane overlay: drag handle ":::" to rearrange (any side), "-" to unsplit. Drag-resize splitters (request #768 40 up, shipped). Max pane count: UNVERIFIED (docs do not state; grid implies >= 4). Mod "NoHighlightSplit" removes active-pane border; "Vertical Split Tab Groups" lists split groups vertically.
- Tag: **NICE** (distinct feature in Arc/Zen; two-pane is cheap with NSSplitView, grid is more work).

### 2.6 Glance
- Alt+click link (configurable Ctrl/Shift) opens modal overlay preview; buttons: close (also click outside), expand-to-tab, add-to-split. Animation "lifted off the page" (1.17b). Auto on off-site links in pinned/essentials. Verge calls it a favourite. Disc "Peek" (#790, 36 up) was the origin.
- Tag: **MUST-HAVE** for Arc-Peek parity; WKWebView in overlay sheet is easy.

### 2.7 Zen Mods (see section 3)
- Tag: **SKIP as CSS-injection-into-chrome** (no equivalent in AppKit/SwiftUI). **NICE**: a curated set of built-in appearance toggles and a user-stylesheet-per-site system (Boosts equivalent).

### 2.8 Workspace themes (gradient/grain/opacity)
- Per-space gradient (multi-dot colour picker on a wheel, algorithms: complementary/analogous/triadic etc., UNVERIFIED which), grain slider (1.19.4b), window opacity/transparency; OS accent colour as default (1.17b). Transparency perf bug fixed on macOS in 1.17b. The "Zen Colored Picker" mod adds the rainbow colour pad. Other agent covers picker detail.
- Tag: **MUST-HAVE** (core identity; use NSVisualEffectView + gradient layer; macOS 26 Liquid Glass can be the substrate).

### 2.9 Keyboard shortcuts customisation
- Settings > Keyboard Shortcuts lists everything, incl. split, compact, workspaces (1-10), tab nav. Defaults use Alt+Ctrl+<key> (non-conflicting with sites) on Windows/Linux; macOS maps to Opt+Cmd. 
- Pain: shortcuts intercepted by sites, e.g. Cmd+S (#9903), copy-URL shortcut not prioritised over site (#8894, 30 up), Cmd+Q / Cmd+, not working at all in early builds (#1629, 33 up), "Pin tab" shortcut (disc #793, 65 up), "Switch workspace" (#791). MacOS menu "Previous Space" broke (#13583).
- Ctrl+Tab behaviours: cycle in order (essentials, pinned, regular) or recently-used (setting); peek toolbar in compact.
- Alt+1..8 index counts essentials then pinned then regular; Alt+9 = last tab.
- Tag: **MUST-HAVE**: every command in menu bar with user-rebindable shortcut. On AppKit, menu key equivalents win over web content, so avoid Zen's site-interception class by default.

### 2.10 Tab unloading
- Auto unload of idle tabs (timeout setting, memory-pressure aware); manual "unload" on pinned/essentials close; unload-all-in-space; ghost style mods ("Better Unloaded Tabs", "Ghost Tabs") grey out unloaded.
- Bugs: auto unload not working (#8822, 43 up), unloaded tabs can't reopen (#2491, 32), keeps logging out of accounts (#7212, 38: unload drops session/ cookies in containers), unloaded tabs blank/frozen (#13391), unloaded tab loads when active tab closes (disc #13919).
- Tag: **MUST-HAVE** (core to battery/RAM story). WebKit: drop WKWebView, keep snapshot + scroll/session state (`interactionState`).

### 2.11 Toolbar layouts (vertical / horizontal / collapsed / single)
- Three modes: Single Toolbar (URL bar compacted in sidebar, Arc style), Multiple Toolbars (sidebar + top bar), Collapsed Toolbar (sidebar icon-only).
- FAQ: horizontal tabs not planned ("core design choice"); #158 horizontal tabs 37 up closed; mod ecosystem fills gaps. Tabs on the right supported. Sidebar resizable even when hidden (1.23b).
- Mods: "Hide Toolbar" (even in single mode), "Lean", "Super Sleek UI", "NavBar Margin", "Load Bar" (loading bar for single toolbar mode).
- Tag: **MUST-HAVE** single toolbar in sidebar (Arc look, already in Wayfinder plan). Multiple-toolbar **NICE**. Horizontal tabs **SKIP** (Safari users still expect it? Offer as setting later).

### 2.12 URL bar modes
- Settings > Look and Feel > Zen URL Bar: Floating only when typing (default; Cmd+T / Cmd+L opens centered panel; clicking keeps top), Always floating, Normal (attached top).
- Floating URL bar was divisive: #3539 "option to disable floating URL bar" 90 up, #3649 "new URL bar so annoying" 33 up. Zen added the Normal option in response.
- Features: switch to tab, search with engines + shortcut keywords (@bing etc.), open extension by name, switch space by name, actions (compact toggle), unified site panel, copy URL button, "Top Sites" in dropdown (mod "No Top Sites").
- Bugs: search shows URLs instead of titles (#9653, 36 up), shows history despite opt-out (#8404), "legacy new tab" mechanism option, history filter by space missing.
- Tag: **MUST-HAVE** (command bar is the centrepiece; ship floating + docked modes from day one).

### 2.13 Media controls and PiP
- Sidebar media controller (play/pause/mute indicators on tabs; mods "Audio Indicator Enhanced", "Quietify", "Bigger Mute Button"). Firefox PiP; auto-PiP on tab-switch is hidden pref `media.videocontrols.picture-in-picture.enable-when-switching-tabs.enabled`.
- Asks: PiP should float above fullscreen apps on macOS (disc #6555, 45 up), PiP trackpad gestures move/resize (#9002, 24), PiP empty window bug (#11881). Mod "Pimp your PiP".
- Bugs: Google Meet audio (#10394), YouTube A/V desync (#12921), video controls under screen in fullscreen (#10594, 36 up), ZenCP Isolated Web Content process pegs cores after media (#9727).
- Tag: **MUST-HAVE** auto-PiP on tab switch + media key support; WebKit has `WKWebView` PiP and AVPictureInPicture natively. Already in Wayfinder (NativePiP.swift) per git status.

### 2.14 Sidebar web panels
- Firefox sidebar-ish extension panels only; no first-class Arc/Vivaldi web panel. Disc requests exist (UNVERIFIED count). Tag: **NICE** (Yab-style panels); **SKIP** for v1.

### 2.15 Sync
- Same-device "Window Sync" (all windows share one set of tabs/essentials/pinned); session backup every N min into `zen-sessions-backup/` as jsonlz4 (since 1.18). Cross-device: Spaces/Folders/Tabs via Mozilla account (1.22b). Before that: Firefox Sync + "Send to Device".
- Tag: window sync **SKIP as default** (see #12008: "Disable window/tab sync by default" 79 up, #7079 meta 165 up). iCloud-based sync of spaces/pins/folders **NICE** (CloudKit or iCloud KVS).

### 2.16 Profiles
- Firefox profile manager (about:profiles) with docs guide; no in-window profile switching. Request "multiple profiles in one window via workspaces" is top-4 discussion (#818, 136 up) and issue #500 (29 up) -> containers per workspace were the answer.
- Bugs: can't edit/delete profile (#9472 macOS).
- Tag: **MUST-HAVE** separate data stores per space (answer to #818). Full profiles **NICE**.

### 2.17 Welcome / import flow
- Import from Firefox/Chrome/Safari via Firefox migration wizard (#221 "import from Firefox not available" 39 up closed). New on-boarding experience (1.22b). Default theme picks OS accent colour. Choose default browser step, essentials seeding unverified.
- Tag: **MUST-HAVE** import (Safari/Chrome/Arc); onboarding **NICE**.

### 2.18 Other notable
- Translations: local Firefox Translations (page, selection, link text), no cloud. **NICE** (Apple Translation framework on macOS 15+ is a native analogue).
- Library (1.23b): unified history/media/downloads/spaces. Missing multi-select bulk delete (#15668, 14 up). **NICE**.
- Extensions: full Firefox add-ons; overflow extensions appear below URL bar (single sidebar, 1.20b). Wayfinder has WebExtension work (Extensions.swift); **NICE**.
- DRM: no Widevine => Netflix/Spotify/Disney+ etc. fail (FAQ, #10689 28 up). WebKit has FairPlay so **Wayfinder wins here: advertise it**.
- Passkeys/security keys: "touch security key does not work" #437 139 up (closed); iCloud Passwords extension broken (#6315, #7210); Entra SSO on macOS (#10498, 32 open); smart card auth broken (#7144). WebKit gets these natively: **MUST-HAVE to not break**.
- Vim mode (#488, 51 up), command palette (#494, 29 up; disc #820, 203 up, top Ideas discussion), native PWA support (disc #800, 178 up), Arc "Developer Mode" (disc #11016, 41 up).
- AI: Zen is deliberately AI-free (Verge). Local LLM summarisation asked (disc #3120, 8 up). **SKIP** unless opt-in.
- No mobile app (FAQ): vertical tabs "do not translate to mobile". iOS app asked (disc #753, 25 up).

## 3. Mods ecosystem

### 3.1 Structure (from docs + source, design ideas only)
Store: github.com/zen-browser/theme-store; one folder per mod keyed by UUID under `themes/<id>/`. Files:
- `theme.json` : id, name, description, homepage, style (URL to chrome.css), readme (URL), image, author, version, tags, createdAt, updatedAt, and boolean `preferences` (= has preferences.json). Master index `themes.json` rebuilt by CI on submission. At time of writing the index has 77 entries (last commit 2026-03-11). UNVERIFIED whether the live site shows more; the official site /mods is a client-rendered page.
- `chrome.css` : CSS only. No JS. Targets browser chrome (XUL/HTML in the Firefox UI), not web content.
- `preferences.json` : array of prefs. Fields: `property` (dotted pref name e.g. `mod.mymod.x`), `label`, `type` (`checkbox` | `dropdown` | `string`), `options` (dropdown only, list of {label,value}), `defaultValue` (optional), `disabledOn` (optional OS list e.g. ["macos"]), `placeholder` (dropdown/string).
- `readme.md`, `image.png`.

Loading (src/zen/mods: ZenMods.mjs, nsZenModsBackend.cpp, ZenStyleSheetCache.cpp, nsIZenModsBackend.idl):
- Installed mods live in profile `chrome/zen-themes/<id>/`; a manifest JSON records enabled flag and versions.
- On startup and whenever pref/toggle observers fire, the JS concatenates all enabled mods' chrome.css into a single generated `zen-themes.css` (header says "DO NOT EDIT"), then calls a C++ XPCOM backend (`rebuildModsStyles`) which re-parses it into a dedicated user-level style sheet in a cache and marks styles changed -> live apply without restart. 
- Sandbox model: CSS in a user-origin sheet cannot run script or touch web content. The trust boundary is "CSS only"; no permissions system, no review beyond GitHub PR submission guidelines.
- Preference exposure: defaults written into prefs (`Services.prefs`) only if unset; values then pushed into every window DOM: `string` -> CSS custom property on `:root` (`--mod-mymod-x`, dots become dashes); `dropdown` -> hidden `<div id=sanitized-mod-name>` with attribute `mod-mymod-x="value"` so CSS uses attribute selectors; `checkbox` -> plain bool pref consumed in CSS via pref-based media/selector (exact selector UNVERIFIED). Settings UI auto-renders controls from preferences.json (switch / select / text input).
- Updates: client compares versions (semver-ish) against theme.json at `zen-browser.github.io/theme-store/themes/<id>/theme.json`; periodic auto-update check with retry; `updatedAt` surfaced.
- Design ideas for Wayfinder: (a) declarative "appearance mods" = JSON of typed settings (toggle/choice/string+color) mapped to a fixed set of native view tweaks, no code; (b) per-site "Boosts" = CSS/JS user stylesheets injected via WKUserScript/WKContentWorld (isolated world), exportable as shareable JSON with readme; (c) typed-pref schema with `disabledOn`, `defaultValue` is simple and sufficient; (d) live reapply without restart.

### 3.2 Popular mods (top ~25)
UNVERIFIED ranking: the store exposes NO install counts in `themes.json`, and Reddit/HN were not scrapable. List below is curated from names repeatedly recommended in blog posts (Super URL Bar, Zen Context Menu, Better Find Bar, SuperPins, Better Unloaded Tabs, Transparent Zen) plus store entries. "P" = has preferences.

| # | Mod | Author | What it does | P |
|---|-----|--------|--------------|---|
| 1 | Transparent Zen | sameerasw | Transparent tab backgrounds, smoother animations | P |
| 2 | Super URL Bar | (store, not in repo index snapshot) | Rounded, centred, borderless URL bar with blur; expands when typing | |
| 3 | Zen Context Menu | KiKaraage | Hide unused right-click menu entries | P |
| 4 | Better Find Bar | RobotoSkunk | Floating, theme-matched find bar (moves from bottom to top) | P |
| 5 | SuperPins | CosmoCreeper | Reworked UX for pinned tabs/essentials | P |
| 6 | Better Unloaded Tabs | Felkazz | Greyscale + transparent unloaded tabs | |
| 7 | Ghost Tabs | Seismix | Same idea incl. folders | |
| 8 | Sidebar Expand on Hover | StormAnon | Mini sidebar that expands on hover | P |
| 9 | Remove Tab X | xXMacMillanXx | Remove close X on tabs | P |
| 10 | Lean | KiKaraage | Declutter extensions/spaces/toolbars | P |
| 11 | Better Active Tab | HliasOuzounis | Bright line marking active tab | P |
| 12 | Hide Toolbar | devdinc | Hide navbar incl. single-toolbar mode | P |
| 13 | Smaller Compact Mode | n7itro | Reduce compact sidebar height | P |
| 14 | Bookmark Toolbar Tweaks | n7itro | Centre/hide icons/transparent bookmark bar | P |
| 15 | Audio Indicator Enhanced | Kaedriz | Polished audio indicator with visualizer | P |
| 16 | Tab Preview Enhanced | Kaedriz | Styled tab hover preview | |
| 17 | Improved Collapsed Tabs | xXMacMillanXx | Better collapsed-sidebar tabs | P |
| 18 | Big Essentials | leaferiksen | 32px essentials icons | |
| 19 | Cleaned URL bar | Dinno-DEV | Declutter URL bar | P |
| 20 | No Top Sites | Ivaon | Remove top sites from URL dropdown | P |
| 21 | Tab Numbers | philmard | Show tab number (matches Alt+N) | P |
| 22 | Private Mode Highlighting | danm36 | Obvious private-window cue | P |
| 23 | Pimp your PiP | shldk | PiP tweaks | |
| 24 | Floating History | ahmaadaziz | Theme-matched floating history panel | P |
| 25 | Hide Inactive Workspaces | GunGunGun | Collapse inactive space icons | |
Honourable: Tab Text Size, Compact tabs title, Better CtrlTab Panel, Colored container tab, Container Halo, Trackpad Animation, Animations Plus, Zen Colored Picker, Custom uiFont, Bleeding Corners Fix, Left close button, Only Close On Hover.

Observations (what mods tell us the defaults got wrong):
- Many mods hide things: reset button on pinned tabs, close X, back/forward, toolbar, top sites, status bar, extensions button. => Offer these as built-in toggles.
- Many make unloaded tabs visually distinct. => Dim unloaded tabs by default.
- Find bar, history panel, context menu, CtrlTab panel mods: native Firefox UI felt not-Zen. => A WebKit/AppKit app has the reverse problem; stay native.
- Transparency + corner artifacts ("Bleeding Corners Fix") show cost of custom-drawing chrome.

## 4. Top GitHub requests (by +1 / thumbs-up; counts as of 2026-10-27)

Issues (zen-browser/desktop). Status: C = closed, O = open. "Req" = feature request, "Bug".

| # | Issue | +1 | Status | Type | Title / gist |
|---|-------|----|--------|------|--------------|
| 1 | 7079 | 165 | C | Bug meta | Window Sync and session restore (tabs lost/duplicated across windows) |
| 2 | 437 | 139 | C | Bug | Touch security key (WebAuthn) does not work |
| 3 | 6302 | 114 | C | Perf | WebRender picture-caching not used (power/CPU) |
| 4 | 3539 | 90 | C | Req | Option to disable floating URL bar |
| 5 | 12008 | 79 | C | Bug | Disable window/tab sync by default |
| 6 | 8932 | 75 | O | Perf meta | Performance, consumption, memory leaks |
| 7 | 8606 | 54 | C | Bug macOS | Compact mode disabled on startup |
| 8 | 488 | 51 | C | Req | Vim mode |
| 9 | 525 | 44 | C | Req | Hierarchical tab groups |
| 10 | 8822 | 43 | C | Bug | Auto tab unload not working |
| 11 | 504 | 42 | C | Perf | Too much RAM |
| 12 | 7280 | 40 | C | Req | XDG base dir support (Linux) |
| 13 | 221 | 39 | C | Req | Import from Firefox |
| 14 | 114 | 38 | C | Req | Sidebery features / integration (tree tabs) |
| 15 | 7212 | 38 | C | Bug | Unload keeps logging out of accounts |
| 16 | 158 | 37 | C | Req | Horizontal tabs (declined by FAQ) |
| 17 | 9653 | 36 | C | Bug | URL bar shows URLs not titles |
| 18 | 10594 | 36 | C | Bug macOS | Video controls under screen in fullscreen |
| 19 | 3649 | 33 | C | Req | New URL bar "so annoying" |
| 20 | 1629 | 33 | C | Bug macOS | Cmd+Q / Cmd+, system shortcuts don't work |
| 21 | 8643 | 33 | C | Bug macOS | Sidebar stuck open with compact mode |
| 22 | 10498 | 32 | O | Bug macOS | Microsoft Entra Platform SSO |
| 23 | 7000 | 30 | C | Privacy | Unwanted connections / default search engine / transparency |
| 24 | 494 | 29 | C | Req | Command palette |
| 25 | 500 | 29 | C | Req | Multiple profiles in one window via workspaces |
| 26 | 10689 | 28 | C | Bug | No DRM (Widevine) |
| 27 | 8894 | 30 | O | Req/Bug | Copy-URL shortcut should beat site's shortcut |

Top Ideas discussions by upvotes:

| Disc | Up | Title |
|------|----|-------|
| 820 | 203 | Command palette |
| 800 | 178 | Native PWA support |
| 813 | 138 | Enhance split view |
| 818 | 136 | Multiple profiles in one window via workspaces |
| 807 | 113 | Search tabs keyboard shortcut |
| 793 | 65 | Add pin-tab keyboard shortcut |
| 6555 | 45 | PiP above other apps in macOS fullscreen |
| 11016 | 41 | Arc "Developer Mode" |
| 768 | 40 | Resize split views by dragging |
| 790 | 36 | Peek / preview websites |
| 8381 | 34 | Change Zen icon |
| 786 | 29 | Rules: URL -> workspace |
| 819 | 30 | Colour per workspace |
| 9002 | 24 | PiP trackpad gestures |
| 13192 | 15 | Archive unused spaces |

Pattern: nearly every top request is (1) tab/session integrity, (2) memory/battery, (3) keyboard/command access, (4) URL bar control, (5) profile isolation. Notice that fancy visuals do NOT appear.

## 5. Complaints

Reliability (most severe, most reacted)
- Tabs lost/duplicated/restored wrongly after introducing window sync (#7079 165, #12008 79, #4797 "all tabs gone after I close Zen" 30, #2601, #9313 "losing tabs randomly", #13354 "new tabs appear after restart" macOS). Docs now ship manual recovery steps with jsonlz4 backups. Lesson: sync-across-windows is a data-loss engine; make it opt-in, journal every mutation.
- Essentials/pinned invariants break under edge ops (move to new window, undo-close, close opened-from-essential).
- Unloaded tabs unresponsive/blank/logged out (#2491, #7212, #13391).

macOS-specific
- Perf/battery: "Obscene memory leak on Mac" (#12496, 24), "Battery Drain MacOS - High CPU" (#12464, 23), "laggy and consumes excessive energy" (#8428, 21), "Dramatic Slowing Down on MacOS" (#14754), "Lag and stuttering M1 Pro" (#14756), ZenCP process pegging cores after media (#9727), laggy scrolling (#9290, 19), picture-caching (#6302 114). HN comment 2026-06: "slow and heavy". HN 2026-01: "seemed laggy".
- Native feel: Cmd+Q/Cmd+, broke (#1629), Cmd+S intercepted by sites (#9903), macOS text replacements (#8158), Magic Mouse swipe between workspaces (#7713), blurred fonts (#2375 30), native popovers only arrived in 1.19b, Tahoe look in 1.17b, squircles 1.22b. macOS menu "Previous Space" broken (#13583).
- Compact mode: resets at launch (#8606), sidebar stuck/freezing (#8643, #13504), video controls fullscreen (#10594).
- Integrations: iCloud Passwords extension (#6315 29, #7210 19), passkeys/security keys (#437 139, #479 30), Entra SSO (#10498), smart cards (#7144), Teams/Meet screen share (#7037, 24), Meet audio (#10394), camera/mic permission prompts (#10471).
- Fullscreen/PiP: PiP does not float over other apps' fullscreen spaces (disc #6555 45).

Product/UX
- Floating URL bar forced on users (#3539 90, #3649 33), Zen "Normal" mode was the fix.
- No DRM: Netflix, Spotify, Disney+, Apple Music (FAQ; Widevine licence pending for 2 years). Verge Oct-2026 still lists it as top gripe, plus weak Web MIDI.
- Horizontal tabs refused; mobile app refused.
- Boosts exist but "not super obvious" and no browsable gallery (Verge update 2026-10-25).
- Keyboard shortcuts: site conflicts; defaults awkward (docs even show Ctrl-based names for macOS); non-Latin layout bug "default shortcuts don't work for 60% of world population" (#9127).
- Extension friction: pinned extensions vanish (#11449), Tab Session Manager broken by `tabs.query` change (#11210), extensions replacing passkeys (#11161).

Trust / privacy
- Mar 2025 HN "Zen browser had a backdoor enabled by default" (46 pts, 31 comments): a debug/remote-debugging style pref shipped on; fixed same day via PR #927. Community split: "open source works" vs "privacy-marketed fork run by young team flipping security prefs on vibes". Persistent recurring question "have they fixed the backdoor?" in later threads (Aug 2025 "Why I'm all-in on Zen", 130 pts). Also #7000 about unwanted connections and default search (30 up).
- Defaults borrowed from Betterfox; privacy differentiation is mostly Firefox's (Techlore comment).
- Enterprise/MDM (Okta VPN restrictions, disc #7439) and Entra SSO gaps.

Community discourse on tradeoffs
- "Everytime I go all in on a browser I go back to Chrome." Typical churn pattern: people leave over polish, DRM, perf.
- Tildes: a daily user left when workspaces became mandatory (prefers LibreWolf): forced concepts annoy minimalists.

## 6. Loved

- Closest living Arc clone, but open source, free, no AI, no account needed. Verge (2026-10-25): "rips off all the best bits of Arc, but skips the AI and bloat", "launcher-like pinned tabs, pop-over Glance". Arc is in maintenance mode / being sunset (Atlassian bought The Browser Company; focus on Dia).
- Extensions: full Firefox add-on ecosystem incl. uBlock Origin with MV2; Verge says Zen handles extensions better than Arc. HN: "Arc is dead because of manifest v3".
- Customisation: mods + userChrome; "heavily modified, extremely moddable/themable and UX driven Firefox".
- Spaces without separate windows: HN "switch between profiles without unloading them... on a call in work space and switch to personal".
- Floating Cmd+T bar: new tab, switch tab, search, run extension in one place.
- Tab model: Arc described as blend of bookmarks and open tabs ("like files: open or closed, in a folder hierarchy"); Zen reproduces it.
- Glance, compact mode, split view, translation local, Live Folders, Boosts (2026).
- Fast release cadence; responsive maintainers (backdoor fixed same day); growing from 0 to 45k stars in 2.5 years.
- Mozilla/Gecko engine independence (HN commenters want non-Chromium diversity); fingerprint resistance upgrades (1.20b).

### Zen vs Arc (what people say)
- Zen better: free/open, no AI, extensions, privacy, mods, ad-blocking (uBO), Linux/Windows support, cross-platform, active development, no account.
- Zen worse: animation polish and drag/drop feel, stability ("young"), DRM, Web MIDI, memory and battery on macOS, Boosts gallery, Arc's native Mac integration, Easels/Notes-style extras, folders for favourites (early), profile/account juggling per space.
- Zen vs Firefox: vertical tabs + spaces now partly in Firefox; Zen implementation preferred by some; others prefer plain Firefox + arkenfox for trust.

## 7. Implications for Wayfinder (WebKit/macOS)

1. Exploit what Gecko cannot: native FairPlay DRM, passkeys/iCloud Keychain/security keys, Apple Pay, Handoff, Safari-quality power efficiency, native AppKit shortcuts, Notification/Media keys. Zen's top issue clusters are exactly these.
2. Do not copy window sync as default. Per-window tab state with explicit shared Essentials; crash-safe journal of session state; keep periodic backups (Zen shipped backups in 1.18 after losing users' tabs).
3. Compact mode state: persisted setting; no inference on launch.
4. URL/command bar: floating default is good for Arc people but ship "docked" mode, history/title display, space-scoped suggestions, and open-by-extension/action/space names.
5. Spaces get isolated `WKWebsiteDataStore` (answer to #818 136 up). Make profile-like isolation first-class, not Firefox containers.
6. Tab unloading must keep login/session (cookie store persists in data store), restore scroll/form state, dim unloaded.
7. Provide Boost-like per-site customisation with a browsable gallery (Zen lacks one).
8. Keep a small set of built-in toggles that cover popular mods (hide close X, hide back/forward, dim unloaded, big essentials, pinned reset button on hover).
9. Splits: horizontal/vertical/grid + draggable resize + keyboard shortcuts; add max-pane limit and clear UX.
10. Add: PiP over fullscreen spaces, trackpad gestures, workspace swipe (Magic Mouse/trackpad).
11. Avoid the privacy-trust trap: audit network calls and defaults, document them in-app.
12. UNVERIFIED items to re-check before design lock: split max panes, exact compact shortcut on macOS, checkbox pref selector mechanism, store install counts.

## 8. Sources

- https://github.com/zen-browser/desktop (issues, discussions, releases, src/zen/*)
- https://github.com/zen-browser/desktop/releases
- https://github.com/zen-browser/theme-store (themes.json, themes/*)
- https://github.com/zen-browser/desktop/blob/dev/src/zen/mods/ZenMods.mjs
- https://docs.zen-browser.app/user-manual/workspaces
- https://docs.zen-browser.app/user-manual/compact-mode
- https://docs.zen-browser.app/user-manual/split-view
- https://docs.zen-browser.app/user-manual/glance
- https://docs.zen-browser.app/user-manual/urlbar
- https://docs.zen-browser.app/user-manual/window-sync
- https://docs.zen-browser.app/user-manual/pip
- https://docs.zen-browser.app/user-manual/shortcuts
- https://docs.zen-browser.app/user-manual/translate
- https://docs.zen-browser.app/themes-store/themes-marketplace-preferences
- https://docs.zen-browser.app/faq
- https://www.theverge.com/tech/1018275/zen-browser-arc-replacement
- https://news.ycombinator.com/item?id=44951799 (Why I'm all-in on Zen)
- https://news.ycombinator.com/item?id=43443494 (backdoor thread)
- https://news.slashdot.org/story/24/09/23/0353206
- https://tildes.net/~tech/1r9o/zen_browser_chrome_alternatives
- https://discuss.techlore.tech/t/zen-browser-an-arc-browser-alternative/10212
- https://dev.to/koshirok096/my-recommended-zen-mods-plugins-bite-size-article-53j1
- https://kitemetric.com/blogs/top-3-zen-mods-plugins-to-boost-your-browsing
- Reddit (old.reddit.com JSON) returned non-JSON; not used. Install counts for mods not publicly available.
