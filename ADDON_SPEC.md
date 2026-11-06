# Ministry of the Allied — Addon Technical Specification

*Version 1.1 — 6 November 2026*
*For WoW: Forever (Interface 16001)*

---

## 0. How to use this document

- **`CODING_BRIEF.md` and this file are the add-on's single source of truth.** The brief is the short version for whoever writes code; this file holds every detail. On 2026-11-06 the old `ADDON_PLAN.md` and `plan/01-core-sync.md` were merged in here and deleted (git history keeps them).
- **Record every new decision here**, with its date, in the section it belongs to and in the decision log (section 19).
- **`CHARTER.md` stays the guild's law** for players. Every Charter rule the add-on needs is written into this file, so add-on work only needs this file and the brief. If the Charter is amended, update the matching rule here too.
- **The look comes from the live design canvas** (section 15), not from colour values written in this file.
- **Order of work:** design the screen on the canvas first, then plan the system here, then build it in small milestones that each load in the game (section 16).

---

## 1. Overview

The Ministry of the Allied addon (MOTA) is a single-codebase WoW addon that surfaces the guild's political state — government, laws, elections, treasury, districts, and court records — as an in-game UI window. It runs entirely within WoW's own addon system, using hidden addon messages for synchronisation. No external tools are required at this stage.

The addon runs in one of two modes, determined automatically by the player's guild rank on login:

- **Crown Mode** — full read/write access, control panel, election management, receiving and counting ballots
- **Citizen Mode** — full read access, vote casting

There is one addon distributed to all members. Crown features are hidden from the UI unless the player holds one of the two Crown guild ranks (section 4).

Every member's addon keeps its own full copy of the guild's records and shares them with everyone else, so the realm stays up to date **even when both Kings are offline** (section 7).

---

## 2. Addon Identity

| Property | Value |
|---|---|
| Addon name | MinistryOfTheAllied |
| Folder | `addon/MinistryOfTheAllied/` in this repo |
| Addon message prefix | `MOTA` |
| SavedVariables name | `MOTADB` |
| SavedVariables scope | Account-wide (`SavedVariablesPerCharacter` not used) |
| Interface version | 16001 (WoW: Forever) |
| Author | The Crown |

*The code built so far still uses the prefix `MotA`, the saved data `MinistryOfTheAlliedDB`, version 0.1.0 and the author "Ministry of the Allied". Renaming them is the first job in section 16.4.*

**Testing setup:** a folder link (a Windows junction) puts `addon/MinistryOfTheAllied/` inside Forever's `Interface/AddOns`, so a change shows in the game after `/reload`, with no copying.

---

## 3. Dependencies

One library, embedded in the addon. Citizens install nothing separately.

| Library | Purpose |
|---|---|
| AceComm-3.0 | Splits long addon messages into 255-byte pieces and joins them back together; paces sending so the game never throttles or disconnects the player |
| ChatThrottleLib | Ships with AceComm; does the pacing |
| LibStub, CallbackHandler-1.0 | Plumbing AceComm needs |

**Not used** *(decided 2026-11-06)*:

- **AceAddon-3.0, AceDB-3.0:** `Core.lua` already handles start-up and the saved data.
- **AceGUI-3.0:** its plain Blizzard-style widgets fight the canvas design. The window, heralds and settings are our own frames, drawn from the canvas.
- **LibSerialize, LibDeflate:** Forever has the game's own packer, `C_EncodingUtil` (`SerializeCBOR` / `DeserializeCBOR`, `CompressString` / `DecompressString`, `EncodeBase64` / `DecodeBase64`), confirmed by `/mota probe`. Compression makes a small record bigger (a sample record: 62 bytes packed, 64 compressed, 88 as text), so only big batches such as catch-up are compressed.

AceComm is downloaded from its official source (WowAce / the Ace3 project) when it's added. Its licence allows shipping it inside the addon.

---

## 4. Permission Model

The Crown is held by two co-monarchs. **Each King has their own guild rank: "The King" and "The Crown".** A character on either rank is the Crown. Only the Guild Master can rename ranks or move people onto them, so nobody can claim the Crown through the addon. If a rank is renamed, the addon stops recognising it until the name in `MOTA.CONST.CROWN_RANK_NAMES` is updated. *(Decided 2026-11-04, second rank 2026-11-06.)*

| Tier | Who | Permissions |
|---|---|---|
| **Crown** | The two Kings (ranks "The King" and "The Crown") | Read all, write all, open/close ballot sessions, receive and count ballots, grant Royal Assent, record treasury entries, register laws, record court rulings, manage citizen registry |
| **Citizen** | All other guild members | Read all, cast votes during open sessions |

- The Crown may delegate The Ring to the Minister of War (section 11.4).
- No citizen can write to canonical state. Every record says who wrote it, and each addon checks that the writer was allowed to write that type of record at that time (section 7.4). Records from anyone else are ignored.
- Office holders (PM, Cabinet, Justices, Representatives) see their duties (section 10.9), but in v1.x the Crown makes the writes.

---

## 5. Game Client

WoW: Forever is a **Classic-era game (levels 1–60, original Azeroth) on the modern retail engine and addon API**, reported as Midnight / 12.1.x era.

- Write against the **modern retail API**, not the Classic Era API. Classic Era addons don't load in Forever.
- Modern tools are available: the modern world map (`WorldMapFrame` data providers and pins), the Settings panel, `C_ChatInfo`, `C_EncodingUtil`, modern templates and atlases.
- Midnight added combat restrictions for addons. `C_ChatInfo.InChatMessagingLockdown` exists in Forever; the send queue waits while it's on.
- **Probe results** (2026-11-05): client 1.60.1, build 70790, **interface 16001**, project ID (`WOW_PROJECT_ID`) **18**. Each Forever patch raises the interface number, so check it after every patch. Send result codes exist, so the queue can tell a throttle from other refusals. The realm clock and the computer clock agreed.
- **Forever has a guild bank** with the game's money log.
- The addon's own fonts load in Forever.

---

## 6. Data Schema

### 6.1 How data is kept

Everything that happens is written down as a **record** in a shared book (section 7). The tables in 6.3 are the **state** each addon works out by reading its book from start to finish; they can be cached in `MOTADB` but the book is what syncs.

### 6.2 MOTADB layout

```lua
MOTADB = {
    settings = {},          -- options: debug, heralds, voice, skins, …
    guilds = {
        -- One book per guild, keyed "<guild name>-<realm>", so a character in
        -- another guild never mixes records with the Ministry's.
        -- ["Ministry of the Allied-Realm"] = {
        --     records  = {},  -- [author][number] = { t, k, d, got }
        --     tops     = {},  -- [author] = highest record number held
        --     reserved = {},  -- highest number another member says they hold of ours
        --     peers    = {},  -- last hello from each member's addon
        --     state    = {},  -- cached state (6.3), rebuilt from records
        -- }
    },
    ballotTally = {},       -- Crown clients only, never sent to the guild (8.2)
    onboarding  = {},       -- local only, never synced (12.3)
    probe = {},             -- last /mota probe report and limits test
    window = {}, minimap = {}, crest = {},  -- window position, size, page; minimap seal; chosen crest
}
```

### 6.3 State

