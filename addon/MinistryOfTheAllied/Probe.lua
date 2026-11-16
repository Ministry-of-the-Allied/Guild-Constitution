-- Ministry of the Allied: the probe.
-- Answers the add-on plan's open questions from inside the Forever client:
-- the interface number, whether the game has its own data packer, how add-on
-- messages behave and who the add-on counts as the Crown.
--
-- /mota probe         client facts, printed in chat
-- /mota probe limits  measures the message limits (about 45 hidden guild messages)
-- /mota probe bank    what the game lets us see of the guild bank (open it first)
-- /mota probe map     what the world map is made of (stand in Stormwind City)
-- /mota probe gossip  [nohide|off] can we see a gossip option being picked and open our own page (19.1)
-- /mota probe quest   [nohide|fade|page|button|off] can the game's quest page be hidden so our own could take its place,
--                     and can we add our own entry to the gossip window (19.1)
--
-- Each probe also saves its results in the add-on's saved file (written on logout
-- or /reload), so they can be read straight from
-- WTF\Account\<account>\SavedVariables\MinistryOfTheAllied.lua.

local _, MOTA = ...
local Probe = {}
MOTA.Probe = Probe

local function yesno(v)
  return v and MOTA:Color("leaf", "yes") or MOTA:Color("crimson", "no")
end

local function P(...)
  MOTA:Print(...)
end

