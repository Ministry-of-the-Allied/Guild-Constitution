-- Ministry of the Allied: the world map skin and other add-ons that dress the
-- map (Batch D5d, D5d2, D5e; Max's answers, 8 and 9 Nov).
--
-- EllesmereUI and ElvUI (route A): when our map skin is on, they are told,
-- for this session only, not to skin the world map. Nothing they have saved
-- changes: EllesmereUI's window style lookup answers "off" for the map alone,
-- and ElvUI's skin loader skips the map's skin alone. Both decide at login,
-- so a change between Plain and a skin takes a /reload for them to follow;
-- until then our skin stays off rather than lie on top of theirs.
--
-- Leatrix Maps' "Use simple map frame" (Max, 9 Nov: ours steps aside): it
-- replaces the map's frame (title, border, location bar), the very parts our
-- skin dresses, so while it is on the map stays Leatrix's and our skin
-- doesn't run. The Settings row says why. Leatrix's other parts (coordinates,
-- icons, zone menus, reveal) work under our skin.
--
-- OpenMap: our frames take no mouse, so its title drag, grips and size
-- slider work as before; the district layer is lifted over its stitched art
-- (UI/WorldMap.lua).

local _, MOTA = ...
local C = {}
MOTA.MapCompat = C

local function loaded(name)
  if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) and true or false end
  return IsAddOnLoaded and IsAddOnLoaded(name) and true or false
end

local function choice()
  return MOTA.db and MOTA.db.settings.mapSkin or "party"
end

-- ElvUI's own world map skin is switched on in its settings.
local function elvSkinsMap()
  local E = type(_G.ElvUI) == "table" and _G.ElvUI[1]
  local b = type(E) == "table" and type(E.private) == "table" and type(E.private.skins) == "table" and E.private.skins.blizzard
  return type(b) == "table" and b.enable and b.worldmap and true or false
end

-- Leatrix Maps' simple map frame is in force this session. (On unless turned
-- off; Leatrix itself locks it off when ElvUI's map skin is on.)
function C:LeatrixSimple()
  if not loaded("Leatrix_Maps") then return false end
  local db = _G.LeaMapsDB
  local v = type(db) == "table" and db.SimpleMapFrame or "On"
  if v ~= "On" then return false end
  if loaded("ElvUI") and elvSkinsMap() then return false end
  return true
end

-- Another add-on that keeps the map its own: our skin doesn't run (a name for the Settings row).
function C:Blocker()
  if self:LeatrixSimple() then return "Leatrix Maps' simple map frame" end
end

-- The add-ons that dress the map unless told not to at login.
local function others()
  local list = {}
  if C.eui then list[#list + 1] = "EllesmereUI" end
  if C.elv and elvSkinsMap() then list[#list + 1] = "ElvUI" end
  return list
end

-- The map skin was turned on or off since login while EllesmereUI or ElvUI is
-- here: they only follow after a /reload.
function C:NeedsReload()
  if self.skipping == nil or #others() == 0 then return false end
  return (choice() ~= "plain") ~= self.skipping
end

-- Whether our skin may dress the map now.
function C:Allowed()
  if self:Blocker() then return false end
  -- turned on after login with EllesmereUI or ElvUI having dressed the map: wait for the /reload
  if self.skipping == false and #others() > 0 then return false end
  return true
end

-- The Settings row's small line, when something holds the skin back.
function C:Note()
  local b = self:Blocker()
  if b then return "Off while " .. b .. " is on" end
  if self:NeedsReload() then return "Type /reload to finish the change" end
end

---------------------------------------------------------------------------
-- Telling EllesmereUI and ElvUI (once, at our ADDON_LOADED: before their
-- skins run at PLAYER_LOGIN)
---------------------------------------------------------------------------

local function wrapEllesmere()
  local E = _G.EllesmereUI
  if C.eui or type(E) ~= "table" or type(E.GetBlizzWindowStyle) ~= "function" then return end
  if not loaded("EllesmereUIBlizzardSkin") then return end
  local orig = E.GetBlizzWindowStyle
  E.GetBlizzWindowStyle = function(winKey, ...)
    if winKey == "worldmap" and C.skipping then return "off" end
    return orig(winKey, ...)
  end
  C.eui = true
end

local function wrapElv()
  local E = type(_G.ElvUI) == "table" and _G.ElvUI[1]
  if C.elv or type(E) ~= "table" or type(E.GetModule) ~= "function" then return end
  local ok, S = pcall(E.GetModule, E, "Skins", true)
  if not ok or type(S) ~= "table" or type(S.LoadSkin) ~= "function" then return end
  local orig = S.LoadSkin
  S.LoadSkin = function(self, info, ...)
    if C.skipping and type(info) == "table" and info.toggle == "worldmap" then return end
    return orig(self, info, ...)
  end
  C.elv = true
end

MOTA:On("ADDON_LOADED", function(_, _, name)
  if name ~= "MinistryOfTheAllied" or C.skipping ~= nil then return end
  -- decided once for the session: with a skin chosen (and nothing holding it back),
  -- EllesmereUI and ElvUI leave the map to us
  C.skipping = choice() ~= "plain" and not C:Blocker()
  wrapEllesmere()
  wrapElv()
end)

MOTA:Listen("MAP_SKIN_CHANGED", function()
  if C:NeedsReload() then
    MOTA:Print(table.concat(others(), " and ") .. " dresses the world map when you log in: type /reload to finish the change.")
  end
end)
