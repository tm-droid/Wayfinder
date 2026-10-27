# Search → Wayfinder gap analysis (B3, 2026-10-27)

Paths are under `Sources/Search/` (upstream Search @ 88017ad, pre-rebrand). Line numbers are approximate after edits.

**Headline:** most of the Arc layer already exists in Search. These are the real gaps:
- no essentials concept separate from pins
- no folders that hold pins, and no nesting
- no fuzzy cross-space switch-to-tab or searchable action palette
- no per-space tint or gradient
- no Mods page
- no blocker counter
- no user per-site CSS/JS (Boosts)
- no glass
- split view is limited to 2 panes
- no space chooser in Little
- no download consent

## W1 Arc sidebar
**Exists**
- Pins:
  - `PinDef` (`Pins.swift:18`: `id, letter, home, title, name, listed`).
  - `Pins` (`:31`) holds pins per space (`bySpace`) plus profile-shared pins (`sharedBy`, key `"shared"`, `:44`) in `pins.json`.
  - The `Pins.changed` notification (`:41`) keeps windows in sync.
  - Shared pins work like Arc favourites: `prefs.sharesPins` (`Prefs.swift:568`), `Tab.everywhere` (`Tab.swift:704`), and "Keep in Every Space" (`Browser.swift:2688`).
- Pin layout:
  - Grid: `PinGrid` (`Side.swift:937`), `PinSquare` (`:959`).
  - Rows instead: `prefs.listsPins` / `PinDef.listed`.
- Today divider and Clear:
  - `KeepLine` (`Side.swift:1317`) is the Today divider with a hover Clear button, wired to `Browser.clearTabs()` (`Browser.swift:3799`).
  - Clear can be undone with ⇧⌘T (`lastClear`, `:2016`).
- Auto-archive: `Closing.swift`.
  - `closeAfter` (`:27`), `stays(because:)` (`:36`), `closeLeftAlone()` (`:50`).
  - Setting `TabLife` (`Prefs.swift:49`: never/12h/day/week/month), key `tabs.close.after`.
  - `Session.Entry.touched`/`.letGo` survive quits.
- Folders:
  - `TabGroup` (`TabGroup.swift:5`: `id, name, collapsed`); membership is `Tab.groupID`.
  - UI in `TabGroups.swift` (`GroupHeading` `:47`).
  - Flat (no nesting), and no pins inside.
- Drag:
  - `PinDrop` (`PinDrop.swift:12`), zones `squares/listed/loose/none`, targets `.squares(i)/.listed(i)/.loose(i)/.group(id)`.
  - Ghosts `PinGhost` (`:92`), `RowGhost` (`:117`).
  - `TabDrag` (`TabDrag.swift:49`), `PinCarried` (`Side.swift:1466`).
- Persistence:
  - `Session.Shape` (`Session.swift:33`): `tabs, active, groups, splits`.
  - `Browser.writeSession` (`:2572`), `writeSessionSoon` (`:3121`), `Store.write` (`Store.swift:201`), `Windows.save` (`Windows.swift:404`).
- Flush on quit: `applicationWillTerminate` (`Links.swift:80`) → `Browsers.flush()` → `Browser.flushSession()` (`:3136`) → `Disk.drain()`.
- Multi-window: one `Tab` per pin per window, sharing the `PinDef`. Sync via `reconcilePins` (`:2607`) and `pinsChanged` (`:2643`).

**Gaps**
- No essentials concept separate from pins.
- No folders that hold pins, and no nesting.
- No archive view beyond ⇧⌘T and History.

**Integrate at**
- `PinDef.essential: Bool?` (optional, so old JSON still decodes).
- A new `PinDrop.Zone`, rendered in `PinGrid`.
- `TabGroup.parent: UUID?` plus pin membership.
- Archive exemptions reuse `stays(because:)`.

## W2 Command bar
**Exists**
- Shortcuts:
  - ⌘L `file.openAddress` (`Shortcuts.swift:166`) → `Browser.edit()`.
  - ⌘T `file.newTab` (`:163`).
  - ⌘K `tabs.search` (`:214`) → `Browser.summon()` (`Browser.swift:5620`).
  - ⌃Tab is `TabSwitcher`.