```lua
state = {
    version = "1.0",
    lastSync = 0,           -- Unix timestamp of the last record received

    government = {
        pm = "",            -- Player name
        party = "",         -- "SILVERHAND" | "AZEROTH_EXCHANGE"
        termStart = 0,      -- Unix timestamp
        termDays = 92,      -- Standard term length in days
        cabinet = {
            treasury   = "",
            war        = "",
            trade      = "",
            recruitment= "",
            justice    = "",
        },
        opposition = {
            leader = "",
            party  = "",
        },
        governmentNumber = 1,
    },

    crown = {
        king1 = "",
        king2 = "",
    },

    citizens = {
        -- ["PlayerName"] = {
        --     district = "CATHEDRAL_WARD",
        --     party    = "SILVERHAND",
        --     joined   = 0,       -- Unix timestamp
        --     lastSeen = 0,
        --     main     = nil,     -- set on a confirmed alt: the main's name (10.1)
        -- }
    },

    ballot = {
        id = 0,
        active = false,
        type = "",          -- "GENERAL_ELECTION" | "SNAP_ELECTION" | "RUN_OFF"
        label = "",         -- Display name e.g. "The Raid Tithe Act"
        openedAt = 0,       -- Unix timestamp
        closesAt = 0,       -- Unix timestamp (openedAt + 7200 for 2hr window)
        eligibility = "ALL",-- "ALL" | district code for district elections
        options = {},       -- Array of {id, label, party} for elections
        totalEligible = 0,
        voted = {},         -- ["PlayerName"] = true (they voted, not how)
        result = nil,       -- Populated on close: {winner, votes, margin}
    },
    -- The count itself is never part of shared state: see MOTADB.ballotTally.

    statutes = {
        -- [id] = {
        --     id        = 1,
        --     title     = "The Guild Bank Levy",
        --     body      = "Every citizen pays...",
        --     author    = "PlayerName",
        --     ministry  = "TREASURY",
        --     district  = nil,    -- set if it mainly affects one district (10.8)
        --     assent    = 0,      -- Unix timestamp of Royal Assent
        --     expires   = 0,      -- Unix timestamp (assent + 7776000 for 90 days)
        --     status    = "IN_FORCE", -- "AWAITING" | "IN_FORCE" | "EXPIRED"
        -- }
    },

    treasury = {
        balance = { gold = 0, silver = 0, copper = 0 },
        ledger = {
            -- [id] = {
            --     date        = 0,    -- Unix timestamp
            --     description = "",
            --     direction   = "IN", -- "IN" | "OUT"
            --     gold        = 0,
            --     silver      = 0,
            --     copper      = 0,
            --     recordedBy  = "",
            -- }
        },
    },

    court = {
        -- [id] = {
        --     date      = 0,
        --     accused   = "",
        --     charge    = "",
        --     verdict   = "GUILTY", -- "GUILTY" | "NOT_GUILTY"
        --     punishment= "",       -- Free text
        --     sanction  = nil,      -- "CENSURE" | "FINE" | "EMBARGO" | "SUSPENSION" | "EXILE" (10.10)
        --     justices  = {},       -- Array of player names
        --     status    = "OPEN",   -- "OPEN" | "RULED" | "APPEALED" | "CLOSED"
        -- }
    },

    elections = {
        -- Historical record of all completed elections
        -- [id] = {
        --     number    = 1,
        --     type      = "GENERAL_ELECTION",
        --     date      = 0,
        --     winner    = "",
        --     party     = "",
        --     votes     = {},     -- {option_id = count}
        --     turnout   = 0,
        -- }
    },

    noConfidence = {
        lastFailed = 0,     -- recorded by the Crown; starts the 30-day cooling period (8.6)
    },

    ring = {},              -- section 11.2
    chronicle = {},         -- section 10.3
    honours = {},           -- section 10.4
    treaties = {},          -- section 10.14
    letters = {},           -- section 10.12
}
```

---

## 7. Sync: the shared book

*Kept from the old Core/Sync plan by Max's decision of 2026-11-06: updates must keep happening when the Kings are offline. This replaces the brief's original Crown-only `STATE_FULL` / `STATE_DELTA` / `STATE_REQUEST` model.*

### 7.1 Records

Everything that happens is a **record**: "the Crown opened polls", "the Crown gave Royal Assent to the Raid Tithe Act", "Aldric beat Mira in a duel".

| Field | Example | Notes |
|---|---|---|
| Author | `Max-Realm` | The character who created it |
| Number | `57` | The author's own running count |
| Time | `1793812345` | The realm's server time (`GetServerTime()`), so every member agrees on deadlines |
| Type | `ballot.open` | What happened |
| Details | `{label="…", closesAt=…}` | Kept as short as possible |

- Author + Number is the record's unique ID. **Numbers are never reused:** the hello reply tells a member the highest number others hold from them, so a crash that lost their latest records doesn't cause a clash.
- Records are **only ever added**, never edited or deleted. A correction is a new record ("the Crown voided record 41").
- Every page is worked out from the records.
- Every member's addon keeps a full copy. If anyone stops playing, nothing is lost.
- **Size:** a busy guild of 100 might create a few thousand records a year. Old ballot details can be folded into a single result record once the result is declared.

### 7.2 Storage

Account-wide SavedVariables, so alts on one account share a book. The game writes it to disk only on logout or `/reload`; records lost in a crash come back from other members at the next sync.

### 7.3 Keeping everyone in step

- **Live news:** when the Crown (or anyone allowed) writes a record, it goes straight to the guild. Everyone online gets it within a second or two, and any herald fires.
- **Catching up:** on login, and every `SYNC_STALE_SECONDS` after, each addon sends a short summary: for each author, the highest record number it holds. Anyone with records the other is missing offers them, after a short random wait so 40 members don't all answer at once; if someone else starts sending, the others stand down. The records go by whisper to that member only, through the slow queue, so catch-up never crowds out live news.
- **Fresh installs** catch up the same way. The Throne Room shows "Catching up with the realm… 64%" until it's done.
- **Footer:** the status strip shows the last sync time ("Moments ago"). If more than `SYNC_AMBER_SECONDS` (30 minutes), the indicator turns amber.

### 7.4 Trust

Addon messages always carry the real name of the sender, which can't be faked.

- **Records sent by their own author** are accepted if the author was allowed to write that type at that time (section 4).
- **Records passed on by someone else** (during catch-up) are held as **unconfirmed** until the author sends them, or two different members pass on identical copies. Unconfirmed records are greyed out where it matters.
- **Record types a copy doesn't know are kept but never acted on**, so a newer copy's records survive in an older one's book.
- *Built so far:* only records sent by their own author are taken; passed-on records wait for catch-up.

**Honest limits:** strong protection against ordinary mischief, not bank-level security. Someone who rewrote the addon could send odd records under their own name, but couldn't pretend to be someone else or use an office they don't hold.

### 7.5 Messages

All messages go through **AceComm-3.0** on the prefix `MOTA`.

| Kind | Channel | What it carries |
|---|---|---|
| Hello | GUILD | Version, records held |
| Hello reply | WHISPER, back to the sender | Version, the highest record number held from them |
| Record | GUILD | One record (7.1) |
| Summary | GUILD | Highest record number held per author (catch-up) |
| Catch-up batch | WHISPER | Missing records, packed and compressed |
| Ballot | WHISPER, to each online King | The sealed vote (8.2) |
| Ballot receipt | WHISPER, King back to the voter | "Your ballot is sealed" |
| Tally hand-over | WHISPER, King to King | The running count, when the second King logs in during a session |
| Probe | GUILD | Test traffic for `/mota probe limits` (only the sender reads it) |

The brief's other message types are now record types: `BALLOT_OPEN` → `ballot.open`, `BALLOT_CLOSE` → `ballot.close`, `CITIZEN_UPDATE` → `citizen.update`, `STATE_DELTA` → whichever record changed. `PETITION_SIGN` is dropped: no-confidence goes by in-game mail (8.6).

- **Format:** a record is packed with `C_EncodingUtil.SerializeCBOR` and turned into channel-safe text with `EncodeBase64`; big batches are compressed with `CompressString` first. (Whether Forever accepts raw binary in addon messages, which would save the Base64 step, is untested.) *(Built so far: short text fields joined by byte 31, protocol 1. Moves to CBOR when AceComm is added.)*
- **Versions:** every message carries a protocol version. Hello and hello reply always keep the version first, so an old copy can tell it's out of date. A copy that hears a newer protocol stops writing records and tells the player to update, but keeps reading.
- **Whispers** are only accepted from guild members. A copy ignores its own guild messages echoed back.
- **Throttling:** never raw `C_ChatInfo.SendAddonMessage`; AceComm splits and paces. Minimum `BROADCAST_MIN_INTERVAL` (3 seconds) between routine GUILD broadcasts; records that trigger a herald go ahead of catch-up.
- **Lockdown:** if the game locks addon messages (for example in a boss fight), the queue waits.

### 7.6 Time

