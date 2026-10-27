# UX specs: Arc / Zen / Yab reference for Wayfinder

Researched 2026-10-27. Legend: [V] verified from a cited source; [U] unverified (recollection or single third-party source); fetch limits noted.
Gaps: resources.arc.net returned 403/404 to fetchers (only search-snippet text of Archive and Favorites articles seen); Reddit blocked; Zen docs have no pages for Essentials/pinned/mods/themes beyond Glance, Split View, Workspaces, Compact Mode, Mods Registry.

---------------------------------------------------------------------------------------------------

## 1. Sidebar model: Favorites/Essentials, Pinned, Today, Archive

### Spec: Arc
- Layout top-down: Favorites (icon grid above space title) -> per-space Pinned (folders allowed) -> divider line -> Today (unpinned) tabs. [V arc help snippet, TidBITS]
- Favorites: shown in every Space, max 12 [V help snippet]. Add by dragging above the space title or right-click > Move To > Favorites. Remove by dragging down into Pinned/Today. [V]
- Pinned tabs are per-space and per-profile; closing a pinned tab keeps the row (tab "sleeps"/unloads) and clicking it reloads at the pinned URL. Navigating away shows the new page in the row; clicking the row's icon (or "Back to Pinned URL") returns to the pinned URL. [V TidBITS describes keep-URL + stay-in-sidebar; reset-button naming U]
- Pinned folders nest (Arc allows folders inside folders; depth cap not found [U]). Yab copies this: "up to five deep" [V Yab 0.15].
- Today: unpinned tabs. Auto-archive default 12h of inactivity; viewing/clicking a tab resets the timer. Timing set per Profile (options reported: 12h, 24h, 7d, 30d [V help snippet + substack, 12h/24h/7d/30d]). **Auto-archive cannot be disabled**; workaround = pin/favorite. Different timings across synced spaces cause problems. [V help snippet]
- "Clear" button at the bottom of Today archives all Today tabs at once (a divider-line action; leaves pinned). Right-click "Archive Tabs Below". [V gigazine, allthings.how]
- Archive: open via Command Bar -> type "View Archive"; restore icon per row on macOS. Library has an "Archive Tabs" box; right-click > "Clear Archive" or type "clear archive". Retention otherwise unbounded in what was found; searchability inside the archive view not verified. [V snippet / U for search]
- Drag rules (reported): drag above line = pin, below = unpin; dragging above space title = favorite. [V popsci]

### Spec: Zen
- Essentials: global across workspaces (but can be per-container, so Essentials tied to a container show only for that container) [V deepwiki / github discussion]; max 12 default via `zen.tabs.essentials.max` [V third-party deepwiki; 429 on refetch]. Restored automatically on restart. Glance auto-triggers (no modifier) when clicking an off-site link from Essentials or a pinned tab. [V docs]
- Pinned tabs: per workspace, look like regular rows under the Essentials grid; can be restyled to look like Essentials only through a mod (Superpins). [V discussion 8389]
- Pinned tab hover shows a reset button; mod "No pinned tab reset btn" hides it. Reset-to-pinned-URL is also available as a keybind with no default (Workspace 1-10 and Reset pinned tab unbound). Pref "Restore pinned tabs to their originally pinned URL on startup" exists. [V zen mods listing, fastshortcuts]
- "Unload": tabs can be unloaded; pinned/essential unloaded rows dim; mod "Better Unloaded Tabs" makes them more noticeable. Closing a pinned tab unloads it rather than removing it. [V]
- Folders added in 2025 (alternativeto news). Live folders exist in later versions [U].
- Window Sync (1.18b+): all windows mirror tabs/workspaces; pref `zen.window-sync.enabled`. [V issue 12008]

