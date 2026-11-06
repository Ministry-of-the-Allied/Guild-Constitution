-- Ministry of the Allied: the core.
-- One shared table (MotA) that every file of the add-on adds to, the event
-- dispatcher, the saved data and the chat helpers. See ADDON_SPEC.md and
-- CODING_BRIEF.md.

local ADDON_NAME, MotA = ...
_G.MinistryOfTheAllied = MotA -- reachable with /dump MinistryOfTheAllied while testing

MotA.NAME = ADDON_NAME
MotA.VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "0.0.0"
MotA.PROTOCOL = 1             -- bump whenever the message format changes
MotA.PREFIX = "MotA"          -- the hidden add-on message prefix (ADDON_SPEC.md, section 7.5)
MotA.CROWN_RANK = "The Crown" -- the guild rank that makes a character the Crown (ADDON_SPEC.md, section 4)

-- Counters for /mota sync, kept for this session only.
MotA.stats = { sent = 0, failed = 0, received = 0, ignored = 0, conflicts = 0 }

---------------------------------------------------------------------------
-- Chat output, in the canvas colours (design/canvas-source/ministry.css)
---------------------------------------------------------------------------

MotA.colors = {
  gold = "C9A24A",
  leaf = "F3D98A",
  sky = "B9C9EE",
  crimson = "E0705C",
  grey = "9A9A9A",
}

function MotA:Color(key, text)
  return "|cff" .. (self.colors[key] or key) .. tostring(text) .. "|r"
end

function MotA:Print(...)
  local msg = strjoin(" ", tostringall(...))
  DEFAULT_CHAT_FRAME:AddMessage(self:Color("gold", "Ministry") .. self:Color("sky", " · ") .. msg)
end

function MotA:Debug(...)
  if self.db and self.db.settings.debug then
    self:Print(self:Color("grey", "[debug] " .. strjoin(" ", tostringall(...))))
  end
end

---------------------------------------------------------------------------
-- Events: any file can listen with MotA:On("EVENT", function(self, event, ...) end)
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

-- One failing handler must not stop the others, so each runs protected and
-- any error goes to the game's normal error display.
local function safeCall(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then geterrorhandler()(err) end
end

function MotA:On(event, fn)
  if not eventHandlers[event] then
    eventHandlers[event] = {}
    eventFrame:RegisterEvent(event)
  end
  table.insert(eventHandlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
  for _, fn in ipairs(eventHandlers[event]) do
    safeCall(fn, MotA, event, ...)
  end
end)

-- The add-on's own signals between files, such as "RECORD_ADDED".
local listeners = {}

function MotA:Listen(name, fn)
  listeners[name] = listeners[name] or {}
  table.insert(listeners[name], fn)
end

function MotA:Fire(name, ...)
  for _, fn in ipairs(listeners[name] or {}) do
    safeCall(fn, self, ...)
  end
end

---------------------------------------------------------------------------
-- Names, times and versions
---------------------------------------------------------------------------

-- Always "Name-Realm", the form the game uses for add-on message senders.
function MotA:FullName(name, realm)
  if not name or name == "" then return nil end
  if name:find("-", 1, true) then return name end
  if realm and realm ~= "" then
    realm = realm:gsub("[%s%-]", "")
  else
    realm = GetNormalizedRealmName() or ""
  end
  return name .. "-" .. realm
end

-- A name for display: the realm is dropped when it isn't needed.
function MotA:Short(fullName)
  return fullName and Ambiguate(fullName, "guild") or "?"
end

function MotA:Ago(t)
  if not t then return "never" end
  local s = GetServerTime() - t
  if s < 60 then return "moments ago" end
  if s < 3600 then return math.floor(s / 60) .. " min ago" end
  if s < 86400 then return math.floor(s / 3600) .. " h ago" end
  local d = math.floor(s / 86400)
  return d .. (d == 1 and " day ago" or " days ago")
end

-- Returns -1, 0 or 1 for "1.2.3"-style version strings.
function MotA:CompareVersions(a, b)
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
function MotA:Defaults(t, d)
  for k, v in pairs(d) do
    if t[k] == nil then
      t[k] = type(v) == "table" and CopyTable(v) or v
    elseif type(v) == "table" and type(t[k]) == "table" then
      self:Defaults(t[k], v)
    end
  end
  return t
end

MotA:On("ADDON_LOADED", function(self, _, name)
  if name ~= ADDON_NAME then return end
  -- Saved account-wide, so alts on the same account share one book (ADDON_SPEC.md, section 7.2).
  MinistryOfTheAlliedDB = MinistryOfTheAlliedDB or {}
  self.db = self:Defaults(MinistryOfTheAlliedDB, {
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
    window = {},  -- where the window was left, its size and page (UI/Window.lua)
    minimap = { angle = 200, hide = false }, -- the minimap seal (UI/Minimap.lua)
  })
end)

-- Each guild gets its own book, keyed by guild name and realm, so a character
-- in another guild never mixes records with the Ministry's.
function MotA:GuildKey()
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
function MotA:CheckGuild()
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

MotA:On("PLAYER_LOGIN", function(self)
  self.me = self:FullName(UnitName("player"))
  if IsInGuild() then C_GuildInfo.GuildRoster() end -- ask the server for the roster
  self:CheckGuild()
end)

MotA:On("PLAYER_GUILD_UPDATE", function(self)
  self:CheckGuild()
end)