Every record uses the realm's server time, so a poll that closes "at 8pm" closes at the same moment for everyone. Times are displayed in each member's local time.

### 7.7 Privacy of personal records

Records meant for one person (letters, a court summons) still travel on the guild channel, so they reach the person after being offline; the addon only **shows** them to that person. Ballots are the exception: they never touch the guild channel (8.2).

---

## 8. The Voting Session Flow

The addon handles elections: General, Snap, run-offs, and district elections (`eligibility` = a district code). Law votes are not managed through the addon — legislation is a Crown/government responsibility handled outside the system. No-confidence votes are submitted by citizens via in-game mail to the Crown, as defined in the Charter; the Crown records the outcome manually.

**Voting is direct.** The Prime Minister is elected in one guild-wide count; every citizen's vote counts the same. A citizen's district only matters when electing that district's Regional Representative (Charter 8.2).

### 8.1 Opening a Session (Crown)

1. Crown opens the Ballot Hall tab in Crown Mode
2. Sets election label and adds the two party candidates as options
3. Clicks **Open Polls** — the addon writes a `ballot.open` record, sent to the guild
4. All online citizens receive it — Ballot Hall notification dot activates and a herald calls "The polls are open!"
5. Citizens who log in during the session receive it through catch-up (7.3)

Polls stay open for `BALLOT_WINDOW_SECONDS` (2 hours, Charter 3.3 as amended 2026-11-06).

### 8.2 Casting a Vote (Citizen) — the secret ballot

*Decided 2026-11-06: secret ballot, delivered by hidden whisper to the Kings only.*

1. Citizen opens Ballot Hall, sees active ballot
2. Selects option, clicks **Seal My Ballot**
3. The addon sends the ballot `{ballotId, optionId, timestamp}` by **hidden addon whisper to each King who is online**. Addon whispers never appear in chat and reach only the named character, so officers and everyone else never receive them.
4. **If no King is online,** the voter's addon holds the sealed ballot and sends it the moment a King logs in, as long as polls are still open. The Ballot Hall shows "Sealed, waiting for the Crown".
5. Each King's addon validates (eligible, not already voted, not a linked alt), adds one to its local `MOTADB.ballotTally`, and **throws the voter's name away** — only "this person has voted" is kept.
6. The King's addon writes a `ballot.voted` record (who voted, not what they chose) to the guild, and whispers a receipt back.
7. Citizen's ballot UI updates to "Your ballot is sealed"

- **Two Kings, two counts.** Both Kings receive every ballot sent while they're online, so their counts can be compared before the result is declared. If only one King was online, their addon hands the running count to the other King by whisper when they log in.
- **Vote secrecy:** raw vote choices are never sent to the GUILD channel or saved with a name. The `voted` list confirms participation, never preference.
- **Honest limits:** the guild trusts the Kings' count, and the Kings' addons briefly see each ballot. Someone writing their own script to read votes is judged highly unlikely.

### 8.3 Closing a Session (Crown)

1. After the 2-hour window (or manual close), Crown clicks **Close Polls**
2. Addon calculates result from the tally, populates `ballot.result`
3. Writes a `ballot.close` record with the result — all citizens receive it, and a herald announces it
4. Result is written to `elections` history and the Chronicle
5. If General Election: Crown is prompted to update `government` state
6. Ballot resets to `active = false`

**Ties:** a run-off between the tied candidates only, within 48 hours (Charter 2.1). The Crown opens it as a `RUN_OFF` ballot.

### 8.4 Who may vote

- **Active citizens:** logged in within `ACTIVE_CITIZEN_DAYS` (30). The addon reads "last online" from the guild roster and publishes the count the Crown would otherwise keep by hand (Charter 5.3). Inactive citizens don't count towards any threshold or turnout, including the 40% for no-confidence.
- **Returning citizens:** someone back from inactivity fewer than 10 days before a vote opens can't vote in it. Brand-new members can vote straight away.
- **One person, one vote:** only a main gets a ballot; linked alts are refused (10.1).

### 8.5 Offline Votes

Citizens offline during a session cannot vote in the current cycle. This is by design — voting windows are declared events. Future upgrade path: async vote queueing with external persistence (section 16).

### 8.6 Elections and no-confidence (Charter rules)

- **Term:** three calendar months from the PM taking office; a General Election at the end of each.
- **General Election timeline:** two weeks of campaigning, then polls (2 hours), then the Crown declares the result; the new PM takes office within 24 hours. A **phase banner** runs across the top of every page during an election ("Campaign period: 9 days to polling").
- **Snap Elections:** the Crown dissolves the government, or a successful no-confidence vote triggers one. Campaign at least `SNAP_ELECTION_MIN_DAYS` (7).
- **Vote of No Confidence:** citizens send it by in-game mail to the Crown. If 40% of active citizens (`NO_CONFIDENCE_THRESHOLD`) do so within seven days, the Crown records the outcome and triggers a Snap Election. After a failed one the Crown records that too, and the Ballot Hall shows the 30-day cooling period ("Cooling period: 12 days left").
- **Debates** happen on Discord voice chat; the addon puts the time on the election timeline, sends a herald and a reminder before it, and records the debate night in the Chronicle.

---

## 9. Skin System

The addon renders in one of four visual skins, selected automatically on login based on the player's guild rank and registered party.

*Decided 2026-11-06: the four skins reuse the four **world map skin designs** on the live canvas (section 9.6). Each is a version of the one Ministry theme: the same frame shape and materials, with the metal, wax, colours and emblem swapped.*

### 9.1 Skin Selection Logic

```lua
local function GetPlayerSkin()
    if MOTA.IsCrown("player") then  -- rank "The King" or "The Crown" (section 4)
        return "CROWN"
    end
    local citizen = MOTA.state.citizens[MOTA.me]
    local party = citizen and citizen.party
    if party == "SILVERHAND" then
        return "SILVERHAND"
    elseif party == "AZEROTH_EXCHANGE" then
        return "AZEROTH_EXCHANGE"
    else
        return "UNREGISTERED"
    end
end
```

The skin is set once on login and refreshed on any `citizen.update` record affecting the current player. It does not hot-swap mid-session without a `/reload`. The Crown skin supersedes party affiliation for Crown rank holders.

### 9.2 The four skins

| Skin key | Design | Colours | Corner emblem |
|---|---|---|---|
| `CROWN` | The Azeroth Exchange's design with royal purple in place of crimson, taken from a royal robe Max chose. Mostly the deep purple; the lighter purple only as small highlights (centre of the title band, top edge of each step and button). Gold filigree on the two bottom corners, inside the frame | Deep royal purple and gold | The Crown crest |
| `SILVERHAND` | Silver metalwork and argent wax | Silver with the party blue `#1F4290` (the silver sets it apart from the Ministry blue) | The Silverhand seal (blue hand) |
| `AZEROTH_EXCHANGE` | Deep crimson and gold | `#9E1B22` and gold | The Exchange seal (coin-scale) |
| `UNREGISTERED` | The Ministry default: royal blue and gold, for citizens not in a party (membership is voluntary, Charter 3.2) | Royal blue and gold | The lion crest |

**The Crown crest** (`design/textures/crest-crown.png`): a deep purple shield with a gold royal crown, crossed gold sceptres, a purple mantle and gold leaves, emeralds on the crown's band and a cross-shaped emerald set into its cross. A transparent cut-out made in Higgsfield (GPT Image 2.6).

**The lion crest** (`design/textures/alliance-crest.png`): the Crown crest's shape with a gold lion head in place of the crown and royal blue in place of the purple. Made in Higgsfield, so it isn't Blizzard's art. The old Stormwind picture stays in `design/reference/alliance-crest.png`. The crest finder (`/mota crests`) stays in, in case the game's own crest is ever wanted.

### 9.3 Colour Tokens

Each skin defines tokens consumed by all UI components. **Final values are taken from the world map skins board on the live canvas** when `Skin.lua` is built; the table below is the brief's placeholder set.

