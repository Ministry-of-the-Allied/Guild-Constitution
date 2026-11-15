-- Ministry of the Allied: party quest markers over NPCs (ADDON_SPEC.md, section 10.18).
-- The Crown marks an NPC as giving a quest for a party; the members of that party
-- see a quest marker over the NPC's name (a "!" for a quest, a "?" for a hand-in, drawn
-- like the game's own but in the party's colours) and, from a distance, a compass
-- arrow that points the way. UI/NPCMarkers.lua draws; this file
-- keeps the facts: which NPC, which party, where it stands.
--
-- Two records in the book (section 7), written by the Crown alone:
--   marker.set    { npc, p, map, x, y, name, q }   this NPC carries a quest for party p
--                  npc  the creature's ID, the number inside its GUID (the same for every copy of it)
--                  p    "sh" (Silverhand), "ex" (the Exchange) or "all" (everyone: a regular quest from
--                       the Crown, so it wears the Crown's colours on every screen)
--                  map, x, y  where the NPC stands, as the Crown stood beside it (for the far arrow)
--                  name the NPC's name, for the arrow's label
--                  q    "in": a quest to hand in here (a "?"); left out: a quest to pick up (a "!")
--                  g    the spawn part of the NPC's GUID (its seventh part): which copy of an NPC
--                       that has many (a Stormwind Guard) is meant. Left out by older records.
--   marker.clear  { npc }                       take the mark off
-- The newest record for an NPC wins. Nothing else is stored or sent.
--
-- Also here: a local test mark on your own target (/mota marker test), which is
-- never written to the book or sent to anyone.

local _, MOTA = ...
local Markers = {}
MOTA.Markers = Markers

Markers.CODES = { sh = "Silverhand", ex = "the Azeroth Exchange", all = "everyone" }
Markers.MAX_NPC = 99999999
Markers.MAX = 60 -- a sanity limit on marked NPCs

Markers.test = {} -- npc -> { p, skin, name, map, x, y }: marks for trying the look, on this screen only

local function secret(v)
  return issecretvalue and issecretvalue(v) or false
end

local function str(v, max) return type(v) == "string" and v ~= "" and #v <= max end

---------------------------------------------------------------------------
-- The settings
---------------------------------------------------------------------------

function Markers:Showing()
  return MOTA.db == nil or MOTA.db.settings.markerShow ~= false
end

-- How a far NPC is shown: "arrow" (a compass arrow round the middle of the screen),
-- "strip" (pips along a compass strip at the top), "both" or "off".
function Markers:Far()
  local v = MOTA.db and MOTA.db.settings.markerFar
  if v == "strip" or v == "both" or v == "off" then return v end
  return "arrow"
end

---------------------------------------------------------------------------
-- The records
---------------------------------------------------------------------------

local function crown(author) return MOTA:IsCrown(author) end

MOTA.Book.rules["marker.set"] = function(a, rec)
  local d = rec and rec.d or {}
  if not crown(a) then return false end
  if type(d.npc) ~= "number" or d.npc ~= math.floor(d.npc) or d.npc < 1 or d.npc > Markers.MAX_NPC then return false end
  if not Markers.CODES[d.p] then return false end
  if type(d.map) ~= "number" or d.map ~= math.floor(d.map) or d.map <= 0 then return false end
  if type(d.x) ~= "number" or type(d.y) ~= "number" or d.x < 0 or d.x > 1 or d.y < 0 or d.y > 1 or (d.x == 0 and d.y == 0) then return false end
  if d.name ~= nil and not str(d.name, 40) then return false end
  if d.q ~= nil and d.q ~= "in" then return false end
  if d.g ~= nil and not (type(d.g) == "string" and #d.g >= 1 and #d.g <= 16 and d.g:match("^%x+$")) then return false end
  return true
end
MOTA.Book.rules["marker.clear"] = function(a, rec)
  local d = rec and rec.d or {}
  return crown(a) and type(d.npc) == "number" and d.npc == math.floor(d.npc) and d.npc >= 1 and d.npc <= Markers.MAX_NPC
end

local cache
local function build()
  local out = {}
  local list = MOTA.Book:Latest()
  for i = #list, 1, -1 do -- oldest first, so the newest record for an NPC wins
    local r = list[i]
    local d = r.d or {}
    if r.k == "marker.set" and MOTA.Book.rules["marker.set"](r.a, r) and MOTA:IsCrown(r.a) then
      out[d.npc] = { npc = d.npc, p = d.p, map = d.map, x = d.x, y = d.y, name = d.name, q = d.q, g = d.g, by = r.a, t = r.t }
    elseif r.k == "marker.clear" and MOTA:IsCrown(r.a) and type(d.npc) == "number" then
      out[d.npc] = nil
    end
  end
  return out
end

local function get()
  if not cache then cache = build() end
  return cache
end

MOTA:Listen("RECORD_ADDED", function(self, rec)
  if rec.k == "marker.set" or rec.k == "marker.clear" then
    cache = nil
    self:Fire("MARKERS_CHANGED")
  end
end)
MOTA:Listen("GUILD_READY", function() cache = nil MOTA:Fire("MARKERS_CHANGED") end)
MOTA:Listen("ROSTER_UPDATED", function() cache = nil MOTA:Fire("MARKERS_CHANGED") end)
MOTA:Listen("PARTY_CHANGED", function() MOTA:Fire("MARKERS_CHANGED") end)

---------------------------------------------------------------------------
-- Who sees which marker
---------------------------------------------------------------------------

local function myParty()
  return MOTA.Party and MOTA.me and MOTA.Party:Of(MOTA.me) or nil
end

-- May I see this marker? The Crown sees them all (to check them); a member sees
-- their own party's and those for everyone; a citizen with no party sees only
-- those for everyone.
function Markers:Visible(m)
  if m.test then return true end
  if m.p == "all" then return true end
  if MOTA.me and MOTA:IsCrown(MOTA.me) then return true end
  return m.p == myParty()
end

-- The marker for a creature ID, if there is one and I may see it.
function Markers:For(npc)
  if not npc then return nil end
  local m = self.test[npc]
  if m then return m end
  m = get()[npc]
  if m and self:Visible(m) then return m end
  return nil
end

-- Every marker I may see, nearest-written first by NPC ID so a redraw never shuffles them.
function Markers:List()
  local out = {}
  for npc, m in pairs(self.test) do out[#out + 1] = m end
  for npc, m in pairs(get()) do
    if not self.test[npc] and self:Visible(m) then out[#out + 1] = m end
  end
  table.sort(out, function(a, b) return a.npc < b.npc end)
  return out
end

-- Every marker in the book, whoever may see it (the Crown's list).
function Markers:All()
  local out = {}
  for _, m in pairs(get()) do out[#out + 1] = m end
  table.sort(out, function(a, b) return a.npc < b.npc end)
  return out
end

---------------------------------------------------------------------------
-- NPCs and their IDs
---------------------------------------------------------------------------

-- Creature IDs seen on two nameplates at once: an NPC with many copies (guards,
-- vendors in every town), so only the copy marked counts (Markers:ForUnit). Kept
-- in the saved variables (MOTADB.npcMany), so it is known from the start next time.
local function many()
  if MOTA.db then
    MOTA.db.npcMany = MOTA.db.npcMany or {}
    return MOTA.db.npcMany
  end
  Markers.manyLocal = Markers.manyLocal or {}
  return Markers.manyLocal
end
function Markers:Many(npc) return many()[npc] == true end
function Markers:SeenMany(npc) many()[npc] = true end

-- The creature ID inside a GUID ("Creature-0-1465-0-2105-1976-00003B2D40"): the
-- sixth part. nil for a player, a pet, an object or anything unreadable (a GUID
-- the game keeps secret is never read).
function Markers:NpcId(guid)
  if secret(guid) or type(guid) ~= "string" then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
  id = tonumber(id)
  if not id or id < 1 or id > self.MAX_NPC then return nil end
  return id
end

-- The spawn part of a creature's GUID (its seventh part, "00003B2D40"): which copy
-- this is. nil when unreadable.
function Markers:SpawnOf(guid)
  if secret(guid) or type(guid) ~= "string" then return nil end
  local spawn = select(7, strsplit("-", guid))
  if type(spawn) ~= "string" or not spawn:match("^%x+$") or #spawn > 16 then return nil end
  return spawn
end

-- The marker for the NPC on a nameplate, if this copy is the one marked (Max, 12 Nov:
-- marking one Stormwind Guard marked them all). A creature ID is the same for every
-- copy, so the mark also keeps which copy (g). That copy matches; another copy of an
-- NPC known to have many does not. An NPC never seen twice at once is taken as the
-- only one (its spawn part changes when the server restarts or it respawns, and the
-- mark should still find it then).
function Markers:ForUnit(npc, guid)
  local m = self:For(npc)
  if not m or not m.g then return m end
  local spawn = self:SpawnOf(guid)
  if spawn == m.g then return m end
  if self:Many(npc) then return nil end
  return m
end

-- The NPC I am targeting: its ID and name (and the spawn part of its GUID, the
-- third answer), or nil and why not.
function Markers:Target()
  if not UnitExists or not UnitExists("target") then return nil, "Target an NPC first." end
  if UnitIsPlayer and UnitIsPlayer("target") then return nil, "That is a player, not an NPC." end
  local ok, guid = pcall(UnitGUID, "target")
  local npc = ok and self:NpcId(guid)
  if not npc then return nil, "That isn't an NPC the add-on can mark." end
  local name = UnitName and UnitName("target")
  if secret(name) or type(name) ~= "string" then name = nil end
  return npc, name, self:SpawnOf(guid)
end

---------------------------------------------------------------------------
-- Writing (the Crown) and trying (anyone)
---------------------------------------------------------------------------

-- Marks the NPC I'm targeting for party p ("sh", "ex" or "all"), with a "!" or,
-- when q is "in", a "?" (a quest to hand in). The place is where I stand: stand
-- beside the NPC.
function Markers:Add(p, q)
  if not (MOTA.me and MOTA:IsCrown(MOTA.me)) then return nil, "Only the Crown can mark an NPC." end
  if not self.CODES[p] then return nil, "Say which party: sh, ex or all." end
  if q ~= nil and q ~= "in" then return nil, "Add ? (or in) for a quest to hand in, or nothing for a new quest." end
  local npc, name, spawn = self:Target()
  if not npc then return nil, name end
  local map, x, y
  if MOTA.Dots then map, x, y = MOTA.Dots:Here() end
  if not map then return nil, "The game won't say where you are here (an instance, or a map with no position). Stand outside, beside the NPC." end
  local total = 0
  for _ in pairs(get()) do total = total + 1 end
  if total >= self.MAX and not get()[npc] then return nil, "That is as many marked NPCs as the add-on keeps (" .. self.MAX .. ")." end
  local rec, why = MOTA.Book:Write("marker.set", { npc = npc, p = p, map = map,
    x = tonumber(("%.4f"):format(x)), y = tonumber(("%.4f"):format(y)), name = name and name:sub(1, 40) or nil, q = q, g = spawn })
  if not rec then return nil, why end
  return rec, name or ("NPC " .. npc)
end

function Markers:Clear(npc)
  if not (MOTA.me and MOTA:IsCrown(MOTA.me)) then return nil, "Only the Crown can take a mark off." end
  if not npc then
    local name
    npc, name = self:Target()
    if not npc then return nil, name end
  end
  if not get()[npc] then return nil, "NPC " .. npc .. " isn't marked." end
  return MOTA.Book:Write("marker.clear", { npc = npc })
end

-- A look at the marker on my own screen, on the NPC I'm targeting: "sh", "ex",
-- "all" (the Crown's colours) or one of the four looks: "crown", "silverhand",
-- "exchange", "ministry"; add "?" (or "in") for the hand-in marker. Never written or sent.
local LOOKS = { crown = "CROWN", silverhand = "SILVERHAND", exchange = "AZEROTH_EXCHANGE", ministry = "UNREGISTERED" }
-- Is a test mark showing now?
function Markers:Testing() return next(self.test) ~= nil end

function Markers:Test(word)
  word = (word or ""):lower()
  if word == "off" or word == "clear" then
    -- kept, so "on" brings the same marks back without a target (Max, 12 Nov: to flick them on and off)
    if next(self.test) then self.lastTest = self.test end
    self.test = {}
    MOTA:Fire("MARKERS_CHANGED")
    return true, "off"
  end
  if word == "on" then
    if not self.lastTest then return nil, "No test mark to bring back yet: target an NPC and try /mota marker test crown." end
    self.test = {}
    for npc, m in pairs(self.lastTest) do self.test[npc] = m end
    MOTA:Fire("MARKERS_CHANGED")
    return true, "on"
  end
  local q
  local a, b = word:match("^(%S*)%s*(%S*)$")
  if b == "?" or b == "in" then word, q = a, "in" elseif a == "?" and b == "" then word, q = "", "in" end
  local npc, name, spawn = self:Target()
  if not npc then return nil, name end
  local m = { npc = npc, test = true, name = name, q = q, g = spawn }
  if word == "" or word == "all" then
    m.p = "all"
  elseif word == "sh" or word == "silverhand" then
    m.p = "sh"
  elseif word == "ex" or word == "exchange" then
    m.p = "ex"
  elseif LOOKS[word] then
    m.p, m.skin = "all", LOOKS[word]
  else
    return nil, "Try: sh, ex, crown, silverhand, exchange, ministry (add ? for the hand-in marker), off, or on."
  end
  -- the arrow needs somewhere to point: where I stand now
  local map, x, y
  if MOTA.Dots then map, x, y = MOTA.Dots:Here() end
  m.map, m.x, m.y = map, x, y
  self.test[npc] = m
  self.lastTest = nil
  MOTA:Fire("MARKERS_CHANGED")
  return true, name or ("NPC " .. npc)
end