- Tab search (summon):
  - `guess()` (`:5635`) uses `openPages(matching:)` (`:5790`).
  - Substring matching, sorted by `touched`.
  - Covers the current space only: it excludes `parkedTabs` and the active tab.
- Omnibox suggestions:
  - `placeOffers(for:)` (`:5739`) returns max 3 places.
  - Sources: `bookmarks.places` (`Bookmarks.swift:149`) and `history.suggestions` (`History.swift:342`, frecency).
  - `Suggestion.Kind` (`History.swift:7-31`): `.open .visited .bookmark .known .search .suggested .command`.
- `AddressCommand` (`AddressCommands.swift:13`):
  - 9 hard-coded commands, exact aliases only.
  - Gated by `prefs.commandBar` (`Prefs.swift:620`, off by default).
- `Command.all` (`Shortcuts.swift:157`): `id, title, section, defaultKey, run(Browser)` for every menu action. Custom keys live in `ShortcutStore`.

**Gaps**
- No fuzzy ranking.
- Tab search covers neither other spaces nor bookmarks, history or actions.
- Commands match only exact aliases.

**Integrate at**
- Extend `openPages(matching:)` to include `parkedTabs`, with a fuzzy score (port `CommandBarRanker` from archive `2fbe10c`).
- `Suggestion.Kind.action(Command.ID)` backed by `Command.all`.
- A `>` prefix in `guess()` for actions.

## W3 Theme engine
**Exists**
- `Palette` (`Design.swift:13`): static light/dark NSColor pairs.
- `Greys` (`:84`), passed through `\.greys` (`:100`, `Side.swift:137`).
- `Look` (`:108`): light/dark/system.
- Sidebar background at `Side.swift:145`; window background at `App.swift:477`.
- `Metrics` (`:148`: side 232, cardRadius 10, cardGap 8) and `Motion` (`:236`).
- `Space` (`Spaces.swift:20`): `id, name, colour:Int, icon, sharesSignIns, downloads, profile`.
  - `Spaces.colours` (`:52`, six colours) is legacy and unused in the UI.
- Prefs: `sidePosition` (`:128`), `roomyTabs` (`:138`), `sideIcons` (`:144`), `sideWidth` (`:156`), `cards` (`:163`), `lightMotion`.
- `SpaceMenu` (`Spaces.swift:588`), `SpaceDot` (`:501`), `PopoverGround` (`Design.swift:403`).

**Gaps**
- No tint or gradient.
- No per-space palette.
- No font, radius or density controls.

**Integrate at**
- `Space.look: SpaceLook?` (optional).
- A `Tint` environment key next to `GreysKey`, applied at `Side.swift:145` and `App.swift:477`.
- A "Look" popover from `SpaceMenu`, using `PopoverGround`.

## W4 Mods
**Exists**
- Internal pages:
  - `InternalPage.Kind` (`InternalPages.swift:18`) are native SwiftUI `search://` pages, with no user CSS.
- Settings:
  - `SettingsPanel.Page` (`Settings.swift:37`): general, appearance, tabs, browsing, spaces, passwords, privacy, ai, extensions, keyboard, about.
  - `SettingsIndex.swift` has `SettingsGroup` (`:15`, groups `:62-95`) and `SettingsItem` (`:25`). It also feeds the ⌘F settings search.
- Existing toggles that are mod-like:
  - `tabs.give`
  - `tabs.reading`
  - `tabs.address`
  - `tabs.shortcuts`
  - `sidebar.roomy`
  - `sidebar.icons`
  - `sidebar.hides`
  - `layout.cards`
  - `toolbar.left`
  - `bookmarks.bar`
  - `glyph`
  - `pins.list`
  - `pins.keep`
- Asleep tabs dim at a hard-coded 0.45 (`Side.swift:988-992`).
- `sideTitle` offers 12.5 or 14 only (`Prefs.swift:151`).

**Gaps**
- No mod or plugin mechanism.
- No hover-only close setting.
- Dim amount is not configurable.
- Text size is limited to those two values.

**Integrate at**
- `Page.mods` plus a `mods` group in `SettingsIndex`.
- Back the mod flags with `Preferences` keys, following the `tabs.give` pattern.