| Token | CROWN | SILVERHAND | AZEROTH_EXCHANGE | UNREGISTERED |
|---|---|---|---|---|
| `PRIMARY_BG` | `#1A0A2E` | `#0E1F45` | `#2A0A0A` | `#1A1409` |
| `BORDER` | `#7B4FA6` | `#C9A24A` | `#C9A24A` | `#8A7340` |
| `ACCENT` | `#9B6EC8` | `#3A63B8` | `#8B1A1A` | `#6B5A28` |
| `HEADER_TEXT` | `#D4A8FF` | `#F3D98A` | `#F3D98A` | `#D4B96A` |
| `BUTTON_BG` | `#5C2D8A` | `#1B3570` | `#6E1212` | `#4A3A18` |
| `BUTTON_TEXT` | `#FFFFFF` | `#F3D98A` | `#F3D98A` | `#D4B96A` |

### 9.4 Skin Application

Skins are applied via a central `MOTA.ApplySkin(skin)` function called during frame initialisation. All UI files reference tokens by name, never hardcoded hex values. Because the window is drawn from textures (section 15), each skin also names its own texture set; a skin swap is still one function call.

```lua
-- Skin tokens are stored in MOTA.skin after ApplySkin() is called
-- Hex values are pre-converted to RGB float tables on load:
-- MOTA.skin.PRIMARY_BG = { r = 0.10, g = 0.04, b = 0.18 }

-- Usage in any UI file:
local c = MOTA.skin.PRIMARY_BG
frame:SetBackdropColor(c.r, c.g, c.b, 1)
```

### 9.5 Skin.lua

A dedicated `UI/Skin.lua` file holds all token definitions, the texture set per skin and the `ApplySkin()` function. It is loaded before all other UI files in the `.toc`.

```lua
-- Skin.lua (excerpt)
local SKINS = {
    CROWN = {
        PRIMARY_BG   = { r=0.10, g=0.04, b=0.18 },
        BORDER       = { r=0.48, g=0.31, b=0.65 },
        ACCENT       = { r=0.61, g=0.43, b=0.78 },
        HEADER_TEXT  = { r=0.83, g=0.66, b=1.00 },
        BUTTON_BG    = { r=0.36, g=0.18, b=0.54 },
        BUTTON_TEXT  = { r=1.00, g=1.00, b=1.00 },
        CREST        = "Interface\\AddOns\\MinistryOfTheAllied\\Media\\crest_crown",
    },
    SILVERHAND = { --[[ ... ]] },
    AZEROTH_EXCHANGE = { --[[ ... ]] },
    UNREGISTERED = { --[[ ... ]] },
}

function MOTA.ApplySkin(skinKey)
    MOTA.skin = SKINS[skinKey] or SKINS.UNREGISTERED
end
```

### 9.6 World map skins

The game's own world map window ("Map & Quest Log") gets a frame in the same skin as the player's addon window. *(Agreed 2026-11-03.)*

- **Only the window around the map changes.** The map art (including its torn parchment edges), the zone name on hover, the quest and travel markers, and the district highlights are left alone.
- **What gets skinned:** the frame border (thin dark metal with gold trim); the title bar ("Map & Quest Log" in gold on a dark strip); the enlarge and close buttons (Blizzard's red squares take the party colours); the location bar ("World > Eastern Kingdoms > Elwynn Forest") with its highlight on the current step, its dropdown arrows and the small button at its right end; the rims of the round buttons over the map (a diamond button top left, a "!" button top right); the quest log toggle in the bottom-right corner and the docked quest log. If the whole window turns out to be too much, cut it back later.
- **The corner seal:** the skin's emblem (9.2) takes the top-left corner, replacing the round book icon that already sits there and breaking out over the frame.
- **Player choice:** settings offers Party (the default), Ministry or Blizzard's plain map.
- **Only on your own screen,** so nothing private is shown.
- **How it's built:**
  - The map's border is made of corner and edge pieces. The addon swaps those pictures and recolours the rest. It never replaces Blizzard's own map code, which keeps it clear of taint.
  - The game redraws the border whenever the map is enlarged or shrunk, so the addon puts the skin back on each time.
  - The skins are one list, one entry per party, so a new party or a reworked skin only needs new artwork.
  - Before skinning, the addon checks that each part of the window is there. If a Blizzard patch has changed it, the plain map is left alone.
  - If another addon restyles or replaces the map window's frame (for example ElvUI's skins), ours steps back. Addons that only add things to the map (such as a coordinates readout) don't count.
- **Design:** the "World map skins" board on the live canvas shows all four skins on the real Elwynn Forest map, plus the setting (first pass 2026-11-04; second pass the same day matched the game window's proportions: title strip, location bar and gap about 15% of the map's height, square enlarge and close buttons flush top-right, outer rim about 30% thinner). The docked quest log isn't drawn yet: it needs a Forever screenshot with the quest log open. Reference: `design/reference/forever-world-map.webp`.

---

## 10. UI Structure and Features

One window with **seven tabs** matching the canvas. Tab availability is the same for Crown and Citizen — the difference is the presence of write controls within each tab. **One page per subject:** related screens are sub-views that swap inside the page (sub-tabs, a toggle or a pop-out), never separate windows. During an election, a phase banner runs across the top of every page.

| Tab | What it holds | Crown extras |
|---|---|---|
| **Throne Room** (home) | Who holds power (Crown, PM and Cabinet, Leader of the Opposition); countdown to the next election; any open ballot with a button to vote; your district and party; your duties (10.9) and letters (10.12); a feed of recent decrees opening into the Chronicle (10.3) | Edit government state, trigger dissolution |
| **Ballot Hall** | **Ballot** (default while polls are open): the parchment ballot paper, sealed with the wax-seal "Seal My Ballot" button. **Results** (default otherwise): the Crown's proclamation of the last result and past elections. The no-confidence status and cooling period (8.6) | Open/close elections, see live tally, record result, record no-confidence outcome |
| **Statute Book** | **In force**, each law with its expiry countdown; **Awaiting Royal Assent / up for renewal / Council consultation** (10.8); **Rulings** — the court registry (10.10); **Treaties** (10.14) | Add law, grant Royal Assent, expire law early, record court rulings |
| **The Parties** | Two fixed parties — The Silverhand and The Azeroth Exchange. Banner, ideology pillars, leader, member count, manifesto and join button | Edit party records, member counts |
| **Treasury** | The ledger in an old accounts-book style: the Minister of the Treasury, the balance, gold in and out, taxes. Fully public: every line shows the member's name, withdrawals included | Record a payment, edit balance |
| **Districts** | **Map:** the Stormwind map with your district glowing in its colour and a pin on your council meeting spot. **Regional Council:** the five Representatives and their districts. **Citizen Roll:** every citizen with district, party and office. **Assignments & transfers** (10.11) | Edit citizen district/party assignments, Citizen Roll |
| **The Ring** | Sign-up, Bracket, Champions (section 11) | Create tournament, record bout results, manage sign-ups |

**Ballot Hall scope:** Elections only (General, Snap, run-off, district). No law votes. No-confidence is tracked manually by the Crown via in-game mail.

**The Parties scope:** No internal chamber mechanics in v1.x. Party membership is public. Joining costs at least 5g paid to the party's designated officer (Charter 3.2); the join button sends the request, and the Crown records membership in the citizen registry once paid. At the close of each campaign period the Parties page shows each party's published donation total.

**Small extras:**
- **Minimap seal:** a wax-seal button that opens the addon (right-click opens settings).
- **Herald pop-ups** (10.2).
- **Sealed letters** (10.12).
- **Citizen card:** shown when you hover over a guild member: district, party, offices held, honours, any unpaid fine or embargo, and whether they have voted (never how).
- **Settings panel:** in the game's own options (Escape > Options > AddOns > Ministry of the Allied).
- **Voice player and Charter Library** (section 12).
- **World map skins** (9.6).

### 10.1 One person, one vote (alt links)

Players link their alts to their main in the addon. A link only counts once it's confirmed from the alt itself (log in on the alt and accept). Only the main gets a ballot; the Kings' addons refuse a ballot from a linked alt. An alt nobody has declared can't be spotted automatically; the activity rules (8.4) and the Crown's power to rule on disputed votes cover the rest.

### 10.2 Herald pop-ups