### Spec: Yab
- Order: pins (squares), kept tabs (above the line), line, Today. `⇧⌘D` pin; `⌘D` keep (as in Arc); `⌘W` on a pin puts it down, pin stays; `⌘W` on a kept tab sleeps it, row stays; X appears once asleep, `⌘Z` restores. Pins/kept never tidied. [V manual pinned-and-kept]
- Pinned address memory: browse away -> row shows slash + current page; click icon returns; pin's menu starts with "Back to". "Edit Pinned Page" changes it. [V manual + 0.18]
- Settings > Spaces > Pins > "In Every Space": pins shared across spaces that share sign-ins, same live tabs, like Arc Favorites; spaces with own sign-ins keep own pins. New installs default on. [V 0.15]
- Auto-tidy: Today tabs unseen 12h are closed together on return to the app (never while reading), notice with Undo, `⇧⌘T` restores. Setting range "12 hours to a month or never". Never closes pins, kept, current tab, playing/call/download/floating. [V manual tidy-and-sleep]
- Sleep: separate from tidy. Sleep only under real memory pressure (heaviest idle first); keeps tabs viewed in last 10 min; optional 4h idle-sleep timer off by default. [V 0.18/0.9]
- Link opened in new tab goes right after its page; from a pin/kept tab opens as Peek; Duplicate puts copy after the tab and keeps focus; `⌥`-click opens beside (split). [V 0.9]
- Folder-in-folder up to 5 deep; Live Folders. [V]

