-- Ministry of the Allied: slash commands.
-- /mota (or /ministry) opens the window (ADDON_SPEC.md, section 16.3);
-- /mota followed by one of the commands below does that instead.

local _, MotA = ...

local commands, order = {}, {}

local function add(name, usage, help, fn)
  commands[name] = fn
  order[#order + 1] = { name = name, usage = usage, help = help }
end

local function needGuild()
  if MotA.guild then return true end
  if IsInGuild() then
    MotA:Print("The guild roster hasn't loaded yet. Try again in a moment.")
    MotA:RequestRoster()
  else
    MotA:Print("This character isn't in a guild. Most of the Ministry needs one.")
  end
  return false
end

local function showHelp()
  for _, c in ipairs(order) do
    MotA:Print(MotA:Color("leaf", "/mota " .. c.name .. (c.usage ~= "" and " " .. c.usage or "")), "·", c.help)
  end
end

local function statusLine()
  local total = MotA.Book:Count()
  local online = MotA.Hello:OnlineCount()
  local guild = MotA.guild and (GetGuildInfo("player") or "?") or "no guild yet"
  MotA:Print(MotA:Color("leaf", "Ministry of the Allied") .. " v" .. MotA.VERSION, "·", guild, "·",
    total, (total == 1 and "record" or "records") .. " ·", online,
    (online == 1 and "other citizen" or "other citizens") .. " online with the add-on")
end

add("sync", "", "records held, who you've heard from, messages sent", function()
  if not needGuild() then return end
  local total, authors, mine = MotA.Book:Count()
  local s = MotA.stats
  local heard = {}
  for name in pairs(MotA.Hello.heard) do heard[#heard + 1] = MotA:Short(name) end
  table.sort(heard)
  MotA:Print("Records:", total, "held from", authors, (authors == 1 and "author" or "authors") .. ",", mine, "of them yours · unconfirmed: 0")
  MotA:Print("Heard from this session:", #heard > 0 and table.concat(heard, ", ") or "nobody yet")
  MotA:Print("Last record received:", MotA:Ago(s.lastReceived))
  MotA:Print("Messages:", s.sent, "sent,", MotA.Comm:Waiting(), "waiting,", s.failed, "failed · received", s.received,
    "(" .. s.ignored .. " ignored, " .. s.conflicts .. " clashing record IDs)")
  if MotA.outdated then
    MotA:Print(MotA:Color("crimson", "A newer version of the add-on is in use, so this copy won't send records. Please update."))
  end
end)

add("who", "", "guild members running the add-on", function()
  if not needGuild() then return end
  MotA:RequestRoster()
  local list = MotA.Hello:List()
  if #list == 0 then
    return MotA:Print("Nobody else's add-on has said hello yet.")
  end
  for _, e in ipairs(list) do
    local p = e.peer
    local where = e.online and MotA:Color("leaf", "online") or ("last heard " .. MotA:Ago(p.seen))
    local count = p.c and (" · " .. p.c .. " records") or ""
    MotA:Print(MotA:Color("leaf", MotA:Short(e.name)), "· v" .. tostring(p.v) .. count, "·", where)
  end
end)

add("test", "<text>", "write a test record and send it to the guild", function(text)
  if not needGuild() then return end
  if text == "" then text = "Hear ye!" end
  -- One record has to fit in one 255-byte message, with room for its ID and type.
  if #text > 150 then
    text = text:sub(1, 150):gsub("[\192-\255][\128-\191]*$", "") -- don't cut a letter in half
    MotA:Print("That's too long for one test record, so it was shortened.")
  end
  local rec, why = MotA.Book:Write("test.note", { text = text })
  if not rec then MotA:Print("Not written:", why) end
end)

add("book", "", "the last 10 records in your book", function()
  if not needGuild() then return end
  local list = MotA.Book:Latest(10)
  if #list == 0 then return MotA:Print("The book is empty. Try /mota test.") end
  for _, r in ipairs(list) do
    MotA:Print(MotA:Color("leaf", MotA:Short(r.a) .. " #" .. r.n), "·", r.k, "·", MotA:Ago(r.t), "·", MotA.Book:Describe(r))
  end
end)

add("probe", "[limits]", "client facts for the add-on plan; 'limits' measures message limits", function(arg)
  if arg == "limits" then
    MotA.Probe:Limits()
  else
    MotA.Probe:Report()
  end
end)

add("scale", "<size>", "the window's size, such as 0.8 (blank for the default)", function(arg)
  local n = tonumber(arg)
  if arg ~= "" and (not n or n < 0.4 or n > 1.5) then
    return MotA:Print("Give a size between 0.4 and 1.5, such as /mota scale 0.8.")
  end
  MotA.db.window.scale = n
  MotA.UI:Build()
  local used = MotA.UI:SetScale(n)
  MotA:Print(("Window size %.2f%s."):format(used, n and used < n and " (as big as fits your screen)" or ""))
end)

add("minimap", "", "hide or show the seal on the minimap", function()
  local show = MotA.db.minimap.hide
  MotA.UI:ShowMinimapSeal(show)
  MotA:Print(show and "The seal is back on the minimap." or "The minimap seal is hidden. /mota minimap brings it back.")
end)

add("settings", "", "open the Ministry's settings in the game's options", function()
  MotA.UI:OpenSettings()
end)

add("herald", "[1-3]", "show the sample heralds from the design canvas", function(arg)
  MotA.Herald:ShowSamples(tonumber(arg))
end)

add("fanfare", "[number]", "list the game's fanfare sounds, or play and choose one", function(arg)
  local list = MotA.Herald:Fanfares()
  if #list == 0 then return MotA:Print("This client has none of the fanfare sounds the add-on knows.") end
  local n = tonumber(arg)
  if n and list[n] then
    MotA.db.settings.fanfareSound = list[n]
    MotA.Herald:PlayFanfare(list[n])
    return MotA:Print("Fanfare", n, "(" .. list[n] .. ") chosen for the heralds.")
  end
  local chosen = MotA.db.settings.fanfareSound or list[1]
  for i, name in ipairs(list) do
    MotA:Print(MotA:Color("leaf", i), name, name == chosen and MotA:Color("leaf", "· chosen") or "")
  end
  MotA:Print("/mota fanfare <number> plays one and chooses it.")
end)

add("crests", "", "show the game's own Alliance crests, to choose one", function()
  MotA.UI:ShowCrests()
end)

add("crest", "<number|ours>", "try one of the game's crests in the window, or ours", function(arg)
  MotA.UI:ChooseCrest(arg)
end)

add("debug", "", "show the raw hidden add-on traffic in chat (on or off)", function()
  MotA.db.settings.debug = not MotA.db.settings.debug
  MotA:Print("Debug messages", MotA.db.settings.debug and "on." or "off.")
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
    return MotA.UI:Toggle()
  end
  local fn = commands[cmd]
  if fn then
    fn(rest or "")
  else
    MotA:Print("Unknown command \"" .. cmd .. "\". Commands:")
    showHelp()
  end
end