- When something happens (polls open, a result is declared, a law passes, a party change, a Ring bout), the record that announces it makes a herald pop-up appear for everyone online, with a fanfare from the game's own sounds.
- The herald is a parchment scroll with gold rollers, the seal, a spaced-out heading line, the title, a line of text and a button. It appears at the top of the screen, one at a time, stays 10 seconds (8 for Modest) or until dismissed, stays up while the mouse is over it, and waits until you're out of combat. Its button can open a page ("Vote now" opens the Ballot Hall).
- **Royal** is 0.8 of the canvas size with the unroll from the board; **Modest** is 70% of that and fades in. Heralds can be switched off in settings.
- Members offline see missed notices when they next log in and catch up.
- Each feature adds its own heralds as it's built.

### 10.3 The Chronicle

A permanent, dated history of the realm: elections and results, laws passed and lapsed, court rulings, party changes, honours and Ring champions. Written automatically from the same records that trigger heralds, and synced, so new members get the whole history. Lives in the Throne Room: the decrees feed has a "See all" that opens it, browsable by month.

### 10.4 Honours and titles

- The Crown awards honours (orders and titles such as "Order of the Lion"), each announced by herald and written into the Chronicle. They show as ribbons on the citizen card, alongside offices held and terms served.
- What the game allows: the name above a character's head and real titles come from Blizzard's servers, so no addon can change them. The addon **can** put the title in front of the name in the mouseover tooltip, in guild chat (10.5), on the citizen card and on the Citizen Roll, and above the head on the **friendly nameplate** (only for people running the addon, only with friendly nameplates on, blocked in dungeons and raids). To test (section 18).

### 10.5 Chat tags

In guild chat, each name gets a small tag for their office and party (e.g. [PM] in party colours), plus their honour title. Only changes how chat looks for people running the addon; can be turned off in settings.

### 10.6 Reminders

On login: any ballot you haven't cast, with the time left. Shortly before your district's council meeting, a Discord debate, or your Ring bout. Same rules as heralds: wait until out of combat, can be toned down.

### 10.7 Treasury

- The Crown records each payment (date, description, in or out, amount, recorded by) and can edit the balance. Ring entry fees are added automatically (11.5).
- The Minister of the Treasury is appointed by the PM (Charter 2.2), not elected.
- Fully public, names included. *(Decided 2026-11-04.)*

### 10.8 Laws

- All laws need Royal Assent and last exactly three months from it (`LAW_EXPIRY_SECONDS`, 90 days).
- **Renewal list:** when a new PM takes office, the Statute Book lists every law that will lapse, with a two-week countdown (Charter 4.2). Laws not renewed expire.
- **Council consultation:** a law marked as mainly affecting one district shows "Awaiting Council consultation" until that district's Representative has been consulted, before Royal Assent (Charter 8.2).
- **Law Registry:** the addon produces the registry (laws, dates, authors, expiry) as text the Minister of Justice copies to the guild's GitHub (Charter 4.3), using 10.15.

### 10.9 Duties panel

Anyone holding an office sees their own to-do list on the Throne Room:
- **Crown:** laws awaiting Royal Assent, results to declare, appeals to decide, ballots to count.
- **PM:** laws to renew, Cabinet posts to fill.
- **Minister of the Treasury:** ledger entries to explain.
- **Minister of War:** The Ring (sign-ups, draw, results).
- **Minister of Recruitment:** new citizens to assign to a district.
- **Regional Representatives:** consultations and transfer requests.
- **Justices:** open cases.

### 10.10 The court registry and punishments

- The Crown records each case and ruling (`court`, section 6.3). Rulings show in the Statute Book and the Chronicle. A separate `UI/Court.lua` file builds the registry, shown inside the Statute Book's Rulings view.
- Justices are three, appointed by the Crown, and can't hold any other office (Charter 6.1); the addon refuses an appointment that breaks this.
- The 48-hour appeal window to the Crown (Charter 7.2) shows on each ruling; the Crown's decision is final.
- **Punishment ladder (Charter 7.1)** and what the addon shows:
  - **Public censure:** in the Chronicle and Rulings permanently.
  - **Treasury fine:** on the citizen card as unpaid until the Crown records the payment.
  - **Trade embargo:** on the citizen card and tooltip, with a warning if anyone opens a trade window with that citizen. Guild bank access is removed by an officer through guild ranks.
  - **Suspension from office:** the office is removed.
  - **Exile:** needs the Crown's sign-off; an officer removes the character from the guild.

### 10.11 District assignment and transfers

- Five districts (`CONSTITUENCIES.md`): the Old Quarter, the Arcane Ward, the Iron District, the Cathedral Ward and the Harbour Quarter. A citizen's district lives in the addon's synced data, not in guild notes, so public and officer notes stay free.
- **New members** appear in the Minister of Recruitment's duties; the Crown assigns their district, taking into account class, main activity and what the citizen asked for.
- **Transfers:** a citizen can apply to move district after one full term, with the approval of both Representatives; the Crown records the move.
- **District sizes** are shown, to keep districts balanced.
- **District map highlight:** your district is drawn as a highlighted area on the real Stormwind map, using zone coordinates.

### 10.12 Official letters

Personal notices arrive as a sealed letter you break open (with a wax-seal crack): appointment to the Cabinet, a summons, a fine, a transfer approved, a party membership accepted. Unread letters show on the Throne Room. Guild-wide news stays as heralds.

### 10.13 Settings panel

In the game's own options, drawn from the canvas's Extras board: the parchment page with the Crown seal and title, the gold-and-blue switches, and the Modest / Royal choice for heralds. Opened by the window's gear, a right-click on the minimap seal, or `/mota settings`. Switches for features not built yet are greyed out with "· later". The minimap seal on/off and window size stay as `/mota minimap` and `/mota scale` until they're added to the canvas. If the game blocks opening its options in combat, the addon says so. Also holds: the world map skin choice (9.6), voice on/off and volume (12), a **Resync** button that asks the guild to send everything again.

### 10.14 Diplomacy register

The guild's relations with other guilds (allied, friendly, neutral, rival) and treaties, kept by the government. In the Statute Book under Treaties. Members of those guilds get a relation tag on their tooltip ("Allied guild: Treaty of Goldshire").

### 10.15 Share to Discord

Results, laws, rulings, the Law Registry and Ring champions can be turned into ready-formatted text in a copy box, to paste into Discord or GitHub. Addons can't post to Discord themselves.

---

## 11. The Ring (Gladiator System)

The Ring is the guild's formal PvP tournament system: a monthly 1v1 duelling tournament, for fun and for raising gold. It is managed by the Crown or the delegated Minister of War, with entry fees, a bracket structure, and a Hall of Champions. Entry fees flow into the guild ledger.

### 11.1 Tournament Structure

- **Season name** — set by Crown (e.g. "The November Ring")
- **Level bracket** — Crown sets the bracket on creation (e.g. "Open" or a level range) to prevent mismatches
- **Format** — single-elimination: Quarter-finals → Semi-finals → The Final
- **Entry fee** — set per tournament; automatically logged to the Treasury ledger as income
- **Guild cut** — defined by law or Crown decree (default 10%); the champion gets the prize pool minus the cut
- **Venue** — Old Town, home of the Old Quarter, the warriors' and PvP district

### 11.2 State

```lua
ring = {
    active = false,
    season = "",            -- Display name, e.g. "The November Ring"
    bracket = "",           -- Level range or "Open"
    entryFee = { gold=0, silver=0, copper=0 },
    guildCut = 0.10,        -- Fraction taken by the guild (default 10%)
    signupsClose = 0,       -- Unix timestamp
    participants = {},      -- ["PlayerName"] = { paid=true, seed=0 }
    rounds = {
        -- [roundName] = { bouts = { {p1, p2, winner} } }
    },
    champion = "",          -- Winner of The Final
    champions = {
        -- Historical record
        -- [season] = { champion, date }
    },
}
```

### 11.3 UI — The Ring Tab

**Bracket sub-tab**
- Tournament name and bracket type
- Bracket draw (Quarter-finals → Semi-finals → Final)
- Next bout display; a herald calls each bout ("Next bout: Aldric v Mira, Old Town")
- "Awaiting the draw" state before sign-ups close

