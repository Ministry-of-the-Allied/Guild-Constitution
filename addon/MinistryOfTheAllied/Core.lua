-- Ministry of the Allied: the core.
-- One shared table (MOTA) that every file of the add-on adds to, the event
-- dispatcher, the saved data and the chat helpers. See ADDON_SPEC.md and
-- CODING_BRIEF.md.

local ADDON_NAME, MOTA = ...
_G.MinistryOfTheAllied = MOTA -- reachable with /dump MinistryOfTheAllied while testing

MOTA.NAME = ADDON_NAME
MOTA.VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "0.0.0"
MOTA.PROTOCOL = 2             -- bump whenever the message format changes (2: AceComm, packed records)
MOTA.PREFIX = "MOTA"          -- the hidden add-on message prefix (ADDON_SPEC.md, section 7.5)

-- Counters for /mota sync, kept for this session only.
MOTA.stats = { sent = 0, failed = 0, received = 0, ignored = 0, conflicts = 0 }

---------------------------------------------------------------------------
-- Chat output, in the canvas colours (design/canvas-source/ministry.css)
---------------------------------------------------------------------------

MOTA.colors = {
  gold = "C9A24A",
  leaf = "F3D98A",
  sky = "B9C9EE",
  crimson = "E0705C",
  grey = "9A9A9A",
}

function MOTA:Color(key, text)
  return "|cff" .. (self.colors[key] or key) .. tostring(text) .. "|r"
end

function MOTA:Print(...)
  local msg = strjoin(" ", tostringall(...))
  DEFAULT_CHAT_FRAME:AddMessage(self:Color("gold", "Ministry") .. self:Color("sky", " · ") .. msg)
end

function MOTA:Debug(...)
  if self.db and self.db.settings.debug then
    self:Print(self:Color("grey", "[debug] " .. strjoin(" ", tostringall(...))))
  end
end

---------------------------------------------------------------------------
-- Events: any file can listen with MOTA:On("EVENT", function(self, event, ...) end)
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

