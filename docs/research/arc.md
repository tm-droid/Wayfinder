# Arc (The Browser Company) - deep-dive research for Wayfinder

Researched 2026-10-27. Scope: everything except the narrow sidebar/command-bar/boost/space-colour/peek/split specs (covered elsewhere).
Confidence tags: [V] verified in a primary/secondary source fetched this session; [K] from background knowledge, not re-verified this session; [?] unverified/conflicting.
Wayfinder assumption: macOS, WKWebView (WebKit), no AI agent yet, so AI features are mostly SKIP or NICE-later.

---

## 0. Headline: Arc is dead as of 2026-12-22

- [V] On 2026-10-22 The Browser Company (TBC, owned by Atlassian) announced "We've decided to sunset Arc on December 22, 2026" (arc.net/farewell, TechCrunch, Wikipedia).
- [V] Stated reason: "Keeping a browser secure takes constant, dedicated work ... Dia ... was built from the ground up to meet today's security standards, so that's where our engineering and security teams will focus."
- [V] Phases: new Arc account signups closed 2026-10-22. Arc Search (iOS) 2026-11-23: Browse for Me and other AI features off, no sign-in or sync, "lite" mobile browser stays (iOS Settings > Export Open Tabs available since 10-22). Desktop (macOS + Windows) stops working 2026-12-22; accounts deactivated, personal data deleted within ~30 days [V via secondary search summary].
- [V] Migration promise: passwords, bookmarks, extensions, history import into Dia; Spaces, Folders, Tab Groups "import over with your data intact" (Spaces are called Profiles in Dia). "Browser features you use in Arc are free in Dia, and the AI is optional."
- [V] Not open-sourced: Arc sits on the proprietary Arc Development Kit (ADK), which is also Dia's engine core. Open-sourcing Arc = leaking Dia IP (Miller, 2025 letter + reaction coverage).
- [V, HN 50197601 "A farewell to Arc browser", 286 pts] Top reactions: "what are you moving to" -> Zen dominates; anger about VC product risk; some report Dia import of Arc account failed; others say Dia "genuinely good, AI can be turned off" but distrust Atlassian.
- Implication: there is a large, newly homeless user pool in Nov-Dec 2026. Wayfinder (WebKit, native macOS, no account required) can position directly at it. Import-from-Arc (bookmarks/pinned/spaces JSON) is high leverage. Arc stores sidebar state in `~/Library/Application Support/Arc/StorableSidebar.json` [K] - worth verifying before building an importer.

---

## 1. Timeline

| Date | Event | Conf |
|---|---|---|
| 2019 | TBC founded (Josh Miller CEO, Hursh Agrawal CTO) as "Browser Company"; originally pitched a "browser as OS" | K |
| 2020-2022 | Seed/Series A/B (~$68M total per Crunchbase quoted in HN, Sept 2024; later reported larger rounds incl. 2024 Series B ~$50M at ~$550M valuation [?]) | K/? |
| 2022 | Arc for Mac private beta, invite/waitlist-only. Waitlist later widely mocked as friction (HN comment: "asinine sign up waiting list") | K / V(HN) |
| 2023-07-25 | Arc 1.0, open to everyone on macOS (The Verge) | V |
| 2023 H2 | Arc Max beta (AI: rename tabs/downloads, 5-second previews, Ask on Page) | K |
| 2024-01 | Arc Search for iOS (Browse for Me, pinch-to-summarize) | K |
| 2024-04/05 | Arc for Windows (Swift on Windows, WinUI) - "huge, difficult undertaking" per HN, but permanently feature-lagged vs Mac | K / V(HN) |
| 2024-02/04 | Live Folders announced (Feb) then shipped (Apr); GitHub Live Folders added later | V (search summary) |
| 2024-08-25/26 | Boosts Firebase vuln found (xyz3va), patched next day | V |
| 2024-09-19 | Public disclosure; HN thread 1469 pts / 498 comments; CVE-2024-45489 | V |
| 2024-10 | TBC says Arc development moves toward "something new" (TidBITS: end of Arc announced Oct 2024, nothing said about Dia until May 2025) | V (TidBITS snippet) |
| 2025-05-27 | "Letter to Arc members": maintenance mode (security + bug fixes only). Dia declared the future. | V |
| 2025-06 | Dia beta (Mac, invite-gated); TidBITS: "Arc users feel left behind" | V |
| 2025-09-04 | Atlassian announces acquisition: $610M cash | V |
| 2025-10-21 | Deal closes; Miller stays CEO, Agrawal CTO, TBC "independent" | V |
| 2026-06 | Last macOS builds ~1.152.0 (Chromium 149) per tracker [?]; Wikipedia lists 1.142.1 on 2026-04-09 - sources conflict on exact last version | ? |
| 2026-10-22 | Sunset announced | V |
| 2026-11-23 | Arc Search AI + sync off | V |
| 2026-12-22 | Desktop Arc stops | V |