**Sign-up sub-tab**
- Entry fee display
- Sign-up sheet (player name list)
- Sign-ups close date
- "Enter the Ring" button (citizen self-registers; entry fee reminder shown)

**Champions sub-tab**
- Hall of Champions — historical list of tournament winners with season and date
- "Gladiator of Stormwind" title shown next to current champion name (an honour, 10.4, for the month)

### 11.4 Crown Controls

Crown (or delegated Minister of War) can:
- Create a new tournament (name, bracket, fee, sign-up deadline)
- Close sign-ups and generate the bracket draw
- Record bout results (winner per matchup)
- Declare the Final champion
- Entry fees are automatically added to the Treasury ledger on sign-up registration

**Duel results:** the game prints "X has defeated Y in a duel" to everyone nearby. The organiser's addon reads it and moves the winner on; the organiser can also click the winner by hand.

### 11.5 Treasury Integration

When a citizen registers for The Ring, the entry fee is logged as a Treasury entry:
```lua
{
    date        = timestamp,
    description = "Ring entry fee — " .. playerName .. " (" .. ring.season .. ")",
    direction   = "IN",
    gold        = ring.entryFee.gold,
    -- silver/copper as set
    recordedBy  = "RING_SYSTEM",
}
```

Prize pool = total entry fees collected. Guild cut is deducted and retained in Treasury. Remainder paid to champion by the Minister of the Treasury in-game. The champion also gets a Chronicle entry.

---

## 12. Voice Onboarding System

Ten pre-generated ElevenLabs voice clips narrate the Royal Charter on first use. Clips play automatically in a staged sequence during early play sessions, and are available on-demand from within the addon at any time.

**Voice rules:** the voice must be an original AI voice, not a copy of a Blizzard character or a real actor, and the voice tool's licence must allow shipping the files inside the addon (check ElevenLabs' terms before generating). Voice has an on/off switch and volume in settings.

### 12.1 Clip List

| # | Title | Charter section |
|---|---|---|
| 1 | Hear Ye | Preamble / intro |
| 2 | The Crown | Part I |
| 3 | The Government | Part II |
| 4 | The Parties | Part III |
| 5 | Legislation | Part IV |
| 6 | The Vote of No Confidence | Part V |
| 7 | The High Judiciary | Part VI |
| 8 | Punishment | Part VII |
| 9 | Citizenship and the Districts | Part VIII |
| 10 | Welcome to the Realm | Closing |

Clips are generated from `CHARTER_VOICESCRIPT.md` (not written yet) using ElevenLabs. Delivered as `.ogg` files at `Media/Voice/voice_01.ogg` through `voice_10.ogg`.

### 12.2 Staged Playback (Onboarding Mode)

On a citizen's first login with the addon active, the onboarding sequence begins automatically:

1. Clip 1 plays immediately via the notification frame
2. Subsequent clips play at approximately 4-minute intervals while the player remains online
3. The sequence resumes on future logins if not completed — it does not restart from clip 1
4. Citizens who dismiss or stop clips are not forced to continue; they can resume from the on-demand library at any time
5. Once all 10 clips have been heard (or skipped), the onboarding flag is set and the automatic sequence does not replay

Clips wait until the player is out of combat. Interval constant: `MOTA.CONST.VOICE_CLIP_INTERVAL = 240` (seconds).

### 12.3 Onboarding state

```lua
-- MOTADB.onboarding["PlayerName"] = {
--     started     = 0,        -- Unix timestamp of first clip play
--     lastClip    = 0,        -- Index of last clip played (0 = none)
--     heard       = {},       -- [clipIndex] = true for each clip heard/skipped
--     complete    = false,    -- true when all 10 clips heard or sequence dismissed
-- }
```

Onboarding state is per-character and stored locally. It is not part of the synced citizen record; nobody else sees it.

### 12.4 Sound API and Playback Constraints

WoW's sound API does not support pause with position tracking. The addon uses stop/restart semantics only.

```lua
-- Play a clip:
local path = string.format(
    "Interface\\AddOns\\MinistryOfTheAllied\\Media\\Voice\\voice_%02d.ogg", index)
local _, handle = PlaySoundFile(path, "Master")
MOTA.voice.handle = handle
MOTA.voice.currentClip = index

-- Stop (resets to start):
if MOTA.voice.handle then
    StopSound(MOTA.voice.handle)
    MOTA.voice.handle = nil
end
```

**There is no pause.** The control set is stop/restart. UI must reflect this — see 12.5.

### 12.5 Notification Frame (VoicePlayer)

A small persistent notification frame slides in from the bottom-right corner when a clip begins playing (like WoW's achievement toast, styled to the player's active skin). It remains visible until dismissed. Its design goes on the canvas before it's built.

**Controls:**

| Button | Icon | Behaviour |
|---|---|---|
| Play | ▶ | Starts or restarts current clip |
| Stop | ■ | Stops playback, resets to start of clip |
| Restart | ↺ | Stops and immediately replays from start |
| Dismiss | ✕ | Closes frame, stops audio, marks clip as heard |

No pause button is shown. The ■ icon (not ⏸) makes clear that stopping resets position.

**Frame contents:**
- Clip number and title (e.g. "2 of 10 — The Crown")
- Progress bar (time-approximated, visual reference only — not seekable). The game can't report a clip's length, so each clip's length is written into the code.
- Control buttons in a row
- "Open Library" link — opens the Charter Library panel

The frame is `UI/VoicePlayer.lua`. It is non-blocking — the player can interact with the world normally while audio plays.

### 12.6 Charter Library (On-Demand)

A sub-panel accessible from the main addon window (and from the "Open Library" link in the notification frame) listing all 10 clips. Players can replay any clip at any time regardless of onboarding status.

- List of 10 clips with title and duration label
- ▶ / ↺ button per row (play if stopped, restart if playing)
- Heard indicator per clip (subtle checkmark or dimmed style)
- Currently playing clip highlighted

Part of `UI/VoicePlayer.lua`, or a separate `UI/CharterLibrary.lua` depending on complexity at build time.

### 12.7 Asset Specification

```
Media/
└── Voice/
    ├── voice_01.ogg    -- Preamble
    ├── voice_02.ogg    -- The Crown
    ├── voice_03.ogg    -- The Government
    ├── voice_04.ogg    -- The Parties
    ├── voice_05.ogg    -- Legislation
    ├── voice_06.ogg    -- No Confidence
    ├── voice_07.ogg    -- The Judiciary
    ├── voice_08.ogg    -- Punishment
    ├── voice_09.ogg    -- Citizenship & Districts
    └── voice_10.ogg    -- Welcome to the Realm
```

Format: `.ogg`, mono or stereo, 44.1kHz. Forever supports `.ogg` via `PlaySoundFile()`; only files that ship inside the addon's folder can be played.

---

## 13. File Structure

Target layout. Files marked *(built)* exist now; *(rename)* shows today's name.

