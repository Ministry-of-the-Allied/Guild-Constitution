# MOTA — Coding Brief

*Drop this file and ADDON_SPEC.md into context. Those two documents are the complete source of truth for all code generation work. Record new decisions in ADDON_SPEC.md (section 19).*

---

## What to build

The Ministry of the Allied addon (MOTA) — a WoW: Forever addon (Interface 16001) that surfaces the guild's political state as an in-game UI and handles voting, law tracking, treasury records, and citizen onboarding.

Single codebase. Crown features are hidden unless the player holds one of the two Crown guild ranks, "The King" or "The Crown". No separate Crown vs Citizen distribution.

The code lives in `addon/MinistryOfTheAllied/` in this repo. Milestones 1–3 and the spec renames are built (ADDON_SPEC.md section 16). Test every change in the pretend game client first: `python tools/sim/sim.py`.

---

## Key constants

Define these in `Data.lua`:

```lua
MOTA.CONST = {
    BALLOT_WINDOW_SECONDS    = 7200,       -- 2-hour voting sessions
    LAW_EXPIRY_SECONDS       = 7776000,    -- 90 days
    NO_CONFIDENCE_THRESHOLD  = 0.40,       -- 40% of active citizens
    ACTIVE_CITIZEN_DAYS      = 30,         -- login within 30 days = active
    RETURN_WAIT_DAYS         = 10,         -- returning citizens wait 10 days to vote
    CROWN_RANK_NAMES         = { ["The King"] = true, ["The Crown"] = true },
    SNAP_ELECTION_MIN_DAYS   = 7,          -- minimum campaign period
    SYNC_STALE_SECONDS       = 300,        -- catch-up summary every 5 min
    SYNC_AMBER_SECONDS       = 1800,       -- footer sync indicator turns amber after 30 min
    BROADCAST_MIN_INTERVAL   = 3,          -- seconds between routine GUILD broadcasts
    VOICE_CLIP_COUNT         = 10,         -- total onboarding voice clips
    VOICE_CLIP_GAP           = 150,        -- seconds from the end of one staged clip to the next
}
```

---

## Build order

| Phase | Files | Notes |
|---|---|---|
| **Built** | Libs/ (AceComm-3.0), Core.lua, Data.lua, Roster.lua, Comm.lua, Book.lua, Hello.lua, Probe.lua, Media.lua, Fonts.lua, UI/MainWindow.lua, UI/Minimap.lua, UI/Crests.lua, UI/Herald.lua, UI/Settings.lua, Commands.lua | Milestones 1–3 and the spec renames (ADDON_SPEC.md 16.4): sync skeleton on AceComm, window, minimap seal, heralds, settings |
| **v1.0** | UI/Skin.lua, UI/ThroneRoom.lua | Skins and the Throne Room (built in v1.0 already: voice onboarding, Voice.lua and UI/Constitution.lua; the secret ballot, Ballot.lua and UI/BallotHall.lua, Milestone 4) |
| **v1.1** | UI/StatuteBook.lua, UI/Treasury.lua | Law registry + ledger |
| **v1.2** | UI/Districts.lua | Citizen roll + regional map |
| **v1.3** | UI/Parties.lua, UI/Court.lua | Parties with the Party Chamber + the Court |
| **v1.4** | UI/Ring.lua, UI/WorldMap.lua | The Ring + world map skins |
| **v2.0** | External persistence layer | Async voting, offline support |

Design each screen on the live canvas before building it (ADDON_SPEC.md section 15).

---

## Framework

- **AceComm-3.0** (with LibStub, CallbackHandler-1.0 and ChatThrottleLib) — all message sending/receiving (never raw `C_ChatInfo.SendAddonMessage`). It splits long messages and paces sending.
- **No other libraries.** Start-up and SavedVariables (`MOTADB`, account-wide) are handled in `Core.lua`; the UI is our own frames drawn from the canvas textures (no AceGUI); packing uses the game's own `C_EncodingUtil` (no LibSerialize / LibDeflate).

All libs embedded in `Libs/`. Citizens install nothing separately.

---

## Sync model

Every member's addon keeps a full copy of the guild's **book of records** and shares it with everyone, so updates keep happening when the Kings are offline. Records are only ever added, each with Author + Number as its ID and the realm's server time. State (government, laws, ballots…) is worked out from the book. Each addon checks the writer was allowed to write that record type. Missed records come back through catch-up summaries. Full detail: ADDON_SPEC.md section 7.

---

## Permission detection

```lua
-- In Core.lua / Roster.lua:
-- GetGuildInfo returns guildName, guildRankName, guildRankIndex.
local function DetectMode()
    local _, rankName = GetGuildInfo("player")
    if rankName and MOTA.CONST.CROWN_RANK_NAMES[rankName] then
        return "CROWN"
    end
    return "CITIZEN"
end
MOTA.mode = DetectMode()
-- GetGuildInfo can be nil right after login: re-check on GUILD_ROSTER_UPDATE.
-- For other members, read their rank name from GetGuildRosterInfo(i) (Roster.lua).
```

---

## Vote secrecy rule

Ballots are sent **only by hidden addon whisper to each online King** (rank "The King" or "The Crown") — never to the GUILD or OFFICER channel. If no King is online, the voter's addon holds the sealed ballot, writes a `ballot.sealed` record (who, not how), and sends the ballot when the voter and a King are online together; a ballot sealed before the polls close still counts until the result is declared (ADDON_SPEC.md 8.2). The Kings' addons count into a local `MOTADB.ballotTally`, throw the voter's name away after counting, and whisper a receipt back. What goes to the guild is a `ballot.voted` record (who voted, not what they chose). This is intentional and must not be changed without explicit instruction.

---

## Sound API constraints

WoW does not support pause/resume with position tracking. The voice player uses stop/restart only:

```lua
-- Play
local path = string.format(
    "Interface\\AddOns\\MinistryOfTheAllied\\Media\\Voice\\voice_%02d.ogg", index)
local soundHandle = select(2, PlaySoundFile(path, "Master"))
MOTA.voice.handle = soundHandle

-- Stop
if MOTA.voice.handle then
    StopSound(MOTA.voice.handle)
    MOTA.voice.handle = nil
end
```

Controls: Stop and Restart (from the beginning). No pause. See ADDON_SPEC.md section 12.

---

## Skin system summary

Skins are set in `UI/Skin.lua` (loaded first of the UI in .toc) via `MOTA.ApplySkin(skinKey)`. All UI frames reference `MOTA.skin.<TOKEN>` as RGB float tables — never hardcoded hex. Four skins: `CROWN`, `SILVERHAND`, `AZEROTH_EXCHANGE`, `UNREGISTERED`. They reuse the four world map skin designs on the live canvas (Crown purple, Silverhand silver and blue, Exchange crimson and gold, Ministry royal blue and gold), each with its own corner emblem. See ADDON_SPEC.md section 9.

---

## Message prefix

`MOTA` — registered with `AceComm:RegisterComm("MOTA", handler)` in `Comm.lua`.

Payloads are packed with `C_EncodingUtil.SerializeCBOR(payload)` and made channel-safe with `C_EncodingUtil.EncodeBase64`. Big batches (catch-up) are compressed with `C_EncodingUtil.CompressString` before encoding; small single records aren't, because compression makes them bigger. Reverse on receive. (Whether Forever accepts raw binary in addon messages, which would save the Base64 step, is untested.)

---

*Ministry of the Allied — MOTA Coding Brief v1.1 — 6 November 2026*