### The 2025 letter - key admissions (primary source)
- "Novelty tax": Arc "too different, with too many new things to learn, for too little reward." D1 retention strong (fanatics) but metrics looked like a pro tool (video editor), not mass-market.
- Usage stats (the most useful data in the whole saga for feature prioritisation):
  - Only **5.52%** of DAUs regularly use more than one Space.
  - Only **4.17%** use Live Folders (incl. GitHub).
  - **0.4%** use Calendar Preview on Hover.
  - Dia: chat-with-tabs used by 40%, personalization 37%.
- "Arc lacked cohesion", "Arc was bloated. We built too much, too quickly." Dia dropped TCA (Composable Architecture) and SwiftUI for performance (HN: "sunsetting TCA and SwiftUI").
- Security team grew 1 -> 5 for Dia (post-CVE).
- Core thesis: "traditional browsers will die... candle business."
- Scott Forstall (ex-Apple) advice quoted: Arc is a saxophone, make it a piano. Wayfinder takeaway: layered complexity, familiar defaults.

---

## 2. Feature inventory (macOS) - tagged for Wayfinder

Tag legend: MUST-HAVE (build early), NICE (after core), SKIP (not for WebKit/no-AI v1). "WK" = WebKit feasibility note.

### 2.1 Core model
- **Vertical sidebar, tabs/bookmarks merged** - sidebar IS the browser chrome; auto-hide, compact. MUST-HAVE (covered by other agent).
- **Spaces** (workspaces w/ own tabs, colour, icon, optionally own Profile). MUST-HAVE, but note 5.52% usage: make the single-space default flawless; spaces must be optional, not required onboarding.
- **Profiles vs Spaces**: Profile = isolated cookies/logins/extensions/history/downloads store (Arc "Profiles" shipped ~2023-24); Space = organisational container that *links* to a profile. Multiple spaces may share a profile; a space can be Personal/Work and switch auto. MUST-HAVE (isolated data stores). WK: `WKWebsiteDataStore(forIdentifier:)` (macOS 14+) gives per-profile isolated storage - exactly this. Separate download dirs/history DB per profile is app logic. [K for Arc detail; WebKit API K]
- **Archive** - auto-archive unpinned tabs after 12h/24h/7d/30d (setting); Archive view searchable; "tab archive" is how Today tabs avoid clutter. MUST-HAVE (cheap, hugely loved; see Loved). Covered in detail by other agent; here only: make the interval configurable and the archive searchable from command bar.
- **Command palette actions** (⌘T): not just URLs - actions ("Create Space", "Toggle Developer Mode", "Pin tab", "Copy as Markdown"...). MUST-HAVE: action registry pattern, every menu item exposed as a command. [other agent covers UX]
- **Keyboard-first**: most shortcuts below. MUST-HAVE.

### 2.2 Little Arc
- Small floating, window-less-chrome browser window for one-off links. Opens via ⌥⌘N or when another app opens a link (default: "Open in Little Arc" for external links). Shows a tiny toolbar; "Move to Sidebar" (→ your active space) or auto-closes; closes quickly with ⌘W; not in your sidebar/Archive until you "Keep". 
- Verdict: **MUST-HAVE** - consensus "workflow-changing, best missing piece in Zen/others". Still unmatched: Zen Discussions #5293 "Is there a plan to add features similar to Little Arc for Zen?" has 102 upvotes [V]; HN Ask thread: "the big missing piece [in Zen] is Little Arc"; PiunikaWeb Sept 2026 says a new browser "Crest" is the only one that replicates it [V snippet].
- WK: just a second NSWindow with a stripped-down chrome hosting a WKWebView in an ephemeral or current-profile data store. Easy.
- Key behaviours to copy: auto-focus on URL field; Esc / ⌘W closes; "Open in sidebar" promotes tab; default for external links configurable; remembers nothing unless promoted.

