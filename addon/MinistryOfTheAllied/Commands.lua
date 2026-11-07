-- Ministry of the Allied: slash commands.
-- /mota (or /ministry) opens the window (ADDON_SPEC.md, section 16.3);
-- /mota followed by one of the commands below does that instead.

local _, MOTA = ...

local commands, order = {}, {}

-- shown (optional): a function that says whether this player is shown the
-- command in the help list; left out, everyone sees it.
local function add(name, usage, help, fn, shown)
  commands[name] = fn
  order[#order + 1] = { name = name, usage = usage, help = help, shown = shown }
end

local function needGuild()
  if MOTA.guild then return true end
  if IsInGuild() then
    MOTA:Print("The guild roster hasn't loaded yet. Try again in a moment.")
    MOTA:RequestRoster()
  else
    MOTA:Print("This character isn't in a guild. Most of the Ministry needs one.")
  end
  return false
end

local function showHelp()
  for _, c in ipairs(order) do
    if not c.shown or c.shown() then
      MOTA:Print(MOTA:Color("leaf", "/mota " .. c.name .. (c.usage ~= "" and " " .. c.usage or "")), "·", c.help)
    end
  end
end

local function statusLine()
  local total = MOTA.Book:Count()
  local online = MOTA.Hello:OnlineCount()
  local guild = MOTA.guild and (GetGuildInfo("player") or "?") or "no guild yet"
  MOTA:Print(MOTA:Color("leaf", "Ministry of the Allied") .. " v" .. MOTA.VERSION, "·", guild, "·",
    total, (total == 1 and "record" or "records") .. " ·", online,
    (online == 1 and "other citizen" or "other citizens") .. " online with the add-on")
end

add("sync", "", "records held, who you've heard from, messages sent", function()
  if not needGuild() then return end
  local total, authors, mine = MOTA.Book:Count()
  local s = MOTA.stats
  local heard = {}
  for name in pairs(MOTA.Hello.heard) do heard[#heard + 1] = MOTA:Short(name) end
  table.sort(heard)
  MOTA:Print("Records:", total, "held from", authors, (authors == 1 and "author" or "authors") .. ",", mine, "of them yours · unconfirmed: 0")
  MOTA:Print("Heard from this session:", #heard > 0 and table.concat(heard, ", ") or "nobody yet")
  MOTA:Print("Last record received:", MOTA:Ago(s.lastReceived))
  MOTA:Print("Messages:", s.sent, "sent,", MOTA.Comm:Waiting(), "waiting,", s.failed, "failed · received", s.received,
    "(" .. s.ignored .. " ignored, " .. s.conflicts .. " clashing record IDs)")
  if MOTA.outdated then
    MOTA:Print(MOTA:Color("crimson", "A newer version of the add-on is in use, so this copy won't send records. Please update."))
  end
end)

add("who", "", "guild members running the add-on", function()
  if not needGuild() then return end
  MOTA:RequestRoster()
  local list = MOTA.Hello:List()
  local hasAddon = {}
  if #list == 0 then
    MOTA:Print("Nobody else's add-on has said hello yet.")
  end
  for _, e in ipairs(list) do
    local p = e.peer
    hasAddon[e.name] = true
    local where = e.online and MOTA:Color("leaf", "online") or ("last heard " .. MOTA:Ago(p.seen))
    local count = p.c and (" · " .. p.c .. " records") or ""
    MOTA:Print(MOTA:Color("leaf", MOTA:Short(e.name)), "· v" .. tostring(p.v) .. count, "·", where)
  end
  -- Online guild members whose add-on hasn't spoken: they don't have it, have
  -- it switched off, or run a copy too old to hear this one.
  local without = {}
  for name, r in pairs(MOTA.roster) do
    if r.online and not hasAddon[name] and not MOTA:IsMe(name) then without[#without + 1] = MOTA:Short(name) end
  end
  table.sort(without)
  if #without > 0 then
    MOTA:Print(MOTA:Color("grey", "Online without the add-on (or with an old copy): " .. table.concat(without, ", ")))
  end
end)

add("test", "<text>", "write a test record and send it to the guild", function(text)
  if not needGuild() then return end
  if text == "" then text = "Hear ye!" end
  -- One record has to fit in one 255-byte message, with room for its ID and type.
  if #text > 150 then
    text = text:sub(1, 150):gsub("[\192-\255][\128-\191]*$", "") -- don't cut a letter in half
    MOTA:Print("That's too long for one test record, so it was shortened.")
  end
  local rec, why = MOTA.Book:Write("test.note", { text = text })
  if not rec then MOTA:Print("Not written:", why) end
end)

add("book", "", "the last 10 records in your book", function()
  if not needGuild() then return end
  local list = MOTA.Book:Latest(10)
  if #list == 0 then return MOTA:Print("The book is empty. Try /mota test.") end
  for _, r in ipairs(list) do
    MOTA:Print(MOTA:Color("leaf", MOTA:Short(r.a) .. " #" .. r.n), "·", r.k, "·", MOTA:Ago(r.t), "·", MOTA.Book:Describe(r))
  end
end)

add("constitution", "", "read and hear the Charter", function()
  MOTA.UI:Build()
  for i, page in ipairs(MOTA.Media.pages) do
    if page.id == "statute" then MOTA.UI:SelectPage(i) end
  end
  MOTA.StatutesPage:Select("charter")
  MOTA.UI.window:Show()
end)

add("ballot", "[count]", "open the Ballot Hall and say where the vote stands; 'count' shows the Crown's count", function(arg)
  if not needGuild() then return end
  local B = MOTA.Ballot
  local b = B:Current()
  local stage = B:Stage(b)
  if arg == "count" then
    if not B:IsKing() then return MOTA:Print("Only the two Crown ranks hold the count.") end
    if not b then return MOTA:Print("No election is open or waiting to be declared.") end
    local t = B:Tally(b.id)
    local parts = {}
    for i, c in ipairs(b.d.cands) do parts[#parts + 1] = c.n .. " " .. (t.counts[i] or 0) end
    MOTA:Print(b.d.name, "·", stage, "·", table.concat(parts, ", "), "· held", B:HeldCount(b), "· refused", t.refused or 0)
    for _, k in ipairs(B:Kings()) do
      if not k.me then
        local pc = B:PeerCount(b.id, k.name)
        MOTA:Print(MOTA:Short(k.name) .. ":", not k.online and "offline" or not pc and "not compared yet"
          or (pc.same and "counts agree (" .. pc.total .. ")" or "counts differ (" .. pc.total .. ")"))
      end
    end
    return
  end
  if stage == "open" then
    local mine = ({ none = "you haven't voted yet", sending = "your ballot is on its way", held = "your ballot is sealed and waiting for a King",
      sent = "your ballot was received", late = "your ballot arrived too late" })[B:MyState(b)]
    MOTA:Print(b.d.name, "· polls close in", B:Left(B:CloseTime(b)), "·", mine)
  elseif stage == "closed" then
    MOTA:Print(b.d.name, "· polls closed, the Crown is counting")
  else
    local last = B:Results()[1]
    MOTA:Print(last and ("No polls open · last result: " .. last.result.name) or "No polls open.")
  end
  MOTA.UI:Build()
  for i, page in ipairs(MOTA.Media.pages) do
    if page.id == "ballot" then MOTA.UI:SelectPage(i) end
  end
  MOTA.UI.window:Show()
end)

add("voice", "[on|off|stop|next|reset]", "the Charter narration: how far it's got, or control it", function(arg)
  local V = MOTA.Voice
  local busy = "Not while the introduction is being read."
  if arg == "on" or arg == "off" then
    if not V:SetEnabled(arg == "on") then return MOTA:Print(busy) end
    MOTA:Print("The Charter narration is", arg == "on" and "on." or "off. You can still play it in the Statute Book.")
  elseif arg == "stop" then
    if V:Locked() then MOTA:Print(busy) else V:Stop() end
  elseif arg == "next" then
    V:PlayNext()
  elseif arg == "reset" then
    if V:Reset() then MOTA:Print("The narration starts again from the introduction.") else MOTA:Print(busy) end
  else
    local s = V:State()
    MOTA:Print("Charter narration:", V:Enabled() and "on" or "off", "·",
      s.complete and "finished" or ("next is " .. s.nextClip .. " of " .. #V:Clips()))
  end
end)

add("ring", "", "who holds the Minister of War rank", function()
  if not needGuild() then return end
  local m = MOTA.Ring:Minister()
  MOTA:Print("Minister of War:", m and MOTA:Short(m) or "none appointed")
end)

add("probe", "[limits|bank]", "client facts for the add-on plan; 'limits' measures message limits, 'bank' what the guild bank shows", function(arg)
  if arg == "limits" then
    MOTA.Probe:Limits()
  elseif arg == "bank" then
    MOTA.Probe:Bank()
  else
    MOTA.Probe:Report()
  end
end)

add("scale", "<size>", "the window's size, such as 0.8 (blank for the default)", function(arg)
  local n = tonumber(arg)
  if arg ~= "" and (not n or n < 0.4 or n > 1.5) then
    return MOTA:Print("Give a size between 0.4 and 1.5, such as /mota scale 0.8.")
  end
  MOTA.db.window.scale = n
  MOTA.UI:Build()
  local used = MOTA.UI:SetScale(n)
  MOTA:Print(("Window size %.2f%s."):format(used, n and used < n and " (as big as fits your screen)" or ""))
end)

local function isCrown()
  return MOTA.me ~= nil and MOTA:IsCrown(MOTA.me)
end

-- Crown ranks only (ADDON_SPEC.md 9.1): everyone else wears the skin of their
-- guild rank, and the command isn't listed for them.
add("skin", "[crown|silverhand|exchange|ministry]", "try a window skin on your own screen until /reload; blank goes back to yours", function(arg)
  if not isCrown() then
    return MOTA:Print("Window skins follow your guild rank; only the Crown ranks can change theirs.")
  end
  local S = MOTA.Skin
  if not S:Preview(arg) then
    return MOTA:Print("There's no skin called \"" .. arg .. "\". Try crown, silverhand, exchange or ministry.")
  end
  MOTA.UI:Build()
  MOTA.UI.window:Show()
  if S.preview then
    MOTA:Print("Trying the skin of " .. S.titles[S.preview] .. ". /mota skin goes back to yours; /reload does too.")
  else
    MOTA:Print("Back to your own skin: " .. S.titles[MOTA.skin.KEY] .. ".")
  end
end, isCrown)

add("books", "open", "Crown: restart the ledger at the balance last counted at the guild bank", function(arg)
  if arg ~= "open" then return MOTA:Print("/mota books open restarts the ledger at the balance last counted at the guild bank.") end
  local rec, err = MOTA.Ledger:OpenBooks()
  if rec then MOTA:Print("The books are open at", MOTA:Money(rec.d.bal) .. ".") else MOTA:Print(err) end
end, isCrown)

add("refunds", "[name]", "Ring organisers: who's owed an entry fee back; a name marks theirs as refunded", function(arg)
  local Ring = MOTA.Ring
  local cur = Ring:Current()
  if not Ring:CanOrganise() then return MOTA:Print("Only the Minister of War or the Crown handle refunds.") end
  if arg and arg ~= "" then
    if not Ring:Refunded(arg) then MOTA:Print("Nobody by that exact name is owed a refund.") end
    return
  end
  local list = cur and cur.refunds or {}
  MOTA:Print(#list > 0 and ("Owed a refund: " .. table.concat(list, ", ")) or "Nobody is owed a refund.")
end, function() return MOTA.Ring:CanOrganise() end)

add("contest", "[advance|ratify sh|ratify ex|declare sh <name>]", "Crown: where the leadership contests stand, or move them on", function(arg)
  local Co = MOTA.Contest
  local word, rest = (arg or ""):match("^(%S*)%s*(.-)$")
  local rec, err
  if word == "advance" then rec, err = Co:Advance()
  elseif word == "ratify" then rec, err = Co:Ratify(rest)
  elseif word == "declare" then
    local p, name = rest:match("^(%a+)%s+(.+)$")
    rec, err = Co:Ratify(p, name)
  else
    for _, p in ipairs({ "sh", "ex" }) do MOTA:Print(MOTA.Party.NAMES[p], "·", Co:Stage(p), "·", Co:Banner(p)) end
    return
  end
  if err then MOTA:Print(err) elseif rec then MOTA:Print("Done.") end
end, isCrown)

add("minimap", "", "hide or show the seal on the minimap", function()
  local show = MOTA.db.minimap.hide
  MOTA.UI:ShowMinimapSeal(show)
  MOTA:Print(show and "The seal is back on the minimap." or "The minimap seal is hidden. /mota minimap brings it back.")
end)

add("settings", "", "open the Ministry's settings in the game's options", function()
  MOTA.UI:OpenSettings()
end)

add("herald", "[1-3]", "show the sample heralds from the design canvas", function(arg)
  MOTA.Herald:ShowSamples(tonumber(arg))
end)

add("fanfare", "[number]", "list the game's fanfare sounds, or play and choose one", function(arg)
  local list = MOTA.Herald:Fanfares()
  if #list == 0 then return MOTA:Print("This client has none of the fanfare sounds the add-on knows.") end
  local n = tonumber(arg)
  if n and list[n] then
    MOTA.db.settings.fanfareSound = list[n]
    MOTA.Herald:PlayFanfare(list[n])
    return MOTA:Print("Fanfare", n, "(" .. list[n] .. ") chosen for the heralds.")
  end
  local chosen = MOTA.db.settings.fanfareSound or list[1]
  for i, name in ipairs(list) do
    MOTA:Print(MOTA:Color("leaf", i), name, name == chosen and MOTA:Color("leaf", "· chosen") or "")
  end
  MOTA:Print("/mota fanfare <number> plays one and chooses it.")
end)

add("crests", "", "show the game's own Alliance crests, to choose one", function()
  MOTA.UI:ShowCrests()
end)

add("crest", "<number|ours>", "try one of the game's crests in the window, or ours", function(arg)
  MOTA.UI:ChooseCrest(arg)
end)

add("debug", "", "show the raw hidden add-on traffic in chat (on or off)", function()
  MOTA.db.settings.debug = not MOTA.db.settings.debug
  MOTA:Print("Debug messages", MOTA.db.settings.debug and "on." or "off.")
end)

add("help", "", "this list", function()
  statusLine()
  showHelp()
end)

SLASH_MINISTRYOFTHEALLIED1 = "/mota"
SLASH_MINISTRYOFTHEALLIED2 = "/ministry"
SlashCmdList.MINISTRYOFTHEALLIED = function(input)
  local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  if cmd == "" then
    return MOTA.UI:Toggle()
  end
  local fn = commands[cmd]
  if fn then
    fn(rest or "")
  else
    MOTA:Print("Unknown command \"" .. cmd .. "\". Commands:")
    showHelp()
  end
end