## W5 Compact mode: already exists
- `Browser.folded` (`Browser.swift:319`) is toggled by ⌘S through `toggleFold()` (`Fold.swift:46`).
- It hides at the edge, with grace and dwell timing.
- `prefs.sideHides` (`sidebar.hides`) persists the state across launches.
- The traffic lights move with the sidebar.

**Gap:** the reveal is not glass (moved to W10), and there is no command-bar action (moved to W2).

## W6 Blocker
**Exists**
- `Shield.shared` (`Shield.swift:11`), with `compile()` (`:107`) producing the single list `"office-shield"`. Its sources:
  - hard-coded `unwanted` domains (`:57`)
  - `slots` CSS selectors (`:81`)
  - `YouTubeAds.rules`
  - `slotsBySite` (`:94`)
- Compiled at launch (`Browser.swift:2134`).
- Attached in `Tab.swift:924` (`protect`) and re-tuned on each navigation (`Browser.swift:6242`, `tune(controller, for:)`). Global toggle at `:2416`.
- Per-site pause: `Shield.paused` (`:30`, `shield.paused`).
  - Its only UI is Settings › Privacy (`Settings.swift:714-727`).
- `YouTubeAds`: two user scripts (`YouTubeAds.swift:64`) injected from `Tab.swift:1141`.

**Gaps**
- No EasyList-scale lists.
- No counter.
- No SiteCard toggle.

**Integrate at**
- `Shield.compile()`.
- A SiteCard row next to `darken`/`sound` (`SiteCard.swift:282-295`).

## W7 Privacy report: nothing exists
- `Privacy.swift` covers only GPC and click-ID stripping.
- `CleanLink.swift` cleans links.
- `BlockedPopups` covers popups only.
- Site card:
  - `SiteCardPanel` (`SiteCard.swift:19`, NSVisualEffectView `.menu` `:85`).
  - `SiteCard` (`:188`) with rows `Row` (`:527`), `Safety` (`:451`), `Header` (`:577`).

**Integrate at:** a new row in `SiteCard.body`.

## W8 Boosts
**Exists**
- `Curtain` (`Curtain.swift:26`): `Veil{selector,label,note}` per host, stored in `hidden.json`.
  - Its CSS is injected as a document-start user script in `Web.world` (`Tab.swift:1147`, `arm(hiding:)` `:1039`).
- `HiddenPanel` (`Hidden.swift:8`).
- `Dusk` per-site dark mode (`Tab.swift:1136`).

**Gap:** no user-authored CSS/JS per site.

**Integrate at:** a `Boosts` store (`boosts.json`, modelled on `hidden.json`) plus `addUserScript` next to `Tab.swift:1147`.

## W9 Power tabs
- **Split:** `TabSplit` (`Split.swift:8`) can already hold N tabs. The runtime assumes 2: `PaneStage.swift:354,513` (`tabs.count == 2`), `startSplit` (`Browser.swift:3187`), and the drag path (`:3177`).
- **Peek:** `PeekClick` (`Prefs.swift:27`: shift, option-shift, option-command) is handled at `Browser.swift:6201`. Also `peeksLinks` (`:408`) and `pinsPeek` (`:415`).
  - Gap: no plain ⌥-click option (Zen Glance).
- **Little:** `Little.swift:35` uses the current space only. Gap: no space chooser.
- **Download consent:** none. Downloads go through `Browser.swift:6530-6539` and `Fetching.swift`.
- **Sleep:** `SleepPace` (`Sleep.swift:36`) is fine as is.

## W10 Liquid Glass
- `#available(macOS 26` appears only in `Design.swift:407` (PopoverGround, which has no glass) and `Translate.swift:498`.
- `NSVisualEffectView(.menu)` is used in `SiteCard`.
- The sidebar uses flat `Palette` colours.
- Not found: `glassEffect`, `NSGlassEffectView`.

## ImportArc
- `ImportArc.swift` maps:
  - spaces → spaces
  - profiles → profiles
  - favourites → ordinary pins
  - loose pinned → listed pins
  - folders → flattened TabGroups (`takeAsleep`)
- Today tabs are dropped.
- Gaps: no essentials flag and no folder nesting (fix in W1). Zen and Yab data are not read.
