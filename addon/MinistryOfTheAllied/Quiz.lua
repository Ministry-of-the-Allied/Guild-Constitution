-- Ministry of the Allied: the Pub Quiz (Duncan, 2026-11-12).
-- The quiz itself happens on Discord; the add-on is the back office. The
-- quizmaster (the Crown or the Minister of Games) opens a quiz; players make
-- teams of up to four, each with a captain. The quizmaster reads a question out
-- on Discord and presses Ask: every captain gets a herald with the question
-- and an answer box (UI/QuizPrompt.lua) that stays until they answer. Answers
-- go to the quizmaster alone, by whisper. After each round the quizmaster marks
-- the answers right, half or wrong and publishes the round's scores. Each team
-- may play its joker on one round, before it starts: that round counts double.
-- At the end the top three teams go in the games log (every member placed,
-- shared places for ties), so the District Cup and the Victor's Laurel follow.
--
-- In the book (everyone sees):
--   quiz.open   quizmaster  { name, rounds, per, secs }
--   quiz.team   a captain   { id, name }        makes a team, its writer the captain
--   quiz.join   a player    { id, cap }         joins a captain's team
--   quiz.leave  a player    { id }              (a captain leaving breaks the team up)
--   quiz.joker  a captain   { id, r }           doubles round r, before it starts
--   quiz.round  quizmaster  { id, r }           round r begins (teams are fixed from round 1)
--   quiz.score  quizmaster  { id, r, s = { [captain] = points } }  (a later one for r corrects it)
--   quiz.tie    quizmaster  { id, a, g = { [captain] = guess } }   closest guess breaks ties
--   quiz.end    quizmaster  { id }              final; the results go in the games log
--   quiz.close  quizmaster or the Crown { id }  ended with no result
--
-- Live, never kept (Comm kinds):
--   QQ  quizmaster -> guild:   id, key, round, number, seconds left, question
--   QX  quizmaster -> guild:   id, key                  the question is closed
--   QR  captain -> quizmaster: id, key, answer          (whisper)
--   QK  quizmaster -> captain: id, key                  answer received (whisper)
-- The questions and answers the quizmaster prepares, and the answers they're
-- sent, stay in their own saved file (MOTA.db.quizDesk), never in the book.

local _, MOTA = ...
local Quiz = {}
MOTA.Quiz = Quiz

Quiz.TEAM_MAX = 4
Quiz.MAX_ROUNDS, Quiz.MAX_PER = 10, 20
Quiz.RESEND = 10      -- seconds: the open question goes out again, for anyone who reloaded
Quiz.GRACE = 3        -- seconds after closing that a late answer still counts
Quiz.DEFAULTS = { rounds = 5, per = 10, secs = 60 }

local function str(v, max) return type(v) == "string" and v ~= "" and #v <= max end
local function num(v) return type(v) == "number" end
local function canRun(name) return MOTA.Games and MOTA.Games:CanRun(name) end

---------------------------------------------------------------------------
-- Records
---------------------------------------------------------------------------

local R = MOTA.Book.rules
R["quiz.open"] = function(a, rec)
  local d = rec and rec.d or {}
  return canRun(a) and str(d.name, 40) and num(d.rounds) and d.rounds >= 1 and d.rounds <= Quiz.MAX_ROUNDS
    and num(d.per) and d.per >= 1 and d.per <= Quiz.MAX_PER and num(d.secs) and d.secs >= 10 and d.secs <= 600 or false
end
R["quiz.team"] = function(a, rec) local d = rec and rec.d or {} return str(d.id, 60) and str(d.name, 24) or false end
R["quiz.join"] = function(a, rec) local d = rec and rec.d or {} return str(d.id, 60) and str(d.cap, 40) and d.cap ~= a or false end
R["quiz.leave"] = function(a, rec) local d = rec and rec.d or {} return str(d.id, 60) or false end
R["quiz.joker"] = function(a, rec) local d = rec and rec.d or {} return str(d.id, 60) and num(d.r) or false end
local function byOrganiser(a, d) return str(d.id, 60) and d.id:match("^(.-)#%d+$") == a end
R["quiz.round"] = function(a, rec) local d = rec and rec.d or {} return byOrganiser(a, d) and num(d.r) or false end
R["quiz.score"] = function(a, rec)
  local d = rec and rec.d or {}
  if not byOrganiser(a, d) or not num(d.r) or type(d.s) ~= "table" then return false end
  for k, v in pairs(d.s) do
    if type(k) ~= "string" or not num(v) or v < 0 or v > 200 then return false end
  end
  return true
