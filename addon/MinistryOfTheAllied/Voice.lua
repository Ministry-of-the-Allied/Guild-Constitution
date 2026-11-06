-- Ministry of the Allied: the Charter narration (ADDON_SPEC.md, section 12).
-- On first login, the introduction plays and can't be stopped. The other clips
-- follow one at a time, VOICE_CLIP_GAP seconds after the last one ended, and
-- pick up where they left off on the next login. WoW can't pause or seek a
-- sound, so a stopped clip can only start again from the beginning.

local _, MOTA = ...
local Voice = {}
MOTA.Voice = Voice

local PATH = "Interface\\AddOns\\MinistryOfTheAllied\\Media\\Voice\\voice_%02d.ogg"
local START_DELAY = 6  -- seconds after the guild is known, so the loading screen has gone
local RETRY_DELAY = 15 -- when a clip comes due during combat or another clip, look again this soon

local playing, handle, endTimer, gapTimer, herald, watcher
local begun

local function CONST() return MOTA.CONST end
function Voice:Clips() return CONST().VOICE_CLIPS end
function Voice:Playing() return playing end -- { index, onboarding, locked }

local function characterId()
  return UnitGUID("player") or UnitName("player")
end

function Voice:State()
  local all = MOTA.db.onboarding
  local id = characterId()
  all[id] = all[id] or { started = 0, nextClip = 1, heard = {}, complete = false }
  return all[id]
end

function Voice:Enabled() return MOTA.db.settings.voice end

-- The Statute Book and /mota voice can't interrupt the introduction.
function Voice:Locked() return playing ~= nil and playing.locked end

function Voice:Length(seconds)
  local whole = math.floor(seconds + 0.5)
  return ("%d:%02d"):format(math.floor(whole / 60), whole % 60)
end

---------------------------------------------------------------------------
-- Playing one clip
---------------------------------------------------------------------------

local function stopWatching()
  if watcher then watcher:Cancel() watcher = nil end
end

-- The game can drop a clip early, such as on tabbing out, without telling the
-- add-on. Where the client can report it, a clip heard playing that then falls
-- silent counts as cut off. A clip never heard playing isn't judged at all.
local function watch(h)
  stopWatching()
  if not (C_Sound and C_Sound.IsPlaying) then return end
  local heard = false
  watcher = C_Timer.NewTicker(1, function()
    if C_Sound.IsPlaying(h) then
      heard = true
    elseif heard then
      stopWatching()
      Voice:CutOff()
    end
  end)
end

local function silence()
  stopWatching()
  if handle then StopSound(handle) end
  handle = nil
  if endTimer then endTimer:Cancel() endTimer = nil end
end

-- Moves the staged sequence on, once a clip has ended or been stopped.
local function clipDone(index)
  local state = Voice:State()
  if state.nextClip == index then state.nextClip = index + 1 end
  if state.nextClip > #Voice:Clips() then state.complete = true end
  if not state.complete then Voice:ScheduleNext(CONST().VOICE_CLIP_GAP) end
end

local function onEnded()
  local p = playing
  stopWatching()
  playing, handle, endTimer = nil, nil, nil
  Voice:State().heard[p.index] = true
  if p.onboarding then clipDone(p.index) end
  if herald then MOTA.Herald:Close(herald) end
  MOTA:Fire("VOICE_CHANGED")
end

local function begin(index, onboarding, locked)
  silence()
  local willPlay, h = PlaySoundFile(PATH:format(index), "Master")
  handle = h
  if willPlay and h then watch(h) end
  if not willPlay then
    MOTA:Print("The narration couldn't play. Check that the game's sound is on. You can replay it in the Statute Book.")
  end
  playing = { index = index, onboarding = onboarding, locked = locked }
  endTimer = C_Timer.NewTimer(Voice:Clips()[index].length, onEnded)
  MOTA:Fire("VOICE_CHANGED")
end

---------------------------------------------------------------------------
-- The pop-ups
---------------------------------------------------------------------------

local PLAYING_TEXT = "Stop it if you wish. It can only restart from the beginning."
local STOPPED_TEXT = "Stopped. Restarting begins again from the beginning."

local function stopButton()
  return { label = "Stop", style = "quiet", keep = true, onPress = function() Voice:Stop() end }
end

local function restartButton(index)
  return { label = "Restart", style = "blue", keep = true, onPress = function() Voice:Replay(index) end }
end

