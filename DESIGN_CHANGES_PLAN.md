# Design changes plan (Max, 7 Nov 2026)

Working file for the batch-by-batch design changes. Update the ticks as each item is done, so a fresh session can pick up from here. **Read this first in any new session.** It is a working list, not a spec: finished items are folded into `ADDON_SPEC.md` / `CODING_BRIEF.md` as needed, then this file can be deleted.

## How we work
- One batch at a time. **At the end of each batch there is a GATE**: stop, say what was done and what is untested, name the model and effort for the next batch, and wait for Max. Max may change model/effort in this session or start a new session (this file is the hand-over).
- **Skin rule, for every change from now on:** nothing is hardcoded blue. Colours that belong to the window come from the skin (`MOTA.skin` tokens, `MOTA:Accent()`, `UI:SkinPiece`, `Kit:AccentArt`), and anything new must be checked in all four skins: Ministry (blue/gold), Silverhand (blue/silver), Exchange (crimson/gold), Crown (plum/gold). Party-owned colours (Silverhand blue, Exchange red) stay as they are.
- Design source is the **live** Claude Design canvas: https://claude.ai/artifact/V6ZmxpJtw85SrWT9S87acJ (read with the Artifact tool). On 7 Nov 2026 the live canvas was identical to the repo mirror `design/canvas-source/` for Treasury, StatuteBook, ThroneRoom, WindowSkins, BallotHall, Extras and Main. Re-diff before each batch that builds a look. Textures come from `python tools/textures/build.py` (needs Edge + Pillow, both present).
- Test: `tools/sim/sim.py` (check it still passes), then Max checks in game (full WoW restart after pulling).
- Max's git is shared with a friend (Duncan): pull first, never force-push, don't commit unless asked.
- Reply layout for Max: numbered sections with lettered points. List any questions he skipped at the end of a reply.

## Recommended model and effort (agreed 7 Nov)
| Batch | Model | Effort | Contents |
|---|---|---|---|
| A | Sonnet 5.5 | low to medium | A1 to A4 |
| B | Sonnet 5.5 | high | B1 to B3 |
| C | Opus 5.5 | medium | C1 to C3 |
| text only | Sonnet 5.5 | low | T1: ten seal ideas (any time) |
| D | Opus 5.5 | high | Districts + map overlay + map skins (new gate before starting) |

## Batch A: quick edits (Sonnet 5.5, low to medium)

