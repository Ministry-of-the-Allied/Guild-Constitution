-- Ministry of the Allied: every real herald, shown on this screen only.
-- /mota heralds lists them; /mota heralds <number> or all shows them.
-- Nothing is written to the book and nothing is sent. Buttons only open pages.
--
-- The wording is copied from where each herald is raised (Ballot, Contest,
-- Party, Bench, Ledger, Ring). Change it there and here together.

local _, MOTA = ...
local Preview = {}
MOTA.HeraldPreview = Preview

-- Long names on purpose, to check that titles fit.
local A, B = "Kíng Atwood", "Elowenwyn"

local function list()
  local money = MOTA:Money(1234567)
  return {
    { "Polls open", { seal = "official", eyebrow = "Hear ye · the Ballot Hall", title = "The polls are open!",
      text = "Election of the Prime Minister: seal your ballot before 21:00, realm time.", button = { label = "Vote now", style = "blue", page = 2 } } },
    { "Ballot reminder", { seal = "official", eyebrow = "Hear ye · the Ballot Hall", title = "You haven't voted yet",
      text = "Election of the Prime Minister: polls close in 2 hours, at 21:00 realm time.", button = { label = "Vote now", style = "blue", page = 2 } } },
    { "Ballot result", { seal = "crown", eyebrow = "By proclamation of the Crown", title = A .. " is elected",
      text = "Election of the Prime Minister. Turnout 14 of 18 active citizens.", button = { label = "Open", style = "quiet", page = 2 } } },
    { "Welcome to a party", { seal = "silverhand", eyebrow = "By the Crown's record", title = "Welcome to the Silverhand",
      text = "Your party's Chamber is now open to you.", button = { label = "Open", style = "blue", page = 4 } } },
    { "Crossing the floor", { seal = "exchange", eyebrow = "Crossing the floor", title = A .. " walks out",
      text = "They leave the Azeroth Exchange. No other party may admit them for 14 days.", button = { label = "Dismiss", style = "quiet" } } },
    { "Contests open", { seal = "crown", eyebrow = "By the Crown", title = "The contests are open",
      text = "Party members may now stand for leader.", button = { label = "Open", style = "blue", page = 4 } } },
    { "Candidate stands", { seal = "silverhand", eyebrow = "Leadership contest", title = A .. " stands",
      text = "A candidate for leader of the Silverhand.", button = { label = "Read it", style = "quiet", page = 4 } } },
    { "Contest vote reminder", { seal = "silverhand", eyebrow = "The last 48 hours", title = "Your vote is waiting",
      text = "Voting in your party's contest closes soon.", button = { label = "Vote now", style = "blue", page = 4 } } },
    { "Run-off", { seal = "exchange", eyebrow = "A tie", title = "A run-off is called",
      text = A .. " and " .. B .. " face 48 hours more voting.", button = { label = "Open", style = "blue", page = 4 } } },
    { "Emergency contest", { seal = "silverhand", eyebrow = "Charter 3.6", title = "Polling day moves back 14 days",
      text = "The Silverhand has no leader, so it holds an emergency contest. Polling day is now 12 Dec.", button = { label = "Open", style = "blue", page = 4 } } },
    { "New leader", { seal = "exchange", eyebrow = "Inaugurated by the Crown", title = A .. " leads",
      text = "Leader of the Azeroth Exchange. The votes are published.", button = { label = "Read it", style = "quiet", page = 4 } } },
    { "Deputy named", { seal = "silverhand", eyebrow = "The front bench", title = B .. " is named Deputy",
      text = "Deputy Leader of the Silverhand, named by " .. A .. ".", button = { label = "Dismiss", style = "quiet" } } },
    { "Deputy takes the lead", { seal = "silverhand", eyebrow = "The front bench", title = B .. " takes the lead",
      text = "The Deputy becomes leader of the Silverhand, without a vote (Charter 3.2).", button = { label = "Open", style = "blue", page = 4 } } },
    { "Books closed", { seal = "treasury", eyebrow = "The Treasury", title = "The books are closed",
      text = "Nothing at the bank is logged until a King opens them. Visit the guild bank, then press Open the books.", button = { label = "Open", style = "blue", page = 5 } } },
    { "Books closed, at the bank", { seal = "treasury", eyebrow = "The Treasury", title = "The books are closed",
      text = "Open them now at " .. money .. ". Until then, nothing at the bank is logged.", button = { label = "Open", style = "blue" } } },
    { "Ring: next bout", { seal = "ring", eyebrow = "The Ring", title = "Next bout",
      text = A .. " v " .. B .. ", Old Town", button = { label = "Dismiss", style = "quiet" } } },
    { "Ring: champion", { seal = "ring", eyebrow = "The Ring", title = A .. " is champion!",
      text = "The Gladiator of Stormwind, by victory in Old Town.", button = { label = "Dismiss", style = "quiet" } } },
  }
end

function Preview:Count() return #list() end

function Preview:Run(arg)
  local all = list()
  local n = tonumber(arg)
  if arg == "all" then
    for _, e in ipairs(all) do MOTA.Herald:Announce(e[2], true) end
    return MOTA:Print("Showing all", #all, "heralds on your screen only. Nothing is sent.")
  elseif n and all[n] then
    MOTA.Herald:Announce(all[n][2], true)
    return MOTA:Print("Showing", all[n][1] .. ", on your screen only. Nothing is sent.")
  end
  for i, e in ipairs(all) do MOTA:Print(MOTA:Color("leaf", i), e[1]) end
  MOTA:Print("/mota heralds <number> shows one, /mota heralds all shows them in turn. Only you see them.")
end