```
MinistryOfTheAllied/
├── MinistryOfTheAllied.toc
├── Core.lua            (built) Namespace, events, chat output, saved data, one book per guild, permission detection
├── Roster.lua          (built) Guild roster: ranks, who is online, who is the Crown
├── Comm.lua            (built) AceComm send/receive, packing
├── Book.lua            (built) The book of records: numbering, adding, sending, who may write which type
├── Hello.lua           (built) Guild handshake and version check
├── Data.lua                    Constants (MOTA.CONST), state built from records, validators
├── Probe.lua           (built) /mota probe and /mota probe limits
├── Media.lua           (built) Texture piece positions (written by tools/textures/build.py)
├── Fonts.lua           (built) The canvas fonts
├── UI/
│   ├── Skin.lua                Token definitions and ApplySkin() — loaded first of the UI
│   ├── MainWindow.lua  (rename: Window.lua) Frame, tab rail, header, footer
│   ├── Minimap.lua     (built) Minimap seal
│   ├── Crests.lua      (built) Crest finder
│   ├── Herald.lua      (built) Herald pop-ups
│   ├── Settings.lua    (built) Settings panel
│   ├── ThroneRoom.lua          Tab 1
│   ├── BallotHall.lua          Tab 2
│   ├── StatuteBook.lua         Tab 3
│   ├── Court.lua               Court registry (Statute Book, Rulings)
│   ├── Parties.lua             Tab 4
│   ├── Treasury.lua            Tab 5
│   ├── Districts.lua           Tab 6
│   ├── Ring.lua                Tab 7
│   ├── WorldMap.lua            World map skins
│   └── VoicePlayer.lua         Notification frame + Charter Library
├── Commands.lua        (built) Slash commands — loaded last
├── Libs/
│   ├── LibStub/
│   ├── CallbackHandler-1.0/
│   └── AceComm-3.0/            (includes ChatThrottleLib)
└── Media/
    ├── chrome.tga, atlas.tga, extras.tga, shadow.tga, seal.tga, crest.tga  (built)
    ├── crest_crown.tga, crest_silverhand.tga, crest_exchange.tga, crest_neutral.tga
    ├── Fonts/          (built) Cinzel, Cinzel Decorative, EB Garamond + their OFL licences
    └── Voice/
        └── voice_01.ogg ... voice_10.ogg
```

---

## 14. .toc File

```
## Interface: 16001
## Title: |cffC9A24AMinistry of the Allied|r
## Notes: The political state of the Ministry of the Allied
## Author: The Crown
## Version: 1.0.0
## IconTexture: Interface\Icons\INV_Misc_Note_02
## SavedVariables: MOTADB
## AddonCompartmentFunc: MinistryOfTheAllied_OnAddonCompartmentClick

# Libraries
Libs\LibStub\LibStub.lua
Libs\CallbackHandler-1.0\CallbackHandler-1.0.lua
Libs\AceComm-3.0\AceComm-3.0.xml

# Core (load order matters: Core first)
Core.lua
Data.lua
Roster.lua
Comm.lua
Book.lua
Hello.lua
Probe.lua
Media.lua
Fonts.lua

# UI
UI\Skin.lua
UI\MainWindow.lua
UI\Minimap.lua
UI\Crests.lua
UI\Herald.lua
UI\Settings.lua
UI\ThroneRoom.lua
UI\BallotHall.lua
UI\StatuteBook.lua
UI\Court.lua
UI\Parties.lua
UI\Treasury.lua
UI\Districts.lua
UI\Ring.lua
UI\WorldMap.lua
UI\VoicePlayer.lua

# Commands last
Commands.lua
```

---

## 15. Design

- **Live design canvas:** https://claude.ai/artifact/V6ZmxpJtw85SrWT9S87acJ (private until shared from its Share menu). It has the style guide, the pages as a clickable prototype, the Extras board (settings, heralds) and the world map skins board. **It is the source of truth for the look.** `design/canvas-source/` is a copy, refreshed from the live canvas before each texture build. Style brief: `design/STYLE_BRIEF.md`.
- **Theme:** regal Stormwind/Alliance. Parchment, wax seals, royal blue and gold. Premium and ceremonial, not basic.
- **Textures:** `design/textures/` holds the parchment, leather, filigree, divider, wax seals and crests. `tools/textures/build.py` lays the window out with the canvas's own stylesheet, draws each piece in Microsoft Edge and packs the pieces into game textures (`Media/*.tga`), with their positions in `Media.lua`. The settings page and herald come from a second layout, `tools/textures/extras.html`. When the design changes, run the script again.
- **Sizes:** one large background (frame, title, parchment page) at 1.46× the canvas size; small pieces (tabs, labels, icons, buttons, seals) at 2×, so they stay sharp. The addon folder is about 19 MB, mostly textures.
- **Fixed-text labels are pictures, live text is game text.** Tab labels, page names and eyebrows are drawn from the canvas, since the game can't space letters like the canvas. Headings, notes and the status strip are game text. Spaced-out capitals in game text are drawn one letter per text piece (`MotA:Tracked`).
- **Shadow:** a soft picture stretched in nine pieces, so its corners stay round.
- **Fonts:** Cinzel, Cinzel Decorative and EB Garamond from Google Fonts ship inside the addon with their SIL Open Font License files. If the game can't load them, the addon uses the game's own font.
- Names, gold amounts, vote counts and laws on the boards are sample data.
- **To update on the boards:** the Treasury board still says the Treasurer was "Elected"; change it to appointed by the PM. Window skins (9.2) and the voice player (12.5) need drawing.

---

## 16. Build Roadmap and Status

### 16.1 Phases

| Phase | Scope |
|---|---|
| **v1.0** | Core framework, sync, window, heralds, settings, Throne Room, Ballot Hall (secret ballot by whisper), VoicePlayer |
| **v1.1** | Statute Book, Treasury Ledger |
| **v1.2** | Districts tab with map, Citizen Roll |
| **v1.3** | Parties tab, Court Registry |
| **v1.4** | The Ring, world map skins |
| **v2.0** | External persistence layer, async voting |

Each phase is built in small milestones that each load in the game and can be tested before the next starts.

### 16.2 Built so far

**Milestone 1 — the addon wakes up** *(built 2026-11-05)*
- Loads in Forever; the account-wide saved data survives `/reload` and logout.
- Guild handshake: on login each copy says hello with its version; everyone who hears it answers by whisper; anyone on an older version is told to update.
- The first records (`test.note`, anyone may write) sent live to the guild.
- Probe: `/mota probe` answers the client questions and saves them.
- Send queue: starts cautious (a burst of 5, then one a second) until the limits test measures Forever's real limits; waits during message lockdown.
- Checked with real Lua 5.1 in two pretend game clients: handshake, test records, relogging, a lost saved file, a newer version arriving, a message lockdown.
- **In game (Max, 2026-11-05, no guild yet):** it loads; interface 16001, project 18; `C_EncodingUtil` works; lockdown check exists and was off in the open world; send result codes exist; clocks agree. **Still to test on a character in a guild:** handshake, test records, `/reload` keeping the book, `/mota probe limits`.

**Milestone 2 — the window** *(built 2026-11-05)*
- `/mota` opens and closes it: blue leather frame, gold rim, filigree corners, the crest breaking out over the top-left corner, title with the page name, settings and close buttons. Draggable, reopens where it was, Escape closes it. Opens at 0.85 of canvas size, or smaller to fit; `/mota scale` changes it.
- Seven tabs with icons, hover look, and the gold active look with its shine. Each page has its eyebrow, heading, divider and a note of what it will hold.
- Live text: name and guild rank at the foot of the rail; status strip with sync status left and place and day right.
- Minimap seal: click to open, drag round the minimap; `/mota minimap` hides or shows it.
- Crest finder: `/mota crests`, `/mota crest <n>`, `/mota crest ours`.
- **In game (Max, 2026-11-06):** it works; textures sharp; addon fonts load; we keep our own crest.

**Milestone 3 — settings and herald pop-ups** *(built 2026-11-06, to test in game)*
- Settings panel (10.13) and heralds (10.2).
- `/mota herald` shows the board's three samples (polls open, Royal Assent, crossing the floor); `/mota herald 1|2|3` shows one. They show even with heralds off.
- A `/mota test` record from another member arrives as a herald.
- `/mota fanfare` lists the game's horn and trumpet sounds; `/mota fanfare <n>` plays and chooses one. Until Max picks, the first one the client has (the level-up fanfare where it exists).
- Checked in the pretend client: samples, the button opening its page, waiting out combat, switches, Modest and Royal, choosing a fanfare, the minimap right-click, a test record arriving as a herald.
- **Results:** *(to fill in after testing)*

### 16.3 Commands

`/mota` (open the window), `/mota sync`, `/mota who`, `/mota test <text>`, `/mota book`, `/mota probe`, `/mota probe limits`, `/mota debug`, `/mota scale [n]`, `/mota minimap`, `/mota crests`, `/mota crest <n|ours>`, `/mota settings`, `/mota herald [1|2|3]`, `/mota fanfare [n]`. `/ministry` works the same.

### 16.4 Next: bring the code in line with this spec