### A1. Initials circles follow the skin
- Max: every circle with initials should take the skin's colour, as the bottom-left circle of the whole window already does (Exchange red, Crown purple, etc.).
- Found: the window's own circle is `portrait` (`UI/MainWindow.lua`, drawn per metal with an accent suffix `~cr`/`~ex`). The Ring foot (`UI/Ring.lua` ~141) and Treasury foot (`UI/Treasury.lua` ~88) use the plain atlas `portrait` via `UI:Piece`, which is always blue.
- Plan: draw those two as `UI:SkinPiece(foot, "portrait", "metal", ...)` anchored to the foot, so a skin change re-skins them. Sized 36 as before.
- Left alone on purpose: Parties page leader portraits (`kitPortraitSh`/`kitPortraitEx`, they are the party's own colour), Ballot Hall candidate portraits (`portrait-king`, Crown candidate purple). Tell Max.
- [x] done 7 Nov (Ring.lua, Treasury.lua now use `UI:SkinPiece`)  [ ] Max checks in game in all four skins (`/mota skin crown|silverhand|exchange|ministry`)

### A2. Header shifted down
- Max: the title "Ministry of the Allied", the page subtitle under it (with its two rules) and the Close and Settings buttons all move down a tiny bit **as one unit**, because they sit too high and touch the top-right corner ornament.
- Plan: one constant `HEADER_DROP` in `UI/MainWindow.lua` added to the title piece, the subtitles, the sub-rules (`PlaceSubRule`) and both knobs (piece and click area). Start at 6 canvas units and look at it.
- Canvas sync owed: the live canvas should get the same shift (see "Canvas sync debt").
- [x] done 7 Nov: `HEADER_DROP = 6` in `UI/MainWindow.lua`  [ ] Max checks it clears the corner ornament in game (nudge the number if not)

### A3. Treasury: coffer box size and "This term"
- Max: make the Guild Coffer box the size it is on the canvas; replace the "Since the books opened" in/out block with the canvas's "This term" block.
- Canvas (Treasury.dc.html): aside column is **236 wide** (add-on has 206, `ASIDE_W` in `UI/Treasury.lua`; the Ring keeps its own 206). Coffer plate is blue, padding 20/16/18, gap 8: 46px icon, eyebrow "The Guild Coffers", amount, small line. That is about 188 tall (add-on has 158).
- "This term": heading, then two rows of `label | bar | amount`: In (green bar) and Out (red bar), bars scaled to the larger of the two.
- Data caveat: the add-on does not track government terms yet, so "This term" uses the ledger's totals since the books opened. Say so to Max. Revisit when terms are tracked (term = 3 months from the PM taking office, Charter 2.3).
- The coffer amount still uses the text "G/S/C" until B2 swaps in coin icons.
- The wax seal in the coffer stays until C3.
- [x] coffer box resized (236 x 188)  [x] "This term" built (bars + amounts)  [ ] Max checks in game: the ledger column is now 452 wide (was 482), so long reasons may be cut short with "..."; coffer text is small until B2

### A4. Party seal on the Ballot Hall vote
- Max: when voting, the mark on the candidate you click, and the seal on the "Seal my ballot" button, should be the seal of that candidate's party (Silverhand seal, Exchange seal), not the default Official seal. Independents keep the Official seal.
- Found (`UI/BallotHall.lua`): `b.marked` (the mark on a chosen row) uses `seal-off`; the "Seal my ballot" button (`btn-seal`) has the Official seal **baked into** its texture (`tools/textures/ballot.html` line 49), with `~cr`/`~ex` accent copies. The after-vote stamp (`stamp`) is the Crown's receipt seal.
- Plan: add `seal-sh` and `seal-ex` pieces to `ballot.html`/`build.py` (sources `design/textures/seal-silverhand.svg`, `seal-exchange.svg`); render `btn-seal` with an empty slot where the seal was and draw the party seal over it in Lua, switching on the chosen candidate's party (`c.p` = `sh`/`ex`/`ind`). Use the same switch for `b.marked`.
- Max said yes (8 Nov): the held block (after sealing, waiting for a King) also wears the party seal. Done as `held-sh` / `held-ex` pieces. The stamp after a King receives it stays the Crown's receipt.
- [x] build.py pieces added (`seal-sh`, `seal-ex`, slot `btn-seal-ico`; the Seal button texture no longer has a seal baked in; `ballot.tga` grew from 1024x1024 to 1024x2048)  [x] marked seal per party  [x] button seal per party  [ ] Max checks sh / ex / ind in game

### GATE A, then B
At the end of Batch A: report what was done and not tested, remind Max of unanswered questions, recommend Sonnet 5.5 at high for Batch B.

## Batch B: Statute Book tabs and coins (Sonnet 5.5, high)

### B1. Statute Book: add the canvas's three views
- Max: add the "In force", "Awaiting" and "Court rulings" ribbons exactly as on the canvas (`StatuteBook.dc.html`: ribbons `rb.force/wait/court`, views `isForce/isWait/isCourt`), following the skin rules.
- The add-on's Statute Book page is `UI/Constitution.lua` (currently the Constitution only). Read the canvas file fully before building; use `Kit:Ribbon` for the ribbons (they follow the accent). Decide with Max where the Constitution lives if it conflicts (open question for the gate).
- [x] built 8 Nov in `UI/Statutes.lua` (new); `UI/Constitution.lua` is now its fourth view ("The Charter" ribbon kept). Ribbons, In force (index + statute page), Awaiting (bills with step marks, renewals with buttons), Court rulings (rulings, Lay a charge, ladder). No laws/Court exist yet, so each shows an empty state; hooks `MOTA.Laws`, `MOTA.Court` are documented at the top of Statutes.lua. Left out: the big drop-cap first letter. [ ] Max checks in game, all four skins (the ribbon mark and ribbons follow the accent)

### B2. Coins, in two steps (do the pass first)
- Max: all the coin icons in the add-on look flat, "like dots". Spruce them up. Then use coins in the Treasury coffer box and the ledger, instead of "13C" / "G" letters.
- Step 1, the pass: coin art lives in `ministry.css` (`.coin.g/.s/.c`, flat radial gradients) and `Kit` (`kitCoinG`, `kitCoinS`; there is no copper coin yet). Redesign gold, silver and copper with a rim, inner ring, a stamped face and a highlight, in the canvas CSS or SVG, then rebuild with `build.py`. Find every use: `grep -rn "kitCoin\|coin" addon tools design/canvas-source`.
- Step 2: coffer box shows `1,240 [g] 35 [s] 10 [c]` as the canvas does; ledger In/Out cells show amount then coin. `Kit:Amount` already does gold and silver; add copper. `MOTA:Money` text stays for places that cannot hold icons (chat).
- [x] pass done 8 Nov: `design/textures/coin-g/s/c.svg` (milled rim, groove, embossed crown, highlight), copper added (`kitCoinC`)  [x] coffer coins (`Kit:Coffer`, big gold, small silver/copper, shrinks if wide)  [x] ledger, accounts, "This term", Ring amounts use `Kit:Amount` with coins (max two parts in tight columns)  [x] `MOTA:Money` text kept for chat and the bank prompt  [ ] Max checks in game: coin size and the ledger columns (money columns 88 wide)

### GATE B, then C
Recommend Opus 5.5 at medium for Batch C. Remind Max that C1 and C2 are best designed on the live canvas first.

## Batch B follow-ups (Max, 8 Nov, after seeing Batch B in game): do these first in the Batch C session
These are small fixes; do them before Batch C. Max sent screenshots; they are described here in words.
- [x] **F1. "Lay a charge" button too narrow.** Court rulings view (`UI/Statutes.lua`, `v.charge`, 112 wide): the label's letters touch the button's edges. Widen it (about 140) so the text sits comfortably. *Done 8 Nov: 140 wide; the line beside it is 26 shorter so they don't meet.*
- [x] **F2. The count label overlaps the Charter ribbon.** With In force selected the label "0 LAWS IN FORCE" (top right of the Statute Book page, `count` in `UI/Statutes.lua`) runs into "The Charter" ribbon, because four ribbons now fill the row. Wrap it onto two lines ("0 LAWS" over "IN FORCE") right-aligned, or otherwise keep it clear of the last ribbon. Check the other views' labels (Awaiting, Court rulings, Ten readings) in case they have the same problem. *Done 8 Nov: every view's count is two right-aligned lines: "0 laws / in force", "0 / awaiting", "0 / rulings", "Ten / readings".*
- [x] **F3. Blue plates are narrower than the boxes under them (Treasury and Ring).** The blue plate (Guild Coffers on the Treasury, The Ring plate on the Ring) shows noticeably narrower than "The accounts", "This term", "The purse" and "Next bout" boxes below it. Cause to check first: the `kitBlue` art includes its soft shadow around the plate, and `Kit:AccentArt(plate, "kitBlue", "BACKGROUND"):SetAllPoints()` stretches the whole picture (shadow included) to the panel, so the plate itself ends up inset. Fix so the visible plate fills the same width as every other box in that column (Treasury column is 236, Ring's is 206). Check the Parties page for the same plate art. Check in all four skins. *Done 8 Nov: cause confirmed (the art is 225 x 177 for a 206 x 158 plate: 9.5 shadow each side, 5.5 above, 13.5 below). New `Kit:PlateArt` lets the shadow hang outside the box; Treasury and Ring use it. The Parties page doesn't use this art. The accent copies (~cr, ~ex) share the same size, so all skins follow.*
- [x] **F4. Party Chamber buttons too narrow.** The Parties page, The Chamber view (Crown's desk, `UI/Parties.lua`): "Set: days away", "Ratify Silverhand" and "Ratify Exchange" need to be a little wider so the text fits comfortably (their letters touch the edges). *Done 8 Nov: the row was full (676 of 676), so it is now two rows: days box, "Set: days away" (156) and "Open contests" (156) above on the left; "Ratify Silverhand" (200) and "Ratify Exchange" (194) below on the right.*
- [ ] Max checks F1 to F4 in game (sim.py 335 passed, 0 failed)

## Batch C: regal look (Opus 5.5, medium)

### C1. Finer, more regal ornate corners on the lit tab
- Max: when a left-hand tab is highlighted, the gold ornate corners are too small for their chunky design: bulky, mechanical. Make them finer, more elegant, regal.
- Where: `design/textures/tab-frame.svg`, `tools/textures/tab-frame-gold.svg`, the `.tab.on` rules in `ministry.css`, `tabOn` piece in `build.py`. Design on the canvas first (propose 2 options in a small board if useful), then rebuild.
- Two options drawn 8 Nov (board `c1-tab-corners.png`, shown to Max): **A, hairline scroll** (a slender acanthus scroll along each edge, a small leaf on the diagonal, a gold pearl in the corner) and **B, fleuron** (a small fleur-de-lis on the diagonal, a fine rule along each edge ending in a pearl). Both drop the stitched line, keep one engraved double rule, and use a 24 slice (was 20) with strokes about half as thick. Silver comes from the existing `.ws-sh .tab.on::after` grayscale filter. The SVGs and the board script are in the shared notes folder `batch-c-design/` (outside the repo).
- **Max picked B (8 Nov), with the ornament OUTSIDE the line.** Built: `tools/textures/tab-frame-gold.svg` is now 72 x 72 used as `24 / 24px` (`.tab.on::after` in `design/canvas-source/ministry.css`); the double rule sits 8.5 in from the edge and each corner's fleur-de-lis points out into the corner, with the edge rules and pearls between the line and the tab's edge. Same file in every skin (Silverhand greys it with the existing filter).
- [x] designed (2 options)  [x] Max picks (B, outside the line)  [x] built (textures rebuilt)  [ ] Max checks in game, four skins

### C2. Two variations each of the Close and Settings buttons
- Max: the circular knobs look odd next to the rest of the UI. Design **two variations for each** button, with a more regal style and a shape that fits the UI (not circles). He picks one of each, then we put it in the add-on.
- Do the design on the live canvas (a board showing the 2 x 2 options in all four skins), not in the add-on yet. Pieces today: `knobClose`, `knobSettings` per skin (`build.py`, `buildKnob` in `MainWindow.lua`).
- Drawn 8 Nov (board `c2-knobs.png`, shown to Max): **1, heater shield** (bowed top; echoes the shield crest in the opposite corner) and **2, notched cartouche** (concave cut corners; echoes the ribbons and plates). Both keep each skin's wax and icon colours from today's knobs, a metal rim (gold, or silver for Silverhand), an inner hairline and a gloss. They are shown 1.2x their 30 x 34 / 36 x 30 drawing so they match today's knob plus its ring. Max can mix (e.g. shield Settings, cartouche Close).
- **Max picked 2, the notched cartouche, for both (8 Nov), and asked for both buttons to move left so they clear the corner ornament.** Built in CSS so the canvas and the build share it: `.knob` in `ministry.css` is a 40 x 34 cartouche (metal rim `--rim`, wax `--wax`, hairline `--hair`, drawn with `clip-path`); `.head-btns` is `right:44px` (was 30), `top:23px`, gap 9, with the outline and shadow as a `filter` on `.head-btns` (`--knob-edge` for Silverhand's dark edge). The skins' knob rules in `WindowSkins.dc.html` now set `--wax` / `--rim` / `--hair` instead of `background`. No Lua change: `buildKnob` takes its size and place from the rebuilt slots.
- [x] two close options  [x] two settings options  [x] Max picks (cartouche, both)  [x] implemented (textures rebuilt)  [ ] Max checks in game, four skins
- **Canvas sync owed (Max said yes, 8 Nov):** upload the new `tab-frame-gold.svg` as an asset, point `ministry.css` at its new `/_blob/` id (and the key in `BLOBS` in `build.py`), upload the new `ministry.css` and repoint each board's `<link rel="stylesheet">` to it, and publish the changed `WindowSkins.dc.html`. The first upload was refused by a permission check on 8 Nov; waiting for Max to allow it.

### C3. New dark emerald Official seal
- Max: the Official wax seal (castle with a flag) clashes with the Exchange's red. Redesign it as a **dark emerald green** seal with a different emblem. Used in: Ring page (top-left), Treasury coffer box, several places in the Ballot Hall (`seal-off`, `seal-tilt`, `hseal_official`, the Seal button, the herald), `design/textures/seal-official.svg`. Find every use before changing.
- Step 1 is T1 (ten ideas, text only). Max picks. Then design and replace everywhere in one go. Watch that the Crown's and parties' seals stay distinct.
- Drafts drawn 8 Nov for 4a portcullis, 4c book and quill, 4h compass star, 4i crossed keys, 4j hourglass (board `c3-seal-drafts.png`; SVGs in the shared notes folder `batch-c-design/seals/`). Same build as `seal-official.svg`: emerald wax `#2F8A5E` / `#0F4A33` / `#03170E`, gold emblem, today's ring text.
- Correction: "By the Crown" is on the Crown's blue seal (`seal-crown.svg`: "Ministry of the Allied ✦ Stormwind ✦ By the Crown"), not on the Official seal. The Official seal reads "Sealed in Stormwind ✦ For the Alliance".
- [x] ideas given  [ ] Max picks  [x] drafts (5)  [ ] designed  [ ] replaced everywhere

## T1. Ten emblem ideas for the emerald seal (text only, Sonnet low)
Not designed, just ideas. Ministry is a guild government, official, neutral (not Crown, not a party). Give ten with a one-line reason each. Avoid red/purple/blue/silver motifs that belong to the parties and the Crown.
- [x] given to Max 8 Nov: 1 portcullis with chains, 2 mace of office, 3 open book and quill, 4 oak branch with acorns, 5 laurel wreath round an "M", 6 gryphon rampant, 7 column under laurel, 8 eight-point compass star, 9 crossed keys, 10 hourglass. Avoided: crown (Crown), hand/light (Silverhand), castle (today's). (An earlier note here said the Official seal's ring text was "By the Crown": wrong, see C3.)
- [ ] Max picks (drafts of 4a, 4c, 4h, 4i, 4j drawn 8 Nov)

## Open items (Max, 8 Nov)
- [ ] **The X buttons in the Ballot Hall's Crown view.** These are the small remove buttons beside each candidate's name box (piece `b_xbtn`, `tools/textures/ballot.html`; used in `UI/BallotHall.lua`). Max wants them changed; ask him what he has in mind, or offer two or three styles that match the cartouche Settings and Close buttons. Check all four skins.
- [x] Crisp text: Max checked the live text in game on 8 Nov and said it "looks great".

## Batch D: Districts and the map (Opus 5.5, high; after A to C)
- Build the Districts page (canvas: `Districts.dc.html`), the world map overlay and the map skins (`WorldMapSkins.dc.html`, reference art in `design/reference/`). New gate and fresh plan before starting. See `CODING_BRIEF.md` v1.4 (`UI/WorldMap.lua`) and `ADDON_SPEC.md` for the district rules.
- [ ] not started

## Canvas sync debt
The canvas is the design source. When the add-on moves away from it, say so to Max and offer to update the canvas:
- A2: header shifted down (title, subtitle, rules, Close, Settings).
- A3: Treasury aside is 236 wide on the canvas; the add-on matches it, but the Ring is still 206. The add-on's Treasury has an Accounts panel and a Minister card at the foot that the canvas lays out differently.
- Everything in Batch C goes canvas first.

## Open questions for Max
(All answered 8 Nov: held block yes, Parties portraits stay party colours, "This term" since the books opened is fine, Duncan's proposals agreed.)

## Uncommitted work already in the tree (7 Nov, not part of this plan)
`addon/MinistryOfTheAllied/UI/MainWindow.lua` had edits before we started: the window uses the learned full name (`MOTA.me`) and shrinks long names to fit the rail foot, and the footer text is moved clear of the corner ornaments. Left as is; Max or Duncan to commit.

## Progress log
- 8 Nov 2026 (after 0.6.3): **the Crown crest replaced the blue crown seal everywhere** (Max).
  - Covered: heralds by the Crown, Royal Assent, the Statute Book's "Given under the seal", the Ballot Hall's Crown seal and stamps, the minimap button, the settings page, and the Ring's laurels.
  - Build: `CROWN_CREST` in `build.py`.
  - Shape: the crest is taller than wide. It fits inside the old square (`object-fit:contain` rule in `ministry.css`). Statutes and Ring size it by its own shape.
  - Canvas boards use the crest blob `95cd0584...` (version 58).
  - sim.py 335 passed, 0 failed. Not seen in game, not committed.
- 8 Nov 2026 (final round today):
  - **Max liked the tab names (2a/2b) and said to make text crisp everywhere (2d).** Done as one mechanism:
    - `build.py` measures the real text in every piece (TEXT_JS, one page per look), draws the piece without it (HIDE_JS), and writes `Media.texts`.
    - `UI/LiveText.lua` lays it over the texture as game text. It follows the texture's show, hide, alpha, tint and size.
    - It is called from `UI:SetPiece`, `ApplySkinPiece`, Kit `art`/`Look`, the herald buttons, and the Ballot Hall `art`/`wear`/held.
    - About 150 pieces are covered: page ribbons, herald buttons, the settings page and its switches, the Ballot Hall ribbons, buttons and pills, and the page subtitles and eyebrows.
    - Still pictures: the window title (gradient letters) and the tilted "Waiting for the Crown" strip.
    - Checked by redrawing the pieces from the records (scratchpad `live_check.py`). Not seen in game.
  - **Lit tab:** beads along the top and bottom edges, plus one on each end, as Max asked. The tile is now 80 (slice 28). Live canvas version 55.
  - Max approved: the lit tab design is final, and the Ballot Hall seal stays at 112.
- 8 Nov 2026 (later again): another round from Max.
  - **Lit tab:** no inner rule. Bolder fleurons and tendrils sit 9 out from the tab: `.tab.on::after` `inset:-9px`, border-image `28 / 28px`. The shine is now a background sweep inside the tab, so the tab no longer clips. The lit tab is raised a frame level over its neighbours (`setTabLook`).
  - **Tab names (2a/2b, a trial for Max to judge in game):**
    - drawn as live text (`MOTA:Tracked` with `tabLabel`, a FontString with `tabSmall`) instead of the baked `label#`/`small#` pieces, which are still built;
    - a dark shadow on resting and hover tabs.
    - **2d is OPEN** if Max likes it: do the same for ribbons, buttons and the subtitle.
  - **Joined letters:**
    - Cinzel Decorative joins "h" + E/I/L/... with -384/-414 kerning. The "oo" join is kept: Max likes it.
    - The add-on and the build now use **Ministry Decorative** (`tools/fonts/make_ministry_decorative.py`, renamed per the OFL; `OFL-MinistryDecorative.txt`). The canvas loads it too: `@font-face` in `ministry.css`, with `--f-deco` first.
    - The title's kerning switch was removed again: the font fixes it.
  - **Live canvas (Max said go):** version 54.
    - New assets: tab `a9f3be1c...`, star `94ef7c92...`, portcullis `99bf4b4c...`, keys `0e3ae79b...`, fonts `1cb79e14...` / `b86b602a...`, `ministry.css` `dbcbfb8f...`.
    - Every board links the new stylesheet.
    - Seals: the Ring board uses the portcullis at 68; the Treasury board's coffer shows the keys at 74; the Ballot Hall "quiet" seal is 112.
    - The Main board calls it "Seal of the State".
    - `BLOBS` in `build.py` follows.
  - Not seen in game.
- 8 Nov 2026 (later): Max's next round.
  - Buttons: `.head-btns` is now `right:52px`.
  - Fleuron tendrils: they curl now, in `tab-frame-gold.svg`.
  - Seal of the State, in emerald:
    - the 8-point star is `seal-official.svg` and the default everywhere;
    - the portcullis `seal-ring.svg` (`hseal_ring`) is on the Ring page and the Ring's heralds;
    - the crossed keys `seal-treasury.svg` (`hseal_treasury`) are on the Treasury coffer and the bank prompt.
  - Bigger seals:
    - Ring 68: the plate is 178 and everything below moves down 20;
    - Treasury 74: `COFFER_H` is 202;
    - Ballot Hall quiet view 112.
  - Statute Book, In force: text beside the ribbon mark wraps short of it (`besideMark` in `UI/Statutes.lua`).
  - Testing: sim.py 335 passed, 0 failed. Textures were rebuilt before the seal-size and herald changes; those are Lua only.
  - Canvas: the new tab frame and the three seals are uploaded as assets (tab `11c95f5e...`, star `94ef7c92...`, portcullis `99bf4b4c...`, keys `0e3ae79b...`). Not yet referenced by any board.
  - Pending:
    - the lit tab redesign: no inner line, corners moved out to the tab's corner, the bolder "B". Needs `.tab.on` `overflow:visible`, a sheen that doesn't spill, `::after` `inset:-9px`, and the build's `tabOn` crop to include the overhang;
    - Max's call on the text-sharpness approach;
    - the canvas boards update.
- 8 Nov 2026: Max picked C1 B (fleuron, outside the line) and C2 cartouche (both), and asked for the buttons to move left. Built via `ministry.css` / `WindowSkins.dc.html` / `tab-frame-gold.svg`, textures rebuilt (frame_gold, frame_silver, skin_* changed; knob slots now 40 x 34 at x 867 / 916), sim.py 335 passed, 0 failed, not seen in game. C3: five emerald drafts drawn (4a, 4c, 4h, 4i, 4j); waiting for Max's pick and his ring-text call. Canvas sync not done: the asset upload was refused by a permission check. Nothing committed.
- 8 Nov 2026 (Opus 5.5 high, Max's choice for all of F and C): F1 to F4 coded, sim.py 335 passed, 0 failed, not seen in game. Files: `UI/Statutes.lua`, `UI/Parties.lua`, `UI/Kit.lua` (new `Kit:PlateArt`), `UI/Treasury.lua`, `UI/Ring.lua`. C1 and C2 options drawn as boards (four skins each) and T1 ideas given; waiting for Max's picks. Nothing built, nothing published to the canvas, nothing committed.
- 8 Nov 2026: Max checked Batch B in game and asked for follow-ups F1 to F4 (above), then Batch C in a NEW session, with a gate first so he can pick the model and effort. That session is started from this file.
- 8 Nov 2026: Batch B coded, held block wears party seal, sim.py 335 passed, 0 failed, not seen in game, nothing committed. New/changed: `UI/Statutes.lua`, `UI/Constitution.lua`, `UI/Kit.lua`, `UI/Treasury.lua`, `UI/BallotHall.lua`, `Fonts.lua`, `Commands.lua`, `.toc`, `tools/textures/*`, `design/textures/coin-*.svg`, regenerated Media.
- 7 Nov 2026: plan written. Batch A code done; sim.py 334 passed, 0 failed. Not yet seen in game. Nothing committed.
- Batch A files: `UI/MainWindow.lua`, `UI/Ring.lua`, `UI/Treasury.lua`, `UI/BallotHall.lua`, `tools/textures/ballot.html`, `tools/textures/build.py`, regenerated `Media.lua`, `Media/ballot.tga`, `Media/accent.tga`.
