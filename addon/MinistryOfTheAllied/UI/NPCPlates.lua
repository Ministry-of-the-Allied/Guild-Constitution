-- Ministry of the Allied: friendly NPC nameplates, on only near a marked NPC
-- (ADDON_SPEC.md 10.18, Max 12 Nov).
--
-- A quest marker stands on the NPC's nameplate, and the game gives friendly NPCs a
-- nameplate only with its "Friendly NPCs" option (the CVar nameplateShowFriendlyNPCs).
-- So players needn't turn it on themselves: when an NPC marked for me is near, the
-- add-on turns it on; when none is near any more, it puts the player's own value
-- back. While the add-on holds it on, every friendly NPC's nameplate shows just its
-- name, drawn like the names the game puts over NPCs' heads (the game's font, the
-- friendly green, the <title> under it). As Lueur does it: the frames on the plate
-- (the game's own unit frame, and any another nameplate add-on put there) are made
-- see-through (SetAlpha 0: never hidden, moved, re-parented or replaced) and the
-- name is drawn on our own frame, anchored to the plate.
--
-- The CVar is the player's own setting:
--   - it is only turned on when it was off, and the old value is kept in the saved
--     variables (MOTADB.npcPlates) until it is put back, so a /reload or a crash
--     can't lose it: at the next login the add-on takes the hold up again and puts
--     it back when no marked NPC is near;
--   - CVars can't change in combat: a change waits for combat to end;
--   - near a marked NPC the add-on has the last word (Max, 12 Nov): if anything
--     turns the option off while we hold it (another add-on such as ElvUI or
--     EllesmereUI on a zone change, or the options), it is turned on again;
--   - if the player already shows friendly NPC nameplates, the CVar is left as it
--     is, but near a marked NPC their friendly NPC nameplates are dressed the same
--     way, so nobody can tell nameplates are on (Max, 12 Nov); away from markers
--     their nameplates are their own again;
--   - put back at logout (and so before a /reload).

local _, MOTA = ...
local Markers = MOTA.Markers
local UI = Markers.UI
local Names = {}
UI.Names = Names

local CVAR = "nameplateShowFriendlyNPCs"
local ON_MARGIN, OFF_MARGIN = 5, 20 -- yards past the nameplate distance: on a little early, off a little late
local TICK = 0.5
-- The name, as the game draws names over NPCs' heads (Max's screenshot, 12 Nov): the
-- game's own font file (not a font object, which ElvUI and others restyle), with a
-- drop shadow, in the friendly green.
local NAME_FONT, NAME_SIZE = "Fonts\\FRIZQT__.TTF", 16 -- /mota marker namesize changes the size
local GREEN = { 0, 1, 0 }
local DEFAULT_NAME_Y = 0 -- the name's foot above the nameplate's foot, which stands over the NPC's head