1. Rename the prefix to `MOTA`, the saved data to `MOTADB` (test saves reset; only Max has it installed), the TOC author and notes.
2. Recognise both Crown ranks, "The King" and "The Crown" (`CROWN_RANK_NAMES`).
3. Add AceComm-3.0 (with LibStub, CallbackHandler, ChatThrottleLib); move `Comm.lua` onto it and the record format onto `C_EncodingUtil`.
4. Add `Data.lua` with `MOTA.CONST`.
5. Rename `UI/Window.lua` to `UI/MainWindow.lua`.

After that, Milestone 4 is to agree with Max. Candidates: the secret ballot and Ballot Hall; window skins (needs the canvas drawn first); catch-up and the trust rules (needs the guild).

### 16.5 How to test

1. The folder link is in place (section 2).
2. At the character screen, open **AddOns** and check **Ministry of the Allied** is ticked. If it says "Out of date" after a Forever patch, tick **Load out of date AddOns** and update the TOC's Interface number.
3. `/reload`, then `/mota`: the window opens on the Throne Room. Click each tab; drag, close and reopen the window; try `/mota scale 0.7` and `/mota scale`.
4. `/mota herald`: three heralds in turn; "Read it" on the second opens the Statute Book. Start a fight and run `/mota herald 1`: it waits until the fight ends.
5. `/mota settings`: switch heralds off, try Modest. `/mota fanfare`, then `/mota fanfare 2` and so on.
6. With a second guild member: both run `/mota who`; one runs `/mota test Hear ye!` and the other sees it. `/reload`, then `/mota book`. `/mota probe limits` about a minute after login, then `/reload`.

---

## 17. Key constants

Defined in `Data.lua` (see `CODING_BRIEF.md` for the code):

| Constant | Value | Meaning |
|---|---|---|
| `BALLOT_WINDOW_SECONDS` | 7200 | 2-hour polls |
| `LAW_EXPIRY_SECONDS` | 7776000 | 90 days |
| `NO_CONFIDENCE_THRESHOLD` | 0.40 | 40% of active citizens |
| `ACTIVE_CITIZEN_DAYS` | 30 | Login within 30 days = active |
| `RETURN_WAIT_DAYS` | 10 | Returning citizens can't vote in a ballot opened within 10 days of return |
| `CROWN_RANK_NAMES` | "The King", "The Crown" | The two Crown ranks |
| `SNAP_ELECTION_MIN_DAYS` | 7 | Minimum campaign period |
| `SYNC_STALE_SECONDS` | 300 | Catch-up summary every 5 minutes |
| `SYNC_AMBER_SECONDS` | 1800 | Footer sync indicator turns amber after 30 minutes |
| `BROADCAST_MIN_INTERVAL` | 3 | Seconds between routine GUILD broadcasts |
| `VOICE_CLIP_COUNT` | 10 | Onboarding voice clips |
| `VOICE_CLIP_INTERVAL` | 240 | About 4 minutes between staged clips |

---

## 18. To test after launch

- **Addon message limits:** size and rate throttle, and whether Midnight-era rules block addon messages in instances or combat. `/mota probe limits` measures it; run `/mota probe` in a dungeon too.
- **Whispered ballots:** that an addon whisper reaches a King on the same realm reliably, and what happens when the King is offline (the send should fail cleanly so the ballot is held).
- **Auto promote/demote:** only a character whose rank has the permission can do it, so results may be applied by a Crown client, possibly with a button click.
- **Honour titles:** that the addon can still add text to friendly nameplates and the mouseover tooltip.
- **Chat tags:** that the addon can still change how guild chat lines display.
- **Duel results:** that "X has defeated Y in a duel" arrives as an ordinary system message.
- **Trade window warning** for embargoed citizens.
- **World map window:** that the skin stays on when the map is enlarged or shrunk, no errors opening the map in combat, and whether the "Player / Cursor" coordinates strip in the reference screenshot is Forever's or another addon's.
- **Game text-to-speech** still works for addons (a possible voice fallback for herald lines).

---

## 19. Open Items, Parked Ideas and Decision Log

### 19.1 Open items

- **The real map:** district shapes need tracing against the live Stormwind map after launch.
- **Herald voice lines:** a town crier calling "Hear ye! The polls are open!" with heralds. Fixed lines only (lines with names or numbers stay as text). Same voice rules as section 12. The game's own text-to-speech is a possible flat-voiced fallback.
- **`CHARTER_VOICESCRIPT.md`** needs writing before the clips can be generated.
- **Notice board:** citizens can have a notice pinned on the Throne Room, by request; the Crown can take it down. Agreed 2026-11-03, not in the first build.

### 19.2 Old-plan ideas set aside for the brief's simpler version

Kept here so they can be brought back later. Each was agreed in the old plan and replaced on 2026-11-06 when the brief became the source of truth.

- **Independent count check:** every member's addon counted ballots on the guild channel ("Count agreed by 31 of 31"). Replaced by the secret ballot (8.2).
- **Self-running elections:** the addon followed the Charter timeline without anyone driving it, called run-offs automatically, with nominations and a **candidacy check** (good standing, two weeks as a citizen, later level 60, raids led, treasury contributions; stage set by the Crown).
- **No-confidence petition signed in the addon,** with progress towards 40% and the days left.
- **Automatic treasury ledger** read from the guild bank money log by every member's addon, with entries confirmed by two readers or by the balance change, lined up by their order in the log, a balance check that flags missing entries, and the Minister of the Treasury adding reasons.
- **Party Chamber and party privacy:** a private side of each party (plans, notes, whip notices) sent only by whisper to that party's verified roster; joining through the party's designated officer, who records the 5g automatically from trade or mail; leaders elected inside the Chamber; roster changes accepted only from the officer or leader; crossing the floor announced by herald, with a 14-day cooling-off before the other party can accept.
- **The Justices' court flow:** accusation filed privately to the Justices, sealed summons with a defence statement, Justices seal the ruling, punishments applied automatically.
- **Office-based writing:** PM, ministers, Justices and Representatives writing their own records (appointments, renewals, assignments, transfers, Ring results) rather than the Crown doing all writes.
- **Several Ring level brackets** at once (20–29, 30–39 … 60), each with its own champion; entry fees counted from the guild bank log rather than at sign-up.
- **Universal crest:** the lion crest on every window regardless of party.
- **World map skin following membership instantly** rather than on `/reload`.

### 19.3 Decision log

- **2026-11-03** Sync over hidden addon messages on the guild channel (no custom chat channel: anyone on the realm could join it and post fake data). District and other details live in the addon's synced data, not guild notes. District glow on the Stormwind map. Regal Stormwind theme. Direct voting. Treasurer appointed by the PM. No waiting period for brand-new members. Debates on Discord. World map skins.
- **2026-11-04** Both Kings' Crown rank (now two ranks, see 2026-11-06). Treasury ledger fully public. Crown map skin: the Exchange's design in royal purple with a regal crest.
- **2026-11-05** Building started with Core/Sync. Code lives in `addon/MinistryOfTheAllied/`, linked into Forever by a junction. No libraries (revised 2026-11-06). Live canvas is the source of truth for the look; the window is drawn from it by `tools/textures/build.py`. Canvas fonts ship inside the addon. Crown crest drawn.
- **2026-11-06** Lion crest replaces the Stormwind crest; we keep our own. Milestone 3 settled heralds and settings (10.2, 10.13).
- **2026-11-06** `CODING_BRIEF.md` and `ADDON_SPEC.md` became the single source of truth; `ADDON_PLAN.md` and the Core/Sync plan were merged in and deleted. Max's changes to the brief:
  - Keep the shared book (section 7) so updates happen with the Kings offline.
  - AceComm-3.0 is the only library.
  - Secret ballot, delivered by hidden whisper to each online King (8.2).
  - Two Crown ranks, "The King" and "The Crown".
  - Names follow the brief: `MOTA`, `MOTADB`.
  - Polls open 2 hours; the Charter is amended to match.
  - The window is skinned per party, reusing the four world map skin designs.
  - Everything else follows the brief (19.2 lists what that set aside).

---

*Ministry of the Allied Addon Spec v1.1 — 6 November 2026*
