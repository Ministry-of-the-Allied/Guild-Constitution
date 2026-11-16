# Ministry of the Allied: guide for Claude

A World of Warcraft (WoW Forever, Interface 16001) guild add-on that runs the guild as a political state: the Crown, elections, secret ballots, parties, districts, laws, a treasury, games and a Chronicle. The repo is the **dev space** (names, plans and decision logs are fine here). **CurseForge is the published space**; see Releasing below.

## How to work here (keeps token use down)

- **Read only what the task needs.** Use the feature map below to go straight to the right files. Don't read whole docs: `grep -n "^## "` a doc first, then read just the section you need.
- **Never read these in full:** `addon/MinistryOfTheAllied/Media.lua` (12k lines, generated), `ADDON_SPEC.md` (1,400 lines; read by section), `Libs/` (third-party Ace3), `design/canvas-source/*.html`, any `.tga/.ttf/.ogg`.
- **Generated files: edit the source, not the output.**
  - `Charter.lua` is generated from `CHARTER.md` by `tools/voice/build.py`.
  - `Media.lua` and `Media/*.tga` are generated from the design canvas by `tools/textures/build.py`.
- **Each new feature gets a fresh chat.** At the end of a feature, update the map below if you added files.
- **Test with the sim:** `py -3 tools/sim/sim.py` should end with `Lua errors: 0` and `0 failed`. Use `py -3`, not `python`. Add sim checks for new logic.
- Code style: plain-English comments. The `.toc` load order matters: libraries, then Core, then features, then UI, with Commands last. New files must be added to `MinistryOfTheAllied.toc`.

## Core architecture (read when touching shared plumbing)

| Area | Files | Spec |
|---|---|---|
| Boot, events, saved data (`MOTADB`) | `Core.lua`, `Data.lua` (constants and rank names) | §2, §6, §17 |
| Permissions (Crown, PM and citizens come from guild ranks) | `Core.lua`, `Data.lua` `CROWN_RANK_NAMES` | §4 |
| Messages (AceComm, prefix) | `Comm.lua`, `Hello.lua` (handshake) | §3, §7 |
| Shared book of records and catch-up | `Book.lua`, `Sync.lua`, `Roster.lua`, `Account.lua` (alts) | §6, §7 |
| Slash commands | `Commands.lua` | — |
| Main window, skins, kit | `UI/MainWindow.lua`, `UI/Skin.lua`, `UI/Kit.lua`, `UI/LiveText.lua`, `Fonts.lua` | §9, §10 |
| Design language | `design/STYLE_BRIEF.md`, `DESIGN_CHANGES_PLAN.md` | §15 |

## Feature map

| Feature | Logic | UI | Docs |
|---|---|---|---|
| Throne Room (home), Chronicle, Calendar | `Throne.lua`, `Chronicle.lua`, `Calendar.lua` | `UI/ThroneRoom.lua`, `UI/ChronicleBook.lua`, `UI/ChroniclePage.lua`, `UI/CalendarPage.lua` | §10.3, `CHRONICLE_BOOK_SAVE.md` |
| Elections, ballots, contests, no confidence | `Elect.lua`, `Ballot.lua`, `Contest.lua`, `Confidence.lua` | `UI/BallotHall.lua` | §8, `CHARTER.md` Parts II, III, V |
| Parties and front benches | `Party.lua`, `Bench.lua` | `UI/Parties.lua` | §10.16, `MANIFESTO_*.md` |
| Charter, laws, judiciary | `Charter.lua` (generated), `Judiciary.lua` | `UI/Statutes.lua`, `UI/Constitution.lua` | §12.6, `CHARTER.md` |
| Charter voice narration | `Voice.lua`, `tools/voice/build.py` | — | §12 |
| Treasury, bank, ledger | `Bank.lua`, `Ledger.lua` | `UI/Treasury.lua`, `UI/BankPrompt.lua` | §10.7 |
| Districts, District Cup, world map | `District.lua`, `Cup.lua` | `UI/Districts.lua`, `UI/WorldMap.lua`, `UI/WorldMapSkin.lua`, `UI/MapCompat.lua` | `CONSTITUENCIES.md`, `DESIGN_CHANGES_PLAN.md` Batch D |
| Guild dots on the maps | `Dots.lua` | `UI/Dots.lua` | §10.17 |
| NPC quest markers and nameplates | `NPCMarkers.lua` | `UI/NPCMarkers.lua`, `UI/NPCPlates.lua` | §10.18 |
| Games: hunt, lottery, honours, games log | `Games.lua`, `Hunt.lua`, `Lottery.lua` (+`Sha256.lua`), `Honours.lua` | `UI/GamesHall.lua`, `UI/HuntGlow.lua` | §19 |
| Hide and Seek | `Hide.lua`, `MapReveal.lua` (generated zone maps) | `UI/HideMap.lua` | §19 |
| Pub Quiz | `Quiz.lua`, `QuizBank.lua` (questions) | `UI/QuizPrompt.lua`, `UI/GamesHall.lua` | §17b |
| The Ring (duelling) | `Ring.lua` | `UI/Ring.lua` | §11 |
| Workshop (crafting guide), market, flipping ledger | `Workshop.lua`, `Market.lua`, `ProbeMarket.lua`, `Flips.lua` | `UI/Workshop.lua`, `UI/WorkshopMarket.lua`, `UI/WorkshopTooltip.lua` | — |
| Heralds (pop-ups) | — | `UI/Herald.lua`, `UI/HeraldPreview.lua` | §10.2 |
| Minimap seal, online tooltip, crests | — | `UI/Minimap.lua`, `UI/OnlineTip.lua`, `UI/Crests.lua` | — |
| Settings and Admin Controls | — | `UI/Settings.lua`, `UI/AdminControls.lua` | — |
| Members without the add-on | `Outreach.lua` | — | — |
| Debug probes | `Probe.lua`, `ProbeMarket.lua` | — | — |
| Textures and fonts pipeline | `tools/textures/`, `tools/fonts/` | — | §9, §15 |

Roadmap, status and open items: `ADDON_SPEC.md` §16 and §19.

## Releasing to CurseForge

1. Bump `## Version:` in `addon/MinistryOfTheAllied/MinistryOfTheAllied.toc`.
2. Run `py -3 tools/release/build.py`. This copies the add-on to `release/` (git-ignored), strips every comment from our Lua and the `.toc`, and **fails if any of our names remain**. Then it zips `release/MinistryOfTheAllied-<version>.zip`.
3. Run `py -3 tools/sim/sim.py release/MinistryOfTheAllied`. It must pass like the source does.
4. Upload the zip to CurseForge. Tag the commit `v<version>` and attach the zip to a GitHub Release.

Names in user-visible strings (anything that isn't a comment) must be fixed in the source; the build tells you where.

## Notes between the developers

If you are working with Max and `NOTE_FOR_MAX.md` exists, summarise it for him at the start of the session, in plain language, before other work. Once he has read it and is happy, offer to delete the file.

If you are working with Duncan and `NOTE_FOR_DUNCAN.md` exists, summarise it for him at the start of the session, in plain language, before other work. Once he has read it and is happy, offer to delete the file.