end
R["quiz.tie"] = function(a, rec)
  local d = rec and rec.d or {}
  if not byOrganiser(a, d) or not num(d.a) or type(d.g) ~= "table" then return false end
  for k, v in pairs(d.g) do if type(k) ~= "string" or not num(v) then return false end end
  return true
end
R["quiz.end"] = function(a, rec) local d = rec and rec.d or {} return byOrganiser(a, d) or false end
R["quiz.close"] = function(a, rec)
  local d = rec and rec.d or {}
  return str(d.id, 60) and (MOTA:IsCrown(a) or d.id:match("^(.-)#%d+$") == a) or false
end

local cache

local function build()
  local out = { all = {} }
  local byId = {}
  local list = MOTA.Book:Latest()
  for i = #list, 1, -1 do -- oldest first
    local r = list[i]
    local d = r.d or {}
    local Q = byId[d.id]
    if r.k == "quiz.open" then
      Q = { id = r.a .. "#" .. r.n, by = r.a, t = r.t, name = d.name, rounds = d.rounds, per = d.per, secs = d.secs,
        teams = {}, order = {}, teamOf = {}, round = 0, started = {}, scores = {}, jokers = {} }
      byId[Q.id] = Q
      out.all[#out.all + 1] = Q
    elseif Q and not Q.closed and not Q.ended then
      local who = r.a
      local fixed = Q.round > 0
      if r.k == "quiz.close" and (MOTA:IsCrown(who) or who == Q.by) then
        Q.closed = { t = r.t, by = who }
      elseif r.k == "quiz.team" and not fixed and who ~= Q.by and not Q.teamOf[who] then
        Q.teams[who] = { cap = who, name = d.name, members = { who }, t = r.t }
        Q.order[#Q.order + 1] = who
        Q.teamOf[who] = who
      elseif r.k == "quiz.join" and not fixed and who ~= Q.by and not Q.teamOf[who] and Q.teams[d.cap]
        and #Q.teams[d.cap].members < Quiz.TEAM_MAX then
        table.insert(Q.teams[d.cap].members, who)
        Q.teamOf[who] = d.cap
      elseif r.k == "quiz.leave" and not fixed and Q.teamOf[who] then
        local cap = Q.teamOf[who]
        local T = Q.teams[cap]
        if cap == who then
          -- The captain leaves: the team breaks up.
          for _, m in ipairs(T.members) do Q.teamOf[m] = nil end
          Q.teams[cap] = nil
          for j, c in ipairs(Q.order) do if c == cap then table.remove(Q.order, j) break end end
        else
          for j, m in ipairs(T.members) do if m == who then table.remove(T.members, j) break end end
          Q.teamOf[who] = nil
        end
      elseif r.k == "quiz.joker" and Q.teams[who] and not Q.jokers[who] and num(d.r) and d.r >= 1 and d.r <= Q.rounds
        and not Q.started[d.r] then
        Q.jokers[who] = d.r
      elseif r.k == "quiz.round" and who == Q.by and num(d.r) and d.r >= 1 and d.r <= Q.rounds and not Q.started[d.r] then
        Q.started[d.r] = r.t
        Q.round = math.max(Q.round, d.r)
      elseif r.k == "quiz.score" and who == Q.by and Q.started[d.r] then
        local s = {}
        for cap, v in pairs(d.s) do if Q.teams[cap] then s[cap] = v end end
        Q.scores[d.r] = s
      elseif r.k == "quiz.tie" and who == Q.by then
        Q.tie = { a = d.a, g = d.g }
      elseif r.k == "quiz.end" and who == Q.by then
        Q.ended = { t = r.t }
      end
    end
  end
  out.cur = out.all[#out.all]
  return out
end

local function get()
  if not cache then cache = build() end
  return cache
end

function Quiz:Current() return get().cur end
function Quiz:All() return get().all end

-- "lobby", "running", "done", "closed", or nil.
function Quiz:Stage(Q)
  Q = Q or self:Current()
  if not Q then return nil end
  if Q.closed then return "closed" end
  if Q.ended then return "done" end
  if Q.round > 0 then return "running" end
  return "lobby"
end

function Quiz:Live(Q)
  local s = self:Stage(Q)
  return s == "lobby" or s == "running"
end

-- The team a player is on (by its captain), or nil.
function Quiz:TeamOf(name, Q)
  Q = Q or self:Current()
  return Q and Q.teamOf[name] and Q.teams[Q.teamOf[name]] or nil
end

function Quiz:IsCaptain(name, Q)
  Q = Q or self:Current()
  return Q ~= nil and Q.teams[name] ~= nil
end

function Quiz:IsMaster(name, Q)
  Q = Q or self:Current()
  return Q ~= nil and MOTA:IsMe(Q.by) and (name == nil or name == Q.by)
end

-- A team's points in round r (the joker doubles it), and its total.
function Quiz:Points(Q, cap, r)
  local v = Q.scores[r] and Q.scores[r][cap]
  if not v then return nil end
  return Q.jokers[cap] == r and v * 2 or v
end

-- The scoreboard: { { cap, name, members, total, rounds = { [r] = pts }, rank } }, best first.
-- Ties are broken by the tie-break question (closest guess), else shared.
function Quiz:Board(Q)
  Q = Q or self:Current()
  local rows = {}
  if not Q then return rows end
  for _, cap in ipairs(Q.order) do
    local T = Q.teams[cap]
    if T then
      local total, by = 0, {}
      for r = 1, Q.rounds do
        local p = self:Points(Q, cap, r)
        by[r] = p
        total = total + (p or 0)
      end
      local miss
      if Q.tie and num(Q.tie.g[cap]) then miss = math.abs(Q.tie.g[cap] - Q.tie.a) end
      rows[#rows + 1] = { cap = cap, name = T.name, members = T.members, total = total, rounds = by, miss = miss, joker = Q.jokers[cap] }
    end
  end
  local function better(a, b)
    if a.total ~= b.total then return a.total > b.total end
    if a.miss and b.miss and a.miss ~= b.miss then return a.miss < b.miss end
    if (a.miss ~= nil) ~= (b.miss ~= nil) then return a.miss ~= nil end
    return false
  end
  table.sort(rows, function(a, b)
    if better(a, b) then return true end
    if better(b, a) then return false end
    return a.name < b.name
  end)
  for i, row in ipairs(rows) do
    local rank = 1
    for j = 1, i - 1 do if better(rows[j], row) then rank = rank + 1 end end
    row.rank = rank
  end
  return rows
end

-- The games-log placings: every member of the top three teams, shared places for ties.
function Quiz:Places(Q)
  local places, at = {}, {}
  for _, row in ipairs(self:Board(Q)) do
    if row.rank <= 3 and row.total > 0 then
      for _, m in ipairs(row.members) do
        if #places < MOTA.Games.MAX_PLACES then
          places[#places + 1] = m
          at[#at + 1] = row.rank
        end
      end
    end
  end
  return places, at
end

---------------------------------------------------------------------------
-- Players: teams, the joker
---------------------------------------------------------------------------

function Quiz:MakeTeam(name)
  local Q = self:Current()
  if self:Stage(Q) ~= "lobby" then return nil, "Teams are made before the first round." end
  if MOTA:IsMe(Q.by) then return nil, "You're the quizmaster." end
  if Q.teamOf[MOTA.me] then return nil, "You're already on a team." end
  name = strtrim(name or "")
  if name == "" then return nil, "Give your team a name." end
  if #name > 24 then return nil, "Keep the team's name to 24 letters." end
  for _, T in pairs(Q.teams) do
    if T.name:lower() == name:lower() then return nil, "There's already a team called " .. T.name .. "." end
  end
  return MOTA.Book:Write("quiz.team", { id = Q.id, name = name })
end

function Quiz:Join(cap)
  local Q = self:Current()
  if self:Stage(Q) ~= "lobby" then return nil, "Teams are made before the first round." end
  if MOTA:IsMe(Q.by) then return nil, "You're the quizmaster." end
  if Q.teamOf[MOTA.me] then return nil, "You're already on a team." end
  local T = Q.teams[cap]
  if not T then return nil, "That team isn't there any more." end
  if #T.members >= self.TEAM_MAX then return nil, T.name .. " is full." end
  return MOTA.Book:Write("quiz.join", { id = Q.id, cap = cap })
end

function Quiz:Leave()
  local Q = self:Current()
  if self:Stage(Q) ~= "lobby" or not Q.teamOf[MOTA.me] then return nil, "You're not on a team you can leave." end
  return MOTA.Book:Write("quiz.leave", { id = Q.id })
end

-- The captain plays the team's joker on round r, before it starts.
function Quiz:Joker(r)
  local Q = self:Current()
  if not self:Live(Q) or not Q.teams[MOTA.me] then return nil, "Only a captain plays the team's joker." end
  if Q.jokers[MOTA.me] then return nil, "Your joker is already on round " .. Q.jokers[MOTA.me] .. "." end
  if not num(r) or r < 1 or r > Q.rounds then return nil, "There's no round " .. tostring(r) .. "." end
  if Q.started[r] then return nil, "Round " .. r .. " has started: the joker must be played before." end
  return MOTA.Book:Write("quiz.joker", { id = Q.id, r = r })
end

---------------------------------------------------------------------------
-- The quizmaster's desk (kept in their own saved file)
---------------------------------------------------------------------------

-- The plan: { name, rounds, per, secs, r = { [round] = { { q, a, alt, bank }, ... } } }.
function Quiz:Desk()
  local d = MOTA.db.quizDesk
  if not d then
    d = { name = "", rounds = self.DEFAULTS.rounds, per = self.DEFAULTS.per, secs = self.DEFAULTS.secs, r = {},
      answers = {}, marks = {}, asked = {} }
    MOTA.db.quizDesk = d
  end
  d.r = d.r or {}
  d.answers, d.marks, d.asked = d.answers or {}, d.marks or {}, d.asked or {}
  return d
end

function Quiz:RoundPlan(r)
  local d = self:Desk()
  d.r[r] = d.r[r] or {}
  return d.r[r]
end

local function bankEntry(id)
  for _, e in ipairs(MOTA.QuizBank.Q) do if e[1] == id then return e end end
end
Quiz.BankEntry = bankEntry

-- Bank questions not yet in the plan, in a category (or any).
function Quiz:Unused(cat)
  local used = {}
  for _, list in pairs(self:Desk().r) do
    for _, q in ipairs(list) do if q.bank then used[q.bank] = true end end
  end
  local out = {}
  for _, e in ipairs(MOTA.QuizBank.Q) do
    if not used[e[1]] and (not cat or e[2] == cat) then out[#out + 1] = e end
  end
  return out
end

function Quiz:AddBank(r, id)
  local e = bankEntry(id)
  if not e then return nil, "No such question in the bank." end
  local plan = self:RoundPlan(r)
  if #plan >= self.MAX_PER then return nil, "A round has at most " .. self.MAX_PER .. " questions." end
  plan[#plan + 1] = { q = e[3], a = e[4], alt = e[5], bank = e[1] }
  MOTA:Fire("QUIZ_CHANGED")
  return #plan
end

function Quiz:AddOwn(r, q, a)
  q, a = strtrim(q or ""), strtrim(a or "")
  if q == "" or a == "" then return nil, "Write the question and its answer." end
  if #q > 200 then return nil, "Keep the question to 200 letters." end
  local plan = self:RoundPlan(r)
  if #plan >= self.MAX_PER then return nil, "A round has at most " .. self.MAX_PER .. " questions." end
  plan[#plan + 1] = { q = q, a = a }
  MOTA:Fire("QUIZ_CHANGED")
  return #plan
end

-- Fills round r up to the set number with random unused bank questions (of a category, or any).
function Quiz:FillRandom(r, cat)
  local d = self:Desk()
  local plan = self:RoundPlan(r)
  local pool = self:Unused(cat)
  local n = 0
  while #plan < d.per and #pool > 0 do
    local e = table.remove(pool, math.random(#pool))
    plan[#plan + 1] = { q = e[3], a = e[4], alt = e[5], bank = e[1] }
    n = n + 1
  end
  MOTA:Fire("QUIZ_CHANGED")
  if n == 0 then return nil, #plan >= d.per and "That round is full." or "No questions left in the bank for that." end
  return n
end

function Quiz:Remove(r, i)
  local plan = self:RoundPlan(r)
  if not plan[i] then return nil, "No question there." end
  table.remove(plan, i)
  MOTA:Fire("QUIZ_CHANGED")
  return true
end

function Quiz:ClearPlan()
  local d = self:Desk()
  d.r = {}
  MOTA:Fire("QUIZ_CHANGED")
end

function Quiz:Open(name)
  if not canRun(MOTA.me) then return nil, "Only the Crown and the Minister of Games run the quiz." end
  if self:Live() then return nil, "A quiz is already on." end
  local d = self:Desk()
  name = strtrim(name or d.name or "")
  if name == "" then name = "The Pub Quiz" end
  if #name > 40 then return nil, "Keep the name to 40 letters." end
  local rec, err = MOTA.Book:Write("quiz.open", { name = name, rounds = d.rounds, per = d.per, secs = d.secs })
  if rec then d.answers, d.marks, d.asked, d.open = {}, {}, {}, nil end
  return rec, err
end

local function key(r, i) return r .. "." .. i end
Quiz.Key = key

-- Starts round r (teams are fixed from round 1; jokers for r must be in before).
function Quiz:StartRound(r)
  local Q = self:Current()
  if not self:Live(Q) or not MOTA:IsMe(Q.by) then return nil, "No quiz of yours is on." end
  r = r or Q.round + 1
  if r > Q.rounds then return nil, "That was the last round." end
  if Q.started[r] then return nil, "Round " .. r .. " has started." end
  if r == 1 and #Q.order == 0 then return nil, "No teams have joined yet." end
  return MOTA.Book:Write("quiz.round", { id = Q.id, r = r })
end

-- The next question to ask in the round under way: its number, or nil.
function Quiz:NextQuestion()
  local Q = self:Current()
  if not Q or Q.round == 0 then return nil end
  local d = self:Desk()
  for i = 1, Q.per do
    if not d.asked[key(Q.round, i)] then return i end
  end
end

local sendQuestion
-- Asks question i of the round under way: every captain gets it, with its time.
function Quiz:Ask(i)
  local Q = self:Current()
  if self:Stage(Q) ~= "running" or not MOTA:IsMe(Q.by) then return nil, "Start a round first." end
  local d = self:Desk()
  if d.open then return nil, "Close question " .. d.open.i .. " first." end
  i = i or self:NextQuestion()
  if not i then return nil, "Every question in this round has been asked." end
  local plan = self:RoundPlan(Q.round)
  local q = plan[i]
  local text = q and q.q or ("Question " .. i .. " (read out on Discord)")
  local k = key(Q.round, i)
  d.asked[k] = true
  d.open = { key = k, r = Q.round, i = i, text = text, ends = GetServerTime() + Q.secs }
  d.answers[k] = d.answers[k] or {}
  sendQuestion()
  MOTA:Fire("QUIZ_CHANGED")
  return k
end

-- Closes the open question: the captains' heralds go.
function Quiz:CloseQuestion()
  local d = self:Desk()
  local Q = self:Current()
  if not d.open or not Q then return nil, "No question is open." end
  local k = d.open.key
  d.closedAt = { key = k, t = GetServerTime() }
  d.open = nil
  MOTA.Comm:Send(MOTA.Comm:Pack("QX", Q.id, k), "GUILD")
  -- Right answers are marked at once; the quizmaster checks the rest.
  self:AutoMark(k)
  MOTA:Fire("QUIZ_CHANGED")
  return k
end

-- Marks exact matches right (the bank's other answers count), leaving the rest to the quizmaster.
function Quiz:AutoMark(k)
  local d = self:Desk()
  local r, i = k:match("^(%d+)%.(%d+)$")
  if not r then return end -- the tie-break is settled by the closest guess
  local q = self:RoundPlan(tonumber(r))[tonumber(i)]
  d.marks[k] = d.marks[k] or {}
  if not q then return end
  for cap, given in pairs(d.answers[k] or {}) do
    if d.marks[k][cap] == nil then
      d.marks[k][cap] = MOTA.QuizBank.Matches(given, q.a, q.alt) and 1 or 0
    end
  end
end

-- Cycles a team's mark for a question: right, half, wrong.
function Quiz:Mark(k, cap, v)
  local d = self:Desk()
  d.marks[k] = d.marks[k] or {}
  if v == nil then
    local cur = d.marks[k][cap] or 0
    v = cur == 1 and 0.5 or (cur == 0.5 and 0 or 1)
  end
  d.marks[k][cap] = v
  MOTA:Fire("QUIZ_CHANGED")
  return v
end

-- A round's points per team, from the marks.
function Quiz:Tally(r)
  local Q = self:Current()
  local d = self:Desk()
  local s = {}
  for _, cap in ipairs(Q.order) do
    local total = 0
    for i = 1, Q.per do
      local m = d.marks[key(r, i)]
      total = total + (m and m[cap] or 0)
    end
    s[cap] = total
  end
  return s
end

-- Publishes round r's scores to everyone.
function Quiz:Publish(r)
  local Q = self:Current()
  if not self:Live(Q) or not MOTA:IsMe(Q.by) then return nil, "No quiz of yours is on." end
  r = r or Q.round
  if not Q.started[r] then return nil, "Round " .. r .. " hasn't started." end
  if self:Desk().open then self:CloseQuestion() end
  return MOTA.Book:Write("quiz.score", { id = Q.id, r = r, s = self:Tally(r) })
end

-- The tie-break: the answer, and each captain's guess (sent as an answer to key "tie").
function Quiz:AskTie(text)
  local Q = self:Current()
  if self:Stage(Q) ~= "running" or not MOTA:IsMe(Q.by) then return nil, "No quiz of yours is running." end
  local d = self:Desk()
  if d.open then return nil, "Close the open question first." end
  d.open = { key = "tie", r = 0, i = 0, text = text or "Tie-break: closest number wins", ends = GetServerTime() + Q.secs }
  d.answers.tie = {}
  sendQuestion()
  MOTA:Fire("QUIZ_CHANGED")
  return true
end

function Quiz:SettleTie(answer)
  local Q = self:Current()
  local d = self:Desk()
  answer = tonumber(answer)
  if not answer then return nil, "Give the right number." end
  local g = {}
  for cap, given in pairs(d.answers.tie or {}) do
    local n = tonumber((tostring(given):gsub("[^%d%.%-]", "")))
    if n then g[cap] = n end
  end
  return MOTA.Book:Write("quiz.tie", { id = Q.id, a = answer, g = g })
end

local recorded = {}
-- Ends the quiz: the final scores, and the top three in the games log.
function Quiz:Finish()
  local Q = self:Current()
  if self:Stage(Q) ~= "running" or not MOTA:IsMe(Q.by) then return nil, "No quiz of yours is running." end
  if self:Desk().open then self:CloseQuestion() end
  return MOTA.Book:Write("quiz.end", { id = Q.id })
end

function Quiz:Close()
  local Q = self:Current()
  if not self:Live(Q) then return nil, "No quiz is on." end
  if not (MOTA:IsCrown(MOTA.me) or MOTA:IsMe(Q.by)) then return nil, "Only " .. MOTA:Short(Q.by) .. ", the quizmaster, or the Crown can end it." end
  return MOTA.Book:Write("quiz.close", { id = Q.id })
end

local function record(Q)
  if recorded[Q.id] or not MOTA:IsMe(Q.by) or not MOTA.Games then return end
  recorded[Q.id] = true
  for _, e in ipairs(MOTA.Games:Log()) do
    if e.g == "quiz" and e.name == Q.name and e.t >= Q.t then return end
  end
  local places, at = Quiz:Places(Q)
  if #places > 0 then MOTA.Games:Record("quiz", Q.name, places, at) end
end

---------------------------------------------------------------------------
-- Live: questions out, answers in
---------------------------------------------------------------------------

Quiz.live = nil      -- the question open now, as heard: { id, key, r, i, text, ends }
Quiz.sent = {}       -- [key] = the answer this captain sent
Quiz.got = {}        -- [key] = true once the quizmaster has it

sendQuestion = function()
  local Q = Quiz:Current()
  local o = Quiz:Desk().open
  if not Q or not o then return end
  local left = math.max(0, o.ends - GetServerTime())
  MOTA.Comm:Send(MOTA.Comm:Pack("QQ", Q.id, o.key, o.r, o.i, left, o.text), "GUILD")
end

MOTA.Comm:Handle("QQ", function(self, sender, channel, f)
  local Q = Quiz:Current()
  if channel ~= "GUILD" or not Q or f[1] ~= Q.id or sender ~= Q.by then return end
  local k = f[2]
  local fresh = not Quiz.live or Quiz.live.key ~= k
  Quiz.live = { id = Q.id, key = k, r = tonumber(f[3]) or 0, i = tonumber(f[4]) or 0,
    ends = GetTime() + (tonumber(f[5]) or 0), text = f[6] or "" }
  if fresh then MOTA:Fire("QUIZ_ASKED") end
  MOTA:Fire("QUIZ_CHANGED")
end)

MOTA.Comm:Handle("QX", function(self, sender, channel, f)
  local Q = Quiz:Current()
  if not Q or f[1] ~= Q.id or sender ~= Q.by then return end
  if Quiz.live and Quiz.live.key == f[2] then Quiz.live = nil end
  MOTA:Fire("QUIZ_ASKED")
  MOTA:Fire("QUIZ_CHANGED")
end)

-- The captain sends the team's answer (it can be changed until the question closes).
function Quiz:Answer(text)
  local Q = self:Current()
  local L = self.live
  if not Q or not L or L.id ~= Q.id then return nil, "No question is open." end
  if not Q.teams[MOTA.me] then return nil, "Only your team's captain answers." end
  text = strtrim(text or "")
  if text == "" then return nil, "Write an answer first." end
  if #text > 100 then text = text:sub(1, 100) end
  self.sent[L.key] = text
  self.got[L.key] = nil
  MOTA.Comm:Send(MOTA.Comm:Pack("QR", Q.id, L.key, text), "WHISPER", Q.by)
  MOTA:Fire("QUIZ_ASKED")
  MOTA:Fire("QUIZ_CHANGED")
  return true
end

-- The herald waits on this captain: a question is open and they haven't answered it.
function Quiz:Waiting()
  local Q = self:Current()
  local L = self.live
  return Q ~= nil and L ~= nil and L.id == Q.id and Q.teams[MOTA.me] ~= nil and self.sent[L.key] == nil
    and GetTime() < L.ends + 1
end

MOTA.Comm:Handle("QR", function(self, sender, channel, f)
  local Q = Quiz:Current()
  if channel ~= "WHISPER" or not Q or f[1] ~= Q.id or not MOTA:IsMe(Q.by) or not Q.teams[sender] then return end
  local d = Quiz:Desk()
  local k = f[2]
  local open = d.open and d.open.key == k
  local late = d.closedAt and d.closedAt.key == k and GetServerTime() - d.closedAt.t <= Quiz.GRACE
  if not open and not late then return end
  d.answers[k] = d.answers[k] or {}
  d.answers[k][sender] = f[3] or ""
  if late and d.marks[k] then d.marks[k][sender] = nil Quiz:AutoMark(k) end
  MOTA.Comm:Send(MOTA.Comm:Pack("QK", Q.id, k), "WHISPER", sender)
  MOTA:Fire("QUIZ_CHANGED")
end)

MOTA.Comm:Handle("QK", function(self, sender, channel, f)
  local Q = Quiz:Current()
  if not Q or f[1] ~= Q.id or sender ~= Q.by then return end
  Quiz.got[f[2]] = true
  MOTA:Fire("QUIZ_CHANGED")
end)

-- Captains who have answered the open question (for the quizmaster's desk).
function Quiz:Answered()
  local d = self:Desk()
  return d.open and d.answers[d.open.key] or {}
end

-- The quizmaster's add-on: the open question goes out again every few seconds
-- (for anyone who reloaded), and closes itself when its time is up.
local wait = 0
local ticker
local function tick(dt)
  local Q = Quiz:Current()
  if not Q or not MOTA:IsMe(Q.by) then return end
  local d = Quiz:Desk()
  if Quiz:Stage(Q) == "done" then record(Q) return end
  if not d.open then return end
  if GetServerTime() >= d.open.ends then
    Quiz:CloseQuestion()
    return
  end
  wait = wait - dt
  if wait <= 0 then
    wait = Quiz.RESEND
    sendQuestion()
  end
end
Quiz.Tick = tick

local function startTicking()
  if ticker or not C_Timer or not C_Timer.NewTicker then return end
  wait = Quiz.RESEND
  ticker = C_Timer.NewTicker(1, function()
    tick(1)
    if not Quiz:Live() and not (Quiz:Stage() == "done") then ticker:Cancel() ticker = nil end
  end)
end

---------------------------------------------------------------------------
-- Lines, heralds, listening
---------------------------------------------------------------------------

function Quiz:Line(Q)
  Q = Q or self:Current()
  local s = self:Stage(Q)
  if not s then return "No quiz has been opened yet." end
  local n = 0
  for _ in pairs(Q.teams) do n = n + 1 end
  if s == "lobby" then return n .. (n == 1 and " team" or " teams") .. " · waiting for round 1" end
  if s == "running" then
    local top = self:Board(Q)[1]
    return "Round " .. Q.round .. " of " .. Q.rounds .. (top and top.total > 0 and (" · " .. top.name .. " lead with " .. top.total) or "")
  end
  if s == "closed" then return "Ended with no result." end
  local top = self:Board(Q)[1]
  return top and ("Won by " .. top.name) or "Over."
end

local function changed()
  cache = nil
  MOTA:Fire("QUIZ_CHANGED")
end

MOTA:Listen("GUILD_READY", function()
  changed()
  C_Timer.After(6, function()
    local Q = Quiz:Current()
    if Q and (Quiz:Live(Q) or Quiz:Stage(Q) == "done") then startTicking() end
  end)
end)
MOTA:Listen("CAUGHT_UP", changed)
MOTA:Listen("ACCOUNT_CHANGED", changed)

local function fmt(v)
  return (v == math.floor(v)) and tostring(v) or string.format("%.1f", v)
end
Quiz.Fmt = fmt

MOTA:Listen("RECORD_ADDED", function(self, rec)
  if not rec.k:find("^quiz%.") then
    if rec.k == "party.post" or rec.k == "ballot.result" then cache = nil end
    return
  end
  changed()
  local Q = Quiz:Current()
  if not Q then return end
  if Quiz:Live(Q) or Quiz:Stage(Q) == "done" then startTicking() end
  local d = rec.d or {}
  if d.id and d.id ~= Q.id and rec.k ~= "quiz.open" then return end
  if self.Book.replaying or not self.Herald then return end
  local Hd = self.Herald
  if rec.k == "quiz.open" then
    Hd:Announce({ seal = "official", eyebrow = "The Pub Quiz", title = tostring(d.name) .. " is on",
      text = d.rounds .. " rounds on Discord, quizmaster " .. self:Short(rec.a) .. ". Make or join a team of up to " .. Quiz.TEAM_MAX .. " in the Games Hall.",
      button = { label = "Open", style = "blue", page = 8 } })
  elseif rec.k == "quiz.round" and Q.teamOf[self.me] then
    self:Print(self:Color("leaf", "Pub Quiz:"), "round " .. d.r .. " of " .. Q.rounds .. " begins" .. (Q.jokers[Q.teamOf[self.me]] == d.r and ", with your joker: double points!" or "."))
  elseif rec.k == "quiz.score" then
    local top = Quiz:Board(Q)[1]
    local mine = Quiz:TeamOf(self.me, Q)
    local my = mine and Quiz:Points(Q, mine.cap, d.r)
    Hd:Announce({ seal = "official", eyebrow = "The Pub Quiz · Round " .. d.r, title = top and (top.name .. " lead with " .. fmt(top.total)) or "Round " .. d.r .. " marked",
      text = (my and ("Your team scored " .. fmt(my) .. " this round. ") or "") .. "The scoreboard is in the Games Hall.",
      button = { label = "Open", style = "blue", page = 8 } })
  elseif rec.k == "quiz.end" then
    local board = Quiz:Board(Q)
    local lines = {}
    for i = 1, math.min(3, #board) do lines[#lines + 1] = board[i].rank .. ". " .. board[i].name .. " (" .. fmt(board[i].total) .. ")" end
    Hd:Announce({ seal = "official", eyebrow = "The Pub Quiz · Final scores", title = board[1] and (board[1].name .. " win " .. Q.name) or (Q.name .. " is over"),
      text = table.concat(lines, "  ·  "), button = { label = "Open", style = "blue", page = 8 } })
    record(Q)
  elseif rec.k == "quiz.close" then
    self:Print(Q.name, "has been ended with no result.")
  end
end)
