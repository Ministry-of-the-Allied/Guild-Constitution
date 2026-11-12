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
--
-- Both also save their results in the add-on's saved file (written on logout
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
  if pick.mode ~= "nohide" or pick.controlSet or pick.kind ~= "option" or pick.optionID == nil then return end
  pick.controlSet = true
  local r = gossipResults()
  -- A rewrite is inferred (no close seen before the reshow), so it never replaces a result seen directly.
  if rewriteOptions ~= nil and not closedByGame and r.control[pick.optionID] then return end
  local c = { closedByGame = closedByGame, name = pick.optionName, npcID = pick.npcID, at = GetServerTime() }
  if rewriteOptions ~= nil and not closedByGame then c.rewritten, c.options = true, rewriteOptions end
  r.control[pick.optionID] = c
  P("  nohide control for option " .. tostring(pick.optionID) .. ": "
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
        local id = p.kind == "option" and p.optionID or nil
        local ctl = id ~= nil and r.control[id] or nil
        local v, text
        if id == nil then
          v, text = "unclear", "verdict: unclear, no option ID for " .. pickIdText(p) .. " to match a nohide control"
        elseif not ctl then
          v, text = "unclear", "verdict: unclear, no nohide control for option " .. tostring(id) .. " yet"
        elseif ctl.closedByGame then
          v, text = "unclear", "verdict: unclear, the game closes option " .. tostring(id) .. " itself (nohide control)"
        elseif p.changed and ctl.rewritten then
          local n2 = p.reshow and p.reshow.options or ctl.options or 0
          v, text = "yes", "verdict: yes, option " .. tostring(id) .. ": our hide closed a window the game leaves open (the game then reshowed it with "
            .. tostring(n2) .. " option" .. (n2 == 1 and "" or "s") .. ")"
        elseif p.changed then
          v, text = "yes", "verdict: yes, option " .. tostring(id) .. ": our hide closed it, and the nohide control stayed open"
        else
          v, text = "no", "verdict: no, option " .. tostring(id) .. ": our hide did not close it, and the nohide control stayed open"
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
    out[#out + 1] = ("option %s: nohide control: %s"):format(tostring(id), c.closedByGame and "game closed it"
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
