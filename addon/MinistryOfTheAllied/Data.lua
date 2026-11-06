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
  VOICE_CLIP_GAP          = 150,      -- 2.5 min from the end of one staged clip to the next
  VOICE_INTRO_HERALD_SECONDS = 20,    -- the introduction's scroll closes itself, the voice plays on
  VOICE_STOPPED_HERALD_SECONDS = 20,  -- how long a stopped clip's scroll offers Restart
  -- Lengths come from the files: the game can't report a sound's length.
  VOICE_CLIPS = {
    { title = "Introduction", length = 73.6 },
    { title = "The Crown", length = 92.0 },
    { title = "The Government", length = 70.7 },
    { title = "The Parties", length = 142.1 },
    { title = "Legislation", length = 56.0 },
    { title = "The Vote of No Confidence", length = 50.3 },
    { title = "The High Judiciary", length = 52.0 },
    { title = "Punitive Measures", length = 70.8 },
    { title = "Citizenship and the Districts", length = 118.9 },
    { title = "Welcome to the Realm", length = 25.5 },
  },
}
