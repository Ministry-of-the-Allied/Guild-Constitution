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
  MINISTER_OF_WAR_RANK    = "Minister of War", -- must match the in-game rank name exactly
  -- The offices, highest first, as the "who's online" tooltip lists them
  -- (Max's answer A2, 8 Nov). Rank names must match the game's exactly. Both
  -- Crown ranks share one section. Every other rank is a Citizen.
  OFFICES = {
    { title = "The Crown",        ranks = { ["The King"] = true, ["The Crown"] = true } },
    { title = "Prime Minister",   ranks = { ["Prime Minister"] = true } },
    { title = "Minister of War",  ranks = { ["Minister of War"] = true } },
    { title = "Deputy PM",        ranks = { ["Deputy PM"] = true } },
    { title = "The Judiciary",    ranks = { ["The Judiciary"] = true } },
  },
  CITIZENS_TITLE          = "Citizens",
  STORMWIND_MAP_ID        = 1453, -- Stormwind City on Forever (Max's map probe, 8 Nov)
  -- The five districts (CONSTITUENCIES.md), in the board's order. Colours are the
  -- Districts board's own; they belong to the districts, not to a skin.
  DISTRICTS = {
    { code = "OLD",  name = "The Old Quarter",     short = "Old Quarter",     place = "Old Town",
      character = "Military, defence, PvP, honour", meet = "SI:7 Headquarters, Old Town",
      color = "8E2B22", lean = "Split" },
    { code = "ARC",  name = "The Arcane Ward",     short = "Arcane Ward",     place = "Mage Quarter",
      character = "Crafting, enchanting, intellect, strategy", meet = "Stormwind Mage Tower, Mage Quarter",
      color = "6B44A8", lean = "Silverhand" },
    { code = "IRON", name = "The Iron District",   short = "Iron District",   place = "Dwarven District",
      character = "Mining, blacksmithing, industry, production", meet = "AH steps, Dwarven District",
      color = "B0621C", lean = "Azeroth Exchange" },
    { code = "CATH", name = "The Cathedral Ward",  short = "Cathedral Ward",  place = "Cathedral Square",
      character = "Justice, diplomacy, ceremony, civic life", meet = "Cathedral of Light, Cathedral Square",
      color = "3D86C6", lean = "Silverhand" },
    { code = "HARB", name = "The Harbour Quarter", short = "Harbour Quarter", place = "Stormwind Harbour",
      character = "Trade, commerce, external affairs, exploration", meet = "Harbour Master's Office, Stormwind Harbour",
      color = "1F7A70", lean = "Azeroth Exchange" },
  },
  -- The game's class colours, if RAID_CLASS_COLORS isn't there.
  CLASS_COLORS = {
    WARRIOR = "C69B6D", PALADIN = "F48CBA", HUNTER = "AAD372", ROGUE = "FFF468", PRIEST = "FFFFFF",
    MAGE = "3FC7EB", WARLOCK = "8788EE", DRUID = "FF7C0A", SHAMAN = "0070DD",
    DEATHKNIGHT = "C41E3A", MONK = "00FF98", DEMONHUNTER = "A330C9", EVOKER = "33937F",
  },
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
