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

*The code was renamed to these on 2026-11-06 (section 16.4). Test saves under the old name `MinistryOfTheAlliedDB` are not carried over. The version is still 0.1.0.*

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
| **Crown** | The two Kings (ranks "The King" and "The Crown") | Read all, write all, open/close ballot sessions, receive and count ballots, grant Royal Assent, register laws, decide court appeals, sign off exile, manage citizen registry and party membership |
| **Citizen** | All other guild members | Read all, cast votes during open sessions |

- **The Crown (both "The King" and "The Crown" ranks) holds every permission the government does.**
- The Minister of War is whoever holds that guild rank, and runs The Ring (section 11).
- No citizen can write to canonical state. Every record says who wrote it, and each addon checks that the writer was allowed to write that type of record at that time (section 7.4). Records from anyone else are ignored.
- Office holders (PM, Cabinet, Justices, Representatives) see their duties (section 10.9), but in v1.x the Crown makes most writes. The exceptions:
  - **Treasury (10.7):** every member's addon may write guild bank readings; the Minister of the Treasury may add reasons to ledger entries.
  - **Court (10.10):** any citizen may file an accusation; the accused may write a statement and appeal; the Justices seal rulings.
  - **Parties (10.16):** party members may write Chamber business and vote for their leader; a citizen may leave their own party.

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
        --     myBallots = {}, -- [character][ballot] = this character's own ballot: the choice
        --                     --   only until a King's receipt arrives, then just "delivered" (8.2)
        --     state    = {},  -- cached state (6.3), rebuilt from records
        -- }
    },
    ballotTally = {},       -- Crown clients only, never sent to the guild (8.2):
                            -- [ballot] = { counts = {per candidate}, counted = {[name] = token}, refused }
                            -- counts and names are never linked; the names go once declared
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
        balance = { gold = 0, silver = 0, copper = 0 },  -- last balance read from the guild bank
        balanceCheck = true,    -- false when money in minus out doesn't match the balance change (10.7)
        ledger = {
            -- [id] = {
            --     date        = 0,    -- Unix timestamp (approximate: the log only gives "3 hours ago")
            --     member      = "",   -- who moved the money, from the money log
            --     description = "",   -- the reason, added by the Minister of the Treasury
            --     direction   = "IN", -- "IN" | "OUT"
            --     gold        = 0,
            --     silver      = 0,
            --     copper      = 0,
            --     recordedBy  = "",   -- the members whose addons read it from the log
            --     status      = "AWAITING", -- "AWAITING" | "CONFIRMED"
            -- }
        },
    },

    court = {
        -- [id] = {
        --     date      = 0,
        --     accuser   = "",       -- shown only to the Justices and the accused
        --     accused   = "",
        --     charge    = "",       -- which law was broken and what happened
        --     statement = "",       -- the accused's defence
        --     verdict   = "GUILTY", -- "GUILTY" | "NOT_GUILTY"
        --     punishment= "",       -- Free text
        --     sanction  = nil,      -- "CENSURE" | "FINE" | "EMBARGO" | "SUSPENSION" | "EXILE" (10.10)
        --     justices  = {},       -- Array of player names
        --     ruledAt   = 0,        -- the 48-hour appeal window runs from here
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

    parties = {
        -- ["SILVERHAND"] = {
        --     leader      = "",   -- elected in the Party Chamber (10.16)
        --     donations   = 0,    -- published total, in copper
        -- }
        -- Chamber contents are never in shared state: they arrive by whisper
        -- to the party's own members only.
    },

    leftParty = {
        -- ["PlayerName"] = { party = "SILVERHAND", at = 0 },  -- 14-day cooling-off (10.16)
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
- *Built so far:* only records sent by their own author are taken; passed-on records wait for catch-up. One exception since Milestone 4: a Crown member's add-on may pass on the open ballot's records (`BO`, 7.5), and those are taken because the Crown is trusted with the count anyway.

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
| Ballot (`BV`) | WHISPER, to each online King | The sealed vote: ballot, choice, a one-off token (so a resent ballot isn't taken for a second one) and the voter's `ballot.sealed` record number if it was held (8.2) |
| Ballot receipt (`BR`) | WHISPER, King back to the voter | `ok`, `dup` (already counted), `closed` (too late) or `unknown` (that King doesn't know the ballot yet) |
| Tally hand-over (`BT`) | WHISPER, King to King | The running count and who was counted (never how), after counting and whenever the two Kings meet; used both to hand the count over and to compare the two counts |
| Open ballot (`BO`) | WHISPER, King to a member who said hello | The open ballot's records (open, close, the latest result under a week old, that member's own `voted` record; for the other King, all `voted` and `sealed` records). Accepted only from a Crown member, and only the Crown's own ballot records plus voters' `sealed` records |
| Sealed ballots heard of (`BS`) | WHISPER, member to a King logging in | Who sealed a ballot while the Kings were away, and when. Only feeds the Crown view's count of ballots still to come |
| Chamber business | WHISPER, to each member on that party's roster | Party Chamber notes, whip notices and leadership votes (10.16) |
| Probe | GUILD | Test traffic for `/mota probe limits` (only the sender reads it) |

The ballot's records (built in Milestone 4): `ballot.open` (Crown: name, kind, candidates, closing time), `ballot.sealed` (the voter: who sealed a held ballot and when, never how), `ballot.voted` (Crown: who voted, never how), `ballot.close` (Crown: polls closed early) and `ballot.result` (Crown: the declared result, complete in itself). Close and result are separate records because held ballots sealed before the close still count until the declaration (8.3).

The brief's other message types are now record types: `BALLOT_OPEN` → `ballot.open`, `BALLOT_CLOSE` → `ballot.close` and `ballot.result`, `CITIZEN_UPDATE` → `citizen.update`, `STATE_DELTA` → whichever record changed. `PETITION_SIGN` is dropped: no-confidence goes by in-game mail (8.6).

- **Format:** a record is packed with `C_EncodingUtil.SerializeCBOR` and turned into channel-safe text with `EncodeBase64`; big batches are compressed with `CompressString` first. (Whether Forever accepts raw binary in addon messages, which would save the Base64 step, is untested.) *(Built 2026-11-06 as protocol 2: the envelope is short text fields joined by byte 31 — protocol, kind, then fields — and a record is one field of packed Base64.)*
- **Versions:** every message carries a protocol version. Hello and hello reply always keep the version first, so an old copy can tell it's out of date. A copy that hears a newer protocol stops writing records and tells the player to update, but keeps reading.
- **Whispers** are only accepted from guild members. A copy ignores its own guild messages echoed back.
- **Throttling:** never raw `C_ChatInfo.SendAddonMessage`; AceComm splits and paces. Minimum `BROADCAST_MIN_INTERVAL` (3 seconds) between routine GUILD broadcasts; records that trigger a herald go ahead of catch-up.
- **Lockdown:** if the game locks addon messages (for example in a boss fight), the queue waits.

### 7.6 Time

Every record uses the realm's server time, so a poll that closes "at 8pm" closes at the same moment for everyone. Times are displayed in each member's local time.

### 7.7 Privacy of personal records

Records meant for one person (letters, a court summons, an accusation) still travel on the guild channel, so they reach the person after being offline; the addon only **shows** them to the people they're for. Someone running their own script could read these; Max judged that unlikely. Two exceptions never touch the guild channel: ballots (8.2) and Party Chamber business (10.16), which go only by whisper.

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
4. **If no King is online,** the voter's addon holds the sealed ballot (kept through `/reload` and logout) and writes a `ballot.sealed` record to the guild: who sealed a ballot and when, never how. It sends the ballot as soon as the voter and a King are online together. The Ballot Hall shows "Sealed, waiting for the Crown", and the Crown's view shows how many sealed ballots are still on their way. A held ballot still counts after the polls close if the King's addon had its `ballot.sealed` record before the close and the result hasn't been declared (8.3).
5. Each King's addon validates (eligible, not already voted, not a linked alt), adds one to its local `MOTADB.ballotTally`, and **throws the voter's name away** — only "this person has voted" is kept.
6. The King's addon writes a `ballot.voted` record (who voted, not what they chose) to the guild, and whispers a receipt back.
7. Citizen's ballot UI updates to "Your ballot is sealed"

- **Two Kings, two counts.** Both Kings receive every ballot sent while they're online, so their counts can be compared before the result is declared. If only one King was online, their addon hands the running count to the other King by whisper when they log in.
- **The last King's warning:** when the only King online starts to log out while polls are open, their addon warns that ballots will wait with their voters, with **Stay online** (cancels the logout) and **Log out anyway**. *(Decided 2026-11-06; to test, section 18.)*
- **Later (v2.0): encrypted ballots** that any member's addon can carry, so a ballot reaches the Kings even if the voter is never online at the same time as one (19.1).
- **Vote secrecy:** raw vote choices are never sent to the GUILD channel or saved with a name. The `voted` list confirms participation, never preference.
- **Honest limits:** the guild trusts the Kings' count, and the Kings' addons briefly see each ballot. Someone writing their own script to read votes is judged highly unlikely.

### 8.3 Closing a Session (Crown)

1. After the 2-hour window the polls close by themselves; the Crown can close them early with **Close Polls**, which writes a `ballot.close` record. No new ballots are taken, but held ballots sealed before the close (8.2, step 4) still count until the result is declared. The Crown's view says how many are still to come; the Crown chooses to wait for them or declare without them.
2. **Declare the result** writes a `ballot.result` record from that King's own count: name, kind, candidates, votes, total, active citizens, and the winner (or the tied candidates). The first result written stands.
3. All citizens receive it, and a herald announces it. The King's add-on then drops the names of who it counted.
4. Result is written to `elections` history and the Chronicle *(the Results view's record of past elections reads the `ballot.result` records; the Chronicle comes later)*
5. If General Election: Crown is prompted to update `government` state
6. Ballot resets to `active = false`

**Ties:** a run-off between the tied candidates only, within 48 hours (Charter 2.1). **Set up the run-off** writes the result with the tie, and fills the Open Polls form with the tied candidates and the kind Run-off; the Crown opens it from there.

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

*Settled 2026-11-06 (window skins design):*
- **Only on your own screen.** Each player sees their own skin; nothing about it is sent to anyone.
- **Only the Crown can switch skins** *(decided 2026-11-06)*. Everyone else wears the skin of their guild rank, as the rule above says, and has no way to change it. For anyone outside the two Crown ranks, the settings row and `/mota skin` are not shown, and a saved Ministry choice or a skin being tried is ignored.
- **Settings choice (Crown ranks only):** "Window skin: Party / Ministry" on the settings page (10.13); the row is hidden for everyone else. Party (the default) uses the rule above, which for the Crown is the Crown skin. Ministry shows the blue and gold instead. This is separate from the world map's own setting (9.6), which also has Plain.
- **When it changes:** a change of party or Crown rank shows at the next login or `/reload`, as above. Changing the setting re-skins the window at once, since a skin is only a swap of textures and colours.
- **Testing (Crown ranks only):** `/mota skin crown|silverhand|exchange|ministry` shows that skin on your own screen until `/reload`; `/mota skin` alone goes back to your own. So all four can be checked from one Crown character. The command is left out of `/mota help` for everyone else, and if someone else types it anyway they are told that skins follow guild rank and nothing changes.

### 9.2 The four skins

| Skin key | Design | Colours | Corner emblem |
|---|---|---|---|
| `CROWN` | The Azeroth Exchange's design with royal purple in place of crimson, taken from a royal robe Max chose. Mostly the deep purple; the lighter purple only as small highlights (centre of the title band, top edge of each step and button). Gold filigree on the two bottom corners, inside the frame | Deep royal purple and gold | The Crown crest |
| `SILVERHAND` | Silver metalwork and argent wax | Silver with the party blue `#1F4290` (the silver sets it apart from the Ministry blue) | The Silverhand seal (blue hand) |
| `AZEROTH_EXCHANGE` | Deep crimson and gold | `#9E1B22` and gold | The Exchange seal (coin-scale) |
| `UNREGISTERED` | The Ministry default: royal blue and gold, for citizens not in a party (membership is voluntary, Charter 3.2) | Royal blue and gold | The lion crest |

**The Crown crest** (`design/textures/crest-crown.png`): a deep purple shield with a gold royal crown, crossed gold sceptres, a purple mantle and gold leaves, emeralds on the crown's band and a cross-shaped emerald set into its cross. A transparent cut-out made in Higgsfield (GPT Image 2.6).

**The lion crest** (`design/textures/alliance-crest.png`): the Crown crest's shape with a gold lion head in place of the crown and royal blue in place of the purple. Made in Higgsfield, so it isn't Blizzard's art. The old Stormwind picture stays in `design/reference/alliance-crest.png`. The crest finder (`/mota crests`) stays in, in case the game's own crest is ever wanted.

**The window in each skin** *(designed 2026-11-06 on the "Window skins" board of the live canvas; mirror `design/canvas-source/WindowSkins.dc.html`)*. The same window, with three kinds of part:

- **Changes with every skin:** the leather (the Crown's adds a soft purple glow behind the title); the resting and hover tabs, pressed in the skin's wax; the settings knob, and the close knob in the skin's wax or coin; the corner emblem; the ink of the lit tab's label; the pale ink (page name under the title, the name at the foot of the rail, the status strip).
  - Ministry: blue leather, oxblood wax tabs, red wax close knob, lion crest (as built in Milestone 2).
  - Silverhand: party-blue leather, steel-blue wax tabs, argent wax close knob, the blue hand seal.
  - Exchange: crimson leather, bright crimson wax tabs, gold coin close knob, the coin-scale seal.
  - Crown: royal purple leather, plum wax tabs with a lighter purple top edge, gold coin close knob, the Crown crest.
  - The two party seals are round, so they sit a little smaller than the shield crests (132 wide against 152).
- **Changes with the metal:** the outer rim, double rule and stitching, the three filigree corners, the title, the lit tab and its tooled border, and the metal rim round the parchment page. **Gold** for the Crown, the Exchange and the Ministry; **silver** for Silverhand. Two sets, not four.
- **Stays the same in every skin:** the parchment page and everything on it (headings, plates, blue buttons, ribbons, seals, the Ballot Hall's pieces); the tab icons and labels; the window's shape, size and shadow; the heralds, the settings page and the minimap seal. Keeping the page the same is what stops every page's pictures being needed four times.

### 9.3 Colour Tokens

Each skin defines tokens for the parts drawn as game text or coloured in the game (labels and icons are drawn once in white and coloured with `SetVertexColor`). The leather, wax and metal are pictures (9.7); their full gradients are in the Window skins board's styles, which the texture build draws from. The brief's placeholder tokens (`PRIMARY_BG`, `BORDER`, `ACCENT`, `HEADER_TEXT`, `BUTTON_BG`, `BUTTON_TEXT`) are replaced by these:

| Token | Used for | CROWN | SILVERHAND | AZEROTH_EXCHANGE | UNREGISTERED |
|---|---|---|---|---|---|
| `METAL` | which metal set (9.7) | gold | silver | gold | gold |
| `TAB_INK` | resting tab label and icon | `#F3D98A` | `#DCE3EE` | `#F3D98A` | `#E5CF92` |
| `TAB_INK_HOVER` | the same, under the mouse | `#FBEFC4` | `#FFFFFF` | `#FBEFC4` | `#FBEFC4` |
| `TAB_SMALL` | resting tab's second line | `#E8C6DC` | `#AEB9CC` | `#F0C9BC` | `#EBC3B2` |
| `TAB_INK_ON` | lit tab label and icon | `#3E0A2F` | `#1F4290` | `#5A0E13` | `#0E1F45` |
| `TAB_SMALL_ON` | lit tab's second line | `#3A2A0A` | `#2B3445` | `#3A2A0A` | `#3A2A0A` |
| `SUBTITLE` | the page's name under the title | `#EBCBDF` | `#D5DEF0` | `#F2CDBE` | `#B9C9EE` |
| `PALE_INK` | rail foot second line, status strip | `#EBCBDF` | `#C6D2EA` | `#F2CDBE` | `#AFC0E6` |
| `NAME_INK` | name at the foot of the rail | `#FBEFC4` | `#FFFFFF` | `#FBEFC4` | `#FBEFC4` |

The sync pip, the line above the rail foot, the portrait ring and the rules beside the page's name are pictures that come with the metal (9.7), so they need no token.

Reference mid tones (for swatches, not used in code): leather `#3D0B2D` / `#1F4290` / `#8E1A21` / `#1E3B7C`; tab wax `#5A1645` / `#2E3E62` / `#7A151C` / `#6E1712`; metal `#C9A24A` / `#AEB8C6`.

### 9.4 Skin Application

Skins are applied via a central `MOTA.ApplySkin(skin)` function called during frame initialisation. All UI files reference tokens by name, never hardcoded hex values. Because the window is drawn from textures (section 15), each skin also names its own texture set; a skin swap is still one function call.

```lua
-- Skin tokens are stored in MOTA.skin after ApplySkin() is called
-- Hex values are pre-converted to RGB float tables on load:
-- MOTA.skin.PRIMARY_BG = { r = 0.10, g = 0.04, b = 0.18 }

-- Usage in any UI file:
local c = MOTA.skin.TAB_INK
label:SetVertexColor(c.r, c.g, c.b, 1)
```

### 9.5 Skin.lua

A dedicated `UI/Skin.lua` file holds all token definitions, the texture set per skin and the `ApplySkin()` function. It is loaded before all other UI files in the `.toc`.

```lua
-- Skin.lua (excerpt)
local SKINS = {
    CROWN = {
        METAL        = "gold",            -- picks frame_gold.tga (9.7)
        TEXTURE      = "skin_crown",      -- leather, wax tabs, knobs, emblem (9.7)
        TAB_INK      = { r=0.95, g=0.85, b=0.54 },
        TAB_INK_ON   = { r=0.24, g=0.04, b=0.18 },
        PALE_INK     = { r=0.92, g=0.80, b=0.87 },
        -- ... the rest of the 9.3 tokens
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

### 9.7 Building the window skins' textures *(settled 2026-11-06, to build)*

Today the whole window background (rim, leather, corners, title and parchment page) is one picture, `chrome.tga` (2048 × 1024, 8 MB), plus `crest.tga` (1 MB). Copying both per skin would add about 27 MB for the three new skins. Instead `tools/textures/build.py` splits the window into layers, so each part is drawn only as often as it really differs:

| Texture | How many | Size | Holds |
|---|---|---|---|
| `parch.tga` | 1, shared | 1024 × 1024, 4 MB | The parchment page alone, at 1.3× (it's soft vellum, so slightly below the window's 1.46× is fine) |
| `frame_gold.tga`, `frame_silver.tga` | 1 per metal | 1024 × 512, 2 MB each | The rim, double rule, stitching, filigree corners and the page's metal rim, cut into corners and edge strips (like the shadow's nine pieces), drawn with the leather hidden; the title; the lit tab and its tooled border |
| `skin_crown.tga`, `skin_silverhand.tga`, `skin_exchange.tga`, `skin_ministry.tga` | 1 per skin | 1024 × 512, 2 MB each | The leather drawn small (0.4×, 400 × 272) and stretched, since it's a soft gradient; the resting and hover tab; the two knobs; the corner emblem at 1.6× (it shows about 130 px wide) |
| `grain.tga` | 1, shared | 256 × 256, 0.25 MB | The leather grain, tiled over the stretched leather so it stays crisp |

- **What each skin adds:** 2 MB. The silver metal adds 2 MB once, for Silverhand.
- **In total (as built):** the textures went from 29.5 MB to **34.75 MB, about 5.25 MB more** for all four skins. That is less than the 7 MB planned, because the tabs, knobs and crest moving out also halved `atlas.tga` (4 MB to 2 MB). The whole add-on folder, with fonts and voice clips, is about 44 MB.
- **Memory:** the game loads a texture only when it's shown, so a player's memory holds just their own skin; the others only cost download size.
- **How the build gets the skins:** `layout.html` takes the skin's class (`ws-sh`, `ws-ex`, `ws-cr`, or none for the Ministry) and its emblem; the per-skin styles come from the Window skins board's `<helmet>` styles, read the same way as the Extras and Ballot Hall boards. The script draws the per-skin pieces once per skin, the metal pieces once with a gold skin and once with Silverhand, and the shared pieces once. `Media.lua` gains a `skins` table: per skin, its texture, its metal and where each piece sits.
- **Coloured in the game, not drawn per skin:** tab labels and icons are already drawn in white; the page names under the title change from blue-grey pictures to white ones, so the 9.3 tokens can colour all of them.
- **Could go smaller later:** if Forever loads `.blp` files for add-ons, the same textures compressed would be about a quarter of the size. One test before relying on it; not part of this milestone.

---

## 10. UI Structure and Features

One window with **seven tabs** matching the canvas. Tab availability is the same for Crown and Citizen — the difference is the presence of write controls within each tab. **One page per subject:** related screens are sub-views that swap inside the page (sub-tabs, a toggle or a pop-out), never separate windows. During an election, a phase banner runs across the top of every page.

| Tab | What it holds | Crown extras |
|---|---|---|
| **Throne Room** (home) | Who holds power (Crown, PM and Cabinet, Leader of the Opposition); countdown to the next election; any open ballot with a button to vote; your district and party; your duties (10.9) and letters (10.12); a feed of recent decrees opening into the Chronicle (10.3) | Edit government state, trigger dissolution |
| **Ballot Hall** | **Ballot** (default while polls are open): the parchment ballot paper, sealed with the wax-seal "Seal My Ballot" button. **Results** (default otherwise): the Crown's proclamation of the last result and past elections. The no-confidence status and cooling period (8.6) | Open/close elections, see live tally, record result, record no-confidence outcome |
| **Statute Book** | **In force**, each law with its expiry countdown; **Awaiting Royal Assent / up for renewal / Council consultation** (10.8); **Rulings** of the High Judiciary (10.10); **Treaties** (10.14) | Add law, grant Royal Assent, expire law early, decide appeals (Justices seal rulings) |
| **The Parties** | Two fixed parties — The Silverhand and The Azeroth Exchange. **Public face:** banner, ideology pillars, leader, members, manifesto, donation total and join button. **Party Chamber:** the private side, only for that party's members (10.16) | Edit party records, record membership |
| **Treasury** | The ledger in an old accounts-book style: the Minister of the Treasury, the balance, gold in and out, taxes. Filled in automatically from the guild bank's money log (10.7). Fully public: every line shows the member's name, withdrawals included | None: the ledger fills itself. The Minister of the Treasury adds reasons |
| **Districts** | **Map:** the Stormwind map with your district glowing in its colour and a pin on your council meeting spot. **Regional Council:** the five Representatives and their districts. **Citizen Roll:** every citizen with district, party and office. **Assignments & transfers** (10.11) | Edit citizen district/party assignments, Citizen Roll |
| **The Ring** | Sign-up, Bracket, Champions (section 11) | Create tournament, record bout results, manage sign-ups |

**Ballot Hall scope:** Elections only (General, Snap, run-off, district). No law votes. No-confidence is tracked manually by the Crown via in-game mail.

**The Parties scope:** each party page has a public face and a private Party Chamber (10.16). Joining follows the brief: the join button sends the request, and the Crown records membership in the citizen registry once the 5g has been paid to the party's designated officer (Charter 3.2). At the close of each campaign period the Parties page shows each party's published donation total.

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

### 10.7 Treasury: the automatic ledger

*Decided 2026-11-06: the old plan's automatic ledger, in place of the brief's hand-typed one.* The game keeps a money log of every guild bank deposit, withdrawal and repair.

- **Everyone's addon reads the log.** Whenever any member opens the guild bank, their addon reads the money log and shares any entries the guild doesn't have yet.
- **Entries are confirmed, not just trusted.** An entry counts as confirmed once two different members' addons have reported it, or once it matches the change in the bank's balance. Until then it shows as "awaiting confirmation". This stops one member's addon inventing entries.
- **No double counting.** The log only gives rough times ("3 hours ago"), so two readings of the same entry won't match exactly. Readings are lined up by their order in the log, so each deposit is counted once.
- **Balance check.** Every reader also reports the bank's gold. Money in minus money out must equal the change in the balance. If it doesn't, an entry is missing and the Treasury page says so.
- **Missed entries.** The log is short, so entries drop off if nobody opens the bank during a busy spell. More readers make this rarer, and the balance check flags any gap.
- **Rank permissions.** Some ranks may not be able to see the money log at all, so they can't help read it (to test, section 18).
- **The Minister of the Treasury adds the reasons.** The log shows who moved how much, never why. Only the Minister can add a note such as "raid repairs".
- The Minister of the Treasury is appointed by the PM (Charter 2.2), not elected.
- **Fully public:** every line shows the member's name, withdrawals included. *(Decided 2026-11-04.)*

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

### 10.10 The Court

*Decided 2026-11-06: the old plan's court, run inside the addon (agreed with Max 2026-11-04), in place of the brief's Crown-recorded registry.* It follows Charter 6 and 7. `UI/Court.lua` builds it; rulings show in the Statute Book's Rulings view.

1. **Accusation.** Any citizen files an accusation privately to the three Justices: who, which law was broken, and what happened. Only the Justices and the accused see it.
2. **Summons.** The accused gets a sealed letter of summons (10.12) and can write a statement in their defence.
3. **Deliberation.** The case appears on the Justices' duties panel (10.9). They discuss it and seal a ruling, choosing a sanction from the punishment ladder below.
4. **Ruling.** The ruling is published in the Statute Book (Rulings) and written into the Chronicle. The punishment is applied as far as the addon can.
5. **Appeal.** The accused has 48 hours to appeal to the Crown (Charter 7.2). The appeal appears on the Crown's duties panel, and the Crown's decision is final.

- Justices are three, appointed by the Crown, and can't hold any other office (Charter 6.1); the addon refuses an appointment that breaks this.
- **Punishment ladder (Charter 7.1)** and what the addon does:
  - **Public censure:** written into the Chronicle and Rulings permanently.
  - **Treasury fine:** on the citizen card as unpaid until the payment shows up in the guild bank ledger (10.7).
  - **Trade embargo:** on the citizen card and tooltip, with a warning if anyone opens a trade window with that citizen. Guild bank access is removed by an officer through guild ranks.
  - **Suspension from office:** the addon removes the office straight away.
  - **Exile:** needs the Crown's sign-off; the addon records it, and an officer removes the character from the guild.

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

### 10.16 Party privacy and the Party Chamber

*Decided 2026-11-06: joining follows the brief; everything else follows the old plan (agreed with Max 2026-11-04, matched to Charter 3.2).* The goal is that neither party can see the other's private chamber, and joining a party to spy and quickly switching back isn't possible.

- **Party membership is public, party business is private.** Who belongs to which party is visible to all. The Party Chamber is not.
- **Joining:** the citizen clicks join; the Crown records them as a member once the 5g is paid (the brief's way).
- **The Party Chamber** holds the party's plans, notes and whip notices. Only that party's members can see it.
- **Chamber data never goes on the guild channel.** It's sent only by private addon whisper to characters on that party's roster, so members of the other party never receive it at all.
- **The party leader is elected by its members,** in a vote inside the Party Chamber, so only that party's members see it. The winner is the party's candidate for PM (Charter 3.2) and is registered with the Crown.
- **Crossing the floor is slow and public.** Leaving a party is announced to the whole guild by herald, and access to the old chamber ends at once. There's then a **14-day** cooling-off period before the other party can accept that person; the Crown's addon refuses to record the new membership until it's over. A citizen can leave their own party themselves, or the Crown records it.
- **Roster changes** are only accepted from the Crown. WoW tells the receiver the real sender of every addon message, so every client can check who issued each change.
- **Honest limits.** A real defector keeps whatever they already read, which is a spy, and good roleplay. Someone skilled enough to rewrite the addon could still cause trouble, so this is strong guild-level security, not bank-level.

---

## 11. The Ring (Gladiator System)

The Ring is the guild's formal PvP tournament system: a monthly 1v1 duelling tournament, for fun and for raising gold. It is managed by the Crown or the delegated Minister of War, with entry fees, a bracket structure, and a Hall of Champions. Entry fees flow into the guild ledger.

*First build 2026-11-06, to test in game: `Ring.lua`, `UI/Ring.lua`. One bracket, at most 8 entrants (first come, first served), byes when fewer. For now the Crown ticks entrants paid by hand (the ledger is not built),  without catch-up (7.3) a member offline when a Ring record is sent does not get it.*

**Who decides (2026-11-06):** whoever holds the `Minister of War` guild rank, and the Crown, can open a tournament, set its entry fee, bracket and sign-up days, make the draw, record results and mark entries paid. Until someone holds the rank, the form shows greyed out for everyone, including the Crown. Once open, the terms can't be changed.

### 11.1 Tournament Structure

- **Season name** — set by Crown (e.g. "The November Ring")
- **Level bracket** — Crown sets the bracket on creation (e.g. "Open" or a level range) to prevent mismatches
- **Format** — single-elimination: Quarter-finals → Semi-finals → The Final
- **Entry fee** — set per tournament; paid into the guild bank, where the automatic ledger records it as income (11.5)
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
- See who has paid: a participant is marked paid once their entry fee deposit appears in the ledger (11.5)

**Duel results:** the game prints "X has defeated Y in a duel" to everyone nearby. The organiser's addon reads it and moves the winner on; the organiser can also click the winner by hand.

### 11.5 Treasury Integration

Citizens pay the entry fee into the guild bank. The automatic ledger (10.7) picks up the deposit from the money log, so the fee is never typed in or logged at sign-up (that would count it twice). When a deposit from a signed-up citizen matches the entry fee during the sign-up window, the addon marks them paid (`participants[name].paid = true`) and gives the ledger entry its reason automatically:

```lua
description = "Ring entry fee — " .. playerName .. " (" .. ring.season .. ")"
```

Prize pool = total entry fees collected. Guild cut is deducted and retained in Treasury. Remainder paid to champion by the Minister of the Treasury in-game, out of the guild bank, so the ledger records the payout too. The champion also gets a Chronicle entry.

---

## 12. Voice Onboarding System

Ten pre-generated ElevenLabs clips narrate the Royal Charter, 12.5 minutes in all, from `CHARTER_VOICESCRIPT.md`. *Built 2026-11-06, to test in game: `Voice.lua`, `UI/Constitution.lua`, `Charter.lua`.*

**Voice rules:** the voice must be an original AI voice, not a copy of a Blizzard character or a real actor, and the voice tool's licence must allow shipping the files inside the addon.

### 12.1 Clips

`Media/Voice/voice_01.ogg` to `voice_10.ogg`: Introduction, The Crown, The Government, The Parties, Legislation, The Vote of No Confidence, The High Judiciary, Punitive Measures, Citizenship and the Districts, Welcome to the Realm. Titles and lengths are in `MOTA.CONST.VOICE_CLIPS` (the game can't report a sound's length). `tools/voice/build.py audio <folder>` converts the narrator's MP3s.

### 12.2 Staged playback

1. A few seconds after a guild member's first login, the introduction plays.
2. Each later clip plays `VOICE_CLIP_GAP` (150 seconds) after the previous one ended or was stopped. Clips wait until the player is out of combat, and until any clip they replayed has finished.
3. The sequence resumes on later logins, after one gap. A clip cut off by logging out plays again from its start.
4. Once clip 10 has ended or been stopped, the sequence is finished. `/mota voice off` switches it off for the account, except during the introduction.

### 12.3 Onboarding state

`MOTADB.onboarding[characterGUID] = { started, nextClip, heard = { [clip] = true }, complete }`. Per character, local, never synced.

### 12.4 Sound API

WoW can't pause or seek. A stopped clip can only start again from the beginning. Clips play with `PlaySoundFile(path, "Master")` and stop with `StopSound(handle)`. New sound files only load after the game is fully restarted, not on `/reload`. The game can drop a clip when the player tabs out, without telling the addon: `C_Sound.IsPlaying` spots this (confirmed in game 2026-11-06) and the scroll offers Restart.

### 12.5 Herald pop-ups

Clips use the herald scroll (10.2), without the fanfare, even when other heralds are switched off.

| Clip | Button | Scroll | Audio |
|---|---|---|---|
| Introduction | Dismiss | Closes on Dismiss or after `VOICE_INTRO_HERALD_SECONDS` (20) | Always plays to the end |
| Others, playing | Stop, plus a corner X | Stays for the whole clip; X closes it | X leaves it playing; Stop ends it |
| Others, stopped | Restart, plus a corner X | Closes after `VOICE_STOPPED_HERALD_SECONDS` (20) | Restart plays from the beginning |

### 12.6 The Constitution, in the Statute Book

On the Statute Book tab. The whole Charter scrolls on the left, generated from `CHARTER.md` by `tools/voice/build.py charter` (rerun it whenever the Charter changes). On the right, ten rows with title, length, "heard" and Play or Stop. Any clip can be replayed any time, except during the staged introduction, which locks the list. Play brings up the herald scroll with Stop. There is only one voice scroll and one sound: pressing Play again switches both to the new clip. Also opened with `/mota constitution`.

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
├── Ballot.lua          (built) The secret ballot: records, whispers, counting (8.2, 8.3)
├── Data.lua            (built) Constants (MOTA.CONST); later the state built from records, validators
├── Probe.lua           (built) /mota probe and /mota probe limits
├── Media.lua           (built) Texture piece positions (written by tools/textures/build.py)
├── Fonts.lua           (built) The canvas fonts
├── UI/
│   ├── Skin.lua                Token definitions and ApplySkin() — loaded first of the UI
│   ├── MainWindow.lua  (built) Frame, tab rail, header, footer
│   ├── Minimap.lua     (built) Minimap seal
│   ├── Crests.lua      (built) Crest finder
│   ├── Herald.lua      (built) Herald pop-ups
│   ├── Settings.lua    (built) Settings panel
│   ├── ThroneRoom.lua          Tab 1
│   ├── BallotHall.lua          (built) Tab 2
│   ├── StatuteBook.lua         Tab 3
│   ├── Court.lua               The Court: accusations, summons, rulings, appeals (Statute Book, Rulings)
│   ├── Parties.lua             Tab 4
│   ├── Treasury.lua            Tab 5
│   ├── Districts.lua           Tab 6
│   ├── Ring.lua                Tab 7
│   ├── WorldMap.lua            World map skins
│   └── Constitution.lua        The Charter and its narration (Voice.lua plays it)
├── Commands.lua        (built) Slash commands — loaded last
├── Libs/               (built)
│   ├── LibStub/
│   ├── CallbackHandler-1.0/
│   ├── AceComm-3.0/            (includes ChatThrottleLib)
│   └── Ace3-LICENSE.txt
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
Ballot.lua
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
UI\Constitution.lua

# Commands last
Commands.lua
```

---

## 15. Design

- **Live design canvas:** https://claude.ai/artifact/V6ZmxpJtw85SrWT9S87acJ (private until shared from its Share menu). It has the style guide, the pages as a clickable prototype, the Extras board (settings, heralds) and the world map skins board. **It is the source of truth for the look.** `design/canvas-source/` is a copy, refreshed from the live canvas before each texture build. Style brief: `design/STYLE_BRIEF.md`.
- **Theme:** regal Stormwind/Alliance. Parchment, wax seals, royal blue and gold. Premium and ceremonial, not basic.
- **Textures:** `design/textures/` holds the parchment, leather, filigree, divider, wax seals and crests. `tools/textures/build.py` lays the window out with the canvas's own stylesheet, draws each piece in Microsoft Edge and packs the pieces into game textures (`Media/*.tga`), with their positions in `Media.lua`. The settings page and herald come from a second layout, `tools/textures/extras.html`, and the Ballot Hall's pieces from a third, `tools/textures/ballot.html`. When the design changes, run the script again.
- **Sizes:** one large background (frame, title, parchment page) at 1.46× the canvas size; small pieces (tabs, labels, icons, buttons, seals) at 2×, so they stay sharp. The add-on folder is about 44 MB (textures 34.75 MB with the window skins, 9.7; the rest fonts and voice clips).
- **Fixed-text labels are pictures, live text is game text.** Tab labels, page names and eyebrows are drawn from the canvas, since the game can't space letters like the canvas. Headings, notes and the status strip are game text. Spaced-out capitals in game text are drawn one letter per text piece (`MotA:Tracked`).
- **Shadow:** a soft picture stretched in nine pieces, so its corners stay round.
- **Fonts:** Cinzel, Cinzel Decorative and EB Garamond from Google Fonts ship inside the addon with their SIL Open Font License files. If the game can't load them, the addon uses the game's own font.
- Names, gold amounts, vote counts and laws on the boards are sample data.
- **Window skins:** the "Window skins" board shows the window in all four skins, what changes and what stays, the colours, and the settings switch (9.1, 9.2, 9.7). *(Drawn and approved by Max 2026-11-06; to build.)*
- **To update on the boards:** the voice player (12.5) needs drawing. *(The Treasury board already shows the Minister of the Treasury as appointed by the PM.)*

---

## 16. Build Roadmap and Status

### 16.1 Phases

| Phase | Scope |
|---|---|
| **v1.0** | Core framework, sync, window, heralds, settings, Throne Room, Ballot Hall (secret ballot by whisper), voice onboarding |
| **v1.1** | Statute Book, Treasury Ledger |
| **v1.2** | Districts tab with map, Citizen Roll |
| **v1.3** | Parties tab with the Party Chamber, the Court |
| **v1.4** | The Ring, world map skins |
| **v2.0** | External persistence layer, async voting, encrypted ballots (19.1) |

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

`/mota` (open the window), `/mota sync`, `/mota who`, `/mota test <text>`, `/mota book`, `/mota probe`, `/mota probe limits`, `/mota debug`, `/mota scale [n]`, `/mota minimap`, `/mota crests`, `/mota crest <n|ours>`, `/mota settings`, `/mota herald [1|2|3]`, `/mota fanfare [n]`, `/mota constitution`, `/mota voice [on|off|stop|next|reset]`, `/mota ballot` (opens the Ballot Hall and says where the vote stands and where your ballot is), `/mota ballot count` (the two Crown ranks only: the count, held and refused ballots, and whether the two Kings' counts agree), `/mota skin [crown|silverhand|exchange|ministry]` (the two Crown ranks only, and listed in the help only for them: try a window skin until `/reload`; blank goes back). `/ministry` works the same.

### 16.4 The code brought in line with this spec *(built 2026-11-06, to test in game)*

1. The add-on's shared table is now `MOTA`, the message prefix `MOTA`, the saved data `MOTADB` (test saves under the old name aren't carried over), and the TOC author and notes follow section 14.
2. Both Crown ranks, "The King" and "The Crown", are recognised (`MOTA.CONST.CROWN_RANK_NAMES`); `/mota probe` lists everyone on either.
3. AceComm-3.0 (Release-r1403, with LibStub, CallbackHandler-1.0 and ChatThrottleLib) is in `Libs/`, with Ace3's licence (`Libs/Ace3-LICENSE.txt`: shipping it inside an add-on is allowed; handing it out on its own isn't). `Comm.lua` sends everything through it; messages wait in our own queue while the game has add-on messages locked or the limits test runs, because ChatThrottleLib would drop them. Live news goes as ChatThrottleLib's ALERT priority, background traffic as BULK. The limits test still sends straight to the game, since it measures the game's own limits.
4. Records are packed with `C_EncodingUtil` and Base64 (message protocol 2). Copies on protocol 1 are told to update.
5. `Data.lua` holds `MOTA.CONST`. `UI/Window.lua` is now `UI/MainWindow.lua`.
6. **The pretend game client** is now kept in the repo, `tools/sim/` (its README says how to run it). It loads the libraries from the TOC and checks that AceComm splits a long record into pieces and joins it back together, and that records travel packed. **66 checks passed, no Lua errors.**

7. **First in-game test with the guild (Max, 2026-11-06):** `/mota who` listed Max himself and no one else. Fixed: the add-on now recognises its own messages in every name form the game uses, and works out its own name again if the realm wasn't known at login. `/mota who` now also lists guild members online without the add-on (or with a copy too old to hear this one). Second test: Max still saw himself, as "Kíng Sinnclair-CAMWOWEU5Realm7PvE". Forever writes the realm in roster names and message senders in a form of its own, different from the game's realm lookup, and the game doesn't shorten it. Fixed: the add-on now takes its own name from its guild roster entry (found by the character's unique ID), uses that realm for everyone, and hides it in names on screen. Character names on Forever can contain spaces and accents ("Kíng Sinnclair", "Lailaika Moonwatcher"). **73 checks passed.**

8. **Test with Kíng Atwood (Max, 2026-11-07), with `/mota debug` on both sides:** the hello on the guild channel worked both ways, but no whisper got through: every one was refused with "No player named 'Kíng Atwood-CAMWOWEU5Realm1PvE' is currently playing". Forever's realm tag differs from screen to screen: Max's game writes every name with "Realm7PvE", Atwood's with "Realm1PvE", and the server refuses a whisper addressed with either. Each add-on also took its own hello, coming back with a tag it didn't expect, for someone else's, listed itself in `/mota who` and whispered itself. A whisper by hand to the name alone (`/w Kíng Atwood`) works. **Fixed (version 0.1.1):** players are known by their name alone everywhere (`MOTA:Bare` in `Core.lua`): roster, message senders, records, ballots and whispers. Saved data from before is renamed once on login, and a player saved under two tags is merged into one (`MOTA:BareGuildBook`, `MOTA:BareTallies`). The pretend client now writes a different tag on each player's screen and refuses tagged whispers, as Forever does. **246 checks passed, 0 Lua errors.**

**To test in game:** `/reload`; `/mota` and `/mota probe` work as before (the probe now says "On the Crown ranks"). With a second guild member online: `/mota who` and `/mota test Hear ye!` both ways. After 0.1.1, both on the new version: each sees the other "online", neither sees themselves, and no "No player named" line appears with `/mota debug` on.

**Milestone 4 — the secret ballot** *(agreed 2026-11-06; built 2026-11-06, to test in game)*

Window skins come after it. Steps: update the Ballot Hall board on the live canvas, Max reviews it, then build.

1. **The Crown opens polls.** One of the Crown ranks fills in the Open Polls form (election name, candidates with name and party) and clicks Open Polls: a `ballot.open` record, polls open 2 hours (`BALLOT_WINDOW_SECONDS`), and a herald "The polls are open!" for everyone online.
2. **A citizen votes.** They mark one name and click Seal my ballot. The ballot goes by hidden add-on WHISPER to each online King (never GUILD or OFFICER). The King's add-on whispers a receipt back, and the ballot shows the sealed stamp "Sealed and sent to the Crown".
3. **No King online.** The ballot shows "Sealed, waiting for the Crown". The voter's add-on keeps the ballot (through `/reload` and logout), writes a `ballot.sealed` record (who, not how), and sends the ballot when the voter and a King are online together. The Crown's view counts the sealed ballots still on their way. When the only King online starts to log out while polls are open, their add-on warns them (Stay online / Log out anyway).
4. **The Kings count.** Each King's add-on writes a `ballot.voted` record (who voted, not how), drops the voter's name from the count, and refuses a second vote from the same person.
5. **Live count only in the Kings' add-ons** (`MOTADB.ballotTally`). The two Kings' counts are compared and the Crown view says whether they agree. A King logging in late gets the count handed over by whisper.
6. **The Crown closes polls and declares the result:** a herald, then the Results view (proclamation, bars, turnout, past elections). A tie offers a run-off between the tied candidates. Held ballots sealed before the close still count until the declaration; the closed view says how many are still to come.
7. **Logging in mid-poll:** an online King's add-on whispers the open ballot to anyone who says hello (full catch-up isn't built yet).
8. **Login reminder:** "You haven't voted yet: polls close in …".
9. **Who may vote, for now:** guild members active in the last 30 days. Later: alt links (10.1), the 10-day return rule (8.4), district elections.
10. **Not in this milestone:** the Throne Room "Vote now", the phase banner, nominations, the no-confidence tab, full catch-up.
11. **Testing:** the pretend game client (`python tools/sim/sim.py`) with two Kings, citizens, a King offline, a mid-poll login, a double vote, a tie and a held ballot delivered after the close; then in game with Max (a King) and another member.

**Design:** the Ballot Hall board on the live canvas was updated and reviewed by Max on 2026-11-06 (Crown view, held ballots, the last King's warning). The law vote was taken off the Throne Room, Statute Book, Treasury and Parties boards.

**Built (2026-11-06):**
- `Ballot.lua`: the five ballot records and the whispers `BV`, `BR`, `BT`, `BO`, `BS` (7.5); held ballots kept through `/reload` and delivered when a King says hello (the `ballot.sealed` record is sent again first, so the King holds it); the Kings' counts with hand-over and comparison; close, declare and the run-off; the "polls are open" and result heralds; the login reminder (herald and chat line, once per ballot per session); the last King's logout warning on `PLAYER_CAMPING` (a game pop-up for now, not the board's parchment one).
- **Double votes:** a King refuses only a voter it has counted itself (also after a hand-over), never one merely on the public voted list, because the other King may have counted the very same ballot. Each ballot carries a one-off token, so the same ballot sent twice isn't taken for a second one; a second, different ballot is refused and shown under "Second ballots refused".
- **Comparing the counts:** if one King's counted voters include all the other's, the bigger count is taken; if they share nobody, they're added up; if they partly overlap, both are kept and the Crown view says "Counts differ by N".
- **A King logging in late** learns the ballot from the other King (`BO`), and other members tell them who sealed a ballot while they were away (`BS`), so "still to come" is right. If neither King's add-on was online when the polls opened, a King logging in later doesn't learn the ballot until full catch-up is built; held ballots stay with their voters until then.
- `Roster.lua`: days since each member was last online, and the count of active citizens (online, or within 30 days), used for turnout.
- `UI/BallotHall.lua` on window page 2: ribbons Ballot, Results and Crown (the Crown ribbon for the two Crown ranks only); the ballot paper with the stamp or the held block; "The Crown is counting" and "The Ballot Hall is quiet"; Results with the proclamation, bars, turnout and the record; the Open Polls form (candidates' parties change with a click); the live count with the two Kings' counts, held and refused ballots, Close polls, Declare the result and Set up the run-off. **Not in this milestone:** the Petition ribbon.
- Textures: a third layout, `tools/textures/ballot.html`, gives `Media/ballot.tga` (ribbons, seals, stamp, buttons, pills) and `Media/papers.tga` (the three papers).
- Checked in the pretend client (`tools/sim/sim.py`, section 13) with two Kings and five citizens: opening polls, a vote with one King online, a second ballot refused, a held ballot delivered when the King returns, a mid-poll login with the reminder, the hand-over to the second King, the same ballot reaching both Kings, counts that partly overlap, the logout warning, a held ballot sealed before the close counting after it, a tie and its run-off, a held ballot arriving after the declaration refused, and a declared result. **176 checks passed, 0 Lua errors.**

**To test in game (Max, a King, plus one other member):**
Each member votes once per election, so the two ways a ballot travels get an election each.
1. Both `/reload`. Max: `/mota ballot`, the Crown ribbon, fill in the form (a name, two candidates), **Open polls**. The other member gets "The polls are open!"; **Vote now** opens the ballot paper.
2. **Election 1, sent at once:** the member marks a name and seals. Within a few seconds: "Your ballot was received by the Crown (Max)" and the red stamp. Max's Crown view shows 1 vote. `/mota book` on either side shows a `ballot.voted` record and no choice.
3. Max: **Close polls**, then **Declare the result**. The member gets the result herald; the Results ribbon shows it.
4. **Election 2, held:** Max opens new polls, then starts to log out: the "last King online" warning should appear. Try **Stay online** (does the logout stop? section 18), then log out for real. The member seals: "Sealed, waiting for the Crown". The member `/reload`s: still waiting. Max logs back in: the member gets the receipt and Max's count shows it.
5. **Mid-poll login:** with polls open, the member logs out and back in: "You haven't voted yet" is not shown (they voted). A member who hasn't voted, logging in, gets it.
6. Max closes and declares election 2 (or sets up the run-off if it's a tie). Note anything that looks off against the canvas board.

**Milestone 5 — window skins** *(designed and approved 2026-11-06; built 2026-11-06, to test in game)*

Design: the Window skins board on the live canvas (9.2, 9.3, 9.7).

**Built:**
- `tools/textures/build.py` draws the window in layers (9.7): `parch.tga` and `grain.tga` shared; `frame_gold.tga` and `frame_silver.tga` (rim, rules and stitching cut into bands, the page's metal rim, the filigree corner, the title, the lit tab, the subtitle's rule, the rail line, pip and portrait ring); `skin_crown`, `skin_silverhand`, `skin_exchange`, `skin_ministry` (leather, resting and hover tabs, the two knobs, the emblem). `chrome.tga` and `crest.tga` are gone. The page names under the title are now drawn in white and coloured in the game. With `--preview` it saves a picture of the window in each skin to the temp folder.
- `UI/Skin.lua`: the tokens (9.3), `MOTA.ApplySkin`, the choice (9.1) and `/mota skin`. It fires `SKIN_CHANGED`, and `UI/MainWindow.lua` puts the new skin's pieces, crest and colours on at once.
- Who gets which: the two Crown ranks get the Crown skin, everyone else the Ministry's, until the Parties page keeps a roll of members (v1.3), which gives Silverhand and Exchange members their party's skin. `/mota skin silverhand` or `exchange` shows those meanwhile, for the Crown only.
- Only the Crown can switch skins (9.1): `/mota skin` is Crown-only and left out of the help for others, who are politely refused if they type it; the settings row is hidden for them (it shows or hides when the guild rank arrives); and `Skin:Choose()` ignores a saved "ministry" choice and any skin being tried unless the player is a Crown rank.
- Settings: a sixth row, "Window skin: Party / Ministry", shown to the Crown ranks only (the switch from the Window skins board; the Extras board still shows five rows).
- Textures: 34.75 MB in all, 5.25 MB more than before (9.7). Every skin texture is 1024 × 512.
- Checked in the pretend client (`tools/sim/sim.py`, section 9b): the Ministry skin for a citizen, `/mota skin` crown, silverhand and exchange (textures, emblem, label colours, gold or silver metal), an unknown name refused, `/mota skin` going back, the Crown skin for a Crown rank, and the setting switching it to Ministry and back, all as a Crown rank; and as a citizen, `/mota skin` refused and left out of the help, no settings row (and clicking it anyway changes nothing), and an old saved Ministry choice unable to override their party's skin. The pretend game now accepts tiled and mirrored textures. **233 checks passed, 0 Lua errors.**

**To test in game:**
1. `/reload`, `/mota`. Max (a Crown rank) should see the purple Crown window; a citizen the blue Ministry one, as before.
1a. On a character that isn't a Crown rank: `/mota help` doesn't list `/mota skin`; typing `/mota skin crown` anyway gets a polite refusal and nothing changes; the settings page has no Window skin row.
2. On the Crown character: `/mota skin silverhand`, `/mota skin exchange`, `/mota skin ministry`, `/mota skin crown`: each changes the window at once. Check the leather, the tabs (rest, hover, lit), the knobs, the corner emblem, the title, the corners and the page rim against the board. `/mota skin` goes back.
3. Look closely at: the leather grain (tiled over the leather; no seams or squares), the rim's bands (no gaps or lines where they meet), the corners at the bottom (mirror images of the top-right one), the two rules beside the page name on each page.
4. Settings (the window's gear): Window skin → Ministry turns Max's window blue at once; Party turns it back.
5. `/reload` after `/mota skin exchange`: back to your own skin.

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
| `VOICE_CLIP_GAP` | 150 | Seconds from the end of one staged clip to the next |

---

## 18. To test after launch

- **Addon message limits:** size and rate throttle, and whether Midnight-era rules block addon messages in instances or combat. `/mota probe limits` measures it; run `/mota probe` in a dungeon too.
- **Whispered ballots:** that an addon whisper reaches a King on the same realm reliably, and what happens when the King is offline (the send should fail cleanly so the ballot is held).
- **The last King's logout warning (8.2):** that the addon hears a logout starting (the `PLAYER_CAMPING` event) and that **Stay online** can cancel it (`CancelLogout`). If not, the warning shows when polls are open and the other King is offline, without stopping the logout. Quitting the game outright (rather than logging out) isn't caught yet.
- **Last-online times and active citizens:** that `GetGuildRosterLastOnline` gives offline members' times, and that the roster lists offline members even with "Show offline members" unticked; otherwise the active-citizen count (turnout) only counts who is online.
- **Auto promote/demote:** only a character whose rank has the permission can do it, so results may be applied by a Crown client, possibly with a button click.
- **Honour titles:** that the addon can still add text to friendly nameplates and the mouseover tooltip.
- **Chat tags:** that the addon can still change how guild chat lines display.
- **Duel results:** that "X has defeated Y in a duel" arrives as an ordinary system message.
- **Trade window warning** for embargoed citizens.
- **Guild bank money log:** which guild ranks can see it, and how many entries the game keeps before old ones drop off (10.7).
- **World map window:** that the skin stays on when the map is enlarged or shrunk, no errors opening the map in combat, and whether the "Player / Cursor" coordinates strip in the reference screenshot is Forever's or another addon's.
- **Game text-to-speech** still works for addons (a possible voice fallback for herald lines).

---

## 19. Open Items, Parked Ideas and Decision Log

### 19.1 Open items

- **Party Chamber, when party data is built:** remove the As member / As outsider preview switch in `UI/Parties.lua` and the example text. Members of a party see their own party's chamber; everyone else, including members of the other party, sees that chamber sealed. The Chamber tab opens on the player's own party. Requested by Duncan, 2026-11-06.
- **Throne Room, for Duncan and Max to agree before anyone builds it (Duncan, 2026-11-06):** Duncan has held off so the two lines of work don't clash. To settle: who builds it; the "Vote now" link to the Ballot Hall; Cabinet posts (guild ranks like `Minister of War`, or appointments); how window skins affect it. Page parts already exist in `UI/Kit.lua` (plates, ribbons, buttons, gems, coins), so reuse them rather than rebuilding them.
- **The real map:** district shapes need tracing against the live Stormwind map after launch.
- **Herald voice lines:** a town crier calling "Hear ye! The polls are open!" with heralds. Fixed lines only (lines with names or numbers stay as text). Same voice rules as section 12. The game's own text-to-speech is a possible flat-voiced fallback.
- **Clip 4 is out of date:** The Parties narration says polls open for forty-eight hours; Charter 3.3 has said 2 hours since 2026-11-06. It needs regenerating.
- **Voice volume and a settings switch:** only `/mota voice on|off` so far; the settings board and the Statute Book layout need adding to the canvas.
- **Notice board:** citizens can have a notice pinned on the Throne Room, by request; the Crown can take it down. Agreed 2026-11-03, not in the first build.
- **Encrypted ballots (v2.0):** the voter's addon locks the ballot so only the Kings can open it and posts it into the shared book, so it reaches the Kings even if the voter is never online with one. Needs encryption written in Lua and a key handed out by each King. Agreed for later on 2026-11-06; until then held ballots follow 8.2, step 4.
- **Party leader votes:** how the vote inside the Party Chamber is counted (open among members, or secret like the elections) is still to decide when Parties is planned in detail.

### 19.2 Old-plan ideas set aside for the brief's simpler version

Kept here so they can be brought back later. Each was agreed in the old plan and replaced on 2026-11-06 when the brief became the source of truth.

- **Independent count check:** every member's addon counted ballots on the guild channel ("Count agreed by 31 of 31"). Replaced by the secret ballot (8.2).
- **Self-running elections:** the addon followed the Charter timeline without anyone driving it, called run-offs automatically, with nominations and a **candidacy check** (good standing, two weeks as a citizen, later level 60, raids led, treasury contributions; stage set by the Crown).
- **No-confidence petition signed in the addon,** with progress towards 40% and the days left.
- **Joining a party through its officer:** the party's designated officer's addon records the 5g automatically from trade or mail, and the officer (or leader) accepts the citizen; roster changes accepted from them rather than the Crown.
- **Office-based writing:** PM, ministers and Representatives writing their own records (appointments, renewals, assignments, transfers, Ring results) rather than the Crown doing those writes.
- **Several Ring level brackets** at once (20–29, 30–39 … 60), each with its own champion.
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
- **2026-11-06** The treasury goes back to the old plan's automatic ledger, read from the guild bank money log by every member's addon (10.7). Ring entry fees are counted from the bank log, not at sign-up (11.5).
- **2026-11-06** Milestone 4 is the secret ballot; window skins after it. Held ballots: a public `ballot.sealed` record, held ballots sealed before the close count until the result is declared, and the last King online is warned before logging out (8.2, 8.3). Encrypted ballots later, with v2.0 (19.1). The law vote was taken off every board.
- **2026-11-06** Parties: joining follows the brief (join button, the Crown records membership); the Party Chamber, leader elections inside it, Chamber privacy by whisper and the 14-day crossing-the-floor rule follow the old plan (10.16). The Court follows the old plan: accusation, summons, Justices' ruling, punishment applied, appeal to the Crown (10.10).
- **2026-11-06** Milestone 4 build: `ballot.close` and `ballot.result` are separate records (held ballots count until the declaration); a King refuses only voters it counted itself; a Crown member may pass on the open ballot's records to members logging in; members tell a King logging in who sealed while the Kings were away, for the count of ballots still to come only; the logout warning uses the game's pop-up for now; the Petition ribbon waits for a later milestone.
- **2026-11-06** Window skins designed and approved by Max: the parchment page stays the same in every skin; the metal is gold except Silverhand's silver; resting tabs take each skin's wax; a "Window skin: Party / Ministry" setting and a `/mota skin` test command; the textures are split into shared, per-metal and per-skin layers, about 2 MB per skin and 7 MB in all (9.1, 9.2, 9.3, 9.7).
- **2026-11-06** Skins locked to rank (done): only the two Crown ranks can switch window skin, by `/mota skin` or the "Window skin" setting; for everyone else both are hidden (the command also refuses politely if typed) and the skin follows their guild rank. A saved Ministry choice or a tried skin is ignored for non-Crown players (9.1, 16.2, 16.3).
- **2026-11-06** Voice onboarding: 2.5 minutes between clips rather than 4; the introduction can't be stopped; clips use herald scrolls rather than a separate notification frame; the readable Charter and its audio live in the Statute Book.

---

*Ministry of the Allied Addon Spec v1.1 — 6 November 2026*