local function eyebrow(index)
  return ("The Royal Charter · %d of %d"):format(index, #Voice:Clips())
end

local function announce(index)
  local clip = Voice:Clips()[index]
  local isIntro = index == 1
  herald = {
    seal = "official",
    eyebrow = isIntro and "Hear ye · the Royal Charter" or eyebrow(index),
    title = clip.title,
    text = isIntro and "Listen well, citizen. You may close this scroll; the narration plays on." or PLAYING_TEXT,
    noFanfare = true,
    stay = isIntro and CONST().VOICE_INTRO_HERALD_SECONDS or false,
    closeX = not isIntro,
    button = isIntro and { label = "Dismiss", style = "quiet" } or stopButton(),
    onShow = function()
      local state = Voice:State()
      if state.started == 0 then state.started = GetServerTime() end
      begin(index, true, isIntro)
    end,
    onGone = function(h) if herald == h then herald = nil end end,
  }
  MOTA.Herald:Announce(herald, true)
end

-- The scroll for a replay. There is only ever one voice scroll: pressing Play
-- again rewrites it where it is, so quick presses never stack up a queue.
local function present(index)
  local h = herald or { seal = "official", noFanfare = true, closeX = true,
    onGone = function(gone) if herald == gone then herald = nil end end }
  h.eyebrow, h.title, h.text = eyebrow(index), Voice:Clips()[index].title, PLAYING_TEXT
  h.button, h.stay, h.closeX, h.onShow = stopButton(), false, true, nil
  if herald then
    MOTA.Herald:Update(h)
  else
    herald = h
    MOTA.Herald:Announce(h, true)
  end
end

---------------------------------------------------------------------------
-- The staged sequence
---------------------------------------------------------------------------

function Voice:ScheduleNext(seconds)
  if gapTimer then gapTimer:Cancel() end
  gapTimer = C_Timer.NewTimer(seconds, function()
    gapTimer = nil
    Voice:Due()
  end)
end

function Voice:Due()
  if not self:Enabled() or not MOTA.guild then return end
  local state = self:State()
  if state.complete then return end
  if playing or herald or InCombatLockdown() then
    self:ScheduleNext(RETRY_DELAY)
    return
  end
  announce(state.nextClip)
end

function Voice:Begin()
  if begun or not self:Enabled() then return end
  local state = self:State()
  if state.complete then return end
  begun = true
  self:ScheduleNext(state.nextClip == 1 and START_DELAY or CONST().VOICE_CLIP_GAP)
end

MOTA:Listen("GUILD_READY", function() Voice:Begin() end)

---------------------------------------------------------------------------
-- The Statute Book and /mota voice
---------------------------------------------------------------------------

-- Plays a clip again. Refused only while the introduction is playing.
function Voice:Replay(index)
  if self:Locked() then return false end
  if playing and playing.onboarding then clipDone(playing.index) end
  begin(index, false, false)
  present(index)
  return true
end

function Voice:Stop()
  if not playing or playing.locked then return false end
  local p = playing
  silence()
  playing = nil
  if p.onboarding then clipDone(p.index) end
  if herald then
    if MOTA.Herald:IsShowing(herald) then
      herald.text, herald.button = STOPPED_TEXT, restartButton(p.index)
      herald.stay = CONST().VOICE_STOPPED_HERALD_SECONDS
      MOTA.Herald:Update(herald)
      MOTA.Herald:HideLater(herald.stay)
    else
      MOTA.Herald:Close(herald)
    end
  end
  MOTA:Fire("VOICE_CHANGED")
  return true
end

-- A clip the game dropped: offer Restart, even for the introduction.
function Voice:CutOff()
  if not playing then return end
  local index = playing.index
  MOTA:Debug("clip", index, "was cut off by the game")
  playing.locked = false
  if herald then
    herald.closeX = true
  else
    present(index)
  end
  self:Stop()
  if herald then
    herald.text = "The narration was interrupted. Restart to hear it from the beginning."
    MOTA.Herald:Update(herald)
    MOTA.Herald:HideLater(herald.stay)
  end
end

function Voice:SetEnabled(on)
  if not on and self:Locked() then return false end
  MOTA.db.settings.voice = on
  begun = nil
  if gapTimer then gapTimer:Cancel() gapTimer = nil end
  if on then self:Begin() end
  return true
end

-- For testing: start the sequence over, or bring the next clip forward.
function Voice:Reset()
  if self:Locked() then return false end
  self:Stop()
  if gapTimer then gapTimer:Cancel() gapTimer = nil end
  MOTA.db.onboarding[characterId()] = nil
  begun = nil
  self:Begin()
  return true
end

function Voice:PlayNext()
  if gapTimer then gapTimer:Cancel() gapTimer = nil end
  self:Due()
end