### Community
- Likes: auto-archive of stale tabs ("I love that it deletes all the tabs I've opened and not interacted with recently" - HN 33539549); spaces as separate workflows, pinned per space; pinned URL memory (a pin that does not drift) praised vs Safari where pins follow last page (TidBITS).
- Complaints Arc: "pinned tabs reset" confusion (users thought they lost state) and pinned tabs landing in "Recovered" folder across profiles (r/ArcBrowser threads); archive cannot be turned off; lost context when tabs auto-archive.
- Complaints Zen: Essentials vs pinned confusing; Essentials stay loaded and eat RAM (2GB+ report, popcar blog); "Tab auto unload not working" (#8822, 83 comments); Window Sync shipped without off switch (#12008, 31 comments); "Pinned tabs reset when opening a second window" (#15407); pinned reset-on-startup not working (#11823); essentials vanishing on launch (#9394); `[META] Window Sync and session restore` (#7079, 180 comments).
- Design implication: show a visible pinned-URL-diverged state, make reset one click, never silently reset on window open, offer archive-off setting (Yab offers "never").

Sources: https://resources.arc.net/hc/en-us/articles/19228855311127 · https://resources.arc.net/hc/en-us/articles/19230755904151 · https://tidbits.com/2025/07/03/do-you-use-it-browser-tab-management/ · https://www.gigazine.net/gsc_news/en/20230727-arc-web-browser · https://www.popsci.com/diy/arc-browser-tips/ · https://docs.zen-browser.app/user-manual/glance · https://docs.zen-browser.app/user-manual/workspaces · https://github.com/zen-browser/desktop/discussions/8389 · https://deepwiki.com/zen-browser/desktop/3.3.1-pinned-tabs-and-essential-tabs · https://github.com/zen-browser/desktop/issues/11823 · .../issues/9394 · .../issues/8822 · .../issues/12008 · .../issues/7079 · .../issues/15407 · https://popcar.bearblog.dev/thoughts-on-zen-browser/ · https://yetanotherbrowser.com/manual/pinned-and-kept · https://yetanotherbrowser.com/manual/tidy-and-sleep · https://yetanotherbrowser.com/changelog/0.15 · https://news.ycombinator.com/item?id=33539549

---------------------------------------------------------------------------------------------------

## 2. Command bar

### Spec: Arc
- `⌘T` opens Command Bar for a new tab (also double-click empty sidebar); `⌘L` edits current URL; Little Arc `⌘⌥N`. [V arc shortcuts page]
- Results (from memory [U]): top hit (URL/search), open tabs across spaces ("Switch to tab" with space name), pinned/archived, bookmarks/history, commands ("View Archive", "clear archive", "Boost"...), site search via Tab (e.g. "youtube" Tab).
- Keys (Arc, recollection [U]): Return = open in current/new tab; `⌘Return` = open in new tab; `⌥Return` = open in Little Arc / new window [unverified]; Esc closes; Tab completes/site-search.

### Spec: Yab ("the field")
- `⌘T` over page for new destination, `⌘L` with current address, `⌘K` per-row actions. [V manual the-field]
- Finds: open tabs in every window (Return switches rather than duplicates), history (deliberately visited first, inline autocomplete accepted by Tab), commands and Settings pages by name, answers (math/units/currency/time), Quick Actions (type "doc"/"meet"), clipboard history, files by path, Mail.
- Order under typed words: search, Ask Claude, Task for Claude; then up to 3 open/visited pages; then 4 search-engine suggestions. Intent beats order: question puts Ask on top, task phrase puts Task on top. Search suggestions can be turned off (Settings > Search). [V manual + 0.15]
- Empty field shows likely-now: just-copied link, next meeting, recent tabs, top sites; user Favorites (`⇧⌘F` toggle, `⌥⌘↑/↓` reorder). [V]
- Keys: Return open; `⌘Return` background tab; `⇧⌘Return` new tab; `⇧⌘Return` variants incl. end of tab list; `⌥Return` takes gray completion / site search / swaps search above Ask; Tab accepts completion; `⇧⌘C` copy link; `⇧Return` pull tab from another window here; `⇧⌫` forget history entry; text selected -> selection commands listed first. [V]
- `⌃Tab` cycles tabs across every space (0.21). [V changelog]
- Perf: typing stays responsive with large history (0.39), a known pain.

### Spec: Zen
- URL bar acts as combined search; new URL bar (floating, "Zen URL bar") introduced; "FR: Command Palette" #494 closed. Keyboard shortcuts customisable (Settings > Keyboard Shortcuts, red outline on conflict, Backspace clears). [V docs shortcuts]
- Compact Mode toggle `Ctrl+S` (Cmd+S on mac).

### Community
- Likes: Arc `⌘T` as single entry point and switch-to-tab across spaces is the single most copied feature (Yab markets "the ⌘T field, the way your hands remember"); Raycast-like actions + clipboard/answers in Yab.
- Complaints: Zen "The New Url Bar is so annoying" (#3649); "URL bar insists on showing history even when option disabled" (#8404, 25 comments); `Cmd+Q/Cmd+,` shortcuts broken on macOS (#1629, 92 comments); Yab laggy typing with big history (fixed 0.39); Zen shortcut resets after relaunch (#1715).
- Design implication: dedupe switch-to-tab (never open duplicate), show space badge, put intent-resolved top hit first, ensure ranking is cheap on large history.

Sources: https://resources.arc.net/hc/en-us/articles/20595231349911-Keyboard-Shortcuts · https://yetanotherbrowser.com/manual/the-field · https://yetanotherbrowser.com/changelog/0.15 · https://yetanotherbrowser.com/changelog/0.39 · https://yetanotherbrowser.com/changelog (0.21) · https://docs.zen-browser.app/user-manual/shortcuts · https://github.com/zen-browser/desktop/issues/3649 · .../issues/8404 · .../issues/1629 · .../issues/1715

---------------------------------------------------------------------------------------------------

## 3. Boosts

### Spec: Arc Boosts
- Boosts 2.0 (May 2023): Zap (click an element to remove it persistently), colour controls (background/text colour, brightness, contrast, saturation), font picker, custom CSS and JS editor ("Code" tab). Created via "+" in bottom bar > Create new boost or right-click page > Boost this site; paintbrush icon in URL bar toggles. [V ghacks, alternativeto, 9to5mac]
- Scope: per-domain (can also be set per URL pattern/wildcard, per user). [V arc CVE blog; domain pattern matching criticised by researcher]
- Sharing: share link, other Arc user installs in one click; **boosts containing JavaScript cannot be shared**. Gallery curated by The Browser Company. [V]
- Used for: dark mode/colour tweaks, font changes, hiding promoted/cookie elements, Reddit/HN/Twitter cleanup (e.g. HN-themed Boost for Reddit, HN 38969331), YouTube Shorts removal.

### Spec: Yab boosts / Store
- Boost = CSS (Manifest V3 content_script with css) per site; JS plugins are separate "plugins with code", reviewed. `⌘T` > type "store" > Tab, or yetanotherbrowser.com/store. `⌘E` = Site Controls (list/toggle/change/version history/delete boosts). [V manual store, 0.9]
- Flow: Try on My Page (opens in a separate tab, nothing saved) -> Keep (`⌘Return`), Undo (Esc); hold `⌥` for "Keep for Every Site" where allowed. Card in corner says "Look boost: no code runs". [V]
- Build It with Claude / Ask for It (votes) / Remix with Claude / Check with Claude (plain-language code read). Share to Store opens PR to `yab-plugins`, live-site checks (selector assertions like `none of`, `some of`), human review. Store boosts auto-update only if permissions do not widen; "Works today" status, flagged "Needs Fix" after 2 failing days. [V]
- Permissions: boosts press a site's buttons only if declared (0.39); network access bypass via elements/styles fixed. Hide Elements `⇧⌘H` (crosshair, persists on site, `⌘Z` undo, Hidden here list in `⌘E`, restored by structural naming after redesign). [V]

### Spec: Zen equivalents
- No per-site boosts. Closest: Zen Mods (CSS/pref packs, global) and extensions (uBlock element picker, Stylus, Tampermonkey). Mods are browser chrome themes, not page edits. [V]

### Community
- Likes: Zap and quick recolour were the "wow" feature; HN theme boost sharing; low friction CSS.
- Security criticisms: CVE-2024-45489 (Sept 2024): Firebase ACL misconfig let attacker rewrite a Boost's `creatorID` so custom CSS/JS would run on a victim's browser given only their userID; reported Aug 25 by xyz3va, fixed in ~1 day, bounty raised $2K->$20K. Arc: JS disabled by default in synced Boosts, left Firebase, hired security engineer, bug bounty, security bulletin. Researcher also criticised domain-pattern matching vs privacy policy; HN 41597250 (1469 pts, "Gaining access to anyone's Arc browser without them visiting a website"). [V]
- Other: Boosts break when sites change DOM; JS editor intimidating for beginners.
- Design implication: keep CSS-only shareable, JS local-only with explicit per-site consent, ship a visible "what can this do" card, signed/reviewed store only, no remote ID-based sync trust.

Sources: https://arc.net/blog/CVE-2024-45489-incident-response · https://9to5mac.com/2024/09/28/arc-browser-vulnerability/ · https://www.thurrott.com/?p=310023 · https://9to5mac.com/2023/05/25/arc-browser-boost-web-editor/ · https://www.ghacks.net/?p=195846 · https://alternativeto.net/news/2023/5/arc-browser-s-boosts-2-0-take-control-of-the-web-and-make-it-look-the-way-you-really-want · https://yetanotherbrowser.com/manual/store · https://yetanotherbrowser.com/manual/publish-a-boost · https://yetanotherbrowser.com/manual/hide-elements · https://yetanotherbrowser.com/changelog/0.9 · https://yetanotherbrowser.com/changelog/0.39 · https://news.ycombinator.com/item?id=41597250

---------------------------------------------------------------------------------------------------

## 4. Theming / Look editor

### Spec: Arc
- Per-space colour: "Edit Space > Theme" -> gradient picker with draggable dot(s) on a colour wheel; up to 2-3 colour dots (primary/secondary) [U], intensity/opacity slider, **grain** (texture) slider, Light/Dark/Auto per space. Also changes app chrome tint. (Detailed ranges unverified: official page not fetchable; Yab's manual describes the equivalent, below.)

### Spec: Yab Look
- Window styles: Edge to edge, A color (page lies on painted window as a card), The site's color. Theme Light/Dark/System. [V manual appearance]
- Editor: field of dots (hue + amount), two tracks for transparency and grain; `⌥` drag = fine control; double-click track resets. Dark window renders colour a shade deeper. [V]
- Per-space: Edit Look... from space menu or `⌘T`; header As Appearance / Light / Dark; preset colours and gradients; +/- adds/removes colour; "Shift with tabs" (hue shifts a step per new tab); "Take the site's colour"; Drawings overlay. ⋯ menu: Reset, Use for All Spaces. Esc closes. Live preview behind card. [V]
- macOS 26 Liquid Glass: transparency track ends in a "bead"; drag past it and window frame becomes Liquid Glass tinted with space colour; honours Reduce Transparency / Increase Contrast. [V 0.18/0.19]
- Match Arc / Match Chrome import. App icon picker. Shortcuts `⇧⌘L`, `⇧⌘B`. [V]

### Spec: Zen
- Workspace theme picker: colour wheel with multiple dots producing gradients, opacity/texture (grain) sliders, per-workspace; native gradients made the SuperGradient mod obsolete. [V CosmoCreeper repo note; details of slider ranges U]
- Zen Mods: community CSS+pref packs from the Mods Registry (zen-browser.app/mods): open mod page, click Install; installed list in Settings; some mods expose preferences (toggles, dropdowns, text fields) defined in a mod manifest "preferences.json" shown in the mod's settings card [U on schema]. Sharing: export mod as JSON, import elsewhere (no in-browser upload). [V registry docs; discussion 9240]
- Example mods: Superpins (pinned look like essentials), Better Find Bar, No pinned tab reset btn, Better Unloaded Tabs, sleek border. [V registry]
- Compact Mode: hide toolbars/sidebar, reveal on edge hover, `Ctrl/Cmd+S`. [V docs]

### Community
- Likes: Zen theme colour wheel "awesome" (popcar); Arc per-space colour is the most-cited identity feature; Yab gets "Arc's editor" parity plus glass.
- Complaints: Zen private windows cannot be themed; narrow sidebar hides extensions; mods break after updates ("sidebar not hiding in compact mode" #11732, "Zen disables compact mode on startup" #8606); Zen docs sparse (popcar).
- Design implication: per-space colour + grain + light/dark is the baseline; add fine-drag modifier and reset; keep mod/theme settings declarative so updates do not break.

Sources: https://yetanotherbrowser.com/manual/appearance · https://yetanotherbrowser.com/changelog/0.18 · https://docs.zen-browser.app/themes-store/themes-marketplace · https://zen-browser.app/mods · https://github.com/zen-browser/desktop/discussions/9240 · https://github.com/CosmoCreeper/Zen-Themes · https://popcar.bearblog.dev/thoughts-on-zen-browser/ · https://docs.zen-browser.app/user-manual/compact-mode · https://github.com/zen-browser/desktop/issues/8606 · .../issues/11732

---------------------------------------------------------------------------------------------------

## 5. Peek / Glance / Split view / Little Arc

### Spec: Arc Peek and Little Arc
- Peek: link click from a pinned tab/favorite or Shift-click on a link opens it in a preview card over the page; actions: open as tab, close (Esc). Auto-peek on cross-site links from pinned tabs [V forum summary; precise key list U].
- Little Arc: external links (from other apps) open in a small floating window without sidebar; `⌘⌥N` new Little Arc; `⌘W` closes; can "Move to Space" to adopt as a tab; no multi-tab. [V arc shortcuts, TidBITS]. Browser Company later dropped it in Dia citing "novelty tax" (TidBITS).
- Split View: up to 4? Arc supports up to 4 tabs in split (grid/horizontal/vertical) [U]; drag tab onto the page; `⌃⇧=`? shortcut unverified.

### Spec: Yab
- Peek: `⇧`-click or Force Click opens panel over page, page dims; Esc/`⌘W` closes; `⌘O` keep as tab; `⇧⌘O` open beside in Split View. Peek belongs to its tab (hides when switching, returns). Meeting links always open as tabs; `⌘`-click still new tab. From pinned tab, links to other sites open as peeks. [V manual peek]
- Split View: exactly two tabs. `⌃⌘\` split/unsplit; right-click Split with Current Tab; drag tab over page; `⌥`-click row. Each half has own address bar; last-clicked half takes `⌘L/R/F`/zoom; divider drag, double-click evens; needs ~650pt width; pins/kept join as copies; mail tabs, agent tabs, already-paired tabs excluded. [V manual split-view]
- Small window: links from other apps open in small window with Back/Forward/Reload (Little Arc successor). [V 0.15]

### Spec: Zen
- Glance: default trigger Alt+Click; alternatives Ctrl+Click or Shift+Click; toggle in Settings > Look and Feel > Glance. In Essentials/pinned tabs, off-site links glance automatically. Top-left buttons: Close (also click outside), Expand (to a tab), Split (add as split tab). [V docs]
- Split View: up to 4 tabs, layouts horizontal / vertical / grid; shortcuts Alt+Ctrl+H / V / G (also splits current tab with the one below); Alt+Ctrl+U unsplit all; per-tab overlay with drag handle `:::` (move to left/right/top/bottom of another tab) and unsplit `-`; resize splits and rearrange items. [V docs, review]

### Community
- Likes: Glance is the favourite Zen feature (popcar); Peek-to-split flow ("From a Peek, one click puts the link beside your page"); Little Arc loved by some, ignored by many.
- Complaints: Zen split view "buggy and unfinished", hard to add tabs, layouts break, unsplit requires hotkey (popcar, PC-Welt); URL bar shows only active pane address (EndeavourOS forum); Little Arc single tab limit and "novelty tax"; Arc Peek hidden/unclear to discover.
- Design implication: Shift-click Peek + modifier alternatives, three buttons (close/expand/split), Esc closes, keep state per tab, cap split at 2-4 with explicit min width, one address bar per pane.

Sources: https://docs.zen-browser.app/user-manual/glance · https://docs.zen-browser.app/user-manual/split-view · https://yetanotherbrowser.com/manual/peek · https://yetanotherbrowser.com/manual/split-view · https://tidbits.com/2025/07/03/do-you-use-it-browser-tab-management/ · https://orionfeedback.org/d/4610-open-different-domains-in-popup-similar-to-arcs-peek · https://forum.endeavouros.com/t/zen-browser-ive-learned-to-appreciate-it/67331?page=3 · https://www.pcwelt.de/?p=2837802 · https://popcar.bearblog.dev/thoughts-on-zen-browser/

---------------------------------------------------------------------------------------------------

## Cross-cutting notes
- Arc status: sold to Atlassian ($610M); Arc in maintenance mode; HN 50197601 "A farewell to Arc browser": users migrating to Zen/Dia/Yab; distrust of VC-funded closed source. Yab's pitch is Arc import ("Bring In" for Arc, Dia, Zen) so import parity matters.
- Zen is Firefox-based: perf worse than Safari/Chrome on Speedometer (31.6 vs 37.6) per review; Widevine/DRM issues on some platforms (popcar). WebKit-native Wayfinder can differentiate on battery/perf/Safari-compat.
- Top copyable defaults: 12h auto-archive with Undo and a "never" option; Essentials cap 12; pinned URL memory with visible diverged state; folders to depth 5; split 2 panes (or 4 grid), 650pt min.