function Probe:Report()
  local out = { at = GetServerTime() }

  local version, build, date, toc = GetBuildInfo()
  out.client = { version = version, build = build, date = date, interface = toc, project = WOW_PROJECT_ID }
  P(MOTA:Color("leaf", "Probe") .. ": client " .. tostring(version) .. ", build " .. tostring(build) .. " (" .. tostring(date) .. ")")
  P("Interface number:", MOTA:Color("leaf", toc), "(the TOC's Interface line should list it) · project ID", tostring(WOW_PROJECT_ID))

  -- The game's own packer could stand in for LibSerialize and LibDeflate.
  local E = C_EncodingUtil
  out.packer = { present = E ~= nil }
  if E then
    out.packer.cbor = E.SerializeCBOR ~= nil
    out.packer.compress = E.CompressString ~= nil
    out.packer.base64 = E.EncodeBase64 ~= nil
    local ok, info = pcall(function()
      local sample = { a = "Aldric-Realm", n = 57, t = GetServerTime(), k = "ballot.cast", d = { election = 12, choice = 2 } }
      local cbor = E.SerializeCBOR(sample)
      local packed = E.CompressString(cbor)
      local b64 = E.EncodeBase64(packed)
      local back = E.DeserializeCBOR(E.DecompressString(E.DecodeBase64(b64)))
      local fine = type(back) == "table" and back.n == 57 and back.d and back.d.choice == 2
      return ("a sample record is %d bytes packed, %d compressed, %d as text; round trip %s"):format(
        #cbor, #packed, #b64, fine and "worked" or "FAILED")
    end)
    out.packer.test = ok and info or ("error: " .. tostring(info))
    P("Built-in packer (C_EncodingUtil):", yesno(true), "· pack", yesno(out.packer.cbor), "compress", yesno(out.packer.compress),
      "text", yesno(out.packer.base64))
    P("  " .. out.packer.test)
  else
    P("Built-in packer (C_EncodingUtil):", yesno(false), "· the add-on will need LibSerialize and LibDeflate")
  end

  -- Add-on messages
  local lockdown = C_ChatInfo.InChatMessagingLockdown
  local inInstance, instanceType = IsInInstance()
  out.messages = {
    prefix = MOTA.Comm:EnumName(Enum.RegisterAddonMessagePrefixResult, MOTA.Comm.prefixResult),
    resultCodes = Enum.SendAddonMessageResult ~= nil,
    lockdownCheck = lockdown ~= nil,
    lockedNow = lockdown and lockdown() or false,
    inCombat = InCombatLockdown(),
    instance = inInstance and instanceType or "none",
  }
  P("Message prefix registered:", out.messages.prefix, "· send result codes:", yesno(out.messages.resultCodes))
  P("Messaging lockdown check:", lockdown and ("present, locked now: " .. tostring(out.messages.lockedNow)) or "not in this client",
    "· in combat:", yesno(out.messages.inCombat), "· instance:", out.messages.instance)

  -- The fonts shipped inside the add-on (Fonts.lua)
  for _, name in ipairs({ "heading", "body", "bodyItalic", "who", "whoSmall", "foot" }) do MOTA:Font(name) end
  out.fonts = #MOTA.fontsFailed == 0 and "loaded" or ("fell back to the game's font: " .. table.concat(MOTA.fontsFailed, ", "))
  P("Add-on fonts (Cinzel, EB Garamond):", #MOTA.fontsFailed == 0 and MOTA:Color("leaf", "loaded") or MOTA:Color("crimson", out.fonts))

  -- Guild and the Crown
  local guildName, rankName, rankIndex = GetGuildInfo("player")
  if guildName then
    local crowns = MOTA:CrownMembers()
    out.guild = { name = guildName, rank = rankName, rankIndex = rankIndex, crown = rankName ~= nil and MOTA.CONST.CROWN_RANK_NAMES[rankName] == true, crownMembers = crowns }
    P("Guild:", guildName, "· your rank:", tostring(rankName), "(" .. tostring(rankIndex) .. ")", "· counts as the Crown:", yesno(out.guild.crown))
    local names = {}
    for i, n in ipairs(crowns) do names[i] = MOTA:Short(n) end
    P("On the Crown ranks (\"The King\", \"The Crown\"):", #names > 0 and table.concat(names, ", ") or "nobody the roster shows")
  elseif IsInGuild() then
    out.guild = { inGuild = true, nameKnown = false }
    P("Guild: the game says you're in a guild, but hasn't told the add-on its name yet. Wait a few seconds and try again.")
    MOTA:RequestRoster()
  else
    out.guild = { inGuild = false }
    P("Guild: this character isn't in a guild.")
  end

  out.clockOffset = GetServerTime() - time()
  P("Realm time minus your computer's clock:", out.clockOffset, "seconds")

  MOTA.db.probe = MOTA.db.probe or {}
  MOTA.db.probe.report = out
end

---------------------------------------------------------------------------
-- /mota probe map: what the world map is made of on Forever (Batch D: the
-- district outlines and the map skins). Run it standing in Stormwind City.
-- Only looks. It never changes the map.
---------------------------------------------------------------------------

-- The parts of the map window the skins and the outlines would use (ADDON_SPEC.md 9.6).
local MAP_PARTS = {
  "BorderFrame", "BorderFrame.NineSlice", "BorderFrame.TitleText", "BorderFrame.CloseButton", "BorderFrame.Tutorial",
  "BorderFrame.MaximizeMinimizeFrame", "NavBar", "ScrollContainer", "ScrollContainer.Child", "SidePanelToggle",
  "TitleCanvasSpacerFrame", "QuestLog", "overlayFrames", "dataProviders",
}
local MAP_APIS = { "C_Map.GetBestMapForUnit", "C_Map.GetPlayerMapPosition", "C_Map.GetMapInfo", "C_Map.GetMapWorldSize",
  "C_Map.SetUserWaypoint", "C_Map.CanSetUserWaypointOnMap", "C_Map.ClearUserWaypoint", "C_SuperTrack.SetSuperTrackedUserWaypoint",
  "UiMapPoint.CreateFromCoordinates", "CreateFromMixins", "MapCanvasDataProviderMixin", "MapCanvasPinMixin" }

local function lookup(root, path)
  local v = root
  for key in path:gmatch("[^%.]+") do
    if type(v) ~= "table" then return nil end
    v = v[key]
  end
  return v
end

function Probe:Map()
  local out = { at = GetServerTime() }
  P(MOTA:Color("leaf", "Map probe") .. " (stand in Stormwind City for the district facts)")

  local missing = {}
  for _, name in ipairs(MAP_APIS) do
    if lookup(_G, name) == nil then missing[#missing + 1] = name end
  end
  out.missingApis = missing
  P("Map functions:", #missing == 0 and MOTA:Color("leaf", "all present") or ("missing: " .. table.concat(missing, ", ")))

  local id = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  out.mapID = id
  if id then
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(id)
    out.mapName = info and info.name
    out.parentID = info and info.parentMapID
    P("You are on map", MOTA:Color("leaf", tostring(id)), "(" .. tostring(out.mapName) .. "), inside map", tostring(out.parentID))
    local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(id, "player")
    if pos then
      out.x, out.y = pos.x, pos.y
      P(("Your place on it: %.3f, %.3f (0 to 1 across, 0 to 1 down)"):format(pos.x, pos.y))
    end
    if C_Map.GetMapWorldSize then
      out.worldW, out.worldH = C_Map.GetMapWorldSize(id)
      P("Map size in yards:", tostring(out.worldW), "x", tostring(out.worldH))
    end
    if C_Map.CanSetUserWaypointOnMap then
      out.waypoints = C_Map.CanSetUserWaypointOnMap(id) and true or false
      P("Map pins (Set waypoint) allowed here:", yesno(out.waypoints))
    end
  else
    P("No map for where you stand (try again outdoors in Stormwind City).")
  end

  local wm = WorldMapFrame
  out.worldMap = wm ~= nil
  if not wm then
    P("World map window:", yesno(false))
  else
    local have, lack = {}, {}
    for _, part in ipairs(MAP_PARTS) do
      if lookup(wm, part) ~= nil then have[#have + 1] = part else lack[#lack + 1] = part end
    end
    out.parts, out.missingParts = have, lack
    P("World map parts found:", #have, "of", #MAP_PARTS .. (#lack > 0 and (" · missing: " .. table.concat(lack, ", ")) or ""))
    out.addDataProvider = type(wm.AddDataProvider) == "function"
    P("Can add a map layer (AddDataProvider):", yesno(out.addDataProvider))
    -- The round buttons over the map, by name, for the skins.
    local names = {}
    for _, f in ipairs(wm.overlayFrames or {}) do
      local n = (f.GetDebugName and f:GetDebugName()) or (f.GetName and f:GetName()) or "?"
      names[#names + 1] = n
    end
    out.overlays = names
    if #names > 0 then P("Buttons over the map:", table.concat(names, ", ")) end
    -- Anything else restyling the map (9.6: ours steps back)
    out.elvui = (ElvUI ~= nil)
    if out.elvui then P("ElvUI is loaded: the map skins would step back.") end
  end

  MOTA.db.probe = MOTA.db.probe or {}
  MOTA.db.probe.map = out
  P("Saved. After /reload it's in the add-on's saved file too (probe.map).")
end

---------------------------------------------------------------------------
-- /mota probe gossip: can an add-on see which gossip option a player picked
-- on an NPC and open its own page instead (19.1, the quest engine)?
-- Listens and reads. The only thing it does is try to hide the gossip window
-- right after an option is picked, to learn whether our own frame could take
-- its place. It never picks an option and never closes the conversation.
-- Off until typed; `/mota probe gossip off` stops it. `/mota probe gossip nohide` is the
-- control run: everything the same but we never hide the window, so what the game does to
-- it by itself is seen (some options, like an innkeeper's "Make this inn your home", make
-- the game close it, which would otherwise be credited to our hide).
---------------------------------------------------------------------------

local GOSSIP_EVENTS = { "GOSSIP_SHOW", "GOSSIP_CLOSED", "GOSSIP_CONFIRM",
  "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" }
local GOSSIP_APIS = { "C_GossipInfo.GetOptions", "C_GossipInfo.GetAvailableQuests", "C_GossipInfo.GetActiveQuests",
  "C_GossipInfo.SelectOption", "C_GossipInfo.CloseGossip", "HideUIPanel", "GossipFrame",
  "Enum.PlayerInteractionType" }
local GOSSIP_KEEP = 20 -- how many picks and interactions are kept in the saved summary

local function gossipResults()
  MOTA.db.probe = MOTA.db.probe or {}
  MOTA.db.probe.gossip = MOTA.db.probe.gossip or {}
  local r = MOTA.db.probe.gossip
  r.picks, r.confirms, r.interactions = r.picks or {}, r.confirms or {}, r.interactions or {}
  r.chains = r.chains or {}
  r.control = r.control or {} -- [optionID] = { closedByGame = bool }, kept across runs
  return r
end

local function keep(list, entry)
  list[#list + 1] = entry
  while #list > GOSSIP_KEEP do table.remove(list, 1) end
end

local function safeString(v)
  if v == nil then return nil end
  local ok, s = pcall(tostring, v)
  return ok and s or "?"
end

-- "Creature-0-1465-0-2105-1234-00001A2B3C" gives the NPC ID (1234).
local function npcIDFromGUID(guid)
  if type(guid) ~= "string" then return nil end
  local id = guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)")
  return id and tonumber(id) or nil
end

local function interactionName(kind)
  local e = Enum and Enum.PlayerInteractionType
  if type(e) == "table" then
    for name, v in pairs(e) do
      if v == kind then return name end
    end
  end
  return nil
end

function Probe:GossipRead()
  local out = {}
  local guid, unit
  for _, u in ipairs({ "npc", "target" }) do
    local ok, g = pcall(UnitGUID, u)
    if ok and type(g) == "string" then guid, unit = g, u; break end
  end
  out.guid, out.unit, out.npcID = guid, unit, npcIDFromGUID(guid)
  if unit and UnitName then
    local ok, n = pcall(UnitName, unit)
    out.npcName = ok and safeString(n) or nil
  end

  local G = C_GossipInfo
  out.options, out.available, out.active = {}, {}, {}
  if G and G.GetOptions then
    local ok, list = pcall(G.GetOptions)
    if ok and type(list) == "table" then
      for _, o in ipairs(list) do
        out.options[#out.options + 1] = { id = o.gossipOptionID, name = safeString(o.name), flags = o.flags,
          status = o.status }
      end
    end
  end
  if G and G.GetAvailableQuests then
    local ok, list = pcall(G.GetAvailableQuests)
    if ok and type(list) == "table" then
      for _, q in ipairs(list) do out.available[#out.available + 1] = { id = q.questID, title = safeString(q.title) } end
    end
  end
  if G and G.GetActiveQuests then
    local ok, list = pcall(G.GetActiveQuests)
    if ok and type(list) == "table" then
      for _, q in ipairs(list) do out.active[#out.active + 1] = { id = q.questID, title = safeString(q.title) } end
    end
  end
  return out
end

-- The sequence log: every probe event and pick in order, with GetTime. One chain
-- per conversation: a chain ends at GOSSIP_CLOSED or an interaction-0 hide, and
-- the next GOSSIP_SHOW after that starts a new one (flushing the old one first).
local CHAIN_KEEP = 10
local SAMPLE_AT = { 0.2, 1, 3, 10, 30 } -- seconds after a pick that the window is looked at
local TEN_AT = 4 -- the 10 s sample (the first window is reported then); the 30 s one is a follow-up
local RESHOW_AT = { 1, 3, 10, 30 } -- seconds after a reshown window appears that it is looked at
local RESHOW_TEN = 3
local RESHOW_WITHIN = 3 -- a GOSSIP_SHOW this soon after a pick is the game showing gossip again
local MERGE_WINDOW = 1 -- a game route within this many seconds of a button pick is the same pick

function Probe:GossipFlush()
  local c = self.gossipChain
  if c and not c.printed then
    c.printed = true
    P("  " .. self:GossipChainLine(c))
  end
end

function Probe:GossipStep(text, isShow)
  local r = gossipResults()
  local c = self.gossipChain
  if c and isShow and c.ended then
    self:GossipFlush()
    c = nil
  end
  if not c then
    c = { start = GetTime(), steps = {} }
    self.gossipChain = c
    r.chains[#r.chains + 1] = c
    while #r.chains > CHAIN_KEEP do table.remove(r.chains, 1) end
  end
  local step = { t = math.floor((GetTime() - c.start) * 100 + 0.5) / 100, s = text }
  c.steps[#c.steps + 1] = step
  return c, step
end

function Probe:GossipChainLine(c)
  local parts = {}
  for _, st in ipairs(c.steps) do parts[#parts + 1] = ("%s@%.1f"):format(st.s, st.t) end
  return "chain: " .. table.concat(parts, " > ")
end

local function pickIdText(pick)
  if pick.kind == "quest" then return "quest " .. tostring(pick.optionID) end
  if pick.optionID ~= nil then return tostring(pick.optionID) end
  return "index " .. tostring(pick.index)
end

-- The key a pick's nohide control is kept under: the option ID, or "q<ID>" for a quest (the two
-- ID spaces are separate, so a quest ID must never overwrite an option's control).
local function controlKey(pick)
  if pick.optionID == nil then return nil end
  if pick.kind == "option" then return pick.optionID end
  if pick.kind == "quest" then return "q" .. tostring(pick.optionID) end
  return nil
end

local function pickLabel(pick)
  return (pick.kind == "quest" and "quest " or "option ") .. tostring(pick.optionID)
end

-- Tries the hide on a pick's window and records "tried" and "changed" (the window
-- was shown before our HideUIPanel and not after it). Never closes anything else.
function Probe:GossipTryHide(pick)
  if pick.mode == "nohide" then return end -- the control run never hides the window
  local r = gossipResults()
  local frame = rawget(_G, "GossipFrame")
  pick.frameFound = frame ~= nil
  if not (frame and frame.IsShown) then return end
  local ok, shown = pcall(frame.IsShown, frame)
  local before = ok and shown and true or false
  if pick.shownBefore == nil then pick.shownBefore = before end
  if rawget(_G, "HideUIPanel") then
    local hok, err = pcall(HideUIPanel, frame)
    pick.tried = true
    if not hok then pick.hideError = safeString(err) end
    local sok, after = pcall(frame.IsShown, frame)
    pick.shownAfter = sok and after and true or false
    pick.changed = (hok and before and not pick.shownAfter) and true or false
    -- Only a window that was open to begin with says anything about whether our hide works.
    if before then r.hideTried = (r.hideTried or 0) + 1 end
    if pick.changed then
      r.hideChanged = (r.hideChanged or 0) + 1
      pick.closedBy, pick.closedAt = "our hide", 0
    end
  end
end

-- Notes what a nohide pick showed about the option itself: did the game close the
-- window (true) or did it stay open (false). Kept per option ID across runs.
-- rewriteOptions (a number) = the window stayed open but the game replaced its contents
-- with a new GOSSIP_SHOW of that many options (saved as rewritten = true).
function Probe:GossipControl(pick, closedByGame, rewriteOptions)
  local key = controlKey(pick)
  if pick.mode ~= "nohide" or pick.controlSet or key == nil then return end
  pick.controlSet = true
  local r = gossipResults()
  -- A rewrite is inferred (no close seen before the reshow), so it never replaces a result seen directly.
  if rewriteOptions ~= nil and not closedByGame and r.control[key] then return end
  local c = { closedByGame = closedByGame, name = pick.optionName, npcID = pick.npcID, at = GetServerTime() }
  if rewriteOptions ~= nil and not closedByGame then c.rewritten, c.options = true, rewriteOptions end
  r.control[key] = c
  P("  nohide control for " .. pickLabel(pick) .. ": "
    .. (closedByGame and "the game closed the window"
        or c.rewritten and ("the window stayed open (the game rewrote it with " .. tostring(c.options) .. " options)")
        or "the window stayed open"))
end

-- "can we close the gossip window after a pick", from our own hide attempts, counting only
-- picks whose option was seen in a nohide run with the window staying open. Returns the
-- overall line and a list of per-pick lines.
function Probe:GossipVerdict()
  local r = gossipResults()
  local lines, n, yes, no, unclear = {}, 0, 0, 0, 0
  if r.mode ~= "nohide" then
    for _, p in ipairs(r.picks) do
      if p.mode ~= "nohide" and p.tried and p.shownBefore then
        n = n + 1
        local key = controlKey(p)
        local ctl = key ~= nil and r.control[key] or nil
        local label = pickLabel(p)
        local v, text
        if key == nil then
          v, text = "unclear", "verdict: unclear, no option ID for " .. pickIdText(p) .. " to match a nohide control"
        elseif not ctl then
          v, text = "unclear", "verdict: unclear, no nohide control for " .. label .. " yet"
        elseif ctl.closedByGame then
          v, text = "unclear", "verdict: unclear, the game closes " .. label .. " itself (nohide control)"
        elseif p.changed and ctl.rewritten then
          local n2 = p.reshow and p.reshow.options or ctl.options or 0
          v, text = "yes", "verdict: yes, " .. label .. ": our hide closed a window the game leaves open (the game then reshowed it with "
            .. tostring(n2) .. " option" .. (n2 == 1 and "" or "s") .. ")"
        elseif p.changed then
          v, text = "yes", "verdict: yes, " .. label .. ": our hide closed it, and the nohide control stayed open"
        else
          v, text = "no", "verdict: no, " .. label .. ": our hide did not close it, and the nohide control stayed open"
        end
        p.verdict = v
        if v == "yes" then yes = yes + 1 elseif v == "no" then no = no + 1 else unclear = unclear + 1 end
        lines[#lines + 1] = text
      end
    end
  end
  local word = (n == 0 or unclear > 0) and "unclear" or (yes == n and "yes") or (no == n and "no") or "unclear"
  r.verdict, r.verdictPicks = word, n
  return ("can we close the gossip window after a pick: %s (%d pick%s)"):format(word, n, n == 1 and "" or "s"), lines
end

-- The nohide control results, one line per option, sorted by ID.
function Probe:GossipControlLines()
  local r = gossipResults()
  local ids = {}
  for id in pairs(r.control) do ids[#ids + 1] = id end
  table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  for _, id in ipairs(ids) do
    local c = r.control[id]
    local what = type(id) == "string" and id:match("^q(.+)$") and ("quest " .. id:sub(2)) or ("option " .. tostring(id))
    out[#out + 1] = ("%s: nohide control: %s"):format(what, c.closedByGame and "game closed it"
      or c.rewritten and ("stayed open (game rewrote it with " .. tostring(c.options) .. " options)") or "stayed open")
  end
  return out
end

local function secs(t) return ("%g s"):format(t) end

local function printWindowLine(pick)
  if pick.windowPrinted then return end
  pick.windowPrinted = true
  local parts = {}
  for i, smp in ipairs(pick.samples) do
    if smp.open then
      parts[#parts + 1] = (i == TEN_AT and "still open at " or "open at ") .. secs(smp.t)
    else
      parts[#parts + 1] = "closed at " .. secs(smp.t) .. " by: " .. (pick.closedBy or (pick.shownBefore == false and "nobody (already closed before the pick)") or "unknown")
      break
    end
  end
  if pick.reshowCut then
    parts[#parts + 1] = pick.closedBy and ("closed at " .. secs(pick.closedAt or 0) .. " by: " .. pick.closedBy)
      or "no close seen before the game showed gossip again"
  end
  local line = "window after pick: " .. table.concat(parts, ", ")
    .. (pick.reshown and " (the game showed gossip again)" or "")
  pick.windowLine = line
  P("  " .. line)
end

-- Follows the window the game showed again after a pick (even an empty one):
-- still open at 1/3/10/30 s, or closed by the game or you.
function Probe:GossipSampleReshow(pick, rs)
  if not (C_Timer and C_Timer.After) then return end
  local function head()
    return "game reshowed gossip (" .. rs.options .. " option" .. (rs.options == 1 and "" or "s") .. "), "
  end
  for i, at in ipairs(RESHOW_AT) do
    pcall(C_Timer.After, at, function()
      if not self.gossipOn or rs.done then return end
      local ok, err = pcall(function()
        local gf = rawget(_G, "GossipFrame")
        local sok, shown = false, false
        if gf and gf.IsShown then sok, shown = pcall(gf.IsShown, gf) end
        local open = sok and shown and true or false
        rs.samples[#rs.samples + 1] = { t = at, open = open }
        if not open then
          rs.done = true
          rs.line = head() .. "closed at " .. secs(at) .. " by: " .. (rs.closedBy or "unknown")
          P("  " .. rs.line)
        elseif i == RESHOW_TEN then
          rs.tenOpen = true
          rs.tenPrinted = true
          rs.line = head() .. "still open at " .. secs(at)
          P("  " .. rs.line)
        elseif i == #RESHOW_AT then
          rs.done = true
          rs.line = head() .. "still open at " .. secs(at)
          P("  reshown window: still open at " .. secs(at))
        end
      end)
      if not ok then P("Gossip probe error:", safeString(err)) end
    end)
  end
end

-- Looks at the window at fixed times after a pick. Only while the probe is on.
function Probe:GossipSample(pick)
  pick.samples = {}
  if not (C_Timer and C_Timer.After) or not rawget(_G, "GossipFrame") then return end
  for i, at in ipairs(SAMPLE_AT) do
    pcall(C_Timer.After, at, function()
      if not self.gossipOn then return end
      local ok, err = pcall(function()
        local gf = rawget(_G, "GossipFrame")
        local sok, shown = pcall(gf.IsShown, gf)
        local open = sok and shown and true or false
        if i > TEN_AT then
          -- The 30 s follow-up: only for a first window that was still open at 10 s and no one has closed.
          if pick.windowPrinted and pick.tenOpen and not pick.closedBy and not pick.reshow then
            pick.samples[#pick.samples + 1] = { t = at, open = open }
            if open then P("  window after pick: still open at " .. secs(at)) end
          end
          return
        end
        if pick.windowPrinted then return end
        if pick.reshow and pick.reshow.at - pick.t <= at then
          -- A later window is up (the game showed gossip again): this sample would be about that one.
          pick.reshowCut = true
          -- No close arrived before the reshow: the window stayed open and the game rewrote it.
          if not pick.closedBy then self:GossipControl(pick, false, pick.reshow.options) end
          printWindowLine(pick)
          return
        end
        pick.samples[#pick.samples + 1] = { t = at, open = open }
        if open then
          pick.closedBy = nil -- still there: whatever hid it did not stick
          if i == TEN_AT then
            pick.tenOpen = true
            self:GossipControl(pick, false)
          end
        end
        if not open or i == TEN_AT then printWindowLine(pick) end
      end)
      if not ok then P("Gossip probe error:", safeString(err)) end
    end)
  end
end

-- The window closed on its own account (GOSSIP_CLOSED or an interaction-0 hide)
-- with no hide of ours: the game closed it, or, if it had stayed open past 10 s, you did.
function Probe:GossipNoteClose()
  local pk = self.gossipLastPick
  if not pk then return end
  local rs = pk.reshow
  if rs then
    if rs.closedBy then return end
    rs.closedAt = math.floor((GetTime() - rs.at) * 10 + 0.5) / 10
    rs.closedBy = rs.tenOpen and "you" or "game"
    if rs.tenPrinted and not rs.done then
      rs.done = true
      P("  reshown window closed " .. secs(rs.closedAt) .. " after it appeared, by: " .. rs.closedBy .. (rs.tenOpen and " (best effort)" or ""))
    end
    return
  end
  if pk.closedBy then return end
  pk.closedAt = math.floor((GetTime() - pk.t) * 10 + 0.5) / 10
  pk.closedBy = pk.tenOpen and "you" or "game"
  if pk.closedBy == "game" then self:GossipControl(pk, true) end
  if pk.windowPrinted and pk.tenOpen then
    P("  window closed " .. secs(pk.closedAt) .. " after the pick with no further pick, by: you (best effort)")
  end
end

local function printPick(pick)
  pick.printed = true
  local head = pick.kind == "quest" and pickIdText(pick) or ("option " .. pickIdText(pick))
  P(MOTA:Color("leaf", "Gossip probe") .. ":", head .. (pick.optionName and (' "' .. pick.optionName .. '"') or "")
    .. " picked" .. (pick.confirmed and " (confirmed)" or "") .. (pick.mode == "nohide" and " [nohide]" or ""))
  P("  route: " .. table.concat(pick.routes, " + ") .. (pick.index and (" (index " .. tostring(pick.index) .. ")") or ""))
  if not pick.frameFound then
    P("  No GossipFrame in this client.")
  elseif pick.tried then
    P("  our hide: tried / changed the window: " .. yesno(pick.changed)
      .. (pick.hideError and (" (error: " .. pick.hideError .. ")") or "")
      .. " · C_GossipInfo.CloseGossip exists: " .. yesno(pick.closeGossipExists))
  elseif pick.mode == "nohide" then
    P("  our hide: not tried (control run: we do NOT hide the window)")
  else
    P("  our hide: not tried")
  end
  pcall(Probe.GossipVerdict, Probe)
end

local function refreshStep(pick)
  if pick.step then
    pick.step.s = "pick " .. table.concat(pick.routes, "+") .. " " .. pickIdText(pick)
  end
end

-- One pick, whichever way it travelled. spec = { via, kind, optionID, index, text, confirmed, hide, btn }.
-- A game route that follows a button pick within a second is the same pick (its
-- option ID is not the index the game reports), so it only adds to that pick.
function Probe:GossipPick(spec)
  if not self.gossipOn then return end
  local r = gossipResults()
  local kind = spec.kind or "option"
  local now = GetTime()
  local lp = self.gossipLastButtonPick
  local old = lp and lp.pick
  if kind == "option" and spec.via ~= "button" and old and now - old.t <= MERGE_WINDOW
      and not old.routeSet[spec.via]
      and (spec.optionID == nil or old.optionID == nil or spec.optionID == old.optionID) then
    old.routeSet[spec.via] = true
    old.routes[#old.routes + 1] = spec.via
    old.index = old.index or spec.index
    old.optionID = old.optionID or spec.optionID
    old.confirmed = old.confirmed or spec.confirmed
    r.viaSeen = r.viaSeen or {}
    r.viaSeen[spec.via] = (r.viaSeen[spec.via] or 0) + 1
    refreshStep(old)
    if old.printed then
      P("  route also: " .. spec.via .. (spec.index and (" (index " .. tostring(spec.index) .. ")") or ""))
    end
    return old
  end

  -- A quest line in the gossip window is clicked like an option button, but the button reports no ID;
  -- the quest route that follows in the same moment names it. That is one pick, and it is a quest.
  if kind == "quest" and spec.optionID ~= nil and old and now - old.t <= MERGE_WINDOW and old.kind == "option"
      and old.optionID == nil and old.index == nil and old.routeSet.button and not old.routeSet[spec.via] then
    old.kind, old.optionID = "quest", spec.optionID
    old.routeSet[spec.via] = true
    old.routes[#old.routes + 1] = spec.via
    r.viaSeen = r.viaSeen or {}
    r.viaSeen[spec.via] = (r.viaSeen[spec.via] or 0) + 1
    refreshStep(old)
    if old.printed then P("  route also: " .. spec.via .. " (it is quest " .. tostring(spec.optionID) .. ")") end
    return old
  end

  local last = self.gossipNPC
  local pick = { at = GetServerTime(), t = now, via = spec.via, routes = { spec.via }, routeSet = { [spec.via] = true },
    kind = kind, optionID = spec.optionID, index = spec.index, text = safeString(spec.text),
    confirmed = spec.confirmed, npcID = last and last.npcID }
  pick.optionName = safeString(spec.text)
  if not pick.optionName and kind == "option" and spec.optionID ~= nil then
    for _, o in ipairs(last and last.options or {}) do
      if o.id == spec.optionID then pick.optionName = o.name end
    end
  end
  local frame = rawget(_G, "GossipFrame")
  pick.frameFound = frame ~= nil
  if frame and frame.IsShown then
    local ok, shown = pcall(frame.IsShown, frame)
    pick.shownBefore = ok and shown and true or false
    pick.shownAfter = pick.shownBefore
  end
  pick.mode = self.gossipMode or "hide"
  if spec.hide ~= false and pick.mode ~= "nohide" then self:GossipTryHide(pick) end
  pick.closeGossipExists = C_GossipInfo ~= nil and C_GossipInfo.CloseGossip ~= nil
  pick.inCombat = InCombatLockdown and InCombatLockdown() or false
  self.gossipLastPick = pick
  keep(r.picks, pick)
  r.viaSeen = r.viaSeen or {}
  r.viaSeen[spec.via] = (r.viaSeen[spec.via] or 0) + 1
  local _, step = self:GossipStep("pick " .. spec.via .. " " .. pickIdText(pick), false)
  pick.step = step
  self:GossipSample(pick)
  -- Printed a moment later so a route that follows straight after joins the same block.
  if C_Timer and C_Timer.After then
    pcall(C_Timer.After, 0.1, function()
      if not self.gossipOn then return end
      local ok, err = pcall(printPick, pick)
      if not ok then P("Gossip probe error:", safeString(err)) end
    end)
  else
    printPick(pick)
  end
  if spec.via == "button" then self.gossipLastButtonPick = { btn = spec.btn, t = now, id = spec.optionID, pick = pick } end
  return pick
end

-- The gossip frame's option buttons, found a few ways. Returns a list and whether a ScrollBox exists.
local function gossipButtons()
  local list, seen = {}, {}
  local function add(f)
    if type(f) == "table" and not seen[f] then seen[f] = true; list[#list + 1] = f end
  end
  local gf = rawget(_G, "GossipFrame")
  if type(gf) ~= "table" then return list, false end
  local panel = gf.GreetingPanel
  local box = type(panel) == "table" and panel.ScrollBox or nil
  if type(box) == "table" and type(box.ForEachFrame) == "function" then
    pcall(box.ForEachFrame, box, function(f) add(f) end)
  end
  if #list == 0 and type(box) == "table" and type(box.ScrollTarget) == "table" and box.ScrollTarget.GetChildren then
    local ok, kids = pcall(function() return { box.ScrollTarget:GetChildren() } end)
    if ok then for _, f in ipairs(kids) do add(f) end end
  end
  return list, type(box) == "table"
end

local function buttonOption(btn)
  local id, name
  local function fromInfo(t)
    if type(t) ~= "table" then return end
    local info = type(t.info) == "table" and t.info or t
    id = id or info.gossipOptionID or t.gossipOptionID
    name = name or info.name or t.name
  end
  if type(btn.GetElementData) == "function" then
    local ok, d = pcall(btn.GetElementData, btn)
    if ok then fromInfo(d) end
  end
  id = id or btn.gossipOptionID or btn.index
  if type(btn.GetOptionID) == "function" then
    local ok, v = pcall(btn.GetOptionID, btn)
    if ok then id = id or v end
  end
  if not name and type(btn.GetText) == "function" then
    local ok, v = pcall(btn.GetText, btn)
    if ok then name = v end
  end
  return id, name
end

-- Hooks any option button not hooked yet. A button is hooked once, ever.
function Probe:GossipHookButtons()
  if not self.gossipOn then return end
  local r = gossipResults()
  self.gossipButtonsHooked = self.gossipButtonsHooked or setmetatable({}, { __mode = "k" })
  local list, hasBox = gossipButtons()
  local newly = 0
  for _, btn in ipairs(list) do
    if not self.gossipButtonsHooked[btn] and type(btn.HookScript) == "function" then
      self.gossipButtonsHooked[btn] = true
      for _, script in ipairs({ "PreClick", "OnClick" }) do
        local ok = pcall(btn.HookScript, btn, script, function(b)
          if not self.gossipOn then return end
          local ok2, err = pcall(function()
            local id, name = buttonOption(b)
            local lp = self.gossipLastButtonPick
            if lp and lp.btn == b and GetTime() - lp.t < 0.05 and lp.id == id then
              -- PreClick and OnClick of one click are one pick. The game's own click
              -- handler has run by OnClick: try our hide there.
              if script == "OnClick" and not lp.pick.tried then self:GossipTryHide(lp.pick) end
              return
            end
            local pick = self:GossipPick({ via = "button", optionID = id, text = name, btn = b, hide = script == "OnClick" })
            if pick then pick.script = script end
          end)
          if not ok2 then P("Gossip probe error:", safeString(err)) end
        end)
        if ok then newly = newly + 1 end
      end
    end
  end
  r.buttons = { seen = #list, scrollBox = hasBox, hookedScripts = (r.buttons and r.buttons.hookedScripts or 0) + newly }
  P("  option buttons seen:", #list, "· ScrollBox found:", yesno(hasBox), "· newly hooked scripts:", newly)
end

-- Other ways a pick could travel, wrapped once each: { table, function, label, kind, byIndex }.
local GOSSIP_ENTRY_POINTS = {
  { "C_GossipInfo", "SelectOptionByIndex", "SelectOptionByIndex", "option", true },
  { "C_GossipInfo", "SelectActiveQuest", "SelectActiveQuest", "quest", false },
  { "C_GossipInfo", "SelectAvailableQuest", "SelectAvailableQuest", "quest", false },
  { "_G", "SelectGossipOption", "SelectGossipOption", "option", true },
}

function Probe:GossipHookEntryPoints(r)
  self.gossipEntryHooked = self.gossipEntryHooked or {}
  r.entryPoints = {}
  for _, e in ipairs(GOSSIP_ENTRY_POINTS) do
    local tname, fname, label, kind, byIndex = e[1], e[2], e[3], e[4], e[5]
    local tbl = tname == "_G" and _G or rawget(_G, tname)
    if not self.gossipEntryHooked[label] and type(tbl) == "table" and type(tbl[fname]) == "function" then
      self.gossipEntryHooked[label] = pcall(hooksecurefunc, tbl, fname, function(arg1)
        if not self.gossipOn then return end
        local ok, err = pcall(function()
          -- By index the game's number is not the option ID: record it as the index only.
          self:GossipPick({ via = label, kind = kind, optionID = (not byIndex) and arg1 or nil,
            index = byIndex and arg1 or nil })
        end)
        if not ok then P("Gossip probe error:", safeString(err)) end
      end)
    end
    r.entryPoints[label] = self.gossipEntryHooked[label] == true
  end
end

function Probe:GossipEvent(event, ...)
  local r = gossipResults()
  local tag = MOTA:Color("leaf", "Gossip probe")
  if event == "GOSSIP_SHOW" then
    local info = self:GossipRead()
    info.at = GetServerTime()
    self.gossipNPC = info
    r.npc = info
    local lp = self.gossipLastPick
    if lp then
      lp.reshown = true -- the game opened gossip again after the pick (an option chain)
      r.reshownAfterPick = true
      if not lp.reshow and GetTime() - lp.t <= RESHOW_WITHIN then
        local rs = { at = GetTime(), options = #info.options, samples = {} }
        lp.reshow = rs
        self:GossipSampleReshow(lp, rs)
      else
        self.gossipLastPick = nil
      end
    end
    self:GossipStep("SHOW(" .. #info.options .. ")", true)
    P(tag .. ": GOSSIP_SHOW, NPC", tostring(info.npcName), "ID", tostring(info.npcID),
      "(" .. tostring(info.guid) .. " via " .. tostring(info.unit) .. ")")
    for _, o in ipairs(info.options) do
      P("  option", tostring(o.id), '"' .. tostring(o.name) .. '"', "flags", tostring(o.flags), "status", tostring(o.status))
    end
    if #info.options == 0 then P("  no gossip options") end
    for _, q in ipairs(info.available) do P("  quest to take", tostring(q.id), tostring(q.title)) end
    for _, q in ipairs(info.active) do P("  quest in progress", tostring(q.id), tostring(q.title)) end
    -- The option buttons are made after the event: look a moment later and hook any new ones.
    if C_Timer and C_Timer.After then
      pcall(C_Timer.After, 0, function()
        local ok, err = pcall(self.GossipHookButtons, self)
        if not ok then P("Gossip probe error:", safeString(err)) end
      end)
    end
  elseif event == "GOSSIP_CLOSED" then
    r.closedSeen = true
    P(tag .. ": GOSSIP_CLOSED")
    self:GossipNoteClose()
    local c = self:GossipStep("CLOSED", false)
    c.closed, c.ended = true, true
    self:GossipFlush()
  elseif event == "GOSSIP_CONFIRM" then
    local gossipID, text, cost = ...
    r.confirmSeen = true
    keep(r.confirms, { at = GetServerTime(), id = gossipID, text = safeString(text), cost = cost })
    self:GossipStep("CONFIRM(" .. tostring(gossipID) .. ")", false)
    P(tag .. ": GOSSIP_CONFIRM", tostring(gossipID), safeString(text) or "", "cost", tostring(cost))
  else
    local kind = ...
    local shown = event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW"
    local name = interactionName(kind)
    keep(r.interactions, { at = GetServerTime(), event = shown and "show" or "hide", type = kind, name = name })
    local c = self:GossipStep((shown and "INT+" or "INT-") .. (name or tostring(kind)), false)
    if not shown and kind == 0 then
      c.ended = true -- the next GOSSIP_SHOW starts a new chain
      self:GossipNoteClose()
    end
    P(tag .. ":", shown and "interaction opened" or "interaction closed", tostring(kind) .. (name and (" (" .. name .. ")") or ""))
  end
end

function Probe:Gossip(arg)
  if arg == "off" then
    if self.gossipOn then
      pcall(self.GossipFlush, self)
      local tag = MOTA:Color("leaf", "Gossip probe")
      local okv, line, lines = pcall(self.GossipVerdict, self)
      if okv then
        local g = gossipResults()
        if g.mode == "nohide" then
          P(tag .. ": control run: we did NOT hide the window, so there is no verdict on our hide.")
          g.verdict, g.verdictPicks = nil, nil
        else
          for _, l in ipairs(lines) do P(tag .. ": " .. l) end
          P(tag .. ": " .. line)
        end
        local okc, cl = pcall(self.GossipControlLines, self)
        if okc then for _, l in ipairs(cl) do P(tag .. ": " .. l) end end
      end
    end
    if self.gossipWatch then self.gossipWatch:UnregisterAllEvents() end
    self.gossipOn = false
    local gr = MOTA.db.probe and MOTA.db.probe.gossip
    return P(MOTA:Color("leaf", "Gossip probe") .. ": off. What it saw stays in the saved file (probe.gossip)."
      .. (gr and gr.run and (" Run " .. gr.run .. " saved.") or ""))
  end

  -- Every run is kept: a fresh table becomes probe.gossip (the latest run) and is also appended
  -- to probe.gossipRuns (same table, so live updates are what a /reload or logout saves).
  local prev = gossipResults()
  local probe = MOTA.db.probe
  probe.gossipRuns = probe.gossipRuns or {}
  local runs = probe.gossipRuns
  local maxRun = 0
  for _, x in ipairs(runs) do if type(x.run) == "number" and x.run > maxRun then maxRun = x.run end end
  if not prev.run and (prev.mode or #prev.picks > 0) then
    -- a run saved before runs were kept: keep it as run 1
    prev.run = maxRun + 1
    maxRun = prev.run
    table.insert(runs, prev)
  end
  local r = { control = prev.control, run = maxRun + 1 }
  probe.gossip = r
  runs[#runs + 1] = r
  while #runs > 20 do table.remove(runs, 1) end
  r = gossipResults()
  r.at = GetServerTime()
  r.startTime = time()
  r.picks, r.confirms, r.interactions, r.chains = {}, {}, {}, {}
  r.reshownAfterPick, r.viaSeen, r.buttons = nil, nil, nil
  r.hideTried, r.hideChanged, r.verdict, r.verdictPicks = 0, 0, nil, nil
  self.gossipChain, self.gossipLastButtonPick, self.gossipLastPick = nil, nil, nil
  self.gossipMode = arg == "nohide" and "nohide" or "hide"
  r.mode = self.gossipMode
  P(MOTA:Color("leaf", "Gossip probe") .. ": run " .. r.run .. " saved (earlier runs kept in MOTADB.probe.gossipRuns)")
  P(MOTA:Color("leaf", "Gossip probe") .. ": mode: " .. (self.gossipMode == "nohide"
    and "nohide, control run: we do NOT hide the window"
    or "hide (normal run: we try to hide the window after each pick)"))
  r.apis = {}
  local missing = {}
  for _, name in ipairs(GOSSIP_APIS) do
    local present = lookup(_G, name) ~= nil
    r.apis[name] = present
    if not present then missing[#missing + 1] = name end
  end
  P(MOTA:Color("leaf", "Gossip probe") .. ":",
    #missing == 0 and "every gossip function is present" or ("missing: " .. table.concat(missing, ", ")))

  self.gossipOn = true
  if not self.gossipWatch then
    self.gossipWatch = CreateFrame("Frame")
    self.gossipWatch:SetScript("OnEvent", function(_, event, ...)
      if not self.gossipOn then return end
      local ok, err = pcall(self.GossipEvent, self, event, ...)
      if not ok then P("Gossip probe error:", safeString(err)) end
    end)
  end
  r.events = {}
  local heard = 0
  for _, event in ipairs(GOSSIP_EVENTS) do
    -- A client without this event would raise an error on registering it.
    r.events[event] = pcall(self.gossipWatch.RegisterEvent, self.gossipWatch, event)
    if r.events[event] then heard = heard + 1 end
  end

  -- A hook can't be taken off, so it's made once and does nothing while the probe is off.
  if not self.gossipHooked and C_GossipInfo and type(C_GossipInfo.SelectOption) == "function" then
    self.gossipHooked = pcall(hooksecurefunc, C_GossipInfo, "SelectOption", function(optionID, text, confirmed)
      local ok, err = pcall(self.GossipPick, self, { via = "SelectOption", optionID = optionID, text = text, confirmed = confirmed })
      if not ok then P("Gossip probe error:", safeString(err)) end
    end)
  end
  r.selectOptionHooked = self.gossipHooked == true
  self:GossipHookEntryPoints(r)
  P("Watching gossip. Hook on C_GossipInfo.SelectOption:", yesno(r.selectOptionHooked),
    "· events registered:", heard .. " of " .. #GOSSIP_EVENTS)
  local eps = {}
  for label, on in pairs(r.entryPoints or {}) do eps[#eps + 1] = label .. "=" .. (on and "yes" or "no") end
  table.sort(eps)
  P("Other entry points hooked:", table.concat(eps, ", "))
  pcall(self.GossipHookButtons, self) -- a gossip window that is already open
  P("Talk to an NPC and pick a gossip option" .. (self.gossipMode == "nohide" and ", then leave the windows alone for 30 s" or "")
    .. ". `/mota probe gossip off` stops it. Results save on /reload.")
end

---------------------------------------------------------------------------
-- /mota probe quest: can the game's quest page be kept from showing, so our own
-- page could take its place (19.1, the quest engine)? The gossip probe showed a
-- quest pick is seen (SelectAvailableQuest, with the quest ID) and that hiding the
-- gossip window changes nothing: the game's quest page opens anyway.
-- Modes (all Crown-only, off until typed, `/mota probe quest off` stops it):
--   hide    (default) right after the quest page opens, HideUIPanel(QuestFrame).
--   fade    makes the page invisible (alpha 0) for 4 s, then puts it back: the
--           conversation should stay alive, so our page could still accept.
--   nohide  the control run: the quest page is never touched.
--   page    PROTOTYPE of the quest engine: the page is faded the moment the quest is picked (and again the
--           instant the game shows it), and our own page is shown over it with Accept, Decline and Close.
--           While it is up AcceptQuest is wrapped so other add-ons' auto-accept is blocked (only our
--           Accept button gets through), and SelectAvailableQuest (both forms) is wrapped so other add-ons
--           cannot auto-select a quest for the player (only the player's own click, from the game's UI, or our
--           own calls pass). Accept on it REALLY accepts the quest.
--           Do not run it together with `/mota probe gossip`: that probe hooks the same functions with
--           hooksecurefunc, and its hooks would see the blocked calls.
--   button  RESEARCH: can we add our own entry to the gossip window? Two tries at once. (1) "inject": a copy of one of the
--           window's own rows (a quest row if the NPC has one, else an option row) is added to its list under a made-up
--           ID and label, so it would sit in the list like the game's own entries. (2) "overlay": our own button is placed
--           just under the gossip window. Clicking either opens a TEST page of ours (nothing real is accepted).
-- Every mode also notes whether quest picks and pages happened in combat, and every action the game blocks
-- (ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN: taint), so the combat and taint questions are answered by any run.
-- Except in page mode, it never accepts, declines, completes or abandons a quest. Hide mode ends the
-- conversation (the game's own close); talk to the NPC again to get the page back.
-- Each page's quest data is read on arrival, and again at 0.2/1/3 s, to learn whether
-- it stays readable once the page is hidden.
---------------------------------------------------------------------------

local QUEST_EVENTS = { "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_GREETING", "QUEST_FINISHED",
  "QUEST_ACCEPTED", "GOSSIP_SHOW", "GOSSIP_CLOSED",
  "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
  "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }
-- Made-up IDs and label for the button mode's test entry (far above any real quest or option ID).
local FAKE_QUEST_ID = 99999901
local FAKE_OPTION_ID = 99999902
local FAKE_LABEL = "[probe] Our own test quest"
local FAKE_PAGE = {
  title = "A test quest (probe)",
  body = "This is not a real quest. You are looking at a page of ours, opened from an entry we added to the gossip window. "
    .. "Nothing can be accepted here: Accept, Decline and Close only close this page.",
  objective = "Objective: tell Max whether this entry looked like it belonged in the list.",
  rewards = "Rewards: none (a test page)",
}
local QUEST_PAGE_EVENTS = { QUEST_DETAIL = "detail", QUEST_PROGRESS = "progress", QUEST_COMPLETE = "complete",
  QUEST_GREETING = "greeting" }
local QUEST_APIS = { "QuestFrame", "HideUIPanel", "GetQuestID", "GetTitleText", "GetQuestText", "GetObjectiveText",
  "AcceptQuest", "DeclineQuest", "CloseQuest", "C_GossipInfo.SelectAvailableQuest", "C_GossipInfo.SelectActiveQuest" }
-- Add-ons known to auto-accept quests or replace the quest page (the list is not complete).
local AUTOQUEST_ADDONS = { "Leatrix_Plus", "QuickQuest", "Immersion", "DialogueUI", "Questie", "EllesmereUIQuestTracker" }
local QUEST_ARM_FOR = 3 -- seconds a page faded on a quest pick waits for the game's page before it is put back
-- { table, function, byID }: which ways a quest pick can travel (the game's quest-list NPCs pass an index).
local QUEST_ENTRY_POINTS = {
  { "C_GossipInfo", "SelectAvailableQuest", true },
  { "C_GossipInfo", "SelectActiveQuest", true },
  { "_G", "SelectAvailableQuest", false },
  { "_G", "SelectActiveQuest", false },
}
local QUEST_SAMPLE_AT = { 0.2, 1, 3 } -- seconds after a page opens that the frame and its data are looked at
local QUEST_FADE_FOR = 4 -- seconds the fade mode keeps the page invisible
local QUEST_STEP_KEEP = 60
local QUEST_RUNS_KEEP = 20
local QUEST_PICK_WITHIN = 5 -- a page this soon after a quest pick is that pick's page

local function callGlobal(name, ...)
  local f = rawget(_G, name)
  if type(f) ~= "function" then return nil end
  local ok, v = pcall(f, ...)
  if ok then return v end
  return nil
end

-- What the game's quest functions say about the page that is open now.
local function readQuestData()
  local d = { id = callGlobal("GetQuestID"), title = safeString(callGlobal("GetTitleText")) }
  local text, obj = callGlobal("GetQuestText"), callGlobal("GetObjectiveText")
  d.textLen = type(text) == "string" and #text or nil
  d.objectiveLen = type(obj) == "string" and #obj or nil
  d.rewards, d.choices, d.money = callGlobal("GetNumQuestRewards"), callGlobal("GetNumQuestChoices"), callGlobal("GetRewardMoney")
  d.readable = (type(d.id) == "number" and d.id ~= 0 and (d.title or "") ~= "") and true or false
  return d
end

-- QuestFrame: shown (true/false, nil if there is no such frame) and its alpha.
local function questFrameState()
  local f = rawget(_G, "QuestFrame")
  if type(f) ~= "table" or type(f.IsShown) ~= "function" then return nil, nil end
  local ok, shown = pcall(f.IsShown, f)
  local alpha
  if type(f.GetAlpha) == "function" then
    local ok2, a = pcall(f.GetAlpha, f)
    if ok2 then alpha = a end
  end
  return (ok and shown and true or false), alpha
end

local function questRound1(x) return math.floor(x * 10 + 0.5) / 10 end

local function inCombat()
  local f = rawget(_G, "InCombatLockdown")
  if type(f) ~= "function" then return false end
  local ok, v = pcall(f)
  return ok and v and true or false
end

function Probe:QuestStep(text)
  local r = self.questRun
  if not r then return end
  r.steps[#r.steps + 1] = { t = math.floor((GetTime() - r.t0) * 100 + 0.5) / 100, s = text .. (inCombat() and " [combat]" or "") }
  while #r.steps > QUEST_STEP_KEEP do table.remove(r.steps, 1) end
end

function Probe:QuestChainLine()
  local r = self.questRun
  local parts = {}
  for _, st in ipairs(r and r.steps or {}) do parts[#parts + 1] = ("%s@%.1f"):format(st.s, st.t) end
  return "events: " .. (#parts > 0 and table.concat(parts, " > ") or "none")
end

-- Makes the game's quest page invisible (alpha 0) with the frame still shown. Done as early as it can
-- be (on the quest pick, and again the instant the frame is shown) so the page never gets drawn.
-- `by` says which of those got there first: "pick", "OnShow" or "event" (late: the page may have flashed).
function Probe:QuestFade(by)
  if self.questFaded then return self.questFaded end
  local frame = rawget(_G, "QuestFrame")
  if type(frame) ~= "table" or type(frame.SetAlpha) ~= "function" then return nil end
  local alpha = 1
  if type(frame.GetAlpha) == "function" then
    local ok, a = pcall(frame.GetAlpha, frame)
    if ok and type(a) == "number" and a > 0.01 then alpha = a end
  end
  if not pcall(frame.SetAlpha, frame, 0) then return nil end
  self.questFaded = { alpha = alpha, by = by, at = GetTime() }
  return self.questFaded
end

-- Puts a faded quest page back to full view.
function Probe:QuestRestore(why)
  local f = self.questFaded
  if not f then return end
  self.questFaded = nil
  local frame = rawget(_G, "QuestFrame")
  if type(frame) == "table" and type(frame.SetAlpha) == "function" then pcall(frame.SetAlpha, frame, f.alpha or 1) end
  if f.page then f.page.restoredBy = why end
  if self.questOn then P(MOTA:Color("leaf", "Quest probe") .. ": quest page back in full view (" .. why .. ")") end
end

-- A quest pick in a fade or page run: the page is coming, so it is faded before it can show.
function Probe:QuestArm()
  if self.questMode ~= "fade" and self.questMode ~= "page" then return end
  local f = self:QuestFade("pick")
  if not f then return end
  self:QuestStep("armed: page faded on the pick")
  if C_Timer and C_Timer.After then
    pcall(C_Timer.After, QUEST_ARM_FOR, function()
      if self.questFaded == f and not f.page then
        self:QuestRestore("no quest page opened within " .. QUEST_ARM_FOR .. " s")
      end
    end)
  end
end

-- The game's own frame being shown is the earliest moment there is, so fade it right there.
function Probe:QuestHookFrame()
  if self.questFrameHooked then return true end
  local frame = rawget(_G, "QuestFrame")
  if type(frame) ~= "table" or type(frame.HookScript) ~= "function" then return false end
  self.questFrameHooked = pcall(frame.HookScript, frame, "OnShow", function()
    if not self.questOn or (self.questMode ~= "fade" and self.questMode ~= "page") then return end
    local ok, err = pcall(function()
      local had = self.questFaded ~= nil
      if self:QuestFade("OnShow") and not had then self:QuestStep("QuestFrame shown, faded at once") end
    end)
    if not ok then P("Quest probe error:", safeString(err)) end
  end)
  return self.questFrameHooked == true
end

-- While one of our pages is up, nobody else may accept the quest: other add-ons that auto-accept do it
-- from QUEST_DETAIL by calling AcceptQuest. Only our own page's Accept button is let through.
function Probe:QuestBlocking()
  return self.questOn == true and self.questMode == "page" and (self.questFaded ~= nil or self.questOwnPage ~= nil)
end

-- Which other add-on is calling? Reads the call stack for AddOns\<name>\ and returns the first name that is
-- neither ours nor the game's own UI (AddOns\Blizzard_*). nil = the game's UI, or no way to tell: such a
-- call is never blocked in the quest-pick wrappers, so the player's own click always works.
local function questCallerAddon()
  if type(debugstack) ~= "function" then return nil end
  local ok, stack = pcall(debugstack, 1, 12, 0)
  if not ok or type(stack) ~= "string" then return nil end
  for name in stack:gmatch("[Aa]dd[Oo]ns[\\/]([^\\/%]\"':]+)") do
    if name ~= "MinistryOfTheAllied" and name:sub(1, 9) ~= "Blizzard_" then return name end
  end
  return nil
end

function Probe:QuestAcceptBlocked(src)
  local r = self.questRun
  if not r then return end
  r.acceptBlocked = (r.acceptBlocked or 0) + 1
  r.blockedFrom = r.blockedFrom or {}
  r.blockedFrom[src] = (r.blockedFrom[src] or 0) + 1
  local pg = self.questPage
  if pg then pg.blocked = (pg.blocked or 0) + 1 end
  self:QuestStep("AcceptQuest blocked (" .. src .. ")")
  P(MOTA:Color("leaf", "Quest probe") .. ": AcceptQuest called by " .. src .. " while our page is up: BLOCKED")
end

function Probe:QuestWrapAccept()
  if self.questAcceptWrapper and rawget(_G, "AcceptQuest") == self.questAcceptWrapper then return true end
  local real = rawget(_G, "AcceptQuest")
  if type(real) ~= "function" then return false end
  self.questRealAccept = real
  local probe = self
  local function wrapper(...)
    if probe:QuestBlocking() and not probe.questOwnAccept then
      local src = questCallerAddon() or "unknown"
      pcall(probe.QuestAcceptBlocked, probe, src)
      return
    end
    return real(...)
  end
  self.questAcceptWrapper = wrapper
  _G.AcceptQuest = wrapper
  return true
end

-- Quest picks: add-ons such as auto-quest ones call SelectAvailableQuest the instant gossip opens, which
-- would reopen our page after Decline. In page mode a pick made by another add-on is blocked (not run at
-- all); the player's own click (game UI) and our own calls pass. The wrapper sits outside the pick hooks.
function Probe:QuestSelectBlocked(label, src, arg)
  local r = self.questRun
  if not r then return end
  r.selectBlocked = (r.selectBlocked or 0) + 1
  r.selectBlockedFrom = r.selectBlockedFrom or {}
  r.selectBlockedFrom[src] = (r.selectBlockedFrom[src] or 0) + 1
  self:QuestStep("pick blocked (" .. src .. ")")
  local fname = tostring(label):match("([%w_]+)$") or tostring(label)
  local what = ""
  if label:find("C_GossipInfo", 1, true) then what = " (quest " .. tostring(arg) .. ")"
  else what = " (index " .. tostring(arg) .. ")" end
  P(MOTA:Color("leaf", "Quest probe") .. ": " .. fname .. " called by " .. src
    .. " (auto-select): BLOCKED, nobody picks a quest for the player in this mode" .. what)
end

function Probe:QuestWrapSelects()
  self.questSelectWrapped = self.questSelectWrapped or {}
  local probe, n = self, 0
  for _, ep in ipairs({ { "C_GossipInfo", "SelectAvailableQuest" }, { "_G", "SelectAvailableQuest" } }) do
    local tname, fname = ep[1], ep[2]
    local label = tname .. "." .. fname
    local tbl = tname == "_G" and _G or rawget(_G, tname)
    if self.questSelectWrapped[label] then
      n = n + 1
    elseif type(tbl) == "table" and type(rawget(tbl, fname)) == "function" then
      local real = tbl[fname]
      local wrapper
      wrapper = function(...)
        if probe.questOn and probe.questMode == "page" then
          local src = questCallerAddon()
          if src then
            pcall(probe.QuestSelectBlocked, probe, label, src, ...)
            return
          end
        end
        return real(...)
      end
      tbl[fname] = wrapper
      self.questSelectWrapped[label] = { tbl, fname, real, wrapper }
      n = n + 1
    end
  end
  return n
end

function Probe:QuestUnwrapSelects()
  for label, e in pairs(self.questSelectWrapped or {}) do
    local tbl, fname, real, wrapper = e[1], e[2], e[3], e[4]
    if tbl[fname] == wrapper then tbl[fname] = real end
    self.questSelectWrapped[label] = nil
  end
end

function Probe:QuestUnwrapAccept()
  if self.questAcceptWrapper and rawget(_G, "AcceptQuest") == self.questAcceptWrapper and self.questRealAccept then
    _G.AcceptQuest = self.questRealAccept
  end
  -- If another add-on wrapped AcceptQuest after us our wrapper stays in its chain, but it only passes calls on once the probe is off.
  self.questAcceptWrapper = nil
end

-- Our own prototype page (page mode): shown over the game's faded page, anchored to it.
function Probe:QuestOwnFrame()
  if self.questOwn then return self.questOwn end
  local f = CreateFrame("Frame", "MOTAQuestProbePage", UIParent)
  f:SetFrameStrata("DIALOG")
  f:SetSize(384, 512)
  f:EnableMouse(true)
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.06, 0.05, 0.08, 0.97)
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -16)
  f.title:SetWidth(352)
  f.title:SetJustifyH("LEFT")
  f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.body:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -56)
  f.body:SetWidth(352)
  f.body:SetJustifyH("LEFT")
  f.body:SetWordWrap(true)
  f.objective = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.objective:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -300)
  f.objective:SetWidth(352)
  f.objective:SetJustifyH("LEFT")
  f.objective:SetWordWrap(true)
  f.rewards = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.rewards:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -400)
  f.rewards:SetWidth(352)
  f.rewards:SetJustifyH("LEFT")
  f.tag = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.tag:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 48)
  f.tag:SetWidth(352)
  f.tag:SetJustifyH("LEFT")
  f.tag:SetText("PROTOTYPE page (Ministry of the Allied probe). The game's own page is invisible behind this one.")
  local function button(label, x, action)
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(110, 24)
    b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 16)
    b:SetText(label)
    b:SetScript("OnClick", function()
      local ok, err = pcall(self.QuestOwnClick, self, action)
      if not ok then P("Quest probe error:", safeString(err)) end
    end)
    return b
  end
  f.accept = button("Accept", 16, "accept")
  f.decline = button("Decline", 137, "decline")
  f.close = button("Close", 258, "close")
  -- Escape closes it like the game's own page: the conversation ends, nothing is accepted or declined.
  f:SetScript("OnHide", function()
    if self.questOwnPage then
      local ok, err = pcall(self.QuestOwnClick, self, "escape")
      if not ok then P("Quest probe error:", safeString(err)) end
    end
  end)
  if type(rawget(_G, "UISpecialFrames")) == "table" then table.insert(UISpecialFrames, "MOTAQuestProbePage") end
  f:Hide()
  self.questOwn = f
  return f
end

local function moneyText(copper)
  copper = tonumber(copper) or 0
  if copper <= 0 then return "no money" end
  return ("%dg %ds %dc"):format(math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100)
end

function Probe:QuestOwnShow(page)
  local f = self:QuestOwnFrame()
  local fake = page.fake
  -- A test page (button mode) opens over the gossip window; the real page over the game's quest page.
  local frame = rawget(_G, fake and "GossipFrame" or "QuestFrame")
  f:ClearAllPoints()
  if type(frame) == "table" then
    local w, h = frame.GetWidth and frame:GetWidth(), frame.GetHeight and frame:GetHeight()
    if type(w) == "number" and type(h) == "number" and w > 100 and h > 100 then f:SetSize(w, h) else f:SetSize(384, 512) end
    f:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  else
    f:SetSize(384, 512)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
  if fake then
    f.title:SetText(fake.title)
    f.body:SetText(fake.body)
    f.objective:SetText(fake.objective)
    f.rewards:SetText(fake.rewards)
    f.tag:SetText("TEST page (Ministry of the Allied probe): not a real quest, nothing can be accepted.")
  else
    f.title:SetText(safeString(callGlobal("GetTitleText")) or "")
    f.body:SetText(safeString(callGlobal("GetQuestText")) or "")
    f.objective:SetText(safeString(callGlobal("GetObjectiveText")) or "")
    f.rewards:SetText(("Rewards: %s item%s, choice of %s, %s"):format(tostring(callGlobal("GetNumQuestRewards") or 0),
      (callGlobal("GetNumQuestRewards") or 0) == 1 and "" or "s", tostring(callGlobal("GetNumQuestChoices") or 0),
      moneyText(callGlobal("GetRewardMoney"))))
    f.tag:SetText("PROTOTYPE page (Ministry of the Allied probe). The game's own page is invisible behind this one.")
  end
  self.questOwnPage = page
  page.ownShown, page.ownShownAt = true, GetTime()
  f:Show()
  self:QuestStep("own page shown")
  if fake then
    P(MOTA:Color("leaf", "Quest probe") .. ": our own TEST page is up (opened from our entry in the gossip window). Nothing real can be accepted on it.")
  else
    P(MOTA:Color("leaf", "Quest probe") .. ": our own page is up (the game's page is invisible behind it). Accept really accepts the quest.")
  end
end

-- One of our page's buttons (or Escape). Never anything but the game's own functions.
function Probe:QuestOwnClick(action)
  local page = self.questOwnPage
  if not page or page.ownAction then return end
  local tag = MOTA:Color("leaf", "Quest probe")
  page.ownAction, page.ownActionAt = action, GetTime()
  self.questOwnPage = nil
  self:QuestStep("own page: " .. action)
  P(tag .. ": our page: " .. action .. " clicked")
  if page.fake then
    -- A test page has no quest behind it: every button only closes it. Accept and Decline go back to the gossip
    -- window; Close (and Escape) end the whole conversation like the game's own Close, so the gossip window goes too.
    if self.questOwn and self.questOwn.IsShown and self.questOwn:IsShown() then self.questOwn:Hide() end
    if action == "close" or action == "escape" then
      if C_GossipInfo and type(C_GossipInfo.CloseGossip) == "function" then
        pcall(C_GossipInfo.CloseGossip)
      end
      local g = rawget(_G, "GossipFrame")
      if type(g) == "table" and g.IsShown and g:IsShown() and rawget(_G, "HideUIPanel") then pcall(HideUIPanel, g) end
    end
    return
  end
  if action == "accept" then
    local fn = self.questRealAccept or rawget(_G, "AcceptQuest")
    self.questOwnAccept = true
    local ok, err = pcall(fn)
    self.questOwnAccept = false
    if not ok then page.acceptError = safeString(err) end
    if C_Timer and C_Timer.After then
      pcall(C_Timer.After, 2, function()
        if not self.questOn then return end
        page.acceptWorked = page.acceptedAt ~= nil
        P(tag .. ": accept through our page: " .. (page.acceptWorked and "worked (QUEST_ACCEPTED came)"
          or ("did not work (no QUEST_ACCEPTED within 2 s" .. (page.acceptError and (", error: " .. page.acceptError) or "") .. ")")))
      end)
    end
  elseif action == "decline" then
    callGlobal("DeclineQuest")
  else
    callGlobal("CloseQuest")
  end
  if self.questOwn and self.questOwn.IsShown and self.questOwn:IsShown() then self.questOwn:Hide() end
  -- The game ends its own page (QUEST_FINISHED) and that puts it back. If it never does, put it back anyway so nobody is stuck.
  if C_Timer and C_Timer.After then
    local f = self.questFaded
    pcall(C_Timer.After, 1.5, function()
      if f and self.questFaded == f then self:QuestRestore("our page's " .. action .. " did not end the conversation") end
    end)
  end
end

local function questSampleText(page)
  local parts = {}
  for _, smp in ipairs(page.samples) do
    parts[#parts + 1] = (smp.shown == nil and "no frame" or (smp.shown and "shown" or "hidden")) .. " at " .. secs(smp.t)
      .. (smp.alpha and smp.shown and (" (alpha " .. ("%g"):format(smp.alpha) .. ")") or "")
  end
  return table.concat(parts, ", ")
end

function Probe:QuestPagePrint(page)
  if page.printed then return end
  page.printed = true
  local tag = MOTA:Color("leaf", "Quest probe")
  local d = page.data
  P(tag .. ": quest page " .. page.kind .. " " .. tostring(d.id) .. (d.title and d.title ~= "" and (' "' .. d.title .. '"') or "")
    .. (page.mode ~= "hide" and (" [" .. page.mode .. "]") or ""))
  P("  data on arrival: readable: " .. yesno(d.readable) .. " · text " .. tostring(d.textLen) .. " chars · objectives "
    .. tostring(d.objectiveLen) .. " chars · rewards " .. tostring(d.rewards) .. " + choices " .. tostring(d.choices))
  if page.pickedVia then P("  picked from the gossip window by: " .. page.pickedVia .. (page.pickedID and (" (quest " .. tostring(page.pickedID) .. ")") or "")) end
  if page.combat then P("  this page opened IN COMBAT") end
  if page.frameFound == false then
    P("  No QuestFrame in this client.")
  elseif page.tried then
    P("  our hide: tried / changed the page: " .. yesno(page.changed)
      .. (page.hideError and (" (error: " .. page.hideError .. ")") or "")
      .. " · frame shown before: " .. yesno(page.shownBefore) .. ", after: " .. yesno(page.shownAfter))
  elseif page.skipped then
    P("  not a quest offer page: the game's page was left alone")
  elseif page.faded then
    P("  our fade: page made invisible (alpha " .. tostring(page.alphaAfter) .. ")"
      .. (page.fadedBy and (" · applied by: " .. page.fadedBy
        .. (page.fadedBy == "event" and " (late, the game's page may have flashed)" or "")) or "")
      .. (page.mode == "fade" and (" for " .. QUEST_FADE_FOR .. " s") or "")
      .. (page.restoredBy and (", then put back (" .. page.restoredBy .. ")") or ""))
  elseif page.mode == "nohide" then
    P("  our hide: not tried (control run: we do NOT touch the quest page)")
  else
    P("  our hide: not tried")
  end
  if page.mode == "page" and not page.skipped then
    P("  our own page: " .. (page.ownShown and "shown" or "not shown") .. (page.ownAction and (" · clicked: " .. page.ownAction) or "")
      .. (page.blocked and (" · AcceptQuest calls blocked: " .. page.blocked) or ""))
  end
  P("  frame after: " .. questSampleText(page))
  local last = page.samples[#page.samples]
  if page.finishedAt then
    P("  the conversation ended (QUEST_FINISHED) " .. secs(page.finishedAt) .. " after the page opened")
  else
    P("  the conversation is still alive at " .. secs(QUEST_SAMPLE_AT[#QUEST_SAMPLE_AT]) .. " · quest data readable: "
      .. yesno(last and last.readable))
  end
end

-- A quest page (detail, progress, complete or greeting) just opened.
function Probe:QuestPageOpened(event)
  local r = self.questRun
  if not r then return end
  local now = GetTime()
  local page = { at = GetServerTime(), t = now, kind = QUEST_PAGE_EVENTS[event], event = event, mode = self.questMode,
    samples = {}, data = readQuestData() }
  if inCombat() then
    page.combat = true
    r.pagesInCombat = (r.pagesInCombat or 0) + 1
  end
  local pick = self.questLastPick
  if pick and now - pick.t <= QUEST_PICK_WITHIN then page.pickedVia, page.pickedID = pick.via, pick.id end
  keep(r.pages, page)
  self.questPage = page

  -- Fade and page runs: the page is invisible from here at the latest (usually it already is: the pick or the frame's
  -- OnShow got there first). Page runs only take over a quest offer (QUEST_DETAIL); any other page is left alone.
  local mode = self.questMode
  if mode == "fade" or mode == "page" then
    if mode == "page" and page.kind ~= "detail" then
      page.skipped = true
      self:QuestRestore("not a quest offer page")
    else
      local f = self.questFaded or self:QuestFade("event")
      if f then
        f.page = page
        page.faded, page.fadedBy, page.alphaBefore = true, f.by, f.alpha
        if mode == "fade" and C_Timer and C_Timer.After then
          -- Put back whether or not the probe is still on, so the page is never left invisible.
          pcall(C_Timer.After, QUEST_FADE_FOR, function()
            if self.questFaded == f then self:QuestRestore("after " .. QUEST_FADE_FOR .. " s") end
          end)
        end
        if mode == "page" then
          local ok, err = pcall(self.QuestOwnShow, self, page)
          if not ok then
            P("Quest probe error:", safeString(err))
            self:QuestRestore("our page could not be shown")
          end
        end
      else
        page.hideError = "could not fade the quest page"
      end
    end
  end
  if not (C_Timer and C_Timer.After) then return end
  -- The game's own handler may show the frame after this event: look at it a moment later.
  pcall(C_Timer.After, 0, function()
    if not self.questOn then return end
    local ok, err = pcall(function()
      local shown, alpha = questFrameState()
      page.frameFound, page.shownBefore = shown ~= nil, shown
      page.alphaBefore = page.alphaBefore or alpha
      local frame = rawget(_G, "QuestFrame")
      if shown == nil then return end
      if page.mode == "hide" and rawget(_G, "HideUIPanel") then
        local hok, herr = pcall(HideUIPanel, frame)
        page.tried = true
        if not hok then page.hideError = safeString(herr) end
        local after = questFrameState()
        page.shownAfter = after
        page.changed = (hok and shown and not after) and true or false
      elseif page.faded then
        local after, aAlpha = questFrameState()
        page.shownAfter, page.alphaAfter = after, aAlpha
      end
    end)
    if not ok then P("Quest probe error:", safeString(err)) end
  end)
  for i, at in ipairs(QUEST_SAMPLE_AT) do
    pcall(C_Timer.After, at, function()
      if not self.questOn then return end
      local ok, err = pcall(function()
        local shown, alpha = questFrameState()
        local d = readQuestData()
        page.samples[#page.samples + 1] = { t = at, shown = shown, alpha = alpha, id = d.id, readable = d.readable }
        if i == #QUEST_SAMPLE_AT then self:QuestPagePrint(page) end
      end)
      if not ok then P("Quest probe error:", safeString(err)) end
    end)
  end
end

function Probe:QuestOwnHide()
  self.questOwnPage = nil
  local f = self.questOwn
  if f and f.IsShown and f:IsShown() then f:Hide() end
end

function Probe:QuestEvent(event, ...)
  local tag = MOTA:Color("leaf", "Quest probe")
  if QUEST_PAGE_EVENTS[event] then
    self:QuestStep(event)
    P(tag .. ": " .. event)
    self:QuestPageOpened(event)
  elseif event == "QUEST_FINISHED" then
    local pg = self.questPage
    if pg and not pg.finishedAt then pg.finishedAt = questRound1(GetTime() - pg.t) end
    self:QuestStep("QUEST_FINISHED")
    P(tag .. ": QUEST_FINISHED")
    if self.questOwnPage then
      self.questOwnPage.ownEndedBy = "QUEST_FINISHED"
      self:QuestOwnHide()
    end
    self:QuestRestore("the conversation ended")
  elseif event == "QUEST_ACCEPTED" then
    local pg = self.questPage
    if pg then
      pg.acceptedAt = GetTime()
      pg.acceptedBy = (pg.ownAction == "accept") and "our page" or "not our page"
    end
    self:QuestStep("QUEST_ACCEPTED")
    P(tag .. ": QUEST_ACCEPTED" .. (pg and (" (" .. pg.acceptedBy .. ")") or ""))
  elseif event == "GOSSIP_SHOW" or event == "GOSSIP_CLOSED" then
    self:QuestStep(event == "GOSSIP_SHOW" and "GOSSIP_SHOW" or "GOSSIP_CLOSED")
    if self.questMode == "button" then
      if event == "GOSSIP_SHOW" then self:QuestButtonShow() else self:QuestButtonClosed() end
    end
  elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
    -- The game refused an action because add-on code was in the way (taint). Worth knowing whose it was.
    local addon, func = ...
    local r = self.questRun
    if r then
      local ours = addon == "MinistryOfTheAllied"
      r.actionBlocked = r.actionBlocked or {}
      keep(r.actionBlocked, { at = GetServerTime(), event = event, addon = safeString(addon), func = safeString(func),
        combat = inCombat() or nil })
      if ours then r.actionBlockedOurs = (r.actionBlockedOurs or 0) + 1 else r.actionBlockedOthers = (r.actionBlockedOthers or 0) + 1 end
      self:QuestStep("GAME BLOCKED " .. tostring(func) .. " (" .. tostring(addon) .. ")")
      if ours then P(tag .. ": the game BLOCKED an action of ours: " .. tostring(func) .. " (" .. event .. ")") end
    end
  else
    local kind = ...
    local name = interactionName(kind)
    self:QuestStep((event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and "INT+" or "INT-") .. (name or tostring(kind)))
  end
end

function Probe:QuestHookEntryPoints(r)
  self.questEntryHooked = self.questEntryHooked or {}
  r.entryPoints = {}
  for _, e in ipairs(QUEST_ENTRY_POINTS) do
    local tname, fname, byID = e[1], e[2], e[3]
    local label = (tname == "_G" and "" or (tname .. ".")) .. fname
    local tbl = tname == "_G" and _G or rawget(_G, tname)
    if not self.questEntryHooked[label] and type(tbl) == "table" and type(tbl[fname]) == "function" then
      self.questEntryHooked[label] = pcall(hooksecurefunc, tbl, fname, function(arg1)
        if not self.questOn then return end
        local ok, err = pcall(function()
          self.questLastPick = { t = GetTime(), via = fname, id = byID and arg1 or nil }
          self:QuestStep("pick " .. fname .. (byID and (" quest " .. tostring(arg1)) or (" index " .. tostring(arg1))))
          local run = self.questRun -- not `r`: the hook is made once, in whichever run came first
          if run and inCombat() then run.picksInCombat = (run.picksInCombat or 0) + 1 end
          -- Button mode: the game's click handler on our injected quest row came here with our made-up ID.
          if byID and arg1 == FAKE_QUEST_ID then
            self:QuestButtonClicked("inject-quest")
            return
          end
          if fname == "SelectAvailableQuest" then self:QuestArm() end
        end)
        if not ok then P("Quest probe error:", safeString(err)) end
      end)
    end
    r.entryPoints[label] = self.questEntryHooked[label] == true
  end
end

-- Page runs: "can our own page replace the game's quest page and accept the quest", from the pages
-- our page was shown for. yes = Accept was clicked on it and the game confirmed (QUEST_ACCEPTED).
function Probe:QuestPageVerdict()
  local r = self.questRun
  local lines, n, yes, no = {}, 0, 0, 0
  for _, p in ipairs(r.pages) do
    if p.ownShown then
      n = n + 1
      local name = "page " .. tostring(p.data.id) .. (p.data.title and p.data.title ~= "" and (' "' .. p.data.title .. '"') or "")
      local v, text
      if p.ownAction == "accept" and p.acceptedAt then
        v, text = "yes", ("verdict: yes, %s: Accept on our page was confirmed by the game (QUEST_ACCEPTED)"):format(name)
      elseif p.ownAction == "accept" then
        v, text = "no", ("verdict: no, %s: Accept was clicked on our page but the game never confirmed it (no QUEST_ACCEPTED)"):format(name)
      elseif p.ownAction then
        v, text = "unclear", ("verdict: unclear, %s: our page was shown and %s was clicked, so accepting through it was not tried"):format(name, p.ownAction)
      else
        v, text = "unclear", ("verdict: unclear, %s: our page was shown but no button was clicked (%s)"):format(name, p.ownEndedBy or "left open")
      end
      p.verdict = v
      if v == "yes" then yes = yes + 1 elseif v == "no" then no = no + 1 end
      lines[#lines + 1] = text
    end
  end
  local word = (n == 0 and "unclear") or (yes == n and "yes") or (no == n and "no") or "unclear"
  r.verdict, r.verdictPages = word, n
  return ("can our own page replace the game's quest page and accept the quest: %s (%d page%s)")
    :format(word, n, n == 1 and "" or "s"), lines
end

-- "can the game's quest page be hidden while the conversation stays alive", from our own
-- hide or fade attempts. Returns the overall line and one line per page we acted on.
function Probe:QuestVerdict()
  local r = self.questRun
  if r.mode == "page" then return self:QuestPageVerdict() end
  if r.mode == "button" then return self:QuestButtonVerdict() end
  local lines, n, yes, no = {}, 0, 0, 0
  local lastAt = QUEST_SAMPLE_AT[#QUEST_SAMPLE_AT]
  if r.mode ~= "nohide" then
    for _, p in ipairs(r.pages) do
      if p.tried or p.faded then
        n = n + 1
        local name = "page " .. tostring(p.data.id) .. (p.data.title and p.data.title ~= "" and (' "' .. p.data.title .. '"') or "")
        local act = p.tried and "hide" or "fade"
        local hidden = p.tried and p.changed == true or (p.faded and p.alphaAfter ~= nil and p.alphaAfter <= 0.01) or false
        local ended = p.finishedAt ~= nil and p.finishedAt <= lastAt
        local v, text
        if not hidden then
          v, text = "no", ("verdict: no, %s: our %s did not hide it"):format(name, act)
        elseif ended then
          v, text = "no", ("verdict: no, %s: our %s hid it but the conversation ended (QUEST_FINISHED %s after the page opened)")
            :format(name, act, secs(p.finishedAt))
        elseif #p.samples < #QUEST_SAMPLE_AT then
          v, text = "unclear", ("verdict: unclear, %s: stopped before %s, so the conversation was not followed long enough"):format(name, secs(lastAt))
        else
          local last = p.samples[#p.samples]
          if last.readable then
            v, text = "yes", ("verdict: yes, %s: our %s hid it and the conversation stayed alive with the quest data readable at %s")
              :format(name, act, secs(lastAt))
          else
            v, text = "unclear", ("verdict: unclear, %s: our %s hid it and no QUEST_FINISHED came, but the quest data was not readable at %s")
              :format(name, act, secs(lastAt))
          end
        end
        p.verdict = v
        if v == "yes" then yes = yes + 1 elseif v == "no" then no = no + 1 end
        lines[#lines + 1] = text
      end
    end
  end
  local word = (n == 0 and "unclear") or (yes == n and "yes") or (no == n and "no") or "unclear"
  r.verdict, r.verdictPages = word, n
  return ("can the game's quest page be hidden while the conversation stays alive: %s (%d page%s)")
    :format(word, n, n == 1 and "" or "s"), lines
end

---------------------------------------------------------------------------
-- Button mode: can we add our own entry to the gossip window?
---------------------------------------------------------------------------

function Probe:QuestButtonResults()
  local r = self.questRun
  r.button = r.button or { overlay = { clicks = 0, routes = {} }, inject = { clicks = 0, attempts = 0, routes = {} } }
  return r.button
end

local function frameRect(f)
  if type(f) ~= "table" or type(f.GetRect) ~= "function" then return nil end
  local ok, l, b, w, h = pcall(f.GetRect, f)
  if not ok or type(l) ~= "number" then return nil end
  return { math.floor(l + 0.5), math.floor(b + 0.5), math.floor((w or 0) + 0.5), math.floor((h or 0) + 0.5) }
end

local function sortedKeys(t, cap)
  local keys = {}
  if type(t) ~= "table" then return keys end
  for k in pairs(t) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  while #keys > (cap or 24) do table.remove(keys) end
  return keys
end

-- (2) overlay: our own button just under the gossip window. Never overlaps the list, so it only shows whether a
-- button of ours is visible and clickable next to the window.
function Probe:QuestButtonOverlay()
  local res = self:QuestButtonResults().overlay
  local gf = rawget(_G, "GossipFrame")
  if type(gf) ~= "table" or type(gf.IsShown) ~= "function" then res.error = "no GossipFrame"; return end
  local b = self.questBtnOverlay
  if not b then
    b = CreateFrame("Button", "MOTAQuestProbeEntry", gf, "UIPanelButtonTemplate")
    b:SetSize(260, 24)
    b:SetText("[probe] Our own button: test quest")
    b:SetScript("OnClick", function()
      local ok, err = pcall(self.QuestButtonClicked, self, "overlay")
      if not ok then P("Quest probe error:", safeString(err)) end
    end)
    self.questBtnOverlay = b
  end
  b:ClearAllPoints()
  b:SetPoint("TOP", gf, "BOTTOM", 0, -6)
  b:Show()
  res.placed, res.error = true, nil
  local ok, vis = pcall(b.IsVisible, b)
  res.visible = ok and vis and true or false
  res.rect, res.windowRect = frameRect(b), frameRect(gf)
end

-- (1) inject: add a copy of one of the window's own rows to its list. A quest row is the best template (our entry then
-- travels like a quest pick, SelectAvailableQuest with our made-up ID); else an option row (SelectOption).
function Probe:QuestButtonInject(dp, by)
  local res = self:QuestButtonResults().inject
  self.questInjected = self.questInjected or setmetatable({}, { __mode = "k" })
  if self.questInjected[dp] then return end
  res.attempts = res.attempts + 1
  local ok, err = pcall(function()
    if type(dp.GetSize) ~= "function" or type(dp.Find) ~= "function" or type(dp.Insert) ~= "function" then
      error("the data provider has no GetSize/Find/Insert")
    end
    local size = dp:GetSize()
    res.rowsBefore = size
    local tQuest, tOption
    for i = 1, size do
      local e = dp:Find(i)
      if type(e) == "table" and type(e.info) == "table" then
        if e.info.questID ~= nil and not tQuest then tQuest = e end
        if e.info.gossipOptionID ~= nil and not tOption then tOption = e end
      end
    end
    local template = tQuest or tOption
    if not template then error("no existing quest or option row to copy (" .. tostring(size) .. " rows)") end
    res.elementKeys, res.infoKeys = sortedKeys(template), sortedKeys(template.info)
    local copy, info = {}, {}
    for k, v in pairs(template) do copy[k] = v end
    for k, v in pairs(template.info) do info[k] = v end
    if tQuest then info.questID, info.title = FAKE_QUEST_ID, FAKE_LABEL else info.gossipOptionID, info.name = FAKE_OPTION_ID, FAKE_LABEL end
    copy.info = info
    dp:Insert(copy)
    res.rowKind = tQuest and "quest" or "option"
    res.rowsAfter = dp:GetSize()
  end)
  if ok then
    self.questInjected[dp] = true
    res.inserted, res.by, res.error = true, by, nil
  else
    res.inserted, res.error = res.inserted or false, safeString(err)
  end
end

-- The game rebuilds the list's data on every update, which throws our row away: put it back each time.
function Probe:QuestButtonHookBox()
  if self.questBoxHooked then return true end
  local gf = rawget(_G, "GossipFrame")
  local panel = type(gf) == "table" and gf.GreetingPanel or nil
  local box = type(panel) == "table" and panel.ScrollBox or nil
  if type(box) ~= "table" or type(box.SetDataProvider) ~= "function" then return false end
  self.questBoxHooked = pcall(hooksecurefunc, box, "SetDataProvider", function(_, dp)
    if not self.questOn or self.questMode ~= "button" or type(dp) ~= "table" then return end
    local ok, err = pcall(self.QuestButtonInject, self, dp, "SetDataProvider hook")
    if not ok then P("Quest probe error:", safeString(err)) end
  end)
  return self.questBoxHooked == true
end

-- The game's click handler on an injected option row calls SelectOption with our made-up ID.
function Probe:QuestButtonHookOption()
  if self.questOptionHooked then return true end
  if not (C_GossipInfo and type(C_GossipInfo.SelectOption) == "function") then return false end
  self.questOptionHooked = pcall(hooksecurefunc, C_GossipInfo, "SelectOption", function(optionID)
    if not self.questOn or self.questMode ~= "button" or optionID ~= FAKE_OPTION_ID then return end
    local ok, err = pcall(self.QuestButtonClicked, self, "inject-option")
    if not ok then P("Quest probe error:", safeString(err)) end
  end)
  return self.questOptionHooked == true
end

-- Gossip window opened (or its list was rebuilt): place our overlay, make sure our row is in the list, then look.
function Probe:QuestButtonShow()
  if not self.questOn or self.questMode ~= "button" then return end
  self:QuestButtonHookBox()
  self:QuestButtonHookOption()
  if not (C_Timer and C_Timer.After) then return end
  pcall(C_Timer.After, 0, function()
    if not self.questOn or self.questMode ~= "button" then return end
    local ok, err = pcall(function()
      self:QuestButtonOverlay()
      -- Fallback for a window the hook missed (or one that was already open): add the row from here.
      local gf = rawget(_G, "GossipFrame")
      local panel = type(gf) == "table" and gf.GreetingPanel or nil
      local box = type(panel) == "table" and panel.ScrollBox or nil
      if type(box) == "table" and type(box.GetDataProvider) == "function" then
        local okd, dp = pcall(box.GetDataProvider, box)
        if okd and type(dp) == "table" then self:QuestButtonInject(dp, "timer") end
      else
        self:QuestButtonResults().inject.error = self:QuestButtonResults().inject.error or "no gossip ScrollBox with a data provider"
      end
    end)
    if not ok then P("Quest probe error:", safeString(err)) end
  end)
  -- A moment later the buttons exist: is our row among them, and hook its clicks.
  pcall(C_Timer.After, 0.4, function()
    if not self.questOn or self.questMode ~= "button" then return end
    local ok, err = pcall(function()
      local res = self:QuestButtonResults().inject
      local list = gossipButtons()
      res.rowSeen = false
      self.questRowHooked = self.questRowHooked or setmetatable({}, { __mode = "k" })
      for _, btn in ipairs(list) do
        -- our row: by the made-up ID in the row's own data, else by the label the button shows
        local isOurs = false
        if type(btn.GetElementData) == "function" then
          local okd, d = pcall(btn.GetElementData, btn)
          local info = okd and type(d) == "table" and (type(d.info) == "table" and d.info or d) or nil
          if info and (info.questID == FAKE_QUEST_ID or info.gossipOptionID == FAKE_OPTION_ID) then isOurs = true end
        end
        if not isOurs then
          local _, name = buttonOption(btn)
          isOurs = type(name) == "string" and name:find(FAKE_LABEL, 1, true) ~= nil
        end
        if isOurs then
          res.rowSeen = true
          res.rowRect = frameRect(btn)
          if not self.questRowHooked[btn] and type(btn.HookScript) == "function" then
            self.questRowHooked[btn] = true
            for _, script in ipairs({ "PreClick", "OnClick" }) do
              pcall(btn.HookScript, btn, script, function()
                if not self.questOn or self.questMode ~= "button" then return end
                local ok2, err2 = pcall(self.QuestButtonClicked, self, "inject-row")
                if not ok2 then P("Quest probe error:", safeString(err2)) end
              end)
            end
          end
        end
      end
      local tag = MOTA:Color("leaf", "Quest probe")
      local ov = self:QuestButtonResults().overlay
      P(tag .. ": our entry: overlay button placed: " .. yesno(ov.placed) .. (ov.error and (" (" .. ov.error .. ")") or "")
        .. " · row added to the list: " .. yesno(res.inserted) .. (res.error and (" (" .. res.error .. ")") or "")
        .. " · row seen among the window's buttons: " .. yesno(res.rowSeen))
    end)
    if not ok then P("Quest probe error:", safeString(err)) end
  end)
end

function Probe:QuestButtonClosed()
  local b = self.questBtnOverlay
  if b and b.Hide then pcall(b.Hide, b) end
  local pg = self.questOwnPage
  if pg and pg.fake then
    pg.ownEndedBy = "the gossip window closed"
    self:QuestOwnHide()
  end
end

-- One of our entries was clicked (route: overlay, inject-row, inject-quest or inject-option). The first click in a
-- short moment opens the test page; the other routes of the same click only count.
function Probe:QuestButtonClicked(route)
  if not self.questOn or self.questMode ~= "button" then return end
  local r = self.questRun
  local res = self:QuestButtonResults()
  local part = route == "overlay" and res.overlay or res.inject
  part.clicks = part.clicks + 1
  part.routes[route] = (part.routes[route] or 0) + 1
  self:QuestStep("our entry clicked (" .. route .. ")")
  local now = GetTime()
  if self.questFakeAt and now - self.questFakeAt < 0.5 then return end
  self.questFakeAt = now
  local tag = MOTA:Color("leaf", "Quest probe")
  P(tag .. ": our entry was clicked (" .. route .. ")")
  local page = { at = GetServerTime(), t = now, kind = "detail", event = "button", mode = "button", samples = {}, fake = FAKE_PAGE,
    via = route, printed = true, data = { id = FAKE_QUEST_ID, title = FAKE_PAGE.title, readable = true } }
  if inCombat() then page.combat = true; r.pagesInCombat = (r.pagesInCombat or 0) + 1 end
  keep(r.pages, page)
  local ok, err = pcall(self.QuestOwnShow, self, page)
  if not ok then page.error = safeString(err); P("Quest probe error:", page.error) end
  if C_Timer and C_Timer.After then
    -- What did the game do about the click? (It was told about a quest or option it has never heard of.)
    pcall(C_Timer.After, 2, function()
      if not self.questOn then return end
      local gf = rawget(_G, "GossipFrame")
      page.gossipShownAfter = (type(gf) == "table" and type(gf.IsShown) == "function" and gf:IsShown()) and true or false
      local t0 = now - r.t0
      local seen = {}
      for _, st in ipairs(r.steps) do
        if st.t >= t0 - 0.01 and (st.s:find("^GOSSIP_CLOSED") or st.s:find("^QUEST_") or st.s:find("^INT") or st.s:find("^GAME BLOCKED")) then
          seen[#seen + 1] = st.s
        end
      end
      page.gameReaction = #seen > 0 and table.concat(seen, ", ") or "nothing"
      P(tag .. ": 2 s after the click: gossip window still open: " .. yesno(page.gossipShownAfter)
        .. " · game's reaction: " .. page.gameReaction)
    end)
  end
end

-- "can we add our own entry to the gossip window": the injected row is the answer, the overlay a fallback.
-- yes = row added, seen among the window's buttons, and a click on it reached us and opened our test page.
function Probe:QuestButtonVerdict()
  local r = self.questRun
  local b = r.button or { overlay = { clicks = 0, routes = {} }, inject = { clicks = 0, attempts = 0, routes = {} } }
  local ov, inj = b.overlay, b.inject
  local lines = {}
  local function routes(t)
    local out = {}
    for k, c in pairs(t or {}) do out[#out + 1] = k .. " x" .. c end
    table.sort(out)
    return #out > 0 and (" (" .. table.concat(out, ", ") .. ")") or ""
  end
  lines[#lines + 1] = ("overlay button under the window: placed %s, visible %s, clicked %d time%s%s"):format(
    ov.placed and "yes" or "no", ov.visible and "yes" or "no", ov.clicks, ov.clicks == 1 and "" or "s", routes(ov.routes))
  lines[#lines + 1] = ("row added to the window's list: %s%s, seen among the buttons %s, clicked %d time%s%s"):format(
    inj.inserted and ("yes (" .. tostring(inj.rowKind) .. " row, by " .. tostring(inj.by) .. ")") or "no",
    inj.error and (", last error: " .. inj.error) or "", inj.rowSeen and "yes" or "no",
    inj.clicks, inj.clicks == 1 and "" or "s", routes(inj.routes))
  local opened = false
  for _, p in ipairs(r.pages) do if p.fake and p.ownShown then opened = true end end
  local word
  if inj.inserted and inj.rowSeen and inj.clicks > 0 and opened then word = "yes"
  elseif inj.attempts > 0 and not inj.inserted then word = "no"
  elseif inj.inserted and not inj.rowSeen then word = "no"
  else word = "unclear" end
  r.verdict, r.verdictPages = word, #r.pages
  r.overlayVerdict = (ov.clicks > 0 and opened) and "yes" or ((not ov.placed) and "no" or "unclear")
  local why = word == "unclear" and (inj.inserted and ", but the row was never clicked (click it)" or ", no gossip window was opened")
    or ""
  return ("can we add our own entry to the gossip window's list and react to its click: %s%s (fallback overlay button: %s)")
    :format(word, why, r.overlayVerdict), lines
end

function Probe:QuestOff()
  local tag = MOTA:Color("leaf", "Quest probe")
  local r = self.questRun
  self:QuestOwnHide()
  self:QuestRestore("probe off")
  self:QuestUnwrapAccept()
  self:QuestUnwrapSelects()
  local ob = self.questBtnOverlay
  if ob and ob.Hide then pcall(ob.Hide, ob) end
  if r then
    for _, p in ipairs(r.pages) do
      if not p.printed then self:QuestPagePrint(p) end
    end
    P("  " .. self:QuestChainLine())
    -- Combat and taint, whichever mode ran.
    P(tag .. ": quest picks made in combat: " .. (r.picksInCombat or 0) .. " · pages opened in combat: " .. (r.pagesInCombat or 0))
    local names = {}
    for _, a in ipairs(r.actionBlocked or {}) do names[#names + 1] = tostring(a.addon) .. ":" .. tostring(a.func) end
    P(tag .. ": actions the game blocked (taint): from us " .. (r.actionBlockedOurs or 0) .. ", from others " .. (r.actionBlockedOthers or 0)
      .. (#names > 0 and (" (" .. table.concat(names, ", ") .. ")") or ""))
    if r.mode == "nohide" then
      P(tag .. ": control run: we did NOT touch the quest page, so there is no verdict.")
      for _, p in ipairs(r.pages) do
        local last = p.samples[#p.samples]
        P(tag .. (": control: page %s: frame %s at %s, quest data readable: %s%s"):format(tostring(p.data.id),
          last and (last.shown == nil and "not found" or (last.shown and "still shown" or "hidden")) or "not sampled",
          last and secs(last.t) or "-", yesno(last and last.readable),
          p.finishedAt and (", conversation ended " .. secs(p.finishedAt) .. " after it opened") or ""))
      end
      r.verdict, r.verdictPages = nil, nil
    else
      if r.mode == "page" then
        local from = {}
        for src, c in pairs(r.blockedFrom or {}) do from[#from + 1] = src .. " x" .. c end
        table.sort(from)
        P(tag .. ": AcceptQuest calls by other add-ons blocked while our page was up: " .. (r.acceptBlocked or 0)
          .. (#from > 0 and (" (" .. table.concat(from, ", ") .. ")") or ""))
        local sfrom = {}
        for src, c in pairs(r.selectBlockedFrom or {}) do sfrom[#sfrom + 1] = src .. " x" .. c end
        table.sort(sfrom)
        P(tag .. ": quest picks by other add-ons blocked: " .. (r.selectBlocked or 0)
          .. (#sfrom > 0 and (" (" .. table.concat(sfrom, ", ") .. ")") or ""))
      end
      local line, lines = self:QuestVerdict()
      for _, l in ipairs(lines) do P(tag .. ": " .. l) end
      P(tag .. ": " .. line)
    end
  end
end

function Probe:Quest(arg)
  local tag = MOTA:Color("leaf", "Quest probe")
  if arg == "off" then
    if self.questOn then
      local ok, err = pcall(self.QuestOff, self)
      if not ok then P("Quest probe error:", safeString(err)) end
    end
    if self.questWatch then self.questWatch:UnregisterAllEvents() end
    self.questOn = false
    local qr = MOTA.db.probe and MOTA.db.probe.quest
    return P(tag .. ": off. What it saw stays in the saved file (probe.quest)."
      .. (qr and qr.run and (" Run " .. qr.run .. " saved.") or ""))
  end

  self:QuestOwnHide()
  self:QuestRestore("a new run started")
  self:QuestUnwrapAccept()
  self:QuestUnwrapSelects()
  local mode = (arg == "nohide" or arg == "fade" or arg == "page" or arg == "button") and arg or "hide"
  MOTA.db.probe = MOTA.db.probe or {}
  local probe = MOTA.db.probe
  probe.questRuns = probe.questRuns or {}
  local runs = probe.questRuns
  local maxRun = 0
  for _, x in ipairs(runs) do if type(x.run) == "number" and x.run > maxRun then maxRun = x.run end end
  local r = { run = maxRun + 1, at = GetServerTime(), startTime = time(), t0 = GetTime(), mode = mode,
    pages = {}, steps = {}, apis = {}, events = {} }
  probe.quest = r -- the latest run; also in questRuns (the same table, so live updates are what is saved)
  runs[#runs + 1] = r
  while #runs > QUEST_RUNS_KEEP do table.remove(runs, 1) end
  self.questRun, self.questMode, self.questPage, self.questLastPick = r, mode, nil, nil
  P(tag .. ": run " .. r.run .. " saved (earlier runs kept in MOTADB.probe.questRuns)")
  P(tag .. ": mode: " .. (mode == "nohide" and "nohide, control run: we do NOT touch the quest page"
    or mode == "fade" and ("fade: the quest page goes invisible for " .. QUEST_FADE_FOR .. " s, then comes back (do not click while it is invisible)")
    or mode == "page" and "page, PROTOTYPE: the game's quest page is made invisible and our own page is shown instead, with Accept, Decline and Close. Accept REALLY accepts the quest. Other add-ons' auto-accept is blocked while it is up, and other add-ons cannot pick a quest for you (only your own click picks one)."
    or mode == "button" and "button, RESEARCH: we add our own test entry to the gossip window (a copy of one of its rows, plus a button under it). Clicking it opens a test page of ours. Nothing real is accepted."
    or "hide (normal run: the quest page is closed right after it opens; the quest is not accepted or declined)"))
  local missing = {}
  for _, name in ipairs(QUEST_APIS) do
    local present = lookup(_G, name) ~= nil
    r.apis[name] = present
    if not present then missing[#missing + 1] = name end
  end
  P(tag .. ":", #missing == 0 and "every quest function is present" or ("missing: " .. table.concat(missing, ", ")))

  self.questOn = true
  if mode == "fade" or mode == "page" then
    r.frameHooked = self:QuestHookFrame()
    P(tag .. ": hook on the game's quest frame (fades it the instant it shows):", yesno(r.frameHooked))
  end
  if mode == "page" then
    r.acceptWrapped = self:QuestWrapAccept()
    P(tag .. ": AcceptQuest wrapper (blocks other add-ons' auto-accept while our page is up):", yesno(r.acceptWrapped))
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded")
    local found = {}
    if type(isLoaded) == "function" then
      for _, name in ipairs(AUTOQUEST_ADDONS) do
        local ok, loaded = pcall(isLoaded, name)
        if ok and loaded then found[#found + 1] = name end
      end
    end
    r.autoQuestAddons = found
    P(tag .. ": known quest add-ons loaded (they can auto-accept or replace the quest page; the list is not complete):",
      #found > 0 and table.concat(found, ", ") or "none")
  end
  if not self.questWatch then
    self.questWatch = CreateFrame("Frame")
    self.questWatch:SetScript("OnEvent", function(_, event, ...)
      if not self.questOn then return end
      local ok, err = pcall(self.QuestEvent, self, event, ...)
      if not ok then P("Quest probe error:", safeString(err)) end
    end)
  end
  local heard = 0
  for _, event in ipairs(QUEST_EVENTS) do
    r.events[event] = pcall(self.questWatch.RegisterEvent, self.questWatch, event)
    if r.events[event] then heard = heard + 1 end
  end
  self:QuestHookEntryPoints(r)
  if mode == "page" then
    r.selectWrapped = self:QuestWrapSelects()
    P(tag .. ": quest-pick wrappers (stop other add-ons picking a quest for you): " .. r.selectWrapped)
  end
  if mode == "button" then
    r.boxHooked = self:QuestButtonHookBox()
    r.optionHooked = self:QuestButtonHookOption()
    P(tag .. ": hook on the gossip list's data (adds our row each time the list is rebuilt):", yesno(r.boxHooked),
      "· hook on option clicks:", yesno(r.optionHooked))
    -- A gossip window that is already open.
    local gf = rawget(_G, "GossipFrame")
    if type(gf) == "table" and type(gf.IsShown) == "function" and gf:IsShown() then self:QuestButtonShow() end
  end
  local eps = {}
  for label, on in pairs(r.entryPoints) do eps[#eps + 1] = label .. "=" .. (on and "yes" or "no") end
  table.sort(eps)
  P("Watching quest pages. Events registered:", heard .. " of " .. #QUEST_EVENTS, "· quest pick hooks:", table.concat(eps, ", "))
  if mode == "button" then
    return P("Talk to an NPC that has a quest to take or at least one gossip option (the row is a copy of one of those). Look for \"" .. FAKE_LABEL
      .. "\" in its list and a button under the window, click each (one at a time, closing the test page between), and say whether the entry looked like it belonged. `/mota probe quest off` stops it. Results save on /reload.")
  end
  P("Talk to an NPC with a quest and click it" .. (mode == "nohide" and ", then leave the windows alone for 30 s" or "")
    .. (mode == "page" and ". Our page should appear: accept it only if you want the quest" or ". Never accept it")
    .. ". `/mota probe quest off` stops it. Results save on /reload.")
end

---------------------------------------------------------------------------
-- /mota probe bank: can the ledger and deposit prompts work on Forever (10.7)?
-- Only watches and reads. It never moves money.
---------------------------------------------------------------------------

local BANK_APIS = { "GetGuildBankMoney", "DepositGuildBankMoney", "WithdrawGuildBankMoney", "CanWithdrawGuildBankMoney",
  "GetGuildBankWithdrawMoney", "QueryGuildBankLog", "GetNumGuildBankMoneyTransactions", "GetGuildBankMoneyTransaction" }

local function gold(copper)
  return ("%.4fg"):format((copper or 0) / 10000)
end

local function bankResults()
  MOTA.db.probe = MOTA.db.probe or {}
  MOTA.db.probe.bank = MOTA.db.probe.bank or {}
  return MOTA.db.probe.bank
end

function Probe:ReadBankLog()
  if not GetNumGuildBankMoneyTransactions or not GetGuildBankMoneyTransaction then return end
  local total = GetNumGuildBankMoneyTransactions() or 0
  local entries = {}
  for i = total, 1, -1 do
    local kind, name, amount, years, months, days, hours = GetGuildBankMoneyTransaction(i)
    entries[#entries + 1] = { kind = kind, name = name, amount = amount, ago = { years, months, days, hours } }
  end
  bankResults().log = { at = GetServerTime(), total = total, entries = entries }
  P("Bank money log:", total, "entries readable")
  for i = 1, math.min(5, #entries) do
    local e = entries[i]
    P("  " .. tostring(e.kind), tostring(e.name), gold(e.amount))
  end
end

function Probe:QueryBankLog()
  if QueryGuildBankLog then QueryGuildBankLog((MAX_GUILDBANK_TABS or 8) + 1) end
end

function Probe:WatchBank()
  if self.bankWatch then return end
  self.bankWatch = CreateFrame("Frame")
  local heard = {}
  for _, event in ipairs({ "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "GUILDBANK_UPDATE_MONEY", "GUILDBANKLOG_UPDATE" }) do
    -- A client without this event would raise an error on registering it.
    heard[event] = pcall(self.bankWatch.RegisterEvent, self.bankWatch, event)
  end
  bankResults().events = heard
  self.bankWatch:SetScript("OnEvent", function(_, event)
    if event == "GUILDBANKLOG_UPDATE" then
      if self.bankLogWanted then
        self.bankLogWanted = false
        self:ReadBankLog()
      end
      return
    end
    if event == "GUILDBANK_UPDATE_MONEY" then
      local now = GetGuildBankMoney and GetGuildBankMoney()
      P("Bank balance changed:", gold(now))
      bankResults().moneyEvent = true
      self.bankLogWanted = true
      self:QueryBankLog()
    else
      P("Bank event:", event)
      if event == "GUILDBANKFRAME_OPENED" then
        self.bankLogWanted = true
        self:QueryBankLog()
      end
    end
  end)
  local function hook(name, key, label)
    if _G[name] then
      hooksecurefunc(name, function(amount)
        P(label, gold(amount))
        bankResults()[key] = true
      end)
    end
  end
  hook("DepositGuildBankMoney", "depositSeen", "Saw a deposit of")
  hook("WithdrawGuildBankMoney", "withdrawSeen", "Saw a withdrawal of")
end

function Probe:Bank()
  local out = bankResults()
  out.at = GetServerTime()
  out.apis = {}
  local missing = {}
  for _, name in ipairs(BANK_APIS) do
    out.apis[name] = _G[name] ~= nil
    if not _G[name] then missing[#missing + 1] = name end
  end
  P(MOTA:Color("leaf", "Bank probe") .. ":", #missing == 0 and "every bank function is present" or ("missing: " .. table.concat(missing, ", ")))
  local _, rankName = GetGuildInfo("player")
  out.rank = rankName
  P("Your rank:", tostring(rankName), "· balance the game reports:", GetGuildBankMoney and gold(GetGuildBankMoney()) or "unknown")
  self:WatchBank()
  self.bankLogWanted = true
  self:QueryBankLog()
  P("Watching. With the bank open, deposit and withdraw a little. Your results save on /reload.")
end

---------------------------------------------------------------------------
-- /mota probe limits
---------------------------------------------------------------------------

local BURST = 20
local TRICKLE = 20
local TRICKLE_GAP = 0.5

local run -- the test in progress

local function message(len, seq)
  local head = MOTA.Comm:Pack("PB", run.id, seq) .. MOTA.Comm.SEP
  return head .. string.rep("x", len - #head)
end

-- Sends without the queue and catches errors, since a too-long message may
-- raise one instead of returning a code.
local function try(len, seq)
  local ok, sent, r = pcall(MOTA.Comm.RawSend, MOTA.Comm, message(len, seq), "GUILD")
  if not ok then return false, "error: " .. tostring(sent) end
  return sent, MOTA.Comm:ResultName(r)
end

local function tally(t, sent, why)
  if sent then
    t.accepted = t.accepted + 1
  else
    t.refused = t.refused + 1
    t.why[why] = (t.why[why] or 0) + 1
  end
end

local function reasons(t)
  local parts = {}
  for why, n in pairs(t.why) do parts[#parts + 1] = n .. " " .. why end
  return #parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or ""
end

local function finish()
  MOTA.Comm.paused = false
  MOTA.Comm:Kick()
  local b, t, e = run.burst, run.trickle, run.echo
  P(MOTA:Color("leaf", "Limits test") .. ":")
  P("  Burst:", BURST, "at once, the game took", b.accepted, "and refused", b.refused .. reasons(b))
  P(("  Then one every %.1f s for %d s: took %d of %d, about %.1f a second%s"):format(
    TRICKLE_GAP, TRICKLE * TRICKLE_GAP, t.accepted, TRICKLE, t.accepted / (TRICKLE * TRICKLE_GAP), reasons(t)))
  P("  255-byte message:", run.size[255], "· 256-byte message:", run.size[256])
  P("  Came back from the server: burst", e.b, "· trickle", e.t, "· size test", e.s,
    "(fewer than were taken means the server dropped some quietly)")
  MOTA.db.probe = MOTA.db.probe or {}
  MOTA.db.probe.limits = {
    at = GetServerTime(), burst = BURST, trickle = TRICKLE, gap = TRICKLE_GAP,
    burstAccepted = b.accepted, burstRefused = b.refused, burstWhy = b.why,
    trickleAccepted = t.accepted, trickleRefused = t.refused, trickleWhy = t.why,
    size255 = run.size[255], size256 = run.size[256], echoes = e,
  }
  run = nil
end

function Probe:Limits()
  if run then return P("The limits test is already running.") end
  if not MOTA.guild then
    return P(IsInGuild() and "The guild roster hasn't loaded yet. Try again in a moment."
      or "The limits test needs a character in a guild, because it measures the guild channel.")
  end

  run = {
    id = tostring(math.random(1000, 9999)),
    burst = { accepted = 0, refused = 0, why = {} },
    trickle = { accepted = 0, refused = 0, why = {} },
    size = {},
    echo = { b = 0, t = 0, s = 0 },
  }
  MOTA.Comm.paused = true -- the add-on's own traffic waits until the test is over
  P("Limits test started: about 45 hidden guild messages over 20 seconds. Results follow.")

  -- 1. A burst, all in the same instant.
  for i = 1, BURST do tally(run.burst, try(250, "b" .. i)) end

  -- 2. Straight after, a steady trickle, to see how fast the allowance comes back.
  C_Timer.After(TRICKLE_GAP, function()
    local i = 0
    C_Timer.NewTicker(TRICKLE_GAP, function()
      i = i + 1
      tally(run.trickle, try(250, "t" .. i))
      if i == TRICKLE then
        -- 3. The largest message, and one byte more.
        C_Timer.After(3, function()
          for _, len in ipairs({ 255, 256 }) do
            local sent, why = try(len, "s" .. len)
            run.size[len] = sent and "taken" or ("refused, " .. why)
          end
          -- 4. Give the last echoes time to arrive.
          C_Timer.After(5, finish)
        end)
      end
    end, TRICKLE)
  end)
end

-- Our own guild messages come back to us; count them to see what really went out.
MOTA.Comm:Handle("PB", function(self, sender, channel, f)
  if not run or sender ~= self.me or f[1] ~= run.id then return end
  local phase = (f[2] or ""):sub(1, 1)
  if run.echo[phase] then run.echo[phase] = run.echo[phase] + 1 end
end)