-- One failing handler must not stop the others, so each runs protected and
-- any error goes to the game's normal error display.
local function safeCall(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then geterrorhandler()(err) end
end

function MOTA:On(event, fn)
  if not eventHandlers[event] then
    eventHandlers[event] = {}
    eventFrame:RegisterEvent(event)
  end
  table.insert(eventHandlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
  for _, fn in ipairs(eventHandlers[event]) do
    safeCall(fn, MOTA, event, ...)
  end
end)

-- The add-on's own signals between files, such as "RECORD_ADDED".
local listeners = {}

function MOTA:Listen(name, fn)
  listeners[name] = listeners[name] or {}
  table.insert(listeners[name], fn)
end

function MOTA:Fire(name, ...)
  for _, fn in ipairs(listeners[name] or {}) do
    safeCall(fn, self, ...)
  end
end

---------------------------------------------------------------------------
-- Names, times and versions
---------------------------------------------------------------------------

-- This character's realm, with spaces and dashes taken out. The game can
-- report no realm for a moment around login, so it falls back to the realm's
-- display name, and returns "" if neither is known yet.
-- Once the guild roster has loaded, the realm is taken from this character's
-- own roster entry (LearnMe), because Forever writes it there and in add-on
-- message senders in a form of its own (e.g. "CAMWOWEU5Realm7PvE").
function MOTA:MyRealm()
  if self.homeRealm then return self.homeRealm end
  local realm = GetNormalizedRealmName and GetNormalizedRealmName()
  if (not realm or realm == "") and GetRealmName then
    realm = (GetRealmName() or ""):gsub("[%s%-]", "")
  end
  return realm or ""
end

-- Always "Name-Realm", the form the game uses for add-on message senders.
function MOTA:FullName(name, realm)
  if not name or name == "" then return nil end
  if name:find("-", 1, true) then return name end
  if realm and realm ~= "" then
    realm = realm:gsub("[%s%-]", "")
  else
    realm = self:MyRealm()
  end
  return name .. "-" .. realm
end

-- Works out this character's own full name once the realm is known.
function MOTA:SetMe()
  local name = UnitName("player")
  local realm = self:MyRealm()
  if name and realm ~= "" then self.me = name .. "-" .. realm end
end

-- Called by Roster.lua with this character's own name exactly as the guild
-- roster writes it (found by the character's unique ID), which is the form
-- add-on messages arrive in.
function MOTA:LearnMe(fullName)
  if not fullName or fullName == self.me then return end
  self:Debug("own name from the roster:", fullName, "(was", tostring(self.me) .. ")")
  self.me = fullName
  self.homeRealm = fullName:match("%-(.+)$")
end

-- True if a sender's name is this character's own, in any of the forms the
-- game uses: "Name" for the player's own realm, or "Name-Realm".
function MOTA:IsMe(name)
  if not name then return false end
  local mine = UnitName("player")
  return name == self.me or name == mine or Ambiguate(name, "none") == mine
end

-- A name for display: the realm is dropped when it's the guild's own.
function MOTA:Short(fullName)
  if not fullName then return "?" end
  local realm = self:MyRealm()
  if realm ~= "" and fullName:sub(-(#realm + 1)) == "-" .. realm then
    return fullName:sub(1, -(#realm + 2))
  end
  return Ambiguate(fullName, "guild")
end

function MOTA:Ago(t)
  if not t then return "never" end
  local s = GetServerTime() - t
  if s < 60 then return "moments ago" end
  if s < 3600 then return math.floor(s / 60) .. " min ago" end
  if s < 86400 then return math.floor(s / 3600) .. " h ago" end
  local d = math.floor(s / 86400)
  return d .. (d == 1 and " day ago" or " days ago")
end

-- Returns -1, 0 or 1 for "1.2.3"-style version strings.
function MOTA:CompareVersions(a, b)
  local pa, pb = { strsplit(".", a or "0") }, { strsplit(".", b or "0") }
  for i = 1, math.max(#pa, #pb) do
    local x, y = tonumber(pa[i]) or 0, tonumber(pb[i]) or 0
    if x ~= y then return x < y and -1 or 1 end
  end
  return 0
end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------

-- Fills in any missing keys of t from d, without touching what is there.
function MOTA:Defaults(t, d)
  for k, v in pairs(d) do
    if t[k] == nil then
      t[k] = type(v) == "table" and CopyTable(v) or v
    elseif type(v) == "table" and type(t[k]) == "table" then
      self:Defaults(t[k], v)
    end
  end
  return t
end

MOTA:On("ADDON_LOADED", function(self, _, name)
  if name ~= ADDON_NAME then return end
  -- Saved account-wide, so alts on the same account share one book (ADDON_SPEC.md, section 7.2).
  MOTADB = MOTADB or {}
  self.db = self:Defaults(MOTADB, {
    schema = 1,
    -- The settings panel's choices (UI/Settings.lua), as the Extras board sets them.
    settings = {
      debug = false,
      herald = true,       -- herald pop-ups
      fanfare = true,      -- a fanfare with each herald
      fanfareSound = nil,  -- which one (/mota fanfare); nil means the first the game has
      glow = true,         -- district glow (comes with the Districts page)
      cards = false,       -- citizen cards (come later)
      heraldSize = "full", -- "full" (Royal) or "small" (Modest)
    },
    guilds = {},  -- one book per guild, see CheckGuild
    window = {},  -- where the window was left, its size and page (UI/MainWindow.lua)
    minimap = { angle = 200, hide = false }, -- the minimap seal (UI/Minimap.lua)
  })
end)

-- Each guild gets its own book, keyed by guild name and realm, so a character
-- in another guild never mixes records with the Ministry's.
function MOTA:GuildKey()
  if not IsInGuild() then return nil end
  local guildName, _, _, guildRealm = GetGuildInfo("player")
  if not guildName then return nil end -- not known yet straight after login
  if guildRealm and guildRealm ~= "" then
    guildRealm = guildRealm:gsub("[%s%-]", "")
  else
    guildRealm = GetNormalizedRealmName() or ""
  end
  return guildName .. "-" .. guildRealm
end

-- Called whenever the guild might have changed. Fires GUILD_READY once the
-- guild is known, and GUILD_LOST if the character leaves it.
function MOTA:CheckGuild()
  if not self.me then self:SetMe() end
  if not self.me and not self.meRetry then
    -- The realm isn't known yet: try again in a second.
    self.meRetry = true
    C_Timer.After(1, function()
      self.meRetry = nil
      self:CheckGuild()
    end)
  end
  if not self.db or not self.me then return end
  local key = self:GuildKey()
  if key == self.guildKey then return end
  self.guildKey = key
  if key then
    self.db.guilds[key] = self:Defaults(self.db.guilds[key] or {}, {
      records = {},  -- [author] = { [number] = record }
      tops = {},     -- [author] = highest record number held
      reserved = {}, -- [author] = highest number a guild member said they hold (see Hello.lua)
      peers = {},    -- [name] = what we last heard from their add-on
    })
    self.guild = self.db.guilds[key]
    self:Fire("GUILD_READY", key)
  else
    self.guild = nil
    self:Fire("GUILD_LOST")
  end
end

MOTA:On("PLAYER_LOGIN", function(self)
  self:SetMe() -- if the realm isn't known yet, CheckGuild tries again later
  if IsInGuild() then C_GuildInfo.GuildRoster() end -- ask the server for the roster
  self:CheckGuild()
end)

MOTA:On("PLAYER_ENTERING_WORLD", function(self)
  self:CheckGuild()
end)

MOTA:On("PLAYER_GUILD_UPDATE", function(self)
  self:CheckGuild()
end)