-- Smaller with distance, as the NPC itself gets smaller (Max, 12 Nov): the game draws
-- nameplates one size on screen at every distance (/mota marker probe: scale 0.64
-- near and far), so the name and its marker shrink by themselves. The size falls as
-- a camera some 15 yards behind you would see it: full size up to NEAR yards, then
-- (NEAR + CAM) / (yards + CAM), never under SMALLEST. A marked NPC's distance is
-- exact (where it was marked). Any other NPC's comes from the game's own checks only
-- (CheckInteractDistance): within 10 yards, within 28, or further, taken as 6, 19
-- and 35 yards, so three sizes, and the size glides between them over about a
-- second. (Item range checks, tried first for 5-yard steps, answered differently for
-- different kinds of NPC: Max's horses beside Erma got other sizes at the same
-- distance. Max chose the game's checks, 12 Nov.) In combat the game won't say for a
-- friendly NPC, so the size stays as it was.
local NEAR, CAM, SMALLEST = 8, 15, 0.45
local STEP_YARDS = { 6, 19, 35 }  -- within 10 yards, within 28, beyond
local EASE = 1.5                  -- how fast the size follows (per second): a glide of about a second
local LOOK_EVERY = 0.15           -- seconds between distance checks per name

Names.holding = false -- the add-on turned the nameplates on and holds them
Names.dressing = false -- friendly NPC plates are dressed name-only now (held by us, or the player's own near a marker)
Names.styled = {}     -- unit -> { frames = { frame -> alpha }, label }: the plates we dress name-only
Names.dark = {}       -- frame -> true: frames on a dressed plate, kept see-through
Names.titles = {}     -- npc ID -> its <title> ("" for none), read once from the game's tooltip

local function secret(v) return issecretvalue and issecretvalue(v) or false end

local function getCVar(name)
  local get = (C_CVar and C_CVar.GetCVar) or GetCVar
  if not get then return nil end
  local ok, v = pcall(get, name)
  if not ok or secret(v) then return nil end
  return v
end

local function setCVar(name, value)
  local set = (C_CVar and C_CVar.SetCVar) or SetCVar
  if not set then return false end
  return pcall(set, name, tostring(value)) == true
end

local function combat()
  return InCombatLockdown and InCombatLockdown() or false
end

function Names:Enabled()
  return MOTA.db ~= nil and MOTA.db.settings.markerPlates ~= false and Markers:Showing()
end

-- How far the game draws nameplates, in yards (its own CVar, 20 to 60; 40 if unknown).
function Names:Range()
  local v = tonumber(getCVar("nameplateMaxDistance"))
  return v and math.max(20, math.min(60, v)) or 40
end

-- Is an NPC marked for me near enough for its nameplate? Its marker already over
-- its head counts; otherwise the place the Crown recorded for it.
function Names:Wanted()
  if not self:Enabled() then return false end
  if next(UI.plates) then return true end
  local ma, mb, instance = UI.MyWorld()
  if not ma then return false end
  local reach = self:Range() + ((self.holding or self.dressing) and OFF_MARGIN or ON_MARGIN)
  for _, m in ipairs(Markers:List()) do
    local ta, tb, ti = UI.WorldOf(m)
    if ta and ti == instance then
      local da, db = ta - ma, tb - mb
      if da * da + db * db <= reach * reach then return true end
    end
  end
  return false
end

---------------------------------------------------------------------------
-- Holding the CVar
---------------------------------------------------------------------------

local function letGo(self)
  self.holding = false
  if MOTA.db then MOTA.db.npcPlates = nil end
end

-- Puts the player's value back (not in combat: it waits). true when done.
function Names:Release()
  if not self.holding then return true end
  if combat() then return false end
  local was = MOTA.db and MOTA.db.npcPlates and MOTA.db.npcPlates.was
  if getCVar(CVAR) == "1" and was then setCVar(CVAR, was) end
  letGo(self)
  return true
end

function Names:Take()
  local cur = getCVar(CVAR)
  if cur == nil or cur == "1" or combat() then return end -- the client lacks it, the player shows them already, or in combat
  MOTA.db.npcPlates = { was = cur }
  if not setCVar(CVAR, "1") or getCVar(CVAR) ~= "1" then
    MOTA.db.npcPlates = nil
    return
  end
  self.holding = true
end

-- Every half second, and when combat ends: on, off, or as it is.
function Names:Tick()
  if not MOTA.db then return end
  if not self.holding and MOTA.db.npcPlates then self:Recover() end
  local want = self:Wanted()
  if self.holding then
    if not want then
      self:Release()
    elseif getCVar(CVAR) ~= "1" and not combat() then
      -- something turned it off while a marked NPC is near: ours has the last word
      setCVar(CVAR, "1")
    end
  elseif want then
    self:Take()
  end
  -- dress the plates while ours are on, or the player's own near a marked NPC
  local dress = self:Enabled() and (self.holding or (want and getCVar(CVAR) == "1")) or false
  if dress ~= self.dressing then
    self.dressing = dress
    if not dress then self:UnstyleAll() end
    UI:Rescan()
  elseif dress then
    self:Restyle()
  end
end

-- After a /reload or a crash while we held it: take the hold up again (the player's
-- value is in the saved variables), so it is put back when no marked NPC is near.
-- If the CVar didn't keep our "1" (the game didn't save it), there is nothing to put back.
function Names:Recover()
  local rec = MOTA.db and MOTA.db.npcPlates
  if not rec or self.holding then return end
  if type(rec.was) ~= "string" or getCVar(CVAR) ~= "1" then
    MOTA.db.npcPlates = nil
    return
  end
  self.holding = true
end

---------------------------------------------------------------------------
-- Name only
---------------------------------------------------------------------------

local function friendlyNPC(unit)
  local ok, player = pcall(UnitIsPlayer, unit)
  if not ok or secret(player) or player then return false end
  if UnitIsFriend then
    local ok2, friend = pcall(UnitIsFriend, "player", unit)
    if ok2 and not secret(friend) then return friend == true end
  end
  local ok3, hostile = pcall(UnitCanAttack, "player", unit)
  return ok3 and not secret(hostile) and hostile == false
end

-- The frames on a nameplate: the game's unit frame, and whatever another nameplate
-- add-on hung there. (Ours are on UIParent, never on the plate.)
local function plateFrames(plate)
  local ok, kids = pcall(function() return { plate:GetChildren() } end)
  local out = {}
  if ok then
    for _, f in ipairs(kids) do
      if type(f) == "table" and not secret(f) and f.SetAlpha then out[#out + 1] = f end
    end
  end
  local okU, uf = pcall(function() return plate.UnitFrame end)
  if okU and type(uf) == "table" and not secret(uf) then
    local seen = false
    for _, f in ipairs(out) do if f == uf then seen = true end end
    if not seen then out[#out + 1] = uf end
  end
  return out
end

-- Keeps a frame see-through while it is on a dressed plate, even if the game or
-- another add-on lights it again (a hook after its SetAlpha: nothing replaced).
local hooked = {}
local function darken(f)
  Names.dark[f] = true
  pcall(f.SetAlpha, f, 0)
  if not hooked[f] and hooksecurefunc then
    hooked[f] = true
    pcall(hooksecurefunc, f, "SetAlpha", function(self, a)
      if Names.dark[self] and type(a) == "number" and not secret(a) and a > 0 and not Names.busy then
        Names.busy = true
        pcall(self.SetAlpha, self, 0)
        Names.busy = false
      end
    end)
  end
end

-- The NPC's <title> ("Engineering Supplier"), as the game's tooltip gives it: the
-- line under the name, unless that line is its level. Read once per NPC.
local LEVEL_WORD = (type(LEVEL) == "string" and LEVEL ~= "") and LEVEL or "Level"
local scanTip
local function titleLine(unit)
  if C_TooltipInfo and C_TooltipInfo.GetUnit then
    local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
    local line = ok and type(data) == "table" and data.lines and data.lines[2]
    return line and line.leftText
  end
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "MinistryOfTheAlliedNameTip", nil, "GameTooltipTemplate")
  end
  local ok = pcall(function()
    scanTip:SetOwner(WorldFrame or UIParent, "ANCHOR_NONE")
    scanTip:SetUnit(unit)
  end)
  local fs = ok and _G["MinistryOfTheAlliedNameTipTextLeft2"]
  local text = fs and fs.GetText and fs:GetText()
  pcall(scanTip.Hide, scanTip)
  return text
end

function Names:Title(unit, npc)
  if npc and self.titles[npc] then return self.titles[npc] end
  local ok, text = pcall(titleLine, unit)
  if not ok or type(text) ~= "string" or secret(text) or text == "" or text:find(LEVEL_WORD, 1, true) then text = "" end
  if npc then self.titles[npc] = text end
  return text
end

local function newLabel()
  -- on WorldFrame with the game's nameplates, so the interface's windows cover it
  local f = CreateFrame("Frame", nil, WorldFrame or UIParent)
  f:SetSize(300, 40)
  f:SetFrameStrata("LOW")
  f:EnableMouse(false)
  local function line()
    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetFont(NAME_FONT, Names:NameSize(), "")
    fs:SetJustifyH("CENTER")
    fs:SetWordWrap(false)
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
    return fs
  end
  f.text, f.title = line(), line()
  f.title:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)
  f.nUnit, f.nMark, f.nWait, f.nGoal, f.nSize = false, false, 0, 1, 0
  f.nFont = Names:NameSize()
  return f
end

local function say(fs, text)
  pcall(fs.SetText, fs, text)
end
local labels = {}

-- Dresses a friendly NPC's plate name-only while we hold the nameplates on: the
-- frames on it see-through, its name (and <title>) drawn by us. Returns the name's
-- font string, for the marker to stand on, or nil when the plate isn't ours to dress.
-- The size for a distance in yards (1 near, smaller further away).
function Names.ScaleFor(yards)
  if type(yards) ~= "number" or yards <= NEAR then return 1 end
  return math.max(SMALLEST, math.min(1, (NEAR + CAM) / (yards + CAM)))
end

-- The game's own range checks for a unit: 10 and 28 yards. true, false, or nil.
local function gameCheck(unit, i)
  if not CheckInteractDistance then return nil end
  local ok, v = pcall(CheckInteractDistance, unit, i)
  if not ok or secret(v) or v == nil then return nil end
  return v and true or false
end

-- For /mota marker probe: what the game says for a unit.
function Names:RangeAnswers(unit)
  local function word(v) return v == true and "yes" or v == false and "no" or "-" end
  return "within 10:" .. word(gameCheck(unit, 3)) .. " within 28:" .. word(gameCheck(unit, 4))
end

-- How far a plate's NPC is: exact for a marked NPC, else the game's step; nil to keep the size as it is.
function Names:Yards(unit, m)
  if m then
    local ma, mb, instance = UI.MyWorld()
    local ta, tb, ti = UI.WorldOf(m)
    if ma and ta and ti == instance then
      local da, db = ta - ma, tb - mb
      return math.sqrt(da * da + db * db)
    end
  end
  if combat() then return nil end -- the game keeps a friendly NPC's range to itself in combat
  local near = gameCheck(unit, 3)
  if near == true then return STEP_YARDS[1] end
  local mid = gameCheck(unit, 4)
  if mid == nil then return nil end
  if near == nil and mid == true then return nil end -- within 28 but not knowing if within 10: keep it
  return mid and STEP_YARDS[2] or STEP_YARDS[3]
end

-- Each frame: the name (and the marker standing on it) eases toward its size.
-- (The label keeps its state in fields set when it is made: nUnit, nMark, nWait,
-- nGoal, nSize; nSize 0 means "no size yet: go straight to the goal".)
local function follow(l, elapsed)
  elapsed = elapsed or 0
  l.nWait = l.nWait - elapsed
  if l.nWait <= 0 then
    l.nWait = LOOK_EVERY
    local yards = Names:Yards(l.nUnit, l.nMark or nil)
    if yards then l.nGoal = Names.ScaleFor(yards) end
  end
  local goal = l.nGoal
  local cur = l.nSize > 0 and l.nSize or goal
  cur = cur + (goal - cur) * math.min(1, elapsed * EASE)
  if math.abs(goal - cur) < 0.005 then cur = goal end
  l.nSize = cur
  local k = UI.WorldScale() * UI.UserScale()
  l:SetScale(cur * k)
  local p = UI.plates[l.nUnit]
  if p and p.seal then p.seal:SetScale(cur * k) end
end
Names.Follow = follow

-- The names' font size (/mota marker namesize; 16 unless changed).
function Names:NameSize()
  return UI.Setting("namesize")
end

function Names:NameY()
  return UI.Setting("namey")
end

function Names:Style(unit, m, plate)
  if not self.dressing or not friendlyNPC(unit) then return self:Unstyle(unit) end
  local s = self.styled[unit]
  if s and s.plate ~= plate then self:Unstyle(unit) s = nil end
  if not s then
    s = { plate = plate, frames = {} }
    self.styled[unit] = s
  end
  for _, f in ipairs(plateFrames(plate)) do
    if s.frames[f] == nil then
      local ok, a = pcall(f.GetAlpha, f)
      s.frames[f] = (ok and type(a) == "number" and not secret(a) and a > 0) and a or 1
    end
    darken(f)
  end
  local l = s.label or table.remove(labels) or newLabel()
  s.label = l
  local size = self:NameSize()
  if l.nFont ~= size then
    l.nFont = size
    pcall(l.text.SetFont, l.text, NAME_FONT, size, "")
    pcall(l.title.SetFont, l.title, NAME_FONT, size, "")
  end
  local ok, name = pcall(UnitName, unit)
  if not ok or name == nil then name = m and m.name or "" end
  say(l.text, name)
  local okG, guid = pcall(UnitGUID, unit)
  local title = self:Title(unit, okG and Markers:NpcId(guid) or nil)
  l.text:ClearAllPoints()
  if title ~= "" then
    say(l.title, "<" .. title .. ">")
    l.title:Show()
    l.text:SetPoint("BOTTOM", l.title, "TOP", 0, 1)
  else
    say(l.title, "")
    l.title:Hide()
    l.text:SetPoint("BOTTOM", l, "BOTTOM", 0, 0)
  end
  if l.nUnit ~= unit then -- a plate new to this label: straight to its size, no easing from the last one's
    l.nWait, l.nSize, l.nGoal = 0, 0, 1
  end
  l.nUnit, l.nMark = unit, m or false
  follow(l, 0)
  l:SetScript("OnUpdate", follow)
  l:ClearAllPoints()
  -- at the foot of the plate (over the NPC's head), where the game's health bar
  -- would be: lower than a full nameplate's name (Max, 12 Nov); /mota marker namey moves it
  l:SetPoint("BOTTOM", plate, "BOTTOM", 0, self:NameY())
  l:Show()
  return l.text
end

-- Gives a plate back as the game had it (the game reuses the frame for other units).
function Names:Unstyle(unit)
  local s = self.styled[unit]
  if not s then return nil end
  for f, a in pairs(s.frames) do
    self.dark[f] = nil
    pcall(f.SetAlpha, f, a)
  end
  if s.label then
    s.label:Hide()
    s.label:SetScript("OnUpdate", nil)
    s.label:ClearAllPoints()
    s.label:SetScale(UI.WorldScale() * UI.UserScale())
    s.label.nUnit, s.label.nMark = false, false
    labels[#labels + 1] = s.label
  end
  local p = UI.plates[unit]
  if p and p.seal then p.seal:SetScale(UI.WorldScale() * UI.UserScale()) end
  self.styled[unit] = nil
  return nil
end

function Names:UnstyleAll()
  for unit in pairs(self.styled) do self:Unstyle(unit) end
end

-- Plates that are gone (a rescan didn't see them).
function Names:Forget(seen)
  for unit in pairs(self.styled) do
    if not seen[unit] then self:Unstyle(unit) end
  end
end

-- What the game does to nameplates over distance, for /mota marker probe: each
-- plate's unit, its scale and effective scale, and its size. (To learn whether the
-- names can follow the game's own shrinking with distance.)
function Names:Probe()
  local out = {}
  if not (C_NamePlate and C_NamePlate.GetNamePlates) then return out end
  local ok, plates = pcall(C_NamePlate.GetNamePlates)
  if not ok or type(plates) ~= "table" then return out end
  for _, plate in ipairs(plates) do
    local function num(fn) local o, v = pcall(fn) return o and type(v) == "number" and not secret(v) and v or 0 end
    local okU, unit = pcall(function() return plate.namePlateUnitToken end)
    local okN, name = false, nil
    if okU and type(unit) == "string" then okN, name = pcall(UnitName, unit) end
    local okF, uf = pcall(function() return plate.UnitFrame end)
    if not okF or type(uf) ~= "table" then uf = nil end
    out[#out + 1] = {
      name = okN and type(name) == "string" and not secret(name) and name or "?",
      scale = num(function() return plate:GetScale() end),
      eff = num(function() return plate:GetEffectiveScale() end),
      ufScale = uf and num(function() return uf:GetScale() end) or 0,
      w = num(function() return plate:GetWidth() end), h = num(function() return plate:GetHeight() end),
    }
  end
  return out
end

-- Where the SetAlpha hook isn't there, keep the dressed frames see-through each tick.
function Names:Restyle()
  for f in pairs(self.dark) do
    local ok, a = pcall(f.GetAlpha, f)
    if ok and type(a) == "number" and not secret(a) and a > 0 then pcall(f.SetAlpha, f, 0) end
  end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

MOTA:On("PLAYER_LOGIN", function()
  C_Timer.NewTicker(TICK, function() Names:Tick() end)
end)
MOTA:On("PLAYER_ENTERING_WORLD", function()
  -- a look soon after a login or a /reload (the half-second tick carries on from there)
  C_Timer.After(2, function() Names:Tick() end)
end)
MOTA:On("PLAYER_REGEN_ENABLED", function() Names:Tick() end)
MOTA:On("PLAYER_LOGOUT", function() Names:Release() end)
