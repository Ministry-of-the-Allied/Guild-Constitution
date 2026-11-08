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

-- Players are known by their name alone ("Kíng Sinnclair"). Forever adds a
-- realm tag to names in the roster and on add-on messages
-- ("Kíng Sinnclair-CAMWOWEU5Realm7PvE"), but the tag differs from one
-- player's screen to another's (Realm7 on one, Realm1 on the next), and the
-- server refuses a whisper addressed with it. Character names can't contain
-- a dash, and are unique within the guild.
function MOTA:Bare(name)
  if type(name) ~= "string" then return nil end
  name = name:match("^([^%-]*)")
  if name == "" then return nil end
  return name
end

-- The name every part of the add-on uses for a player (see Bare). Kept under
-- this name because the roster, messages and whispers all go through it.
function MOTA:FullName(name)
  return self:Bare(name)
end

-- A ballot's ID is its author and number, "Name#12"; an ID written before
-- names lost their tag ("Name-Realm#12") becomes the same.
function MOTA:BareId(id)
  if type(id) ~= "string" then return id end
  return (id:gsub("%-[^#]*#", "#"))
end

-- Works out this character's own name. Forever's UnitName gives only the first
-- part ("Kíng"), while the roster and message senders say "Kíng Atwood", and
-- two players can share that first part. So the short name only stands in until
-- LearnMe finds the real one, which is remembered for the next login.
function MOTA:SetMe()
  if self.meLearned then return end
  local saved = self.db and self.db.myNames and self.db.myNames[UnitGUID("player") or ""]
  if saved then
    self.me, self.meLearned = saved, true
    return
  end
  local name = UnitName("player")
  if name and name ~= "" then self.me = self:Bare(name) end
end

-- Called with this character's name as the guild knows it: from its roster
-- entry (by unique ID), or from its own hello coming back (Comm.lua).
function MOTA:LearnMe(name)
  name = self:Bare(name)
  if not name then return end
  self.meLearned = true
  if name == self.me then return end
  self:Debug("own name:", name, "(was", tostring(self.me) .. ")")
  self.me = name
  if self.db then
    self.db.myNames = self.db.myNames or {}
    self.db.myNames[UnitGUID("player") or ""] = name
  end
  if self.guild then self:MoveMyBook(self.guild) end
  self:Fire("ME_LEARNED", name)
end

-- True if a name is this character's own, with or without a realm tag.
function MOTA:IsMe(name)
  name = self:Bare(name)
  if not name then return false end
  return name == self.me or name == self:Bare(UnitName("player"))
end

-- A name for display.
function MOTA:Short(name)
  return self:Bare(name) or "?"
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
      windowSkin = "party", -- "party" (your party's or the Crown's) or "ministry" (UI/Skin.lua)
      mapSkin = "party",    -- the world map's dress (UI/WorldMapSkin.lua): "party" (as the window),
                            -- "ministry" or "plain". On from the start; a choice is kept until changed by hand.
      voice = true,        -- the Charter narration on first login (/mota voice off)
    },
    guilds = {},  -- one book per guild, see CheckGuild
    window = {},  -- where the window was left, its size and page (UI/MainWindow.lua)
    onboarding = {}, -- [character ID] = how far the Charter narration has got (Voice.lua)
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

-- Saved data from before players were known by their name alone (MOTA:Bare)
-- holds names with a realm tag, sometimes the same player under two tags.
-- Done once per guild book: each name loses its tag and the entries merge.
local function biggest(t, k, v)
  if type(v) == "number" and v > (t[k] or 0) then t[k] = v end
end

function MOTA:BareGuildBook(g)
  if g.names == 2 then return end
  local records = {}
  for author, list in pairs(g.records or {}) do
    local a = self:Bare(author) or author
    records[a] = records[a] or {}
    for n, r in pairs(list) do
      if type(r) == "table" and type(r.d) == "table" then
        if type(r.d.b) == "string" then r.d.b = self:BareId(r.d.b) end
        if type(r.d.v) == "string" then r.d.v = self:Bare(r.d.v) end
      end
      local have = records[a][n]
      if not have or (type(r) == "table" and r.t and have.t and r.t < have.t) then records[a][n] = r end
    end
  end
  g.records = records
  for _, key in ipairs({ "tops", "reserved" }) do
    local merged = {}
    for name, n in pairs(g[key] or {}) do biggest(merged, self:Bare(name) or name, n) end
    g[key] = merged
  end
  local peers = {}
  for name, p in pairs(g.peers or {}) do
    local bare = self:Bare(name)
    local have = bare and peers[bare]
    if bare and (not have or (p.seen or 0) > (have.seen or 0)) then peers[bare] = p end
  end
  g.peers = peers
  if g.myBallots then
    local mine = {}
    for name, list in pairs(g.myBallots) do
      local bare = self:Bare(name) or name
      mine[bare] = mine[bare] or {}
      for id, e in pairs(list) do mine[bare][self:BareId(id)] = e end
    end
    g.myBallots = mine
  end
  g.names = 2
end

-- Moves what this copy saved under the short name to the real one. Nothing else
-- can be under the short name: a record is only accepted if its author matches
-- its sender, and senders always have the full name.
function MOTA:MoveMyBook(g)
  local short, me = self:Bare(UnitName("player")), self.me
  if not short or not me or short == me then return end
  local function swapId(id)
    if type(id) == "string" and id:sub(1, #short + 1) == short .. "#" then return me .. id:sub(#short + 1) end
    return id
  end
  for _, list in pairs(g.records or {}) do
    for _, r in pairs(list) do
      if type(r) == "table" and type(r.d) == "table" then
        if r.d.v == short then r.d.v = me end
        r.d.b = swapId(r.d.b)
      end
    end
  end
  local old = g.records and g.records[short]
  if old then
    g.records[me] = g.records[me] or {}
    for n, r in pairs(old) do
      if not g.records[me][n] then g.records[me][n] = r end
    end
    g.records[short] = nil
  end
  for _, key in ipairs({ "tops", "reserved" }) do
    if g[key] and g[key][short] then
      biggest(g[key], me, g[key][short])
      g[key][short] = nil
    end
  end
  if g.peers then g.peers[me], g.peers[short] = nil, nil end
  local ballots = g.myBallots and g.myBallots[short]
  if ballots then
    g.myBallots[me] = g.myBallots[me] or {}
    for id, e in pairs(ballots) do g.myBallots[me][swapId(id)] = e end
    g.myBallots[short] = nil
  end
end

-- The same for the Kings' running counts, saved for the whole account.
function MOTA:BareTallies()
  if self.db.names == 2 then return end
  local tallies = {}
  for id, t in pairs(self.db.ballotTally or {}) do
    if type(t) == "table" and type(t.counted) == "table" then
      local counted = {}
      for name, v in pairs(t.counted) do counted[self:Bare(name) or name] = v end
      t.counted = counted
    end
    tallies[self:BareId(id)] = t
  end
  if self.db.ballotTally then self.db.ballotTally = tallies end
  self.db.names = 2
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
  -- The game can briefly not know the guild's name around login; that isn't leaving.
  if not key and IsInGuild() then return end
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
    self:BareGuildBook(self.guild)
    self:BareTallies()
    self:MoveMyBook(self.guild)
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
