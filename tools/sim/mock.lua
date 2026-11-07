-- A pretend WoW client: just enough of the game's API for the add-on to run.
-- Globals provided by Python before this runs: PLAYER, REALM, GUILD, ROSTER (list),
-- py_send(prefix, msg, channel, target) -> code, py_print(msg), py_error(msg),
-- py_roster_request(), LOCKDOWN (nil/false/true)

local now = 0
local timers = {}

function GetTime() return now end
-- The realm's clock is shared: CLOCK_START is the pretend world's time when
-- this client started (set by sim.py), so a client that logs in later agrees.
function GetServerTime() return 1793800000 + math.floor((CLOCK_START or 0) + now) end
function time() return GetServerTime() + 3 end

C_Timer = {}
function C_Timer.After(d, fn)
  timers[#timers + 1] = { at = now + d, fn = fn }
end
function C_Timer.NewTicker(d, fn, n)
  local t = { cancelled = false, left = n }
  function t:Cancel() self.cancelled = true end
  local function sched()
    timers[#timers + 1] = { at = now + d, fn = function()
      if t.cancelled then return end
      fn(t)
      if t.left then
        t.left = t.left - 1
        if t.left <= 0 then return end
      end
      if not t.cancelled then sched() end
    end }
  end
  sched()
  return t
end

function mock_advance(dt)
  local target = now + dt
  while true do
    local idx, best
    for i, tm in ipairs(timers) do
      if tm.at <= target and (not best or tm.at < best.at) then idx, best = i, tm end
    end
    if not best then break end
    table.remove(timers, idx)
    now = best.at
    local ok, err = pcall(best.fn)
    if not ok then py_error("timer: " .. tostring(err)) end
  end
  now = target
end

-- frames and events
local frames = {}
function CreateFrame()
  local f = { events = {}, scripts = {} }
  function f:RegisterEvent(e) self.events[e] = true end
  function f:SetScript(name, fn) self.scripts[name] = fn end
  frames[#frames + 1] = f
  return f
end
function mock_fire(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.scripts.OnEvent then
      local ok, err = pcall(f.scripts.OnEvent, f, event, ...)
      if not ok then py_error(event .. ": " .. tostring(err)) end
    end
  end
end

function geterrorhandler() return function(err) py_error(tostring(err)) end end

-- string and table helpers the game adds
function strjoin(sep, ...) return table.concat({ ... }, sep) end
function tostringall(...)
  local t = { ... }
  local n = select("#", ...)
  for i = 1, n do t[i] = tostring(t[i]) end
  return unpack(t, 1, n)
end
function strsplit(delim, str)
  local out, start = {}, 1
  while true do
    local i = string.find(str, delim, start, true)
    if not i then out[#out + 1] = str:sub(start); break end
    out[#out + 1] = str:sub(start, i - 1)
    start = i + 1
  end
  return unpack(out)
end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function CopyTable(t)
  local c = {}
  for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end
  return c
end
function Ambiguate(name) if ODD_REALM then return name end return (name:gsub("%-.*$", "")) end

-- player, guild, roster
-- With REALM_LATE the game knows no realm for the first half second, as can
-- happen around login.
-- With ODD_REALM the game's realm lookup gives a different form from the one
-- in roster names and message senders, and Ambiguate never strips it, as in
-- Forever ("CAMWOWEU5Realm7PvE").
function GetNormalizedRealmName()
  if REALM_LATE and GetTime() < 0.5 then return nil end
  if ODD_REALM then return "Realm7PvE" end
  return REALM
end
function GetRealmName() if REALM_LATE and GetTime() < 0.5 then return nil end return REALM end
function UnitName() return PLAYER end
function UnitGUID() return "Player-" .. PLAYER .. "-" .. REALM end
function IsInGuild() return GUILD ~= nil end
local myRank, myRankIndex = "Citizen", 3
for _, m in ipairs(ROSTER) do
  if m[1]:match("^[^%-]*") == PLAYER then myRank, myRankIndex = m[2], m[3] end
end
function GetGuildInfo() if not GUILD or not ROSTER_READY then return nil end return GUILD, myRank, myRankIndex, nil end
function mock_set_rank(r) myRank = r end
C_GuildInfo = { GuildRoster = function() py_roster_request() end }
function GetNumGuildMembers() return ROSTER_READY and #ROSTER or 0, 0, 0 end
function GetGuildRosterInfo(i)
  local m = ROSTER[i]
  return m[1], m[2], m[3], 60, "Paladin", "Stormwind", "", "", m[4], 0, "PALADIN", 0, 0, false, false, 8, "Player-" .. m[1]
end

C_AddOns = { GetAddOnMetadata = function(_, key) if key == "Version" then return ADDON_VERSION or "0.1.0" end end }

Enum = {
  SendAddonMessageResult = { Success = 0, InvalidPrefix = 1, InvalidMessage = 2, AddonMessageThrottle = 3,
    InvalidChatType = 4, NotInGroup = 5, TargetRequired = 6, InvalidChannel = 7, ChannelThrottle = 8, GeneralError = 9 },
  RegisterAddonMessagePrefixResult = { Success = 0, DuplicatePrefix = 1, InvalidPrefix = 2, MaxPrefixes = 3 },
}
C_ChatInfo = {
  RegisterAddonMessagePrefix = function(p) return 0 end,
  SendAddonMessage = function(prefix, msg, channel, target)
    if #msg > 255 then return 2 end
    return py_send(prefix, msg, channel, target)
  end,
}
if LOCKDOWN ~= nil then C_ChatInfo.InChatMessagingLockdown = function() return LOCKDOWN end end

DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) py_print((msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))) end }
function GetBuildInfo() return "1.60.1", "70790", "Nov 5 2026", 16001 end
WOW_PROJECT_ID = 99
function IsInInstance() return false, "none" end
function InCombatLockdown() return false end
SlashCmdList = {}

-- saved variables, written the way the game writes them
local function ser(v, indent)
  if type(v) == "table" then
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do
      local ks = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
      parts[#parts + 1] = indent .. "  " .. ks .. " = " .. ser(v[k], indent .. "  ")
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
  elseif type(v) == "string" then
    return string.format("%q", v)
  else
    return tostring(v)
  end
end
function mock_saved()
  return "MOTADB = " .. ser(MOTADB, "")
end

function mock_load(path, ns)
  local f = assert(io.open(path, "rb"))
  local src = f:read("*a")
  f:close()
  local chunk, err = loadstring(src, "@" .. path:match("[^/\\]+$"))
  if not chunk then py_error("syntax: " .. err); return end
  local ok, e = pcall(chunk, "MinistryOfTheAllied", ns)
  if not ok then py_error("load: " .. tostring(e)) end
end

-- The Ballot Hall (Milestone 4): last-online times, the realm clock, logging out.
-- ROSTER entries may carry a fifth field: days since that member was last online.
function GetGuildRosterLastOnline(i)
  local m = ROSTER[i]
  if m[4] then return nil end
  local days = m[5] or 1
  return 0, 0, math.floor(days), 0
end
-- The realm clock starts at 8:28 pm.
function GetGameTime()
  local mins = 20 * 60 + 28 + math.floor((GetServerTime() - 1793800000) / 60)
  return math.floor(mins / 60) % 24, mins % 60
end
LOGOUT_CANCELLED = 0
function CancelLogout() LOGOUT_CANCELLED = LOGOUT_CANCELLED + 1 end
StaticPopupDialogs = {}
POPUP_SHOWN = nil
function StaticPopup_Show(which, a1)
  assert(StaticPopupDialogs[which], "no such popup " .. tostring(which))
  POPUP_SHOWN = which
  POPUP_TEXT = StaticPopupDialogs[which].text:format(a1 or "")
  return {}
end
