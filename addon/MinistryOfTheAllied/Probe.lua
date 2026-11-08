-- Ministry of the Allied: the probe.
-- Answers the add-on plan's open questions from inside the Forever client:
-- the interface number, whether the game has its own data packer, how add-on
-- messages behave and who the add-on counts as the Crown.
--
-- /mota probe         client facts, printed in chat
-- /mota probe limits  measures the message limits (about 45 hidden guild messages)
-- /mota probe bank    what the game lets us see of the guild bank (open it first)
-- /mota probe map     what the world map is made of (stand in Stormwind City)
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
