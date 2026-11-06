-- Ministry of the Allied: window skins (ADDON_SPEC.md section 9).
-- The window wears one of four skins: the Crown's for the two Crown ranks,
-- the player's party's, or the Ministry's blue and gold. Only on your own
-- screen. The pictures come in layers from tools/textures/build.py (9.7):
-- per skin (leather, wax tabs, knobs, emblem) and per metal (gold or
-- silver: rim, corners, title, lit tab). Labels and live text are coloured
-- here, with the tokens below (9.3).
--
-- The skin is chosen at login, once the guild rank is known. A change of
-- party or rank shows at the next login or /reload; the settings switch
-- (Party or Ministry) and /mota skin change it at once.

local _, MOTA = ...
local Skin = {}
MOTA.Skin = Skin

-- Colours from the Window skins board (ADDON_SPEC.md 9.3). "hex" strings,
-- turned into { r, g, b } tables when the skin is applied.
local SKINS = {
  UNREGISTERED = {
    TAB_INK = "E5CF92", TAB_INK_HOVER = "FBEFC4", TAB_SMALL = "EBC3B2",
    TAB_INK_ON = "0E1F45", TAB_SMALL_ON = "3A2A0A",
    SUBTITLE = "B9C9EE", PALE_INK = "AFC0E6", NAME_INK = "FBEFC4",
  },
  SILVERHAND = {
    TAB_INK = "DCE3EE", TAB_INK_HOVER = "FFFFFF", TAB_SMALL = "AEB9CC",
    TAB_INK_ON = "1F4290", TAB_SMALL_ON = "2B3445",
    SUBTITLE = "D5DEF0", PALE_INK = "C6D2EA", NAME_INK = "FFFFFF",
  },
  AZEROTH_EXCHANGE = {
    TAB_INK = "F3D98A", TAB_INK_HOVER = "FBEFC4", TAB_SMALL = "F0C9BC",
    TAB_INK_ON = "5A0E13", TAB_SMALL_ON = "3A2A0A",
    SUBTITLE = "F2CDBE", PALE_INK = "F2CDBE", NAME_INK = "FBEFC4",
  },
  CROWN = {
    TAB_INK = "F3D98A", TAB_INK_HOVER = "FBEFC4", TAB_SMALL = "E8C6DC",
    TAB_INK_ON = "3E0A2F", TAB_SMALL_ON = "3A2A0A",
    SUBTITLE = "EBCBDF", PALE_INK = "EBCBDF", NAME_INK = "FBEFC4",
  },
}
Skin.keys = { "CROWN", "SILVERHAND", "AZEROTH_EXCHANGE", "UNREGISTERED" }

-- Words /mota skin accepts.
Skin.names = {
  crown = "CROWN", silverhand = "SILVERHAND", exchange = "AZEROTH_EXCHANGE",
  ministry = "UNREGISTERED", unregistered = "UNREGISTERED",
}
Skin.titles = {
  CROWN = "the Crown", SILVERHAND = "Silverhand", AZEROTH_EXCHANGE = "the Azeroth Exchange", UNREGISTERED = "the Ministry",
}

-- The player's party, once the Parties page keeps a roll (v1.3). Until then
-- nobody has one, so citizens get the Ministry skin.
local function myParty()
  return MOTA.PartyOf and MOTA.me and MOTA:PartyOf(MOTA.me) or nil
end

-- Which skin the player should wear (9.1).
function Skin:Choose()
  if self.preview then return self.preview end
  if MOTA.db and MOTA.db.settings.windowSkin == "ministry" then return "UNREGISTERED" end
  if MOTA.me and MOTA:IsCrown(MOTA.me) then return "CROWN" end
  local party = myParty()
  if party == "SILVERHAND" or party == "AZEROTH_EXCHANGE" then return party end
  return "UNREGISTERED"
end

function MOTA.ApplySkin(key)
  if not SKINS[key] then key = "UNREGISTERED" end
  local media = MOTA.Media.skins[key]
  local skin = { KEY = key, FILE = media.file, METAL = media.metal }
  for token, hex in pairs(SKINS[key]) do
    local r, g, b = MOTA:RGB(hex)
    skin[token] = { r = r, g = g, b = b }
  end
  MOTA.skin = skin
  MOTA:Fire("SKIN_CHANGED", key)
end

-- Chooses again and applies it if it changed. Before the guild rank is
-- known, and when forced (the setting, /mota skin), a change shows at once;
-- after that it waits for the next login.
function Skin:Refresh(force)
  local key = self:Choose()
  if MOTA.skin and MOTA.skin.KEY == key then return end
  if force or not self.settled then MOTA.ApplySkin(key) end
end

-- /mota skin <name>: try a skin on your own screen until /reload.
-- No name (or "off") goes back to your own.
function Skin:Preview(word)
  word = (word or ""):lower()
  if word == "" or word == "off" or word == "mine" then
    self.preview = nil
  else
    local key = self.names[word]
    if not key then return false end
    self.preview = key
  end
  self:Refresh(true)
  return true
end

MOTA.ApplySkin("UNREGISTERED") -- the default until the player is known

MOTA:On("PLAYER_LOGIN", function()
  Skin:Refresh()
end)

-- The guild rank is known once the guild is: choose for this session.
MOTA:Listen("GUILD_READY", function()
  Skin:Refresh()
  Skin.settled = true
end)