### 2.3 Air Traffic Control (link routing)
- Rules: when a link is opened *from outside the browser* (or any), route by URL pattern (domain, path, subdomain) to a specific Space/Profile or to Little Arc. Also "Open in Little Arc" default for unmatched external. Settings > Links > "Air Traffic Control", rules like `*.company.com -> Work space`, `figma.com -> Design space`; also "Always open in Little Arc" and "Open links from here in" per-source-app? (per-source-app matching: [?]).
- Verdict: **MUST-HAVE (simplified)**. Cheap (regex/glob list → space/profile), high payoff for multi-profile people, and it pairs with being the default browser. Add per-source-app (frontmost app bundle id) matching later - NICE.
- WK/macOS: register as http/https handler; `NSAppleEventManager` URL events; read `NSWorkspace.shared.frontmostApplication` at event time for the source app (approximate). Easy.

### 2.4 Easels
- Infinite-canvas whiteboards in the sidebar: drop links, live web captures (a live-updating web element), images, text, arrows; share via link; "live easel" can act as dashboard. Capture (screenshot) is a related toolbar tool.
- Community verdict: gimmick for most (a departing user lists Easels and Boosts as "gimmicky" [V]; HN suggested splitting Easels/Shared Folders into standalone apps). TBC itself said Arc "lacked cohesion".
- Verdict: **SKIP** (v1). Revisit "Notes" instead.

### 2.5 Notes
- Per-space/pinned quick notes in sidebar; block editor (headings, lists, code, to-dos, "Pinned Notes"); shareable. Nice for quick clipboard dumping.
- Verdict: **NICE** (low). Safari/Apple Notes users already have Notes. Consider simple "per-space scratchpad" later.

