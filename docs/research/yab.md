# Yab ("Yet Another Browser") research

Researched 2026-10-27. Primary source: yetanotherbrowser.com (home, /changelog/*, /manual/*, /compare/*, /privacy, /terms, /developers, /ai, /download, sitemap.xml with 434 URLs). Version facts below are from the site itself; community facts are thin and flagged.

## TL;DR

- Yab = closed-source, free, macOS 15.4+, WebKit, Arc-clone shell (spaces, pins, folders, Peek, Split, one field for T/L) plus a very large agent/mail/store layer on top. Maker: Serafim Korablev ("Serafim Labs", hello@serafimlabs.io).
- 40 mac releases (0.1 to 0.40) in 30 days (Sep 26 to Oct 25 2026), plus 19 iPhone TestFlight builds. About 1,290 "Fixed" bullet lines in the changelogs. Velocity is the product; polish is chasing it.
- Public footprint is tiny: one HN submission (1 point, 1 comment), one blog (iThinkDiff), testimonials on the homepage. No Product Hunt, Reddit, YouTube, Mastodon or Bluesky coverage found. No public issue tracker.
- Fork of Search: NOT confirmed on any public Yab page (see below). Circumstantial evidence is strong.

## Fork relationship

Claim from the Wayfinder session: "yab's credits say yab is a fork of Search". What I could verify:

- yetanotherbrowser.com has NO credits/acknowledgements/licenses/about page (/credits, /about, /licenses, /acknowledgements, /open-source, /legal all 404). Terms, privacy, manual and all 434 sitemap pages have no mention of "Search", "Office Commun", "driceroland", "MIT" or "fork". The in-app About/Acknowledgements screen was not inspected (needs the binary) so the user's credits quote is UNVERIFIED by me. If it exists it lives in the app.
- The compare pages say, for Yab: "Closed source". MIT allows that but requires the copyright and licence notice to ship with the software.
- HN submission "Yab, yet Another Browser" (https://news.ycombinator.com/item?id=50218347, 2026-10-24, 1 point) has one comment from pamcake: "Brings in everything from: Arc, Dia, Chrome, Safari, Firefox, Brave" I'm skeptic. Where is the source code (with licenses and attributions)?" No reply. This is the only public attribution challenge.
- Search (github.com/driceroland/Search): MIT, "Copyright (c) 2026 Office Commun", created 2026-09-20, 2.7k stars, 267 forks, releases v1.0.5 (Oct 14), v1.0.6 (Oct 24), v1.0.7 (Oct 25). Yab 0.1 shipped 2026-09-26 (compare page says "September 25, 2026: Yab: First release"), 5-6 days after Search's repo was created.
- Textual and architectural overlap with Search's README (very strong circumstantial evidence):
  - Search: "Chrome extensions, without Chrome ... runs on WebKit's own extension engine ... where Chrome has APIs WebKit doesn't (bookmarks, history, downloads, side panel, offscreen documents, fonts, notifications, speech, OAuth sign-in), Search fills them in itself ... macOS 15.4 or later."
  - Yab manual /extensions: "Yab runs Chrome extensions on WebKit's own extension engine, the one Safari uses. Where Chrome has something WebKit doesn't, such as bookmarks, history, downloads, side panels, notifications, speech or signing in with your Google account, Yab fills it in ..." Requires macOS 15.4.
  - Search: "Bring yours in from Chrome, Arc, Dia, Brave or Edge". Yab: "bring the ones you use from Chrome, Arc, Dia, Brave or Edge".
  - Search: "Hide anything, for good (shift-cmd-H)", keep-awake sites, Split View with saved pairs, float video, passwords in login keychain tagged by app, ad blocker before the page, private tabs, AppleScript. Yab: hide elements, "Always keep these sites awake", Split View, floating video, keychain, ad blocker "inside WebKit itself, before a request is made", private tabs, AppleScript "as Arc and Chrome do".
  - Search ships `bench-mcp` (MCP server over a Unix socket) and AI*.swift files; Yab's "yab mcp" + CLI is the same shape, scaled up.
  - Same ~2 week window of heavy iteration; Search issue #690 asks for "Arc's Folder Previews", #691 "Peek window opens at 100% zoom".
- Not proof. Could be convergent (both target WKWebExtension on macOS 15.4). Treat "fork" as likely, attribution as unverified. Wayfinder is MIT-derived from the same upstream, so copying Yab *ideas* is fine; copying Yab *code* is impossible (closed) and unnecessary.
- Wayfinder should keep Search's MIT notice and credit upstream clearly (Yab's lack of visible attribution is exactly what drew the HN skeptic).

## Release history (macOS), all from /changelog/0.N

| Ver | Date (2026) | Headline features |
|---|---|---|
| 0.1 | Sep 26 | First release. One field for T/L (addresses, tabs, history, bookmarks, commands, settings, clipboard history, emoji, units, rates, sums). Agents (Claude Code, Codex on your own plan) in own tabs; chat column on right; selection commands via J; permission modes Ask/Auto/Bypass; `yab "..."` CLI + MCP. Spaces with colour on field of dots + grain, optional own sign-ins. Pins/kept tabs above a line, folders by dropping a tab on another, daily tidy of today's tabs. Independent windows, Split View, Peek (+Force Click). Passwords/passkeys/cards/addresses in keychain. Import from Chrome/Arc/Safari etc. Chrome Web Store extensions. uBlock-list blocker, hide elements. Translate, reading mode, page as Markdown. Capture. Floating call/video window. Meeting on pinned calendar. Developer Mode + DevTools card. Private tabs, sleeping tabs. Remappable shortcuts. Self-update. Telemetry via random install ID |
| 0.2 | Sep 29 | Ask-agent from field (Search/Ask/Task), Mail (Gmail, experimental, own space), Remind Me/Send Later/Undo Send, code-from-mail autofill, new welcome, menu at ShiftCmdK, live folders (GitHub PRs, Linear...), Routines, screen sharing from Yab's box |
| 0.3 | Sep 30 | Google connect in welcome, Calendar meetings, DevTools in Chrome's order, console errors handed to agent, yab://you memory notebook, Done cmd-return |
| 0.4 | Oct 1 | Mail splits (VIP/Team/Receipts), reply-all/forward/Bcc/rich text, invitations, per-extension site access, Site Controls (appearance, translate, hidden, float video in one place) |
| 0.5 | Oct 2 | Mail moved to Settings > Experimental, horizontal-scroll no longer triggers back/forward, crash-report setting respected |
| 0.6 | Oct 3 | Changelog body is a copy of 0.4 (publishing slip) |
| 0.7 | Oct 3 | Close tabs left/right, link rules by URL pattern, meeting notice with Join, downloads pinned bottom-left, site notifications, no white flash on tab switch |
| 0.8 | Oct 3 | Split View with an existing tab (pick in field), edit link rules, meeting card (Cron-style), copy file/path in downloads, password-manager extension wake no longer freezes window for seconds (1Password) |
| 0.9 | Oct 5 | The Store (boosts/plugins), Boosts in Site Controls, "Build It with Claude" / "Ask for It" (votes), spaces slide like Arc, tabs stay awake for hours |
| 0.10 | Oct 6 | Sidebar Left/Right/Off (tabs across top), local-network protection prompt, link-under-pointer status with click action |
| 0.11 | Oct 6 | Sync between Macs (spaces, tabs, folders, bookmarks, settings, routines, chats, 2 weeks history), call window captions, React DevTools |
| 0.12 | Oct 7 | Passwords/2FA/cards sync, selectable text in images (Live Text), Ask About Image, call window redraw |
| 0.13 | Oct 7 | Translate To any language, Put Tab to Sleep (context menu), Network in Detail, top-tabs open at end, Google icons |
| 0.14 | Oct 7 | Fix freeze after update, Arc-style Change Icon picker (every emoji) on pin/kept/folder, per-space Look chips in Settings, agents manage Gmail labels, mail stays local |
| 0.15 | Oct 8 | Folders in folders (5 deep), Favorites in field (ShiftCmdF), search-engine suggestions, extensions sync across Macs, Chrome Network panel |
| 0.16 | Oct 8 | Drag tab out of window with live preview, "always keep awake" sites (WhatsApp, Slack, Discord, Gmail...), Smart Zoom, page corners drawn once |
| 0.17 | Oct 8 | Sites' own PiP button opens Yab float, float video speed 0.5-2x and subtitles, Elements panel as Chrome's |
| 0.18 | Oct 9 | Open at Login (hidden), pop-ups kept back ("Window blocked"), "Page not working?" offers to disable blocker after 3 reloads in 20s, routines on any schedule, Look works as Arc's editor |
| 0.19 | Oct 10 | Density Comfortable (Arc's sizes) vs Compact, spaces row at column foot like Arc, pinned addresses, Liquid Glass in Look, Live Folders in Settings, Measure dock |
| 0.20 | Oct 11 | Swipes between spaces fixed, sign-ins persist, Zen/Firefox in Bring In, rewrites in place, Bookmarks display modes, lighter column |
| 0.21 | Oct 12 | iPhone public beta, site notifications with tab closed, Ctrl-Tab across every space, Dia spaces import |
| 0.22 | Oct 13 | Extensions no longer slow tabs, one ad blocker at a time (extension vs built-in), password managers (1Password/Bitwarden/NordPass) connect, extension side panels in the column |
| 0.23 | Oct 13 | Claude Chrome extension in side panel, much more of Chrome extension API (omnibox, tab groups, downloads, capture), Tampermonkey userscript prompt, smooth tab drag, ad blockers as fast as Chrome |
| 0.24 | Oct 14 | Claims: tabs open faster than Chrome, instant Back/Forward, 200 tabs in half Chrome's memory. Userscripts kept in Yab, Snippets (;name expansion, cmd-;), agent buttons on GitHub/Linear/GCal/Amazon/X |
| 0.25 | Oct 15 | Marked "Important update". PiP stays on 2nd display, mailto into Yab Mail, Find in PDFs, Outlook/Superhuman mail modes |
| 0.26 | Oct 15 | Tab cards say what is happening (draft unsent, call, page not working), chat-tab "answering" ring, Arc address menu, "Promises" Now row |
| 0.27 | Oct 16 | AppleScript as Arc/Chrome, cmd-W shows next page at once, Chat with Folder, closed folder restore as one line |
| 0.28 | Oct 16 | Folder from cmd-click/middle-click (AI-named), New Tab in Folder, Move folder to Space, edit own chat messages |
| 0.29 | Oct 17 | 1Password on macOS 26, Slack app links, location prompts, other mail (IMAP) experimental, agent file uploads |
| 0.30 | Oct 19 | Google Docs sharp on macOS 26.1/26.2, kept tabs in every window, Dia folders import (nested), artifact cards (Peek on click), bookmark menus, wrong-password-save fixes |
| 0.31 | Oct 19 | Halloween icons/drawings, update while closed, snippets import from Raycast/Alfred |
| 0.32 | Oct 20 | Watch a page (price drop/stock), tables to CSV/Excel, tabs to one PDF, agent-made files; Superhuman-style mail list |
| 0.33 | Oct 20 | Keep typed addresses in their space, Remove Personal space, Reading colours (System/Light/Dark/Sepia/custom), double-click sidebar blank for new tab, safe large blocklists |
| 0.34 | Oct 21 | Slow pages show loading bar at once, stop autocorrecting typed words on web pages |
| 0.35 | Oct 22 | Pin a Split View pair as one square, PDF fill and sign, Files search (downloads, attachments, sent) |
| 0.36 | Oct 23 | Gemini and Cursor as full agents, Today's tabs in every window, per-space search engine, Tidy, smoother scrolling/switching, many report-driven fixes |
| 0.37 | Oct 23 | Agents open own tabs not take yours, compact result previews, quick-answer icons, download names |
| 0.38 | Oct 24 | Extension menu dupes fixed, multi-file picker, custom Next/Prev Space shortcuts keep priority over page keys |
| 0.39 | Oct 25 | Typing in field responsive with huge history, boost permissions tightened (declared per-site), thin fading scrollbars, Settings clarity (site shows 0.39.7 as current download) |
| 0.40 | Oct 25 | Stop an agent but keep page, folder colour+icon together, per-space search, better Peek and sidebar controls, clearer split menus |

Also: a /changelog/nightly page exists (empty body when fetched). iPhone TestFlight builds: 0.0.1 (Oct 9, spaces/tabs/pins/chats, E2E sync, QR join), 0.0.2 (Oct 10, All Tabs like Arc Search), 0.0.10-0.0.14, 0.1.1-0.1.13 (Oct 26: iPad Split View, space swipe vs row-swipe gesture bug, stopped-process page reload fix). iPhone 0.1.4 has no page.

## Feature inventory (tag = what Wayfinder should do)

Search already has (grep of Wayfinder Sources + Search README): Peek, Split, Spaces + SpaceSwipe, Pins, TabGroup/Fold, Sleep, Hidden (hide elements), Float/NativePiP, Reader, Translate, Shield blocker + YouTubeAds, Import (Arc/Chrome/Safari etc.), WKWebExtension + Crx (Chrome Web Store), Passwords/Passkeys/ApplePasswords, Updater, Scripting (AppleScript), SidePanel, Profiles, AI*.swift, bench-mcp. Search lacks: Boosts/Store, live folders, essentials grid, sync, mail, userscripts, snippets, MCP for end users, iPhone, Look editor (Search has Dusk/DuskColours themes only).

### Shell
- Spaces + colour (MUST-HAVE, Wayfinder has spaces). Per space: name, emoji, colour+grain, optional own cookie jar ("sign-ins of its own"), own search engine (0.36), ctrl-1..9, Ctrl-Tab across spaces, swipe, space row at column foot. Off by default; "Turn On Spaces" turns existing tabs into "Personal".
- Look editor (MUST-HAVE, copy ranges). Window styles: Edge to edge / A colour (page as card) / Site's colour. Editor: draw a ringed dot on a field of dots = hue + saturation; two tracks: transparency and grain. Alt = slow drag, double-click track resets. Dark window = each colour a shade deeper. "Match Arc / Match Chrome" colour import. Per-space: Light/Dark/As Appearance, presets + gradients, +/- extra colours (multi-colour gradients), "Shift with tabs" (hue steps with each new tab), "Take the site's colour", "Drawings" overlay, Reset, Use for All Spaces. macOS 26 Liquid Glass bead at end of transparency track (past it = glass, colour a tint, sidebar text kept legible; Reduce Transparency/Increase Contrast = solid). Exact numeric ranges are not published; only slider semantics.
- Pins / kept / today's tabs (MUST-HAVE). Order: pins (squares, icon or letter), kept tabs, a line, today's tabs. cmd-W on a pin "puts it down" (unloads, pin stays). Daily tidy: tabs unvisited 12h (configurable 12h to a month or never) are closed on return with Undo notice. Pins/kept/playing/calls/downloading never auto-closed. Pin Pair: pin both halves of a split as one square (0.35).
- Folders (MUST-HAVE). Drop tab on tab; nested 5 deep; AI-named folders from cmd-click/middle-click chains; Move to Space; New Tab in Folder (alt-cmd-T); closed folder restores as one line "Q4 Planning · 7 tabs"; folder colour+icon; Chat with Folder; sleep a whole folder. Live folders (NICE): folder fed by GitHub PRs/search, Linear issues (RSS-like).
- Peek (MUST-HAVE; Search has it). Shift-click link opens over the page; Force Click; artifact cards open in Peek; pop out to tab.
- Split View (MUST-HAVE; Search has). Pick existing tab in field; pin pair; menus clarified in 0.40; separate address bars on iPad.
- T / L field (MUST-HAVE, Wayfinder has command bar). One box for addresses, search, tabs, history, bookmarks, commands, settings, clipboard history, emoji, calculator, units, rates, dates; Favorites row (ShiftCmdF); empty-field shows next meeting, copied link, scheduled opens; per-space engine; search-engine suggestions; site search; Ask/Task rows. Typing lag with huge history was a real bug (0.39).
- Sleep (MUST-HAVE; Search has). Memory-pressure driven (not timer): heaviest idle page first, one at a time until macOS relents; protects last-10-min tabs, audio in last minute, pins/kept, splits, calls, floating video, loading, downloads, unsent typing. "Keep these sites awake" list (WhatsApp, Telegram, Slack, Discord, Gmail). Manual Put to Sleep on tabs/folders. ⌘Q while agent runs sleeps tabs.
- Sidebar Left/Right/Off (tabs across top) (NICE; user asked about right-side). Density Comfortable (Arc sizes) / Compact. Downloads fixed bottom-left. Double-click blank = new tab.
- Windows: independent windows, tab drag-out with live preview, kept tabs in every window, Small window (floating mini). (NICE)
- Private tabs (MUST-HAVE; no agent access to them).

### Page / content
- Ad blocker (MUST-HAVE). WebKit content rules compiled from EasyList, EasyPrivacy, uBlock filters, badware, privacy lists, Peter Lowe's list (~160,000 rules claimed); weekly refresh with no cookies; per-site switch via lock icon or Settings > Privacy; YouTube: ads removed from player data, leftovers muted+sped+skipped; after 3 reloads in 20s on a blocked page, offers to disable; "one ad blocker at a time" prompt when an ad-blocking extension is added.
- Chrome extensions (MUST-HAVE; Search has the engine). Add to Yab button on CWS pages, paste link/id, import from Chrome/Arc/Dia/Brave/Edge by re-downloading; plain-language permission summary; CRX signature check; per-site allowed list, "On click"; pin to tiles with 1-8; side panels in the column; omnibox keywords, tab groups, downloads, capture; Claude extension works. Private tabs excluded by default.
- Boosts / Store (MUST-HAVE for customisation parity with Zen mods; user asked). Store lists ~70+ curated boosts (YouTube no Shorts/comments/related/home feed, Reddit hide promoted/wide thread, X no Grok/trends, HN readable, GitHub wide repo, Amazon no Rufus/sponsored, Google no AI Overview, Wikipedia readable, MDN/npm readable) each tagged "Works today" or "Not checked". Site Controls panel lists boosts for current site + store matches with Try. "Build It with Claude" generates one; "Ask for It" is a voting board. Boosts only click buttons on sites they declare (0.39). Plugins API + automations + publish flow in manual (/build-plugins, /plugin-api, /publish-a-boost). Userscripts (.user.js) kept alongside; Tampermonkey import.
- Hide elements (MUST-HAVE; Search has).
- Reading mode with System/Light/Dark/Sepia/custom colours (NICE). Page as Markdown/clean text (NICE).
- Floating video/PiP + speed/subtitles + site's own PiP button; call window for Zoom/Meet/Slack with captions (NICE).
- Translate Page / Translate To any macOS language (NICE; Search has).
- Capture region/full page framed (NICE). Find in PDF, PDF fill & sign (SKIP now). Snippets ;name expansion + Raycast/Alfred import (NICE). Calculator/units in field (NICE). Clipboard history (SKIP). Developer Mode + Chrome-ordered DevTools card + React DevTools + Measure dock (SKIP; use WebKit inspector).
- Local-network protection prompt (NICE, privacy plus). Pop-up blocking with "Window blocked" chip (NICE; Search has BlockedPopups).

### Import / identity
- Bring In (MUST-HAVE; Search has most): Arc (spaces, emoji, colour, grain, pins, kept tabs, folders, passwords, cards, bookmarks, history, extensions, sign-ins by reading Arc files locally), Dia (spaces, nested folders, favorites as pins), Zen/Firefox (bookmarks, history), Chrome, Safari, Brave, Edge.
- Passwords/passkeys/cards (NICE): keychain; 1Password/Bitwarden/NordPass connection; agents sign in without seeing secrets.
- Sync (NICE, later): E2E, no account; recovery key PDF; same-Apple-ID Macs auto-join; code + 4-digit match for other Apple IDs/iPhone; syncs spaces/tabs/pins/folders/bookmarks/settings/chats/routines/extensions/passwords/2 weeks of history. Wayfinder: skip until core is solid.
- iPhone beta (SKIP now): TestFlight, mirrors Mac spaces/tabs, chats answered by Mac agent.

### AI / MCP / Mail (scope creep zone)
- Agents: Claude Code, Codex, then Gemini and Cursor (0.36), billed on user's own plan; no Yab account; tabs of their own (up to 8 helpers); Send/Pay/Delete/upload gated; Ask/Auto/Bypass; Done closes agent tabs; Stop keeps page; memory as Markdown notes; skills; routines; watch-a-page; selection commands (J) with rewrite-in-place; site buttons; artifact cards. (NICE but only the MCP/driver slice.)
- `yab mcp` + `yab setup` writes MCP config and skill into Claude Code/Codex/Cursor/Zed/Windsurf/Claude Desktop (/developers page, ~50 tools across navigation, page, tabs/spaces, boosts, skills, sync devices, mail, tasks). (MUST-HAVE minimal: tab/space/page read-click-type tools; Search's bench-mcp is the seed.) Selling point: your signed-in browser, no Playwright profile.
- Mail (Gmail, IMAP, splits, snooze, send later, calendar) (SKIP). Wrapped, Halloween icons, referral-unlocked icons (SKIP).
- Telemetry: random daily ID counted for usage stats (opt-out), crash reports opt-in prompt. Search ships none (SKIP; Wayfinder should stay zero-telemetry, a differentiator).

## Right idea, weak execution

Evidence base: changelog fixes (what broke), Yab's own "honestly" limits on compare pages, HN comment, scope. No third-party bug reports exist publicly, so the shortfall list is inferred from the release notes and is labelled as such.

1. Idea: be Arc, exactly. -> Shortfall: shell fidelity arrived piecemeal and was repeatedly re-fixed: row density "as roomy as Arc's" only at 0.19; spaces row at foot at 0.19; Arc icon picker 0.14; Look as Arc's editor 0.18; Arc address menu 0.26; swipes between spaces "keep working" 0.20, again a frame of the old space flashing in 0.33, previous space's page behind a kept-only space in 0.36, Next/Prev Space shortcut priority in 0.38. -> Wayfinder: spaces model first (done); define one space-switch state machine (current space id + per-space stage) so swipe, shortcut, drag-to-foot, and cross-window all use it. Snapshot-test the transition frame.
2. Idea: "Look" editor with dot-field colour, grain, glass. -> Shortfall: not documented numerically, dark-mode dot showed white as black until 0.19, window styles three-way plus site colour plus shift-with-tabs plus drawings = many knobs; "Match Arc/Chrome" only imports colours. -> Wayfinder: ship hue/sat dot + transparency + grain, per-space, light/dark variants, live preview, reset/double-click, and write the ranges down (hue 0-360, sat 0-1, grain 0-1, transparency 0-1, defined defaults). Skip multi-colour gradients and drawings first.
3. Idea: sleeping tabs. -> Shortfall: memory-pressure-only plus special-case allow-lists grew each release (0.4 sleep while heavy, 0.7/0.8 stay awake overnight, 0.9 hours, 0.16 keep-awake list and macOS-says-short looping, 0.18 cmd-Q while agent runs, 0.32 cmd-W waking another sleeper). -> Wayfinder: model sleep as a single policy object with a tested protected-reasons set (audio, call, download, form-dirty, pinned, split, floating, recent). Show a visible dimmed state and the reason.
4. Idea: Chrome extensions in WebKit. -> Shortfall: 1Password/other extension wake froze the window for seconds (0.8), extensions slowed tabs (0.22), duplicate menu items (0.38), stale idle notices (0.37), leaked rule data (0.37), extension sign-in pages auto-opening on import (0.29), Surfshark reload loop (0.35), tab listed twice crashed Extensions (0.12). -> Wayfinder: Search already has ExtensionWorkerRecovery and tests; keep that, add a compatibility list (known-good: Bitwarden, uBO Lite, Dark Reader, Grammarly, 1Password; known-bad) shown at Add time.
5. Idea: bundled blocker with ~160k rules. -> Shortfall: breakage handling was bolted on later (0.18 "Page not working?" after 3 reloads, 0.22 single-blocker prompt, 0.33 "handle large blocking lists safely", 0.37 finished ads altering video speed/position, 0.38 videos wrongly selected for pop-out). YouTube is whack-a-mole. -> Wayfinder: per-site toggle in lock menu from day one, auto-suggest toggle on reload loop, size cap on compiled lists, test fixtures for YouTube player. Prefer WKContentRuleList categories users can toggle.
6. Idea: one field for everything. -> Shortfall: typing lag with large history (0.39), autocorrect altering web text (0.34, "Yab leaves what you type alone"), quick-answer icons ambiguous (0.37). -> Wayfinder: index history off-main with a bounded candidate set; never enable system autocorrect substitutions in page fields.
7. Idea: Store of boosts (Zen-mods analogue). -> Shortfall: curated by the author, "Works today / Not checked" status is manual, 70 items, no obvious user submissions beyond voting; boosts originally could press buttons on sites freely (permission tightened 0.39). -> Wayfinder: sandboxed CSS-first boosts, declared per-site permissions from the start, community-sharable JSON, diff/preview before install. Zen mods popularity = CSS themes, not agents; copy that.
8. Idea: agents-in-browser. -> Shortfall: a Mail client, routines, memory, skills, Promises, Wrapped, Halloween icons, PDF signing, Files search, in 30 days; agents initially took over existing tabs (fixed 0.37 "open pages in tabs of their own instead of taking over existing tabs"); Gemini connect "can no longer hang"; many agents each with distinct quirks. Mail reset into Experimental at 0.5. -> Wayfinder: expose a minimal MCP (list tabs/spaces, read page, click/type, screenshot) over the Unix socket Search already has; no mail, no memory, no plan-billing integration.
9. Idea: sync everything E2E. -> Shortfall: shipped within 11 days of launch (0.11); passwords sync 0.12; "tab listed twice from a chat or sync crashes tab bar" 0.12; shortcut changes on another Mac took effect only after 0.24. -> Wayfinder: defer; if done, ship settings+bookmarks only first.
10. Idea: ship daily. -> Shortfall: 40 versions in 30 days, changelog 0.6 duplicated 0.4 text, "Important update" at 0.25, point builds (0.39.7) not in changelog, nightly page empty; HN skeptic wants source. -> Wayfinder: slower cadence, accurate notes, open source with attribution.
11. Platform: macOS 15.4+, Mac-only, WebKit ("a site tested only in Chrome can misbehave" per Yab's own compare page), Google Docs needed a dedicated sharpness fix on macOS 26.1/26.2 (0.30), 1Password on macOS 26 (0.29). -> Wayfinder is already Xcode/SwiftUI/sandboxed; keep a WebKit-compat quirk list per site.
12. Trust: closed source + usage ID telemetry (opt-out) + claim "no account/no server" yet Sync server exists (sealed boxes). Privacy page is detailed and good, but code can't be audited. -> Wayfinder: open source, zero telemetry, say so on the front page.

## Community (what exists)

- Hacker News: one post, https://news.ycombinator.com/item?id=50218347, 1 point, 1 comment (the attribution skeptic, unanswered). Algolia search "yetanotherbrowser" returned only this.
- Blog: iThinkDiff, "Yab Is a Free Arc Alternative for Mac with Claude and ChatGPT" (reports v0.35.5, ~40 MB, no account, macOS 15.4+, Korablev). Promotional tone, repeats the site's claims.
- Homepage testimonials from X: dzlgfcb "so glad YAB is on webkit"; ArtyShatilov "i love every single part of yab !" (links x.com/dzlgfcb/status/2106064500206064052 and x.com/ArtyShatilov/status/2106133032415740175). Cherry-picked by the maker.
- Not found (searches returned nothing relevant): Product Hunt listing, Reddit (old.reddit.com blocks scripted access, web search found no thread), YouTube reviews, Lobsters, Mastodon, Bluesky, Discord/forum, public GitHub for Yab (gh search "yab browser" returned only unrelated repos). Support channel = in-app "Send Feedback" (Settings > About) and hello@serafimlabs.io. Treat the absence as "none indexed", not "none exist" - X search could not be queried directly.
- Competitor context: Arc frozen since May 2025 (Atlassian bought TBC); Zen (Firefox, beta labels), SigmaOS (stale since Feb 2025), Nook, Ora (open-source WebKit Arc-likes, Nook had 86 PH upvotes). Yab's real moat is velocity + agent hooks, not browser fundamentals.

## Wayfinder takeaways

1. Don't chase Yab's breadth. Copy shell parity (spaces/pins/folders/Peek/Split/field/Look) and a tiny MCP.
2. Boosts are the Zen-mods parity answer; copy Yab's per-site Site Controls + Store shape, make them CSS-first, permissioned, open.
3. Write down Look ranges and the sleep/blocker policies as tested units; Yab's churn shows what to specify upfront.
4. Keep MIT attribution to Search visible; Yab's silence is its biggest public reputation hit.
5. Zero telemetry + open source is the differentiator vs Yab's closed, opt-out usage ID.

## Sources

- https://yetanotherbrowser.com/ , /changelog , /changelog/0.1 ... /changelog/0.40 , /changelog/iphone-0.0.1 ... iphone-0.1.13 , /changelog/nightly
- https://yetanotherbrowser.com/manual/ (appearance, spaces, pinned-and-kept, folders, peek, tidy-and-sleep, ad-blocker, extensions, store, sync, privacy, mcp, updates-and-feedback)
- https://yetanotherbrowser.com/compare/yab-vs-arc , yab-vs-zen , yab-vs-sigmaos , yab-vs-chrome
- https://yetanotherbrowser.com/privacy , /terms , /developers , /ai , /download , /sitemap.xml
- https://github.com/driceroland/Search (README, LICENSE, releases, issues #690 #691)
- https://news.ycombinator.com/item?id=50218347 (via hn.algolia.com/api/v1/items/50218347)
- https://www.ithinkdiff.com/?p=351525
- Unverified: in-app credits text; exact Look slider numeric ranges; any Reddit/X/YouTube sentiment.
