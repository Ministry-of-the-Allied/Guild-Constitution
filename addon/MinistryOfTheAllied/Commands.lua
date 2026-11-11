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

local function isCrown()
  return MOTA.me ~= nil and MOTA:IsCrown(MOTA.me)
end

-- Who may use which command (Max, 10 Nov): every command is the Crown's alone,
-- except the ones named here. Add a command's name to OPEN to let everyone use it
-- (for the guild to test or look at a feature); a command's own checks still apply.
local OPEN = { help = true, noconfidence = true, settings = true }

local function allowed(name)
  return OPEN[name] == true or isCrown()
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
    if allowed(c.name) and (not c.shown or c.shown()) then
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

add("missing", "", "guild members without the add-on, newest to the guild first, to reach out to", function()
  if not needGuild() then return end
  MOTA:RequestRoster()
  local lines = MOTA.Outreach:Lines()
  if #lines == 0 then return MOTA:Print("Everyone in the guild has the add-on.") end
  MOTA:Print(#lines, #lines == 1 and "member doesn't" or "members don't", "have the add-on yet:")
  for _, line in ipairs(lines) do MOTA:Print(line) end
end)

add("alts", "", "the Crown only: players with more than one character in the guild", function()
  if not needGuild() then return end
  if not MOTA:IsCrown(MOTA.me) then return MOTA:Print("Only the Crown sees which characters are one player.") end
  local groups = MOTA.Account:Groups()
  if #groups == 0 then return MOTA:Print("No player has linked more than one character yet.") end
  MOTA:Print(#groups, #groups == 1 and "player has" or "players have", "more than one character (the first named is the first linked):")
  for _, names in ipairs(groups) do
    local shown = {}
    for i, n in ipairs(names) do shown[i] = MOTA:Short(n) end
    MOTA:Print(table.concat(shown, ", "))
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

add("voice", "[on, off, stop, next, reset]", "the Charter narration: how far it's got, or control it", function(arg)
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

add("ring", "", "who the Minister of War is (the Cabinet's, or the guild rank before a government)", function()
  if not needGuild() then return end
  local m = MOTA.Ring:Minister()
  MOTA:Print("Minister of War:", m and MOTA:Short(m) or "none appointed")
end)

add("probe", "[limits|bank|map]", "client facts for the add-on plan; 'limits' measures message limits, 'bank' what the guild bank shows, 'map' what the world map is made of", function(arg)
  if arg == "limits" then
    MOTA.Probe:Limits()
  elseif arg == "map" then
    MOTA.Probe:Map()
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
  -- changed in the background: the window (and the map) wear it next time they open (Max, 9 Nov)
  MOTA.UI:Build()
  if S.preview then
    MOTA:Print("Trying the skin of " .. S.titles[S.preview] .. ". /mota skin goes back to yours; /reload does too.")
  else
    MOTA:Print("Back to your own skin: " .. S.titles[MOTA.skin.KEY] .. ".")
  end
end, isCrown)

-- Districts: citizens place themselves on first use, the Crown moves them; everyone can read (the page comes in D3).
add("district", "[<name> <code> | rep <code> [name]]", "districts: yours and their sizes; Crown: place a citizen (OLD ARC IRON CATH HARB), or name a Rep.", function(arg)
  if not needGuild() then return end
  local D = MOTA.District
  if arg == "" then
    local mine = D:Of(MOTA.me)
    MOTA:Print("Your district:", mine and mine.name or "none yet (your add-on places you soon after you first log in)")
    local sizes, total = D:Sizes()
    for _, d in ipairs(MOTA.CONST.DISTRICTS) do
      local rep = D:Rep(d.code)
      MOTA:Print(MOTA:Color("leaf", d.code), d.name .. ":", sizes[d.code], sizes[d.code] == 1 and "citizen" or "citizens",
        "· Rep.", rep and MOTA:Short(rep) or "vacant")
    end
    MOTA:Print(total, "placed.")
    return
  end
  if not isCrown() then return MOTA:Print("Only the Crown moves citizens between districts. /mota district shows the districts.") end
  local rep = arg:match("^rep%s+(.*)$")
  if rep then
    local word, who = rep:match("^(%S+)%s*(.-)$")
    local code = D:Code(word)
    if not code then return MOTA:Print("Which district? Try OLD, ARC, IRON, CATH or HARB.") end
    local rec, err = D:SetRep(code, who)
    if rec then
      MOTA:Print("Representative of", D.byCode[code].name .. ":", who ~= "" and rec.d.who or "seat vacant")
    else
      MOTA:Print(err)
    end
    return
  end
  local who, word = arg:match("^(.-)%s+(%S+)$")
  local code = word and D:Code(word)
  if not who or not code then return MOTA:Print("Usage: /mota district <name> <code>, where the code is OLD, ARC, IRON, CATH or HARB.") end
  local rec, err = D:Assign(who, code)
  if rec then MOTA:Print(rec.d.who, "is now a citizen of", D.byCode[code].name .. ".") else MOTA:Print(err) end
end)

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

add("contest", "[advance, ratify sh, declare sh <name>, emergency sh]", "Crown: where the leadership contests stand, or move them on", function(arg)
  local Co = MOTA.Contest
  local word, rest = (arg or ""):match("^(%S*)%s*(.-)$")
  local rec, err
  if word == "advance" then rec, err = Co:Advance()
  elseif word == "ratify" then rec, err = Co:Ratify(rest)
  elseif word == "emergency" then rec, err = Co:CallEmergency(rest)
  elseif word == "date" then rec, err = Co:SetDate(rest) -- testing: skips the gates
  elseif word == "declare" then
    local p, name = rest:match("^(%a+)%s+(.+)$")
    rec, err = Co:Ratify(p, name)
  else
    for _, p in ipairs({ "sh", "ex" }) do MOTA:Print(MOTA.Party.NAMES[p], "·", Co:Stage(p), "·", Co:Banner(p)) end
    return
  end
  if err then MOTA:Print(err) elseif rec then MOTA:Print("Done.") end
end, isCrown)

add("noconfidence", "[yes]", "where a Vote of No Confidence stands, or cast yours with yes", function(arg)
  local C = MOTA.Confidence
  if arg == "yes" then
    local ok, err = C:Vote()
    if err then return MOTA:Print(err) end
    return MOTA:Print("Your vote of no confidence is cast. Only the Kings see who voted.")
  end
  MOTA:Print(C:Line() or (C:Blocked() or "No vote is open. /mota noconfidence yes opens one, for 7 days."))
end)

add("justice", "[appoint <name>, remove <name>]", "the High Judiciary; the Crown appoints the three Justices", function(arg)
  local J = MOTA.Judiciary
  local word, rest = (arg or ""):match("^(%S*)%s*(.-)$")
  local rec, err
  if word == "appoint" then rec, err = J:Appoint(rest)
  elseif word == "remove" then rec, err = J:Remove(rest)
  else
    MOTA:Print(J:Line())
    for _, s in ipairs(J:Justices()) do MOTA:Print(MOTA:Short(s.name), "sits until", date("%d %b %Y", s.ends)) end
    return
  end
  if err then MOTA:Print(err) elseif rec then MOTA:Print("Done.") end
end)

add("games", "[result <title>: <first>, <second>, ...]", "the games log; the Crown and the Minister of Games record results", function(arg)
  if not needGuild() then return end
  local G = MOTA.Games
  local word, rest = (arg or ""):match("^(%S*)%s*(.-)$")
  if word == "result" then
    local title, names = rest:match("^(.-):%s*(.+)$")
    if not title then return MOTA:Print("Usage: /mota games result <title>: <first>, <second>, ... (start the title with hunt, hide, race or quiz to say what kind)") end
    local kind, plain = title:match("^(%a+)%s+(.+)$")
    if not (kind and G.KINDS[kind:lower()]) then kind, plain = "other", title else kind = kind:lower() end
    local places = {}
    for n in names:gmatch("[^,]+") do places[#places + 1] = strtrim(n) end
    local rec, err = G:Record(kind, plain, places)
    if err then MOTA:Print(err) elseif rec then MOTA:Print("Recorded.") end
    return
  end
  local log = G:Log()
  if #log == 0 then return MOTA:Print("No games recorded yet.") end
  MOTA:Print("The games, newest first:")
  for i, e in ipairs(log) do
    if i > 10 then break end
    MOTA:Print(G:Line(e))
  end
end)

add("lottery", "[open <name>, <gold per ticket>, <days>, draw, cancel]", "the Royal Lottery: tickets are bought at the guild bank", function(arg)
  if not needGuild() then return end
  local Lo = MOTA.Lottery
  local word, rest = (arg or ""):match("^(%S*)%s*(.-)$")
  local rec, err
  if word == "open" then
    local parts = {}
    for part in rest:gmatch("[^,]+") do parts[#parts + 1] = strtrim(part) end
    if #parts < 3 then return MOTA:Print("Usage: /mota lottery open <name>, <gold per ticket>, <days of sales>") end
    rec, err = Lo:Open(parts[1], parts[2], parts[3])
  elseif word == "draw" then
    rec, err = Lo:Draw()
  elseif word == "cancel" then
    rec, err = Lo:Cancel()
  else
    local L = Lo:Current()
    MOTA:Print((L and (L.name .. ": ") or "") .. Lo:Line(L))
    local mine = L and Lo:TicketsOf(MOTA.me, L) or 0
    if L and Lo:Stage(L) == "cancelled" and Lo:Owed(L) > 0 then
      for _, e in ipairs(Lo:Refunds(L)) do MOTA:Print(MOTA:Short(e.name), "is owed", MOTA:Money(e.amt)) end
      MOTA:Print("Pay them from the guild bank with Lottery payout as the reason.")
    end
    if L and Lo:Stage(L) == "selling" then
      MOTA:Print(mine > 0 and ("You hold " .. mine .. (mine == 1 and " ticket." or " tickets.")) or "Buy tickets at the guild bank: deposit gold and choose Lottery tickets as the reason.")
    end
    return
  end
  if err then MOTA:Print(err) elseif rec then MOTA:Print("Done.") end
end)

add("hunt", "[mark <riddle>, unmark, publish <name>, discard, end, glow]", "the Treasure Hunt: your clue, or set one (the Crown and the Minister of Games)", function(arg)
  if not needGuild() then return end
  local Hu = MOTA.Hunt
  local word, rest = (arg or ""):match("^(%S*)%s*(.-)$")
  local rec, err
  if word == "mark" then
    rec, err = Hu:Mark(rest)
    if rec then return MOTA:Print("Clue", #Hu:Draft().clues, "marked here, in", rec.z .. ". Mark the next, or /mota hunt publish <name>.") end
  elseif word == "unmark" then rec, err = Hu:Unmark()
  elseif word == "publish" then rec, err = Hu:Publish(rest)
  elseif word == "discard" then rec, err = Hu:Discard()
  elseif word == "end" then rec, err = Hu:Close()
  elseif word == "glow" then
    local on = not MOTA.HuntGlow:Enabled()
    MOTA.HuntGlow:SetEnabled(on)
    return MOTA:Print(on and "The hunt's gold glow is on." or "The hunt's gold glow is off. Chat still tells you how far, every 10 yards.")
  else
    local H = Hu:Current()
    MOTA:Print((H and (H.name .. ": ") or "") .. Hu:Line(H))
    if H and Hu:Stage(H) == "running" then
      local i = Hu:Progress(MOTA.me, H) + 1
      local text, zone = Hu:Riddle(i, H)
      if text then MOTA:Print("Clue " .. i .. " of " .. #H.clues .. ", in " .. tostring(zone) .. ": " .. text) end
    end
    local d = Hu:Draft()
    if #d.clues > 0 then MOTA:Print("Your draft hunt has", #d.clues, "marked clues.") end
    return
  end
  if err then MOTA:Print(err) elseif rec then MOTA:Print("Done.") end
end)

add("honour", "<name>, <order>, [citation] or remove <name>, <order>", "the Crown confers an order (crown, lion, quill or star)", function(arg)
  if not needGuild() then return end
  local H = MOTA.Honours
  local remove = arg:match("^remove%s+(.+)$")
  local parts = {}
  for part in (remove or arg):gmatch("[^,]+") do parts[#parts + 1] = strtrim(part) end
  if #parts < 2 then return MOTA:Print("Usage: /mota honour <name>, <order>, <citation>. The orders: " .. H:OrderNames() .. ".") end
  local rec, err
  if remove then rec, err = H:Revoke(parts[1], parts[2])
  else rec, err = H:Award(parts[1], parts[2], table.concat(parts, ", ", 3)) end
  if err then MOTA:Print(err) elseif rec then MOTA:Print("Done.") end
end)

add("honours", "[name]", "the Roll of Honour, or one player's honours", function(arg)
  if not needGuild() then return end
  local H = MOTA.Honours
  local function line(h)
    return h.title .. (h.n > 1 and (" ×" .. h.n) or "") .. " · " .. date("%d %b %Y", h.t) .. (h.why and (" · " .. h.why) or "")
  end
  if arg ~= "" then
    local who = MOTA.District:Resolve(arg)
    if not who then return MOTA:Print("There's nobody called " .. arg .. " in the guild.") end
    local list = H:Of(who)
    if #list == 0 then return MOTA:Print(MOTA:Short(who), "holds no honours yet.") end
    MOTA:Print(MOTA:Styled(who) .. ":")
    for _, h in ipairs(list) do MOTA:Print(line(h)) end
    return
  end
  local roll = H:Roll()
  if #roll == 0 then return MOTA:Print("The Roll of Honour is empty so far.") end
  MOTA:Print("The Roll of Honour:")
  for _, e in ipairs(roll) do
    local titles = {}
    for _, h in ipairs(e.list) do titles[#titles + 1] = h.title .. (h.n > 1 and (" ×" .. h.n) or "") end
    MOTA:Print(MOTA:Styled(e.name) .. " · " .. table.concat(titles, ", "))
  end
end)

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

add("heralds", "[number|all]", "preview the real heralds, on your screen only", function(arg)
  MOTA.HeraldPreview:Run(arg ~= "" and arg or nil)
end)

add("throne", "preview [off]", "draw the Throne Room with a made-up government, to check the Cabinet (nothing is saved)", function(arg)
  local word, flag = (arg or ""):lower():match("^(%S*)%s*(%S*)$")
  if word ~= "preview" then return MOTA:Print("/mota throne preview shows a made-up government on the Throne Room; /mota throne preview off ends it.") end
  local on = flag ~= "off"
  MOTA.Throne:Preview(on)
  if on then
    local window = MOTA.UI:Build()
    MOTA.UI:SelectPage(1)
    window:Show()
  end
  if MOTA.ThronePage and MOTA.ThronePage.Refresh then MOTA.ThronePage:Refresh() end
  MOTA:Print(on and "The Throne Room now shows a made-up government, tagged Preview. Nothing is saved or sent. /mota throne preview off ends it."
    or "The Throne Room shows the real state of the realm again.")
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

add("booksound", "[number]", "list the holy sounds for the Chronicle book, or play and choose one", function(arg)
  local Book = MOTA.ChronicleBook
  local list = Book:HolySounds()
  if #list == 0 then return MOTA:Print("This client has none of the holy sounds the add-on knows.") end
  local n = tonumber(arg)
  if n and list[n] then
    MOTA.db.settings.bookSound = list[n]
    Book:PlayHoly(list[n])
    return MOTA:Print("Holy sound", n, "(" .. list[n] .. ") chosen for the Chronicle book.")
  end
  local chosen = MOTA.db.settings.bookSound
  for i, name in ipairs(list) do
    MOTA:Print(MOTA:Color("leaf", i), name, name == chosen and MOTA:Color("leaf", "· chosen") or "")
  end
  MOTA:Print(chosen and "/mota booksound <number> plays one and chooses it."
    or "None chosen: the book plays the first one the game has. /mota booksound <number> plays one and chooses it.")
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

-- What the Admin Controls window (UI/AdminControls.lua) reads: every command, in
-- order, with its usage and help text (the same words /mota help shows), and a way to
-- run one exactly as if it had been typed. A command added above shows up there too.
MOTA.Commands = {
  list = order,
  Allowed = allowed,
  Open = OPEN, -- the exceptions: a name set to true here is for everyone
  Run = function(self, name, arg)
    local fn = commands[name]
    if not fn then return false end
    if not allowed(name) then
      MOTA:Print("The Ministry's commands are for the Crown alone.")
      return false
    end
    fn(arg or "")
    return true
  end,
}

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
    MOTA.Commands:Run(cmd, rest or "")
  else
    MOTA:Print("Unknown command \"" .. cmd .. "\". Commands:")
    showHelp()
  end
end
