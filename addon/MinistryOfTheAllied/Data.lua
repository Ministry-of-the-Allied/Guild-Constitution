-- Ministry of the Allied: the realm's fixed numbers (ADDON_SPEC.md, section 17).
-- Loaded straight after Core.lua, so every other file can read MOTA.CONST.

local _, MOTA = ...

MOTA.CONST = {
  BALLOT_WINDOW_SECONDS   = 7200,     -- 2-hour voting sessions (Charter 3.3)
  LAW_EXPIRY_SECONDS      = 7776000,  -- 90 days
  NO_CONFIDENCE_THRESHOLD = 0.40,     -- 40% of active citizens
  ACTIVE_CITIZEN_DAYS     = 30,       -- login within 30 days = active
  RETURN_WAIT_DAYS        = 10,       -- returning citizens wait 10 days to vote
  -- The two Crown ranks, one per King (ADDON_SPEC.md, section 4). Must match
  -- the in-game rank names exactly, capitals included.
  CROWN_RANK_NAMES        = { ["The King"] = true, ["The Crown"] = true },
  SNAP_ELECTION_MIN_DAYS  = 7,        -- minimum campaign period
  SYNC_STALE_SECONDS      = 300,      -- catch-up summary every 5 min
  SYNC_AMBER_SECONDS      = 1800,     -- footer sync indicator turns amber after 30 min
  BROADCAST_MIN_INTERVAL  = 3,        -- seconds between routine GUILD broadcasts
  VOICE_CLIP_COUNT        = 10,       -- onboarding voice clips
  VOICE_CLIP_INTERVAL     = 240,      -- about 4 min between staged clips
}