### 2.6 Library
- One view of: Media (all images/videos/audio you've opened - actually downloaded & media captured from tabs? - screenshots, Captures), Downloads, Spaces, Archive, Easels, Notes. Presented as a dedicated pane (⌘⇧L?). 
- Verdict: **MUST-HAVE (Downloads + Archive)**, **NICE (Media)**, rest SKIP. Downloads popover with progress, reveal in Finder, drag-out. Per-profile download folders were a Zen user request (Zen discussion #15149) - do it.

### 2.7 Media & Picture-in-Picture
- **Sidebar media controls**: audio/video playing in a background tab shows play/pause/seek in the sidebar (also Google Meet mute/leave). MUST-HAVE-ish: users loved it. WK: observe `WKWebView.mediaCaptureState`, `mediaPlaybackState` (macOS 15+) and JS `MediaSession` API; `pauseAllMediaPlayback`, `setAllMediaPlaybackSuspended`. Medium.
- **Mini Player**: floating always-on-top mini window for the playing tab (YouTube/Meet). Thumbnail pop-out. NICE→MUST for video users.
- **Auto-PiP**: when you switch away from a tab playing video it pops out automatically into PiP; returns when you come back. NICE-high. WK: `WKWebView` has native PiP via `<video>` webkitSetPresentationMode('picture-in-picture'); auto-PiP requires JS (`mediaSession` "enterpictureinpicture" action) or app-level injection on tab blur. Medium. Note Wayfinder repo already has NativePiP.swift.
- Zen Discussion #6555 "PiP should show above other apps in full screen" (45 upvotes) - PiP over fullscreen spaces is a real gap to nail.

### 2.8 Capture
- ⌘⇧5-style screenshot tool in browser: area / full page / visible; paste to clipboard, auto-saves to Library > Media, can annotate. NICE. WK: `WKWebView.takeSnapshot(with:)` + `createPDF`; full-page needs stitching or `WKSnapshotConfiguration.rect` with scrollHeight. Easy-medium. 

### 2.9 Link copying
- **⌘⇧C** copies current URL. Pasting into rich text yields a hyperlink with page title (Arc pastes as link); toast "Copied URL". Also "Copy as Markdown". MUST-HAVE (trivial, loved). Add copy-as-Markdown / plain / title+URL via palette.

### 2.10 Split View, Peek
- Covered by other agent. Note Dia kept Split View; Chromium 2025 added native split view.

### 2.11 Boosts
- Covered by other agent (CSS + JS site customization; zap mode). Security warning relevant: CVE-2024-45489 hinged on *synced, executable JS boosts*. If Wayfinder adds user scripts (WKUserScript), never auto-run synced JS; require per-script consent, signature, and never trust client-provided creator IDs. See §4.

### 2.12 Live Folders (RSS / GitHub)
- Folders auto-filled from a source: RSS/Atom feed, GitHub "my PRs / review requests / issues" etc. Items appear as tabs. Used by 4.17% of DAU [V].
- Verdict: **NICE (RSS) / SKIP (GitHub)**. RSS-as-folder is cheap and nerd-pleasing (parse feed, list as pseudo-tabs). Low demand, don't prioritise.

### 2.13 Developer Mode
- Toggle that gives each tab a dev-style tab strip (localhost labelled, preview of `localhost:*`, opens DevTools easily, shows page "Pinned developer tabs"?) Arc's Developer Mode: auto-opens DevTools, "localhost" pinned, inspect shortcuts, shows Command Bar dev actions. Zen Discussion #11016 "[Feature Request] Arc's Developer Mode" has 41 upvotes [V]. 
- Verdict: **NICE**. WK: Web Inspector is enabled via `isInspectable = true` (macOS 13.3+). Low effort wins: ⌥⌘I, auto-inspectable localhost, copy-as-curl not needed.

### 2.14 Site Search shortcuts
- In command bar type a keyword + Tab: "g" Google, "yt" YouTube, "gh" GitHub; add custom. MUST-HAVE (very cheap; Orion/Safari/Zen/Vivaldi all do it). Include DuckDuckGo-bang-like list; per-profile.

### 2.15 Pinned extensions
- Pin extension icons to sidebar toolbar; chrome extensions via Chrome Web Store (Chromium engine). Dev-mode extensions supported. [K]
- WK: Safari Web Extensions are the only native route (WKWebExtension API in macOS 15.4+/iOS 18.4+; MV2 & MV3 support via `WKWebExtensionController`). Users who rely on uBlock Origin/Bitwarden/1Password will check this first. HN: "Arc died to me when they moved to Manifest V3 and uBlock Origin stopped working. Switched to Zen" [V]. Wayfinder: ship a **built-in content blocker** (WKContentRuleList) so uBO-lite parity isn't blocked by extensions. MUST-HAVE (blocker); extensions UI NICE.

### 2.16 Window themes / appearance
- Per-Space gradient/colour/grain/opacity themes; window tinting; light/dark. (Space colour picker covered elsewhere.) Strong brand identity of Arc; Zen copied it. MUST-HAVE for feel. Cheap with `NSVisualEffectView` / macOS 26 Liquid Glass.

### 2.17 Calendar Preview on Hover
- Hover a date/time on a web page → popup of your calendar free/busy, Google Calendar connection. 0.4% DAU [V]. SKIP.

### 2.18 Arc Max / AI features (Wayfinder has no AI agent yet)
- **Tidy Tabs** (Tidy button): AI groups & names open tabs into labelled sections; Clear button purges unpinned tabs. Strongly requested clone: Zen Discussion #16175 "Arc-style 'Tidy' button: sort unpinned tabs into labelled sections" [V title]. Verdict: **NICE** - a rule-based (domain/title-keyword) Tidy needs no AI. "Clear" button (archive all unpinned) is the loved half. MUST-HAVE for Clear; NICE for rules-based group.
- **Tab titles / rename AI**: auto-renames pinned tabs/downloads/Easels to friendly titles. SKIP (or on-device later).
- **5-second previews**: hold ⇧ while hovering a link → AI summary card. SKIP (AI). A "link preview on hold" without AI (Peek-like) is covered by other agent.
- **Ask on Page** (⌘F → ask question, AI answers with highlighted passage). SKIP until AI exists. Note Find-in-page upgrade (match highlighting, regex) can be NICE without AI.
- **Browse for Me** (Arc Search iOS; Arc Max macOS): AI assembles a page from multiple searches. SKIP.
- **Instant Links / Max command bar**: ⌘T → "Search with ChatGPT/Perplexity" providers. Shortcut-based AI search providers are just Site Search entries. NICE (free).
- Strategic note: Dia usage 40% chat-with-tabs [V]. That's the pivot's reason. But HN sentiment (below) shows large sub-population wants AI fully removable. When Wayfinder adds AI: opt-in, off by default, no UI traces when off.

### 2.19 Arc Sync
- Account-based sync of spaces, pinned/favorites, folders, notes, boosts, easels across Macs/Windows and (limited) iOS. Required an Arc account (sign-in required even for local use - top complaint). 
- Verdict: **NICE (iCloud/CloudKit sync, no account)**. WK-native advantage: CloudKit/iCloud Keychain/Passwords, zero extra account. Avoid Firebase-like third-party BaaS with client-supplied IDs.

### 2.20 Default-browser rules
- Beyond Air Traffic Control: Settings > Links "Open links from other apps in: [Little Arc / Current space / Specific space]"; "Open links from Arc in..." Combined with ATC = default-browser rule engine. MUST-HAVE for default-browser users.

### 2.21 Misc lesser-known
- **Pinned tab pop-up** / "pin then split": folder pins. (Covered elsewhere.)
- **Tab previews on hover** - SKIP.
- **Quick Capture / drag to Easel** - SKIP.
- **Share → Arc Link Sharing / "Share tab"** (arcmeet...)? SKIP.
- **Cmd+Shift+D** toggle compact... see shortcuts.
- **Mute tab** (⌘⇧M?) [?] NICE.
- **Quick Switch / Tab Switcher** (⌃Tab recents; Wayfinder repo already has TabSwitcher.swift). NICE.
- **Pull-up pinned "Essentials"** covered elsewhere.
- **Gestures**: two-finger swipe in the sidebar between Spaces; trackpad "swipe to switch space" - MUST-HAVE (feel).
- **Auto-fill / Passwords**: Arc relied on Chromium password manager (Google). Wayfinder has Passwords/Apple Passwords already.
- **Pinned "Today" tab cleaner**: ties into Archive.
- **Ad blocker**: bundled uBlock Origin (Wikipedia). Yes: MUST-HAVE in Wayfinder via WKContentRuleList.
- **Reader Mode**: Arc lacked a real one; HN user wants "smarter reader mode that removes ads even on same-domain". Safari has Reader. Wayfinder: NICE (WebKit has `_WKReader`? private; use Readability.js).

### 2.22 Keyboard shortcuts (Arc, macOS) - cheat sheet [K - verify against Arc Help > Keyboard Shortcuts before copying]
- ⌘T command bar (new tab / search / actions) | ⌘L focus URL in command bar over current tab | ⌘⌥N Little Arc | ⌘N new window | ⌘⇧N new Incognito window
- ⌘S toggle sidebar | ⌘⇧C copy URL | ⌘D pin/unpin tab | ⌘⇧D pin to Favorites/top? [?] | ⌘W close tab (archive) | ⌘⇧T reopen closed tab
- ⌘⌃←/→ or ⌘⌥←/→ switch Spaces | ⌘1-9 jump to favorite/pinned tab | ⌃Tab recent tabs | ⌘⌥↑/↓ move between tabs in sidebar
- ⌘⌥S? split view create ⌃⇧+ → | ⌘⇧E (?) | ⌘⇧K? Open Library (⌘⇧L?) | ⌘⌥B / "Open Boost" via command bar
- ⌘F Find (Ask on Page via Max) | ⌘⌥I Developer tools | ⌘⇧P? picture-in-picture (⌘⇧P) [?] | ⌘E? Easel
- Design rule: every action also in palette; shortcuts user-rebindable (Arc never allowed full rebinding - see wishes).

---

## 3. Loved (ranked by evidence)

1. **The sidebar/vertical tabs + auto-hide**: "The Arc UX is still my favorite desktop browser UX out there even to this day ... auto-hiding sidebar, the pins, the smart folders, split tabs, command bar" [V, HN farewell thread]. "Loved the vertical tabs and I hope they land in Safari" [V]. Chrome copied vertical tabs/split view later.
2. **Spaces + pinned vs today separation** - mental model: pinned = apps, unpinned = scratch that auto-archives. Even with only 5.52% regularly using >1 Space, power users call it THE feature. Zen copied it ("sidebar tabs, pinned vs generic tabs, global bookmarks, spaces", HN).
3. **Little Arc** - "workflow-changing" (HN Ask thread); still missing in competitors.
4. **Command bar** (Spotlight-like, fuzzy switch, search tabs, actions) - "split view, command palette and tab search keyboard driven start to finish" [V HN].
5. **Auto-archive of tabs** (declutter without guilt).
6. **Design & whimsy**: per-space themes, grain gradients, pixel-art cat that chases the cursor on the CVE write-up page [V HN], polished motion. The brand was *delight*.
7. **Boosts** - custom CSS per site (dark mode for HN, Zen mode). A user: "I want ... custom webpage scheme (I created a dark scheme for HN)" [V HN].
8. **Peek, Split, Media controls, ⌘⇧C** - small compounding conveniences.
9. **D1 retention "fanatics"** [V letter]: those who learn it don't leave.
10. **Honest-ish comms (letter)**: "very well written piece of honest, unfiltered communication ... As a DAU I understand and respect the decision" [V] - minority view, but exists.

## 4. Complaints (ranked)

1. **Abandonment & trust**. Maintenance mode announced via a Twitter reply (HN: "went into maintenance-only mode with Arc to shift to Dia, without any real announcement. Just a reply to a Twitter post") [V]; TidBITS: no apology for Oct 2024-May 2025 silence [V]. "Never trust a product that takes VC funding" [V HN]. "Writing was on the wall" [V]. Now sunset: "Another dead VC browser."
2. **Sign-in requirement + telemetry**: Arc required an account; Firebase queries sent `hostPattern` (the hostname of every site you visited with Boosts) plus your user ID. HN commenter: "Does this make Arc the least private web browser currently in use?" [V]. Contradicted Arc's own privacy statement ("Arc doesn't know which sites you visit") [V HN quote]. 
3. **CVE-2024-45489 (Boosts/Firebase)**: Firestore rules let a client change a Boost's `creatorID`, so an attacker could attach a JS boost to any user ID and have it execute in the victim's browser, no site visit required. Found Aug 25 2024, fixed Aug 26; discovered by xyz3va; bounty $2,000 ("insulting", "I'm struggling to put into words how disappointing" [V HN]); NVD/INCIBE CVSS 9.8 vs TBC "low impact, no users affected". Comms delayed (public ~3 weeks later). Fixes: JS disabled by default on synced boosts, Firebase dropped for new features, ACL audit, security engineer hired, bug bounty program. Lessons for Wayfinder: never accept client-supplied ownership IDs; JS boosts are RCE-in-browser by design; don't sync executable code silently; ship a bug-bounty/security.txt; disclose within days.
4. **Performance / RAM / battery**: bloated; high memory & battery drain with many spaces [V skiddle blog]; Chromium base; TBC itself: "Arc was bloated" [V]. Dia rewrote without TCA/SwiftUI for speed.
5. **Chromium / Manifest V3**: uBlock Origin broke (Arc moved to MV3 w/ Chromium update) - cited as the exit trigger [V HN]. Chromium also means Google dependency and less distinct engine.
6. **Learning curve / complexity**: "saxophone" [V]. Users called Easels/Boosts gimmicky [V blog]. Hard to explain to non-nerds; sidebar-only UI disliked by "I want my browser faster and lighter, not whatever Arc did" [V HN].
7. **Windows parity**: Windows build lagged Mac and was never caught up [V Beebom/dev.to snippets].
8. **Sync fragility**: "If you rely on classic bookmarks or robust multi-device syncing, Arc's approach might frustrate you" [V]. iOS Arc Search never synced spaces fully.
9. **Waitlist** at launch (2022-23): friction, FOMO, then backlash [V HN].
10. **Business model opacity**: "had no answer" re sustainability [V HN]; 5+ years, 100+ employees, no revenue, $610M exit [V HN]. Users fear data monetisation. Wayfinder messaging: local-first, no account, no telemetry.
11. **Apple Silicon only** (no Intel) [V HN, mild].
12. **AI pivot resentment**: "AI seems like a feature to add to existing browsers, not something that needs its own dedicated browser"; "So the new browser uses AI to read your tabs? No thanks!" [V HN]. Counter-view: "Dia ... you can turn off the AI features, it's a well designed and thoughtful UX" [V HN].

## 5. Never-shipped / most-requested wishes (evidence mostly HN, Zen discussions, blogs; no ranked official list exists - [?] Reddit blocked/untested)

- Real **extension parity** (MV2/uBO), Firefox-engine or non-Chromium option [V HN wants non-Chromium].
- **Full keyboard rebinding / custom shortcuts** [K, long-standing Arc Reddit request].
- **Tree-style tabs of infinite depth / nested folders** [V HN Ask: "Full tree style tabs ... infinite depth"]; Arc folders were nested but not tab trees.
- **Multiple profiles in the same window** (cookie isolation per tab group) [V HN].
- **Better sync**: iOS-Mac spaces sync, bookmarks import/export standard, offline mode [V blog].
- **Linux / Android** (never existed); Windows parity [K].
- **Real reader mode** with ad stripping [V HN].
- **Focus mode / named workspace groups that hide everything else**, RSS integration [V blog/HN].
- **Developer Mode parity** and Little Arc in other browsers [V Zen discussions].
- **Open-source / self-host** (people asked for Arc open-sourcing; refused due to ADK) [V].
- **Per-space download folders** [V Zen #15149].
- **Archive unused Spaces** [V Zen #13192].
- **Filter address-bar history suggestions per space** [V Zen #16193].
- **Open external links in blank unsynced window on the display where click happened** [V Zen #16181] - multi-monitor nuance for Little Arc.
- **Mermaid/PlantUML in notes** [V HN joke-level].
- **Offline/local LLM summarisation (no cloud)** [V Zen #3120].

## 6. Where refugees went and why

Evidence is anecdotal (HN, blogs, Zen GitHub discussions, SupaSidebar/Sigma blogs - both vendors have bias).

| Destination | Why people pick it | Why not |
|---|---|---|
| **Zen** (Firefox/Gecko fork, MPL, free) | Closest clone: vertical tabs, pinned vs tabs, Essentials, Spaces/Workspaces, Glance (Peek), split view, compact mode, containers, uBO MV2, no AI, no account, open source. "Zen scratches most of my Arc itches" [V HN]. #1 answer in the farewell thread. HN 2024 launch thread 828 pts / 409 comments [V]. | Firefox-engine site breakage; macOS performance/memory (Zen "Performance, consumption and memory leaks" meta issue open since 2025-06) [V GitHub]; window/tab sync bug had 165 reactions; floating URL bar complaint (90); no Little Arc; no Windows-style polish. |
| **Dia** (TBC/Atlassian) | Official successor; imports Arc data (passwords, bookmarks, extensions, history); Spaces→Profiles, folders, tab groups, split view; "genuinely good" per a skeptic [V HN]; AI optional per TBC. | Distrust of TBC/Atlassian and AI; Arc import failed for some [V HN]; sidebar/spaces less central; "a browser extension in a trench-coat" [V HN paraphrase]. Mixed. Dia removed or demoted several Arc-isms to chase "piano" simplicity. |
| **Orion** (Kagi, WebKit) | Native WebKit on macOS, vertical tabs, Chrome+Firefox extension support, no telemetry, lighter RAM. Direct Wayfinder competitor: same engine. | Extension compat bugs; polish; (Kagi account not needed). |
| **Safari** | Free RAM/battery, Passwords, iCloud tab sync, Profiles, Tab Groups, macOS 26 refresh; HN: "hope vertical tabs land in Safari soon". | No vertical tabs/command bar/Little Arc/space theming; Apple pace. |
| **Vivaldi** | Ultra-configurable, tab stacks, tiling, mature vertical tabs, hover-reveal sidebar request; forum threads (Vivaldi forum posts) ask for Arc-style compact vertical mode [V search]. | Heavy settings, Chromium MV3 limits, aesthetic less Arc-like. |
| **Sigma OS / Sigma Browser, Radian, Crest, SigmaOS, Deta Surf, Fellou, Comet, Ghost** | Radian: "looks like Arc but made by an individual" [V HN]. Crest: only one with Little Arc equivalent (PiunikaWeb Sept 2026) [V snippet]. Deta Surf: better AI-in-workspace integration [V HN]. Sigma: sells "Arc workflow" + its own blog says Arc is better if you love organised spaces [V; vendor bias]. | Small teams: same VC/abandonment risk. |
| **Brave / Chrome / Edge / Helium** | Brave: tolerant of MV2-ish via uBO/own shields; HN user chose Brave for command palette+split+tab search now in Chromium [V]. | Not Arc-like. |
| **DIY / extension** | ArcThing (Chrome sidebar extension, HN Show), shi-yan/shrome (own browser, HN) [V]. | Fragile. |

### Takeaways on switchers' priorities
- They want Arc UX **without** VC/AI/telemetry risk -> local-first, no account, open-source-ish ethos is a *marketing* feature.
- They accept Gecko/WebKit only if the engine's sites work. WebKit risk: Chromium-only sites (Google Meet quirks, Figma, some enterprise SSO). Mitigation: Safari-compatible user-agent defaults, easy "Open in Chrome" escape hatch.
- Extensions are the #1 deal-breaker -> WKWebExtension support + built-in blocker.
- Dia vs Arc, from forums: Dia is "simpler, faster, more conventional", keeps vertical tabs and Spaces (renamed Profiles) [V Thurrott/USMobile]; loses whimsy/"playful" Arc identity and Boosts/Easels-style experimentation. Those who want AI: Dia; those who don't: Zen. The gap in market: **Arc-like UX + native macOS + WebKit + no AI + no account + Little Arc**.

---

## 7. Product/Engineering lessons for Wayfinder (condensed)

1. Ship Little Arc + link routing + sensible default-browser behaviour early; no one else does them well.
2. Make Spaces optional and invisible until needed (5.52% stat). Keep first-run = Safari-like.
3. Per-profile isolation via `WKWebsiteDataStore(forIdentifier:)`; spaces map to profiles.
4. No account, no third-party BaaS; sync via CloudKit/iCloud if at all. Zero-telemetry default; document it.
5. Treat JS boosts/user scripts as untrusted code: per-script consent, never auto-run synced code, strict origin allowlist.
6. Import tooling: Arc sidebar JSON, Chrome/Firefox/Zen/Safari bookmarks - target Dec 2026 refugees. Export Open Tabs parity (Arc Search lets users export).
7. Content blocker built in (WKContentRuleList) - replaces the "uBO bundled" Arc selling point.
8. Performance claims matter: ship tab discarding/unloading (Zen's "tab unloading", Safari's tab suspension) and advertise RAM numbers.
9. AI later, optional, removable without trace; consider on-device Foundation Models (macOS 26) for Tidy/summarise to dodge the cloud-privacy story.
10. Don't clone gimmicks (Easels, Calendar preview, Live Folders GitHub). Stats show <5% use.

## 8. Unverified / gaps (do before relying on this doc)
- Arc Help Center (resources.arc.net) returned HTTP 403 to fetch; exact shortcut list, Library contents, Little Arc/ATC settings paths in §2 come from background knowledge -> check against screenshots or the help center via browser (open -a Safari).
- Reddit (r/ArcBrowser) not accessed; "never shipped" list partly inferred from HN/Zen issue titles.
- Funding figures other than the HN-quoted $68M Crunchbase total and $610M Atlassian price are unverified.
- Last Arc version conflicts (Wikipedia 1.142.1 on 2026-04-09 vs tracker 1.152.0 on 2026-06-18).
- Dia open-signup date and whether Dia ships Little Arc-like windows: not checked.
- Oct 2024 "Arc stepping back" statement known only via TidBITS snippet.

## Sources
- https://arc.net/blog/CVE-2024-45489-incident-response (also serves the "A farewell to Arc" page content on 2026-10-27 fetch; sunset, migration, Arc Search phases)
- https://techcrunch.com/2026/10/22/arc-browser-sunsets-december-22-as-the-browser-company-doubles-down-on-dia/
- https://browsercompany.substack.com/p/letter-to-arc-members-2025 (stats, admissions)
- https://en.wikipedia.org/wiki/Arc_(web_browser)
- https://en.wikipedia.org/wiki/Dia_(web_browser)
- https://www.theregister.com/2025/05/27/arc_browser_development_ends/
- https://www.androidauthority.com/arc-browser-development-ends-3561650/
- https://tidbits.com/2025/06/20/dia-browser-debuts-with-contextual-ai-chat-but-arc-users-feel-left-behind/
- https://www.thurrott.com/?p=343150 (Dia carries Arc features)
- https://nvd.nist.gov/vuln/detail/CVE-2024-45489 ; https://www.sentinelone.com/vulnerability-database/cve-2024-45489/ ; https://www.techzine.eu/news/applications/124668/leak-in-arc-browser-fixed-after-one-day
- HN: https://news.ycombinator.com/item?id=41597250 (CVE, 1469 pts) ; https://news.ycombinator.com/item?id=45126358 (Atlassian, 523 pts) ; https://news.ycombinator.com/item?id=45128889 (Ask HN Arc/Dia features) ; https://news.ycombinator.com/item?id=50197601 (farewell, 286 pts) ; https://news.ycombinator.com/item?id=44102709 (Letter) ; https://news.ycombinator.com/item?id=41303974 (Zen launch)
- https://github.com/zen-browser/desktop/discussions (Little Arc #5293, Dev Mode #11016, PiP #6555, Tidy #16175, per-container downloads #15149) and issues (perf meta #8932)
- https://skiddle.id/posts/3lhj3mh32s227 ; https://feedbagel.com/post/switching-to-zen-browser-a-power-users-alternative-after-arcs-ai-pivot ; https://werd.io/why-im-all-in-on-zen-browser/
- https://piunikaweb.com/2026/09/23/the-best-life-after-arc-browser-not-ready-replace-arc/ (snippet only; fetch 403)
- https://www.sigmabrowser.com/blog/dia-vs-arc-browser-in-2026-ai-workspaces-switching (vendor bias) ; https://supasidebar.com/blog/zen-vs-arc (vendor bias)
- https://nohalo.substack.com/p/10-features-id-love-to-see-in-arc ; https://dev.to/sidtalesara/arc-browser-is-dead-and-dia-isnt-the-answer-a-deeply-frustrated-honest-review-21e8
