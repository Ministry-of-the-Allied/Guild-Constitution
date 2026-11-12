"""Runs the Ministry add-on in pretend WoW clients and checks what happens."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
# lupa (Python's Lua bridge) runs the add-on in real Lua 5.1, the same Lua the
# game uses. Install it with `pip install lupa`, or point MOTA_PYLIB at a folder
# holding it.
if os.environ.get("MOTA_PYLIB"):
    sys.path.insert(0, os.environ["MOTA_PYLIB"])
from lupa import lua51  # noqa: E402

ADDON = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "..", "addon", "MinistryOfTheAllied")
def toc_files():
    """The TOC's files in load order, with each XML file's scripts in its place."""
    out = []
    for line in open(os.path.join(ADDON, "MinistryOfTheAllied.toc"), encoding="utf-8"):
        f = line.strip().replace("\\", os.sep)
        if not f or f.startswith("#"):
            continue
        if f.endswith(".xml"):
            folder = os.path.dirname(f)
            for script in re.findall(r'<Script file="([^"]+)"', open(os.path.join(ADDON, f), encoding="utf-8").read()):
                out.append(os.path.join(folder, script))
        else:
            out.append(f)
    return out


FILES = toc_files()
REALM = "Realm"
GUILD = "Ministry of the Allied"
ROSTER = [
    ["Max-Realm", "The Crown", 0, True],
    ["Bram-Realm", "Citizen", 3, True],
    ["Mira-Realm", "Citizen", 3, False],
    ["Aldric-Realm", "The King", 1, False],
    ["Elowen-Realm", "Citizen", 3, True],  # online, without the add-on
    ["Kael-Realm", "Citizen", 3, True],
    # For the ballot (section 13): two more citizens, offline at first, and one
    # inactive for 45 days (not an active citizen).
    ["Tobin-Realm", "Citizen", 3, False, 2],
    ["Wren-Realm", "Citizen", 3, False, 3],
    ["Oswin-Realm", "Citizen", 3, False, 45],
    # Two players whose names start alike, as on Forever (section 1e).
    ["Kíng Atwood-Realm", "Citizen", 3, False, 45],
    ["Kíng Sinnclair-Realm", "Citizen", 3, False, 45],
]

errors = []
pending = []  # (deliver_at, client, args)
clock = [0.0]


class Client:
    # tag: the realm tag this client's game writes on every name, in the roster
    # and on add-on message senders. Forever writes one that differs from one
    # player's screen to another's ("CAMWOWEU5Realm7PvE" on one, "...Realm1PvE"
    # on the next), and refuses a whisper addressed with it.
    def __init__(self, name, saved=None, version=None, lockdown=None, protocol=None, realm_late=False, odd_realm=False, voice=False, tag=None, short=None, place=False, link=False, bnet=None, guarded=False):
        self.name = name
        self.full = name + "-" + REALM
        self.tag = tag or REALM
        self.log = []
        self.wire = []  # every message this client handed to the game
        self.whispered = []  # every whisper's target
        self.tokens = 10.0
        self.last = clock[0]
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        g = self.lua.globals()
        g.PLAYER, g.REALM, g.GUILD = name, REALM, GUILD
        g.SHORT_NAME = short  # Forever's UnitName gives only a name's first part
        g.ROSTER = self.lua.table_from([self.lua.table_from([m[0].split("-")[0] + "-" + self.tag] + m[1:]) for m in ROSTER])
        g.ROSTER_READY = False
        g.ADDON_VERSION = version
        g.LOCKDOWN = lockdown
        g.REALM_LATE = realm_late
        g.ODD_REALM = odd_realm
        g.CLOCK_START = clock[0]
        g.py_send = self.send
        g.py_print = self.print
        g.py_error = self.error
        g.py_roster_request = self.roster_request
        self.lua.execute(open(os.path.join(HERE, "mock.lua"), encoding="utf-8").read())
        self.lua.execute(open(os.path.join(HERE, "mock_ui.lua"), encoding="utf-8").read())
        if bnet:  # the player's BattleTag, as BNGetInfo gives it
            self.lua.execute('function BNGetInfo() return 1, "%s" end' % bnet)
        if saved:
            self.lua.execute(saved)
        ns = self.lua.table()
        self.ns = ns
        for f in FILES:
            g.mock_load(os.path.join(ADDON, f), ns)
        if protocol:
            ns.PROTOCOL = protocol
        g.mock_fire("ADDON_LOADED", "SomeOtherAddon")
        g.mock_fire("ADDON_LOADED", "MinistryOfTheAllied")
        ns.db.settings.voice = voice  # the narration has its own checks (section 12)
        if not guarded:  # commands are the Crown's alone (section 17); only that section's clients keep the rule
            for c in ns.Commands.list.values():
                ns.Commands.Open[c.name] = True
        if not place:  # placing yourself in a district writes a record; it has its own checks (section 100b)
            ns.District.PLACE_DELAY = 10 ** 9
        if not link:  # linking the account writes a record too; its checks are in section 15e
            ns.Account.LINK_DELAY = 10 ** 9
        g.mock_fire("PLAYER_LOGIN")
        g.mock_fire("PLAYER_ENTERING_WORLD", True, False)

    # bridge from the pretend client
    def send(self, prefix, msg, channel, target):
        now = clock[0]
        self.tokens = min(10.0, self.tokens + (now - self.last) * 1.0)
        self.last = now
        if self.tokens < 1:
            return 3
        self.tokens -= 1
        self.wire.append(msg)
        if channel == "GUILD":
            for c in clients:
                pending.append((now + 0.1, c, (prefix, msg, "GUILD", self.name + "-" + c.tag, "")))
        elif channel == "WHISPER":
            self.whispered.append(target)
            for c in clients:
                # The game takes the name alone, or the name with the realm's
                # proper name; never a Forever tag.
                if target in (c.name, c.full):
                    pending.append((now + 0.1, c, (prefix, msg, "WHISPER", self.name + "-" + c.tag, c.name)))
        return 0

    def print(self, msg):
        self.log.append(msg)
        print(f"  [{self.name}] {msg}")

    def error(self, msg):
        errors.append(f"{self.name}: {msg}")
        print(f"  !! [{self.name}] LUA ERROR: {msg}")

    def roster_request(self):
        self.lua.execute("C_Timer.After(0.2, function() ROSTER_READY = true; mock_fire('GUILD_ROSTER_UPDATE') end)")

    def slash(self, text):
        print(f"  [{self.name}] > /mota {text}")
        self.lua.globals().SlashCmdList.MINISTRYOFTHEALLIED(text)

    def saved(self):
        return self.lua.globals().mock_saved()

    def said(self, pattern):
        return any(re.search(pattern, l) for l in self.log)


clients = []


def run(seconds, step=0.05):
    end = clock[0] + seconds
    while clock[0] < end - 1e-9:
        clock[0] += step
        for c in clients:
            c.lua.globals().mock_advance(step)
        due = [p for p in pending if p[0] <= clock[0]]
        for p in due:
            pending.remove(p)
            if p[1] in clients:
                p[1].lua.globals().mock_fire("CHAT_MSG_ADDON", *p[2])


checks = []


def check(label, ok):
    checks.append((label, ok))
    print(("  PASS " if ok else "  FAIL ") + label)


print("== 1. Max and Bram log in")
max_ = Client("Max")
clients.append(max_)
run(1)
bram = Client("Bram")
clients.append(bram)
run(8)
max_.slash("who")
check("Max hears Bram's hello", max_.said(r"Bram · v0\.1\.0"))
bram.slash("who")
check("Bram hears Max's reply", bram.said(r"Max · v0\.1\.0"))

check("/mota who doesn't list yourself", not max_.said(r"^Ministry . Max · v"))
check("/mota who names who's online without the add-on", max_.said(r"Online without the add-on \(or with an old copy\): Elowen, Kael"))

print("== 1b. Kael's game doesn't know the realm at login")
kael = Client("Kael", realm_late=True)
clients.append(kael)
run(16)  # its hello goes later, once the realm is known  # replies to a hello come 0.5 to 3 seconds after it, at random
kael.slash("who")
check("Kael doesn't list himself", not kael.said(r"Kael · v") and kael.said(r"Bram · v"))
kael.slash("test from Kael")
run(2)
check("Kael's record carries his full name", bram.said(r'Test record #1 from Kael: "from Kael"')
      and any(a == "Kael" for a in bram.lua.eval("(function() local t = {} for a in pairs(MinistryOfTheAllied.guild.records) do t[#t+1] = a end return table.concat(t, ',') end)()").split(",")))
clients.remove(kael)

print("== 1c. Kael on a Forever-style realm name")
kael = Client("Kael", odd_realm=True)
clients.append(kael)
run(12)
kael.slash("who")
check("Forever realm: Kael doesn't list himself", not kael.said(r"Kael · v") and kael.said(r"Bram · v"))
check("Forever realm: names show without the realm", kael.said(r"Online without the add-on \(or with an old copy\): Elowen$"))
kael.slash("test Forever realm")
run(2)
check("Forever realm: Kael's record carries his roster name", bram.said(r'Test record #2 from Kael: "Forever realm"'))
clients.remove(kael)

print("== 1d. Forever's realm tag differs from screen to screen")
# On Kael's screen every name ends "-CAMWOWEU5Realm7PvE"; on Max's and Bram's
# it ends "-Realm". Whispers addressed with a tag go nowhere, as in Forever.
kael = Client("Kael", tag="CAMWOWEU5Realm7PvE")
clients.append(kael)
max_.whispered.clear()
bram.whispered.clear()
run(12)
kael.log.clear()
kael.slash("who")
check("Realm tags: Kael sees Max and Bram online (their whispered replies reached him)",
      kael.said(r"Max · v0\.1\.0 .*· .*online") and kael.said(r"Bram · v0\.1\.0 .*· .*online"))
check("Realm tags: Kael doesn't list himself, though his own hello came back tagged",
      not kael.said(r"Kael · v"))
max_.log.clear()
max_.slash("who")
check("Realm tags: Max sees Kael online", max_.said(r"Kael · v0\.1\.0 .*· .*online"))
check("Realm tags: every whisper went to a name alone",
      all("-" not in t for c in (max_, bram, kael) for t in c.whispered)
      and len(max_.whispered) > 0 and len(kael.whispered) == 0)
check("Realm tags: Kael didn't whisper himself", "Kael" not in kael.whispered)
check("Realm tags: names are kept without a tag",
      kael.lua.eval('MinistryOfTheAllied.guild.peers["Max"] ~= nil and MinistryOfTheAllied.me == "Kael"') is True
      and kael.lua.eval('MinistryOfTheAllied:IsGuildMember("Bram") and MinistryOfTheAllied:IsOnline("Bram")') is True)
clients.remove(kael)

print("== 1d2. The guild bank probe")
kael = Client("Kael")
kael.slash("probe bank")
check("Bank probe: a client without the bank functions says so, without errors", kael.said(r"missing: GetGuildBankMoney"))
kael = Client("Kael")
kael.lua.execute("""
  BANK = 5000000
  GetGuildBankMoney = function() return BANK end
  DepositGuildBankMoney = function(a) BANK = BANK + a end
  WithdrawGuildBankMoney = function(a) BANK = BANK - a end
  CanWithdrawGuildBankMoney = function() return true end
  GetGuildBankWithdrawMoney = function() return 0 end
  QueryGuildBankLog = function() end
  GetNumGuildBankMoneyTransactions = function() return 1 end
  GetGuildBankMoneyTransaction = function() return "deposit", "Bram", 50000, 0, 0, 0, 3 end
""")
kael.slash("probe bank")
kael.lua.execute('DepositGuildBankMoney(50000)')
check("Bank probe: every function found", kael.said(r"every bank function is present"))
check("Bank probe: a deposit is seen", kael.said(r"Saw a deposit of 5\.0000g"))

print("== 1e. Two players whose UnitName is the same short name")
OLD_BOOK = """MOTADB = { schema = 1, guilds = { ["Ministry of the Allied-Realm"] = { names = 2,
  records = { ["Kíng"] = { { t = 1, k = "test.note", d = { text = "old" } } } },
  tops = { ["Kíng"] = 1 }, reserved = {}, peers = { ["Kíng Atwood"] = { seen = 1, v = "0.1.0" } } } } }"""
# Atwood's tag hides him from the roster's ID check, so only his hello can tell
# him; Sinnclair finds himself in the roster.
atwood = Client("Kíng Atwood", short="Kíng", tag="CAMWOWEU5Realm1PvE", saved=OLD_BOOK)
sinn = Client("Kíng Sinnclair", short="Kíng")
others = clients[:]  # kept apart, so their records stay out of later counts
clients[:] = [atwood, sinn]
run(12)
def me(c):
    return c.lua.eval("MinistryOfTheAllied.me")
check("Short names: each learns the name the guild knows them by", me(atwood) == "Kíng Atwood" and me(sinn) == "Kíng Sinnclair")
atwood.log.clear()
atwood.slash("who")
check("Short names: Atwood doesn't list himself, and sees Sinnclair", not atwood.said(r"Atwood · v") and atwood.said(r"Sinnclair · v"))
sinn.log.clear()
sinn.slash("who")
check("Short names: Sinnclair doesn't list himself, and sees Atwood", not sinn.said(r"Sinnclair · v") and sinn.said(r"Atwood · v"))
check("Short names: nobody whispered themselves", "Kíng Atwood" not in atwood.whispered and "Kíng Sinnclair" not in sinn.whispered)
check("Short names: nobody whispered the short name", all(t != "Kíng" for c in clients for t in c.whispered))
check("Short names: Atwood's old record moved to his real name",
      atwood.lua.eval('MinistryOfTheAllied.guild.records["Kíng Atwood"][1].d.text == "old" and MinistryOfTheAllied.guild.records["Kíng"] == nil and MinistryOfTheAllied.guild.tops["Kíng Atwood"] == 1 and MinistryOfTheAllied.guild.peers["Kíng Atwood"] == nil') is True)
sinn.slash("test from Sinnclair")
atwood.slash("test from Atwood")
run(2)
check("Short names: records from both arrive, each under its own name",
      atwood.lua.eval('MinistryOfTheAllied.guild.records["Kíng Sinnclair"][1].d.text == "from Sinnclair" and MinistryOfTheAllied.guild.records["Kíng Atwood"][2].d.text == "from Atwood"') is True
      and sinn.lua.eval('MinistryOfTheAllied.guild.records["Kíng Atwood"][2].d.text == "from Atwood"') is True)
keep = atwood.saved()
clients.remove(atwood)
atwood = Client("Kíng Atwood", short="Kíng", tag="CAMWOWEU5Realm1PvE", saved=keep)
check("Short names: the real name is known at once on the next login", me(atwood) == "Kíng Atwood")
clients[:] = others

print("== 2. test records")
max_.slash("test Hear ye, the polls are open!")
run(2)
check("Bram receives Max's test record #1", bram.said(r'Test record #1 from Max: "Hear ye, the polls are open!"'))
bram.slash("test")
run(2)
check("Max receives Bram's test record", max_.said(r'Test record #1 from Bram: "Hear ye!"'))
max_.slash("test " + "é" * 120)
run(2)
max_.slash("book")
max_.slash("sync")
check("Max holds 5 records", max_.said(r"Records: 5 held from 3 authors, 2 of them yours"))
check("AceComm split the long record into pieces", any(m.startswith("\x01") for m in max_.wire)
      and any(m.startswith("\x03") for m in max_.wire))
check("...and Bram got it back whole", bram.said(r"Test record #2 from Max: \"é{20,}"))
check("Records travel packed, not as readable text",
      any("\x1fRC\x1f" in m for m in max_.wire) and not any("polls are open" in m for m in max_.wire))

print("== 3. other commands")
max_.slash("")
max_.slash("nonsense")
max_.slash("probe")
check("Probe sees Max as the Crown", max_.said(r"counts as the Crown: yes"))
check("Probe lists the interface number", max_.said(r"Interface number: 16001"))
bram.slash("probe")
check("Probe sees Bram as not the Crown", bram.said(r"counts as the Crown: no"))
check("Both Crown ranks are recognised", bram.said(r'On the Crown ranks \("The King", "The Crown"\): Aldric, Max'))
max_.slash("probe map")
check("Map probe runs without errors and saves what it found", max_.said(r"Map probe") and max_.said(r"Saved\. After /reload"))
max_.slash("debug")
max_.slash("debug")
max_.slash("probe limits")
run(30)
check("Limits test finishes", max_.said(r"Limits test:"))
check("Limits test sees the burst throttle", max_.said(r"Burst: 20 at once, the game took \d+ and refused \d+ \(\d+ AddonMessageThrottle\)"))
check("256-byte message refused", max_.said(r"256-byte message: refused"))

print("== 4. Max relogs with saved data")
saved = max_.saved()
clients.remove(max_)
max2 = Client("Max", saved=saved)
clients.append(max2)
run(8)
max2.slash("sync")
check("Max still holds 5 records after relog", max2.said(r"Records: 5 held"))
max2.slash("test after relog")
run(2)
check("Next record is #3", bram.said(r"Test record #3 from Max"))

print("== 5. Max's saved file is lost (crash); Bram tells Max his top number")
clients.remove(max2)
max3 = Client("Max")
clients.append(max3)
run(8)
max3.slash("test fresh start")
run(2)
check("Fresh Max doesn't reuse a number (#4)", bram.said(r'Test record #4 from Max: "fresh start"'))
check("No clashing records at Bram", not bram.said(r"[1-9]\d* clashing"))

print("== 6. Mira arrives with a newer version and protocol")
mira = Client("Mira", version="0.2.0", protocol=3)
clients.append(mira)
run(8)
check("Max is told to update", max3.said(r"A newer version of the Ministry add-on is in use \(0\.2\.0\)"))
mira.slash("test from the future")
run(2)
check("Max ignores the newer-protocol record", not max3.said(r"from the future"))
max3.slash("test old copy")
check("Max's old copy refuses to write records", max3.said(r"Not written: a newer version is in use"))

print("== 7. messaging lockdown holds the queue")
clients.remove(mira)
locked = Client("Mira", lockdown=True)
clients.append(locked)
run(8)
locked.slash("sync")
check("Locked client keeps its hello waiting", locked.said(r"0 sent, 1 waiting"))

print("== 8. a character with no guild")
GUILD_SAVE = GUILD
GUILD = None
loner = Client("Loner")
GUILD = GUILD_SAVE
clients.append(loner)
run(8)
loner.slash("probe")
loner.slash("probe limits")
loner.slash("sync")
check("Probe says the character has no guild", loner.said(r"this character isn't in a guild"))
check("Limits test explains why it can't run", loner.said(r"needs a character in a guild"))

print("== 9. the window (Milestone 2)")
ui_client = Client("Bram")
clients.append(ui_client)
run(8)
L = ui_client.lua
ns = L.globals().MinistryOfTheAllied
ui_client.slash("")
win = L.globals().MinistryOfTheAlliedFrame
check("/mota opens the window", win is not None and win.shown)
check("The window opens on the Throne Room", ns.UI.heading.text == "The Throne Room")
check("Footer shows sync status", "SYNCED WITH" in ns.UI.footLeft.text)
check("Footer shows the place and weekday", ns.UI.footRight.text == "TRADE DISTRICT · THURSDAY")
check("Footer: a hint at the right points at the resize corner", ns.UI.footHint.text == "DRAG CORNER TO RESIZE ->")
check("Rail foot shows the player's name", ns.UI.who.text == "Bram" and ns.UI.initials.text == "B")
tab3 = ns.UI.tabs[3]
tab3.scripts.OnEnter(tab3)
check("Hovering a tab shows its hover look", tab3.bgHover.shown and not tab3.bgRest.shown)
tab3.scripts.OnLeave(tab3)
tab3.scripts.OnClick(tab3)
check("Clicking a tab switches page", ns.UI.heading.text == "The Statute Book" and ns.UI.subtitles[3].shown and not ns.UI.subtitles[1].shown)
check("The active tab turns gold", tab3.bgOn.shown and not ns.UI.tabs[1].bgOn.shown)
ns.UI.tabs[7].scripts.OnClick(ns.UI.tabs[7])
check("Gladiator's Ring page", ns.UI.heading.text == "The Gladiator's Ring")
ui_client.slash("")
check("/mota again closes it", not win.shown)
ui_client.slash("")
ui_client.slash("scale 0.7")
check("Scale 0.7", abs(win.scale - 0.7) < 1e-6)
ui_client.slash("scale 9")
ui_client.slash("scale")
check("Default scale fits the screen", 0.4 < win.scale <= 0.85)
ui_client.slash("minimap")
seal = L.globals().MinistryOfTheAlliedMinimapButton
check("Minimap seal hides", seal is not None and not seal.shown)
ui_client.slash("minimap")
check("Minimap seal comes back", seal.shown)
before = ns.db.minimap.angle
seal.scripts.OnDragStart(seal)
seal.scripts.OnUpdate(seal)
seal.scripts.OnDragStop(seal)
check("Dragging the seal moves it", ns.db.minimap.angle != before)
seal.scripts.OnClick(seal)
check("Clicking the seal toggles the window", not win.shown)
ui_client.slash("crests")
ui_client.slash("crest 10")
check("Trying a game crest", ns.db.crest is not None and ns.db.crest.atlas == "bfa-landingbutton-alliance-up")
ui_client.slash("crest 11")
ui_client.slash("crest 99")
ui_client.slash("crest ours")
check("Back to our crest", ns.db.crest is None)

print("== 9a. drag a corner to resize the window (3c, 11 Nov)")
def QW(code):
    return ui_client.lua.eval("(function() local M = MinistryOfTheAllied " + code + " end)()")
QW('M.UI.window.mockRects = true')  # the mock gives this window's edges (and no other frame's)
def recentre():
    QW('M.db.window.point = nil M.db.window.scale = nil M.UI:RestorePosition()')
def corner_px(corner):
    return QW('local f = M.UI.window local e = f:GetEffectiveScale() return '
              + ('f:GetLeft()' if "LEFT" in corner else 'f:GetRight()') + ' * e, '
              + ('f:GetTop()' if "TOP" in corner else 'f:GetBottom()') + ' * e')
def drag(idx, x, y):
    QW(f'local g = M.UI.grips[{idx}] g.scripts.OnMouseDown(g, "LeftButton") CURSOR = {{ {x}, {y} }} g.scripts.OnUpdate(g, 0.016) g.scripts.OnMouseUp(g, "LeftButton")')
def grip_index(corner):
    return QW(f'for i, g in ipairs(M.UI.grips) do if g.grip.corner == "{corner}" then return i end end')
def near(a, b, tol=0.05):
    return abs(a - b) < tol
corners = sorted(QW('local t = {} for _, g in ipairs(M.UI.grips) do t[#t + 1] = g.grip.corner end return table.concat(t, ",")').split(","))
# Only the bottom right corner has a resize grip (the crest's top left never does)
check("Only the bottom right corner has a resize grip (the crest's top left never does)",
      corners == ["BOTTOMRIGHT"])
check("The bottom right grab zone is 36 by 36", QW('return M.UI.grips[1]:GetWidth()') == 36)
recentre()
check("Window starts at the default size, centred", near(QW('return M.UI.window:GetScale()'), 0.85, 1e-6))
tl = corner_px("TOPLEFT")
drag(grip_index("BOTTOMRIGHT"), tl[0] + 700, tl[1] - 476)
check("Dragging the bottom right corner sets the size the cursor asks for", near(QW('return M.UI.window:GetScale()'), 0.7, 1e-4))
after = corner_px("TOPLEFT")
check("...the opposite (top left) corner stays put", near(after[0], tl[0]) and near(after[1], tl[1]))
check("...and the size is saved in the settings", near(QW('return M.db.window.scale'), 0.7, 1e-4))
check("...with the corner it is anchored on", QW('return M.db.window.point') == "TOPLEFT")
drag(grip_index("BOTTOMRIGHT"), tl[0] + 100, tl[1] - 50)
check("The size never goes below 0.6", near(QW('return M.UI.window:GetScale()'), 0.6, 1e-4))
drag(grip_index("BOTTOMRIGHT"), 1364, 1)
check("A huge drag stops while the whole window is still on the screen",
      QW('local f = M.UI.window local e = f:GetEffectiveScale() return f:GetBottom() * e >= -0.01 and f:GetRight() * e <= UIParent.w + 0.01 and f:GetScale() <= 1.5'))
recentre()
tl = corner_px("TOPLEFT")
drag(grip_index("BOTTOMRIGHT"), tl[0] + 700, tl[1] - 476)
QW('M.UI.window:SetScale(1) M.UI.window.scale = 1')
QW('M.UI:RestorePosition()')
check("The saved size is restored at login", near(QW('return M.UI.window:GetScale()'), 0.7, 1e-4))
check("The size can reach 1.5 on a large screen",
      near(QW('local ow, oh = UIParent.w, UIParent.h UIParent.w, UIParent.h = 6000, 4000 local g = M.UI.grips[1].grip '
              'local s = M.UI:ScaleForCursor(g, 0, 4000, 6000, 0) UIParent.w, UIParent.h = ow, oh return s'), 1.5, 1e-6))
# in combat, only a protected window is left alone (this window isn't protected, but a page might one day make it so)
recentre()
tl = corner_px("TOPLEFT")
QW('COMBAT = true M.UI.window.IsProtected = function() return true end')
drag(grip_index("BOTTOMRIGHT"), tl[0] + 700, tl[1] - 476)
check("In combat, a window that is protected is not resized", near(QW('return M.UI.window:GetScale()'), 0.85, 1e-6))
QW('M.UI.window.IsProtected = nil')
drag(grip_index("BOTTOMRIGHT"), tl[0] + 700, tl[1] - 476)
check("In combat, an unprotected window still can be", near(QW('return M.UI.window:GetScale()'), 0.7, 1e-4))
QW('COMBAT = false')
recentre()

print("== 9b. window skins (Milestone 5)")
def rgb255(t):
    return tuple(round(t.color[i] * 255) for i in (1, 2, 3))
def skin_tex(t):
    return (t.texture or "").rsplit("\\", 1)[-1]
tab2 = ns.UI.tabs[2]
check("A citizen in no party wears the Ministry skin", ns.skin.KEY == "UNREGISTERED"
      and skin_tex(tab2.bgRest) == "skin_ministry.tga" and skin_tex(ns.UI.tabs[1].bgOn) == "frame_gold.tga")
check("The crest is the lion crest from the Ministry skin", skin_tex(ns.UI.crest) == "skin_ministry.tga")
# Only the Crown ranks may switch skins (spec 9.1); everyone else wears their rank's skin.
crown_ns = max3.lua.globals().MinistryOfTheAllied
crown_tab2 = lambda: crown_ns.UI.tabs[2]
check("The Crown wears the Crown skin", crown_ns.skin.KEY == "CROWN")
max3.slash("skin crown")
check("The Crown can try its own skin", max3.said(r"Trying the skin of the Crown"))
def accent_of(ns):
    a = ns.Accent(ns)
    g = ns.skin.GEM
    return a.INK, a.SUFFIX, round(g.r * 255), round(g.g * 255), round(g.b * 255)
check("The Crown skin's accent is plum with a jade jewel", accent_of(crown_ns) == ("58143F", "~cr", 0x0B, 0x7A, 0x38))
max3.slash("skin silverhand")
check("Silverhand's accent is blue with a sapphire jewel", accent_of(crown_ns) == ("1B3570", "", 0x2F, 0x5F, 0xD0))
max3.slash("skin exchange")
check("The Exchange skin's accent is crimson with an amethyst jewel", accent_of(crown_ns) == ("7A1219", "~ex", 0x9B, 0x5B, 0xD6))
max3.slash("skin silverhand")
check("/mota skin silverhand puts Silverhand's skin on the Crown's screen at once", crown_ns.skin.KEY == "SILVERHAND"
      and skin_tex(crown_tab2().bgRest) == "skin_silverhand.tga" and skin_tex(crown_ns.UI.crest) == "skin_silverhand.tga")
check("Silverhand's skin brings the silver metal", skin_tex(crown_ns.UI.tabs[1].bgOn) == "frame_silver.tga")
check("The lit tab's label takes the party blue", rgb255(crown_ns.UI.tabs[crown_ns.UI.page].label.letters[1]) == (0x1F, 0x42, 0x90))  # live text: each letter is a FontString
max3.slash("skin exchange")
check("The Exchange's skin is gold again", crown_ns.skin.KEY == "AZEROTH_EXCHANGE" and skin_tex(crown_ns.UI.tabs[1].bgOn) == "frame_gold.tga")
max3.slash("skin bogus")
check("An unknown skin is refused", max3.said(r"There's no skin called \"bogus\"") and crown_ns.skin.KEY == "AZEROTH_EXCHANGE")
max3.slash("skin ministry")
check("The resting tab's label takes the Ministry's ink", crown_ns.skin.KEY == "UNREGISTERED" and skin_tex(crown_tab2().bgRest) == "skin_ministry.tga")
max3.slash("skin")
check("/mota skin alone goes back to your own", crown_ns.skin.KEY == "CROWN" and max3.said(r"Back to your own skin: the Crown"))
crown_ns.db.settings.windowSkin = "ministry"
crown_ns.Skin.Refresh(crown_ns.Skin, True)
check("The setting Ministry gives the Crown the blue and gold", crown_ns.skin.KEY == "UNREGISTERED")
crown_ns.db.settings.windowSkin = "party"
crown_ns.Skin.Refresh(crown_ns.Skin, True)
check("The setting Party gives the Crown skin back", crown_ns.skin.KEY == "CROWN")
mark = len(max3.log)
max3.slash("help")
check("/mota skin is listed in the help for the Crown", any(re.search(r"/mota skin", l) for l in max3.log[mark:]))

# A citizen (Bram): refused, not listed, no settings row, rank skin kept.
ns.PartyOf = lambda self, name: "SILVERHAND"  # pretend Bram's party is Silverhand
ns.Skin.Refresh(ns.Skin, True)
check("A non-Crown citizen's skin follows their party", ns.skin.KEY == "SILVERHAND")
ui_client.slash("skin crown")
check("A citizen is politely refused by /mota skin", ui_client.said(r"only the Crown ranks can change theirs"))
check("...and nothing changes", ns.skin.KEY == "SILVERHAND" and ns.Skin.preview is None)
ui_client.slash("skin ministry")
check("...for any skin, the Ministry's too", ns.skin.KEY == "SILVERHAND")
mark = len(ui_client.log)
ui_client.slash("help")
check("/mota skin isn't listed for a citizen", not any(re.search(r"/mota skin", l) for l in ui_client.log[mark:])
      and any(re.search(r"/mota scale", l) for l in ui_client.log[mark:]))
ns.db.settings.windowSkin = "ministry"  # an old saved choice
ns.Skin.Refresh(ns.Skin, True)
check("An old saved Ministry choice can't override a citizen's rank skin", ns.skin.KEY == "SILVERHAND")
ns.db.settings.windowSkin = "party"
def Q(c, code):  # as below (section 13); needed here first
    return c.lua.eval("(function() local M = MinistryOfTheAllied " + code + " end)()")


def open_settings(client):
    """The Settings page, in the add-on's own window (Max, 9 Nov)."""
    client.slash("settings")
    return client.lua.globals().MinistryOfTheAllied.SettingsPage
bram_panel = open_settings(ui_client)
check("Settings: /mota settings opens the page in the window, the gear lit, no tab lit",
      Q(ui_client, 'return M.UI.window:IsShown() and M.UI.settingsOpen and M.UI.knobSettings.lit.shown and M.UI.settingsSub.shown') is True
      and Q(ui_client, 'for _, t in ipairs(M.UI.tabs) do if t.look == "on" then return false end end return true') is True)
check("A citizen sees no Window skin group", not bram_panel.groups[3].shown and bram_panel.groups[2].shown)
skin_btn = bram_panel.controls[11]   # (the herald size has three choices since 10 Nov)
skin_btn.scripts.OnClick(skin_btn)
check("...and clicking it anyway changes nothing", ns.db.settings.windowSkin == "party" and ns.skin.KEY == "SILVERHAND")
# the World map skin row (D5f): everyone's, Party at first; Plain takes the dress off at once
map_btns = [bram_panel.controls[7], bram_panel.controls[8], bram_panel.controls[9]]
check("A citizen sees the World map skin row, Party chosen", map_btns[0].on.shown and map_btns[1].off.shown and map_btns[2].off.shown
      and ns.db.settings.mapSkin == "party")
ui_client.lua.execute('MAP_SKIN_HEARD = 0; MinistryOfTheAllied:Listen("MAP_SKIN_CHANGED", function() MAP_SKIN_HEARD = MAP_SKIN_HEARD + 1 end)')
map_btns[2].scripts.OnClick(map_btns[2])
check("...Plain chosen, the map is told", ns.db.settings.mapSkin == "plain" and map_btns[2].on.shown and map_btns[0].off.shown
      and ui_client.lua.globals().MAP_SKIN_HEARD == 1)
map_btns[0].scripts.OnClick(map_btns[0])
check("...and Party again", ns.db.settings.mapSkin == "party" and map_btns[0].on.shown)
max_panel = open_settings(max3)
party_btn = max_panel.controls[10]
check("The Crown sees the Window skin group, Party chosen", party_btn.on.shown and not party_btn.off.shown
      and max_panel.controls[11].off.shown and max_panel.groups[3].shown)
ministry_btn = max_panel.controls[11]
ministry_btn.scripts.OnClick(ministry_btn)
check("...and can use it", crown_ns.db.settings.windowSkin == "ministry" and crown_ns.skin.KEY == "UNREGISTERED")
crown_ns.db.settings.windowSkin = "party"
crown_ns.Skin.Refresh(crown_ns.Skin, True)
# the gear again, or a tab, goes back to the page you were on
Q(ui_client, 'M.UI:ShowSettings()')
check("Settings: the gear again goes back to the page", Q(ui_client, 'return not M.UI.settingsOpen and not M.UI.knobSettings.lit.shown and M.UI.tabs[M.UI.page].look == "on"') is True)
Q(ui_client, 'M.UI:ShowSettings(true)')
ui_client.lua.execute('local t = MinistryOfTheAllied.UI.tabs[MinistryOfTheAllied.UI.page]; t.scripts.OnClick(t)')
check("Settings: ...and so does the tab you were on", Q(ui_client, 'return not M.UI.settingsOpen and M.UI.tabs[M.UI.page].look == "on" and not M.UI.settingsSub.shown') is True)
check("Settings: the game's options keep a small entry with Open settings", ui_client.lua.globals().MinistryOfTheAlliedOptions.open is not None)
Q(max3, 'M.UI.window:Hide()')
max3.slash("skin exchange")
check("/mota skin changes the skin without opening the window",
      Q(max3, 'return M.Skin.preview') == "AZEROTH_EXCHANGE" and not Q(max3, 'return M.UI.window:IsShown()'))
max3.slash("skin")
ui_client.slash("probe")
check("Probe reports the fonts", ui_client.said(r"Add-on fonts \(Cinzel, EB Garamond\): loaded"))
ui_client.slash("help")
print("  Methods the pretend game didn't know:", L.globals().mock_unknown())
media_dir = os.path.join(ADDON, "Media")
missing = []
for path in L.globals().mock_textures().split("\n"):
    if path.startswith("Interface\\AddOns\\MinistryOfTheAllied\\"):
        rel = path[len("Interface\\AddOns\\MinistryOfTheAllied\\"):].replace("\\", os.sep)
        if not os.path.exists(os.path.join(ADDON, rel)):
            missing.append(path)
check("Every texture and font the add-on asks for exists", not missing)
for m in missing:
    print("   missing:", m)

print("== 10. the window remembers its page after a relog")
saved = ui_client.saved()
clients.remove(ui_client)
again = Client("Bram", saved=saved)
clients.append(again)
run(8)
again.slash("")
check("Reopens on the last page", again.lua.globals().MinistryOfTheAllied.UI.heading.text == "The Gladiator's Ring")


def herald_button(f, key):
    """The herald shows its button in this style with this label, as "quiet:Dismiss" (one button
    per style since the banner, 9 Nov; its label is spaced out, a font string a letter)."""
    style, label = key.split(":")
    b = f.buttons[style]
    if b is None or not b.shown:
        return False
    letters = b.label.letters
    return "".join(letters[i].text for i in range(1, len(letters) + 1) if letters[i].shown) == label.upper()


print("== 11. herald pop-ups and settings (Milestone 3)")
hc = Client("Bram")
clients.append(hc)
run(8)
HL = hc.lua.globals()
hns = HL.MinistryOfTheAllied
hc.slash("herald")
hf = HL.MinistryOfTheAlliedHerald
check("/mota herald shows the first sample", hf is not None and hf.shown and hf.title.text == "The polls are open!")
check("The eyebrow is letter-spaced", sum(1 for _ in hf.eyebrow.letters.values()) >= 20)
check("Royal size by default", abs(hf.scale - 0.8) < 1e-6)
check("A fanfare played", HL.LAST_SOUND == 888)
run(11)
check("After ten seconds the next sample shows", hf.title.text == "The Guild Bank Levy is law")
check("...with the gold Read it button of Max's banner", herald_button(hf, "gold:Read it") and not hf.buttons.blue.shown)
check("...on the banner in the window's skin", hf.slices[1].texture.endswith("herald_ministry.tga") and hf.seal.texture.endswith("herald_ministry.tga"))
hns.Herald.Press(hns.Herald)
check("Its button opens the Statute Book", HL.MinistryOfTheAlliedFrame.shown and hns.UI.heading.text == "The Statute Book")
check("Then the third sample", hf.title.text == "Elowen Marsh defects!")
hns.Herald.Press(hns.Herald)
check("Dismiss empties the queue", not hf.shown and hns.Herald.Waiting(hns.Herald) == 0)
B = hns.Media.herald
long_text = ("Tickets 1g each, bought at the guild bank (choose Lottery as the reason). "
             "The draw is after 12 Nov. The winner takes 70% of the pot.")
hns.Herald.Announce(hns.Herald, hc.lua.table_from({"seal": "treasury", "eyebrow": "The Royal Lottery", "title": "Spring Draw is open",
                                                  "text": long_text, "button": hc.lua.table_from({"label": "Dismiss", "style": "quiet"})}), True)
shown_lines = [hf.lines[i].text for i in range(1, len(hf.lines) + 1) if hf.lines[i].shown]
check("A long text wraps by words, a line each", len(shown_lines) == 3 and " ".join(shown_lines) == long_text)
check("...and the banner grows a line for it", abs(hf.h - (B.h + B.text.line)) < 1e-6)
hns.Herald.Press(hns.Herald)
run(1)
top_before = hc.lua.eval("MinistryOfTheAllied.guild.tops[MinistryOfTheAllied.me] or 0")
hc.wire.clear()
hc.slash("heralds all")
n_prev = hns.HeraldPreview.Count(hns.HeraldPreview)
check("/mota heralds all queues every real herald", hns.Herald.Waiting(hns.Herald) == n_prev and n_prev >= 16)
for _ in range(n_prev):
    hns.Herald.Press(hns.Herald)
check("The preview writes and sends nothing", hc.lua.eval("MinistryOfTheAllied.guild.tops[MinistryOfTheAllied.me] or 0") == top_before and len(hc.wire) == 0)
check("...and all of them dismiss cleanly", hns.Herald.Waiting(hns.Herald) == 0)
hc.slash("heralds 3")
check("/mota heralds <number> shows one", hns.Herald.Waiting(hns.Herald) == 1)
hns.Herald.Press(hns.Herald)

HL.COMBAT = True
hc.slash("herald 1")
check("A herald waits during combat", not hf.shown)
HL.COMBAT = False
HL.mock_fire("PLAYER_REGEN_ENABLED")
check("...and shows when combat ends", hf.shown)
hns.Herald.Press(hns.Herald)

hc.slash("settings")
check("/mota settings opens the Settings page in the window", hns.UI.settingsOpen is True and hns.UI.window.shown)
controls = hns.SettingsPage.controls
herald_switch, glow_switch = controls[1], controls[6]
herald_switch.scripts.OnClick(herald_switch)
check("The herald switch turns heralds off", hns.db.settings.herald == False and herald_switch.off.shown)
check("A non-sample herald is then skipped", hns.Herald.Announce(hns.Herald, HL.MinistryOfTheAllied.Herald.samples[1]) == False)
herald_switch.scripts.OnClick(herald_switch)
hc.lua.execute('GLOW_HEARD = 0; MinistryOfTheAllied:Listen("GLOW_CHANGED", function() GLOW_HEARD = GLOW_HEARD + 1 end)')
glow_switch.scripts.OnClick(glow_switch)
check("The District glow switch turns the glow off and tells the map",
      hns.db.settings.glow == False and glow_switch.off.shown and HL.GLOW_HEARD == 1)
glow_switch.scripts.OnClick(glow_switch)
cards_switch = controls[15]   # (the two Guild on the maps switches sit before it since 11 Nov)
cards_switch.scripts.OnClick(cards_switch)
check("A switch for a later feature doesn't change", hns.db.settings.cards == False)
modest = controls[3]
modest.scripts.OnClick(modest)
check("Modest is chosen", hns.db.settings.heraldSize == "small" and modest.on.shown and not controls[5].on.shown)
hc.slash("herald 3")
check("A Modest herald is smaller", abs(hf.scale - 0.56) < 1e-6)
hns.Herald.Press(hns.Herald)
# Stately, halfway between Modest and Royal (Max, 10 Nov)
stately = controls[4]
stately.scripts.OnClick(stately)
check("Stately is chosen", hns.db.settings.heraldSize == "medium" and stately.on.shown and modest.off.shown and controls[5].off.shown)
hc.slash("herald 3")
check("A Stately herald is halfway between Modest and Royal", abs(hf.scale - 0.68) < 1e-6)
hns.Herald.Press(hns.Herald)
# Where heralds appear (Max, 10 Nov): Preview, the round lock, drag, Save
hc.slash("herald 1")
preview_btn = hns.SettingsPage.GROUPS[1].rows[4].button
preview_btn.scripts.OnClick(preview_btn)
check("Settings' Preview shows a herald that stays, with the round lock and Save",
      hf.shown and hf.title.text == "Where heralds appear" and hf.lock.shown and herald_button(hf, "blue:Save")
      and "skin_" in hf.lock.art.texture)
check("...the herald that was up waits its turn behind it", hns.Herald.Waiting(hns.Herald) == 2)
check("...locked at first", hns.Herald.IsUnlocked(hns.Herald) is False)
hf.lock.scripts.OnClick(hf.lock)
check("The round lock opens it", hns.Herald.IsUnlocked(hns.Herald) is True)
hc.lua.execute("MinistryOfTheAlliedHerald.cx, MinistryOfTheAlliedHerald.cy = 300, 200")   # dragged there
hns.Herald.Press(hns.Herald)
pos = hns.db.settings.heraldPos
check("Save keeps where it stands (its top middle, from the screen's top middle)",
      pos is not None and abs(pos.x - (300 * 0.68 - 1365 / 2)) < 1e-6
      and abs(pos.y - ((200 + hns.Media.herald.h / 2) * 0.68 - 768)) < 1e-6)
check("...the lock shuts and the waiting herald comes back, standing there",
      hns.Herald.IsUnlocked(hns.Herald) is False and hf.shown and hf.title.text == "The polls are open!" and not hf.lock.shown
      and hc.lua.execute('local p, _, rp, x, y = MinistryOfTheAlliedHerald:GetPoint(1) '
                      'return p == "TOP" and rp == "TOP" and math.abs(x - (300 * 0.68 - 1365 / 2) / 0.68) < 1e-6') is True)
hns.Herald.Press(hns.Herald)
hns.Herald.ResetPosition(hns.Herald)
check("...and back to the top of the screen when reset", hns.db.settings.heraldPos is None)
# Position presets (Max, 10 Nov): a cross of five buttons just above the middle of the screen
def herald_point():
    return tuple(hc.lua.execute('local p, _, rp, x, y = MinistryOfTheAlliedHerald:GetPoint(1) return p, rp, x, y'))
def button_at(name):
    return tuple(hc.lua.execute(f'local b = MinistryOfTheAlliedHeraldPresets.buttons.{name} '
                                'local p, _, rp, x, y = b:GetPoint(1) return x, y'))
preview_btn.scripts.OnClick(preview_btn)
cross = HL.MinistryOfTheAlliedHeraldPresets
names = ("top", "left", "center", "right", "bottom")
check("The preview shows five preset buttons, just above the middle of the screen",
      cross is not None and cross.shown and all(cross.buttons[n] is not None for n in names)
      and hc.lua.execute('local p, _, rp, x, y = MinistryOfTheAlliedHeraldPresets:GetPoint(1) '
                         'return p == "CENTER" and rp == "CENTER" and x == 0 and y > 0') is True)
at = {n: button_at(n) for n in names}
check("...each where it sends the herald", at["left"][0] < at["center"][0] < at["right"][0]
      and at["top"][1] > at["center"][1] > at["bottom"][1] and at["top"][0] == at["center"][0] == at["bottom"][0])
s68 = hf.scale
cross.buttons.left.scripts.OnClick(cross.buttons.left)
p, rp, x, y = herald_point()
check("Left sends the preview to the left edge", p == "LEFT" and rp == "LEFT" and abs(x * s68 - 58) < 1e-6)
hns.Herald.Press(hns.Herald)
check("Save keeps the preset by name, and the buttons go with the preview",
      hns.db.settings.heraldPos.preset == "left" and not cross.shown)
hc.slash("herald 1")
check("The next herald stands at the left edge", herald_point()[0] == "LEFT")
hns.Herald.Press(hns.Herald)
preview_btn.scripts.OnClick(preview_btn)
cross.buttons.bottom.scripts.OnClick(cross.buttons.bottom)
p, rp, x, y = herald_point()
check("Bottom: the banner's foot the same gap from the screen's foot", p == "BOTTOM" and abs(y * s68 - 58) < 1e-6 and x == 0)
cross.buttons.top.scripts.OnClick(cross.buttons.top)
p, rp, x, y = herald_point()
crown = -hns.Media.pieces["herald_ministry:frame"].y
check("Top: the crown the same gap from the screen's top", p == "TOP" and abs(-y * s68 - (58 + crown * s68)) < 1e-6)
hf.lock.scripts.OnClick(hf.lock)
hf.scripts.OnDragStart(hf)
hf.scripts.OnDragStop(hf)
hns.Herald.Press(hns.Herald)
check("Dragged after a preset, Save keeps its own place instead",
      hns.db.settings.heraldPos.preset is None and hns.db.settings.heraldPos.x is not None)
hns.Herald.ResetPosition(hns.Herald)
# A long title steps down in its own font until it fits its line (Max, 10 Nov: heralds 13, 18, 26)
# (the pretend game measures 6 a letter in any font, so the title here is long enough to need it there)
long_title = "Elowenwyn of Goldshire is appointed a Justice of the High Judiciary at last"
hns.Herald.Announce(hns.Herald, hc.lua.table_from({"seal": "crown", "eyebrow": "By the Crown", "title": long_title,
                                                  "text": "A seat on the High Judiciary.",
                                                  "button": hc.lua.table_from({"label": "Dismiss", "style": "quiet"})}), True)
check("A long title keeps the title's font, stepped down to fit its line",
      hf.title.text == long_title and hf.titleSize < 21 and hf.title.font.path.endswith("MinistryDecorative-Bold.ttf"))
hns.Herald.Press(hns.Herald)
hc.slash("heralds 13")
check("A title that fits keeps its full size", hf.titleSize == 21 or len(hf.title.text) * 6 > 386)
hns.Herald.Press(hns.Herald)
hc.slash("fanfare")
hc.slash("fanfare 2")
check("Fanfare 2 chosen", hns.db.settings.fanfareSound == "READY_CHECK" and HL.LAST_SOUND == 8960)
hns.UI.window.Hide(hns.UI.window)
seal = HL.MinistryOfTheAlliedMinimapButton
seal.scripts.OnClick(seal, "RightButton")
check("Right-clicking the minimap seal opens the Settings page", hns.UI.settingsOpen is True and hns.UI.window.shown)

max4 = Client("Max")
clients.append(max4)
run(8)
max4.slash("test Hear ye from Max")
run(2)
check("A test record from another member arrives as a herald", hf.shown and hf.title.text == "A test from Max")
print("== 12. the Charter narration and the Constitution page")
vc = Client("Mira", voice=True)
clients.append(vc)
VL = vc.lua.globals()
vns = VL.MinistryOfTheAllied
V = vns.Voice
played = lambda: len(list(VL.VOICE_PLAYED.values()))
last = lambda: VL.VOICE_PLAYED[played()]
vh = lambda: VL.MinistryOfTheAlliedHerald

run(8)
check("The introduction starts by itself on first login", played() == 1 and last().endswith("voice_01.ogg"))
check("Its scroll has no Stop button", vh().shown and vh().title.text == "Introduction" and not vh().closeX.shown and herald_button(vh(), "quiet:Dismiss"))
check("No fanfare over the narration", VL.LAST_SOUND != 888)
vc.slash("voice stop")
check("The introduction can't be stopped", VL.VOICE_STOPPED == 0 and V.Locked(V))
vc.slash("voice off")
check("...or switched off", vns.db.settings.voice)
vc.slash("constitution")
check("/mota constitution opens the Statute Book", VL.MinistryOfTheAlliedFrame.shown and vns.UI.heading.text == "The Statute Book")
for view_name in ("force", "wait", "court", "charter"):
    vns.StatutesPage.Select(vns.StatutesPage, view_name)
check("Statute Book: every view opens without errors", True)
check("The board's layout replaces the page heading", not vns.UI.heading.shown and not vns.UI.divider.shown)
check("The Charter text is there", any(b[2] == "Preamble" for b in vns.Charter.values()))
vns.ConstitutionPage.Press(vns.ConstitutionPage, 3)
check("The page can't interrupt the introduction", played() == 1)
run(21)
check("Its scroll closes after a while", not vh().shown)
check("...while the voice plays on", V.Playing(V) is not None and VL.VOICE_STOPPED == 0)
run(55)
check("The introduction finishes", V.Playing(V) is None and V.State(V).nextClip == 2)
run(135)
check("No second clip before the gap is up", played() == 1)
run(12)
check("Part 1 comes after about two and a half minutes", played() == 2 and last().endswith("voice_02.ogg"))
check("Its scroll has Stop and a close button", vh().shown and vh().title.text == "The Crown" and vh().closeX.shown)
run(30)
check("...and stays while the clip plays", vh().shown)
vns.Herald.Press(vns.Herald)
check("Stop stops the sound", VL.VOICE_STOPPED == 1 and V.Playing(V) is None)
check("...and offers Restart", vh().shown and herald_button(vh(), "blue:Restart"))
vns.Herald.Press(vns.Herald)
check("Restart plays from the beginning", played() == 3 and last().endswith("voice_02.ogg") and herald_button(vh(), "quiet:Stop"))
vh().closeX.scripts.OnClick(vh().closeX)
check("The X closes the scroll, the voice plays on", not vh().shown and V.Playing(V) is not None)
V.Stop(V)
vns.ConstitutionPage.Press(vns.ConstitutionPage, 5)
check("The page replays any clip", last().endswith("voice_05.ogg"))
vns.ConstitutionPage.Press(vns.ConstitutionPage, 5)
check("...and stops it", V.Playing(V) is None)
check("...with a Restart on its scroll", vh().shown and herald_button(vh(), "blue:Restart"))
vh().closeX.scripts.OnClick(vh().closeX)
n, stopped = played(), VL.VOICE_STOPPED
for clip in (4, 6, 7, 8):
    vns.ConstitutionPage.Press(vns.ConstitutionPage, clip)
check("Play shows a scroll with Stop", vh().shown and vh().closeX.shown and herald_button(vh(), "quiet:Stop"))
check("Quick presses leave one scroll, showing the last clip", vh().title.text == "Punitive Measures" and vns.Herald.Waiting(vns.Herald) == 1)
check("...and one sound: each new clip stops the last", played() == n + 4 and VL.VOICE_STOPPED == stopped + 3)
run(60)
check("The earlier clips' timers don't end it early", V.Playing(V).index == 8 and vh().shown)
run(11)
check("The scroll closes when the last clip ends", V.Playing(V) is None and not vh().shown)
V.ScheduleNext(V, 1)
vns.ConstitutionPage.Press(vns.ConstitutionPage, 7)
run(2)
V.Stop(V)
vh().closeX.scripts.OnClick(vh().closeX)
n = played()
run(16)
check("Stopping a replay doesn't stall the sequence", played() == n + 1 and last().endswith("voice_03.ogg"))
V.Stop(V)
vh().closeX.scripts.OnClick(vh().closeX)
state = V.State(V)
state.nextClip = 3
state.complete = False
VL.COMBAT = True
V.PlayNext(V)
n = played()
check("A clip waits during combat", played() == n and not vh().shown)
VL.COMBAT = False
VL.mock_fire("PLAYER_REGEN_ENABLED")
run(16)
check("...and plays after combat ends", played() == n + 1 and last().endswith("voice_03.ogg"))
V.Stop(V)
vh().closeX.scripts.OnClick(vh().closeX)
state = V.State(V)
state.nextClip = 10
V.PlayNext(V)
run(26)
check("After the last clip the sequence is complete", state.complete)
run(200)
check("...and nothing more plays", V.Playing(V) is None and not vh().shown)
vc.lua.execute("C_Sound = { IsPlaying = function() return SOUND_ALIVE end }; SOUND_ALIVE = true")
vns.ConstitutionPage.Press(vns.ConstitutionPage, 5)
run(2)
check("A playing clip isn't called cut off", V.Playing(V) is not None)
VL.SOUND_ALIVE = False
run(2)
check("A clip the game drops offers Restart", V.Playing(V) is None and vh().shown and herald_button(vh(), "blue:Restart"))
clients.remove(vc)

print("== 12b. the Parties page")
vns.UI.SelectPage(vns.UI, 4)
pp = vns.PartiesPage
check("The Parties page replaces the page heading", not vns.UI.heading.shown and not vns.UI.note.shown)
pp.Select(pp, "ex")
pp.Select(pp, "ch")
check("The chamber opens sealed, on the last party viewed", pp.Select is not None)
pp.Select(pp, "sh")
vns.UI.SelectPage(vns.UI, 1)

print("== 12c. the party roll and the bank prompt")
others = clients[:]
crownP = Client("Max", tag="CAMWOWEU5Realm7PvE")
cit = Client("Bram")
clients[:] = [crownP, cit]
run(12)
BANK_STUB = """
  BANK = 5000000
  GetGuildBankMoney = function() return BANK end
  DepositGuildBankMoney = function(a) BANK = BANK + a end
  WithdrawGuildBankMoney = function(a) if a <= BANK then BANK = BANK - a end end
  LOG = {}
  QueryGuildBankLog = function() end
  GetNumGuildBankMoneyTransactions = function() return #LOG end
  GetGuildBankMoneyTransaction = function(i) return LOG[i][1], LOG[i][2], LOG[i][3] end
  MinistryOfTheAllied.Bank:Install()
"""
cit.lua.execute(BANK_STUB)
crownP.lua.execute(BANK_STUB)
def P(c, code):
    return c.lua.eval("(function() local M, Pa = MinistryOfTheAllied, MinistryOfTheAllied.Party " + code + " end)()")
check("Party: the Crown can't ask to join", P(crownP, 'return (Pa:JoinState("sh"))') == "The Crown stands apart" and P(crownP, 'return Pa:Ask("sh") == nil') is True)
check("Party: a citizen can", P(cit, 'return (Pa:JoinState("sh"))') == "Ask to join")
P(cit, 'Pa:Ask("sh")')
run(1)
check("Party: the Crown sees the request, unpaid", P(crownP, 'local q = Pa:Requests()[1] return q and q.name == "Bram" and q.p == "sh" and q.paid == 0') is True)
check("Party: the Crown hears of it", crownP.said(r"Bram asks to join the Silverhand"))
cit.lua.execute('DepositGuildBankMoney(50000)')
check("Bank: no prompt until the balance really changes", P(cit, 'return M.BankPrompt:IsShown()') is False)
cit.lua.execute('mock_fire("GUILDBANK_UPDATE_MONEY")')
check("Bank: the deposit raises the prompt", P(cit, 'return M.BankPrompt:IsShown()') is True)
keepB = cit.saved()
cit2 = Client("Bram", saved=keepB)
clients[:] = [crownP, cit2]
run(7)
check("Bank: an unanswered prompt comes back after a reload", P(cit2, 'return M.BankPrompt:IsShown()') is True)
cit = cit2
cit.lua.execute(BANK_STUB)
check("Bank: Other needs a note", P(cit, 'return M.BankPrompt:Answer("other", "  ") == nil and M.BankPrompt:IsShown()') is True)
P(cit, 'M.BankPrompt:Answer("party_sh")')
run(1)
check("Bank: small amounts show on the party's funds", P(crownP, 'return M:Money(100)') == "1s" and P(crownP, 'return M:Money(0)') == "0g" and P(crownP, 'return M:Money(52001)') == "5g 20s 1c")
check("Bank: answering says it was recorded", cit.said(r"Recorded in the guild's book: 5g deposit . Silverhand donation"))
check("Bank: answering clears the prompt", P(cit, 'return M.BankPrompt:IsShown()') is False)
check("Party: the donation reaches the Crown and the party's funds", P(crownP, 'return Pa:Requests()[1].paid == 50000 and Pa:Funds("sh") == 50000') is True)
crownP.lua.execute('LOG = { { "deposit", "Bram-CAMWOWEU5Realm7PvE", 50000 } }; mock_fire("GUILDBANKLOG_UPDATE")')
check("Party: the bank log confirms it", P(crownP, 'return Pa:Requests()[1].confirmed') is True)
check("Party: a citizen can't admit", P(cit, 'local r = Pa:Roll(); local before = r.members.Bram; M.Book:Write("party.admit", { v = "Bram", p = "sh" }); return before == nil') is True)
run(1)
check("Party: and their record is ignored", P(crownP, 'return Pa:Of("Bram") == nil') is True)
P(crownP, 'Pa:Admit("Bram")')
run(1)
check("Party: admitted on every copy", P(crownP, 'return Pa:Of("Bram")') == "sh" and P(cit, 'return Pa:Of("Bram")') == "sh")
check("Party: membership gives the party's skin", P(cit, 'return M.skin.KEY') == "SILVERHAND")
vnsP = cit.lua.eval("MinistryOfTheAllied")
vnsP.UI.Build(vnsP.UI)
vnsP.UI.SelectPage(vnsP.UI, 4)
cit.lua.execute('MinistryOfTheAllied.PartiesPage:Select("ch")')
check("Party: the member's button offers leaving", P(cit, 'return (Pa:JoinState("sh"))') == "Leave the party")
check("Party: a member can't ask to join the other party", P(cit, 'return (Pa:JoinState("ex"))') == "Leave your party first")
P(cit, 'Pa:Leave()')
run(1)
check("Party: leaving takes effect everywhere", P(crownP, 'return Pa:Of("Bram") == nil and #Pa:Roll().floor == 1') is True)
check("Party: leaving returns the Ministry skin", P(cit, 'return M.skin.KEY') == "UNREGISTERED")
P(cit, 'M.Book:Write("party.join", { p = "ex" })')
run(1)
P(crownP, 'M.Book:Write("party.admit", { v = "Bram", p = "ex" })')
run(1)
check("Party: the 14-day wait refuses the other party", P(crownP, 'return Pa:Of("Bram") == nil and Pa:WaitUntil("Bram", "ex") ~= nil') is True)
P(crownP, 'Pa.WAIT = 0; M:Fire("GUILD_READY")')
check("Party: after the wait, the other party's admission counts", P(crownP, 'return Pa:Of("Bram")') == "ex")
crownP.lua.execute('MinistryOfTheAllied.UI:Build(); MinistryOfTheAllied.UI:SelectPage(4); MinistryOfTheAllied.PartiesPage:Select("ch")')
check("Party: the Crown's desk opens without errors", True)

print("== 12d. the ledger")
run(31)
check("Books closed: a Crown rank has a herald that stays", P(crownP, 'local h = M.Ledger:ClosedHerald() return h ~= nil and h.stay == false') is True)
check("Books closed: a citizen doesn't", P(cit, 'return M.Ledger:ClosedHerald() == nil') is True)
crownP.lua.execute('MinistryOfTheAllied.UI:SelectPage(5)')
check("Ledger: the Treasury page replaces the page heading", not crownP.lua.eval("MinistryOfTheAllied.UI.note.shown"))
check("Ledger: a citizen can't open the books", P(cit, 'M.Bank.seenBalance = 0; M.Book:Write("bank.open", { bal = 999 }); return true') is True)
run(1)
check("Ledger: their record is ignored", P(crownP, 'return M.Ledger:Get().open == nil') is True)
check("Ledger: the books need the bank to have been open", P(crownP, 'M.Bank.seenBalance = nil; local _, err = M.Ledger:OpenBooks(); return err ~= nil') is True)
crownP.lua.execute('BANK = 0; LOG = {}; MinistryOfTheAllied.Bank:ReadLog()')
check("Books closed: at the bank, the herald's button opens them", P(crownP, 'local h = M.Ledger:ClosedHerald() return h ~= nil and h.button.onPress ~= nil') is True)
P(crownP, 'M.Ledger:OpenBooks()')
run(1)
check("Books closed: once open, the herald goes", P(crownP, 'return M.Ledger:ClosedHerald() == nil') is True)
check("Ledger: both copies open at the counted balance", P(cit, 'return M.Ledger:Get().open.bal') == 0 and P(crownP, 'return M.Ledger:Get().balance') == 0)
check("Ledger: money from before the opening doesn't count", P(cit, 'return Pa:Funds("sh") == 0 and #M.Ledger:Get().lines == 0') is True)
cit.lua.execute('BANK = 0; DepositGuildBankMoney(30000); mock_fire("GUILDBANK_UPDATE_MONEY")')
run(1)
check("Ledger: an unanswered deposit shows as unexplained", P(crownP, 'return M.Ledger:Get().unexplained') == 30000)
P(cit, 'M.BankPrompt:Answer("tax")')
run(1)
check("Ledger: answering balances the books", P(crownP, 'local d = M.Ledger:Get() return d.unexplained == 0 and d.moneyIn == 30000 and d.treasury == 30000') is True)
check("Ledger: the line has the depositor and reason", P(crownP, 'local l = M.Ledger:Page(1, 5)[1] return l.who == "Bram" and l.r == "tax" and l.t ~= nil') is True)
cit.lua.execute('DepositGuildBankMoney(1000); mock_fire("GUILDBANK_UPDATE_MONEY")')
run(1)
P(cit, 'M.Bank.Pending(M.Bank)[1].t = GetServerTime() - 5; M.Bank:SeeBalance()')
P(crownP, 'BANK = 31000; M.Bank:SeeBalance(); M.Ledger:OpenBooks()')
run(1)
P(cit, 'M.BankPrompt:Answer("tax")')
run(1)
check("Ledger: a move answered after the opening isn't counted twice", P(crownP, 'local d = M.Ledger:Get() return d.unexplained == 0 and d.moneyIn == 0 and d.expected == 31000') is True)
P(crownP, 'BANK = 0; M.Bank:SeeBalance(); M.Ledger:OpenBooks()')
run(1)
P(cit, 'DepositGuildBankMoney(30000)')
cit.lua.execute('BANK = 30000; mock_fire("GUILDBANK_UPDATE_MONEY")')
run(1)
P(cit, 'M.BankPrompt:Answer("tax")')
run(1)
crownP.lua.execute('LOG = { { "deposit", "Bram", 30000 }, { "deposit", "Mira-Realm", 7000 }, { "repair", "Bram", 500 } }; MinistryOfTheAllied.Bank:ReadLog()')
check("Ledger: the log finds entries with no line", P(crownP, 'local u = M.Ledger:Unmatched() return #u == 2 and u[1].name == "Mira" and u[2].kind == "repair"') is True)
P(crownP, 'M.Bank:AskFor(M.Ledger:Unmatched()[1])')
check("Ledger: the Crown is asked for the reason", P(crownP, 'return M.BankPrompt:IsShown()') is True)
# The prompt wears the herald's banner (10 Nov 2026), in each skin.
BP = crownP.lua.globals().MinistryOfTheAlliedBankPrompt
BPH = crownP.lua.globals().MinistryOfTheAllied.Media.herald
def bp_wears(skin):
    tga = f"herald_{skin}.tga"
    return (all(BP.slices[i].texture.endswith(tga) for i in range(1, 6)) and BP.seal.texture.endswith(tga)
            and BP.confirm.art.texture.endswith(tga))
def bp_seal(name):
    p = crownP.lua.eval(f'MinistryOfTheAllied.Media.pieces["herald_" .. MinistryOfTheAllied.skin.FILE .. ":seal_{name}"]')
    return abs(BP.seal.coords[1] - p.l) < 1e-9 and abs(BP.seal.coords[3] - p.t) < 1e-9
check("Bank prompt: on the herald's banner, with the Treasury seal", bp_wears(crownP.lua.eval("MinistryOfTheAllied.skin.FILE")) and abs(BP.h - BPH.h) < 1e-6 and bp_seal("treasury"))
check("Bank prompt: the chooser on the banner's text column, up to the button",
      abs(BP.chooser.points[1][4] - BPH.text.x) < 1e-6
      and abs(BP.chooser.w - (BPH.buttons.blue.x - BPH.text.gap - BPH.text.x)) < 1e-6)
check("Bank prompt: Confirm is the blue button, greyed until a reason is chosen",
      BP.confirm.enabled is False and abs(BP.confirm.alpha - 0.45) < 1e-6
      and "".join(BP.confirm.label.letters[i].text for i in range(1, 8)) == "CONFIRM")
BP.chooser.scripts.OnClick(BP.chooser)
check("Bank prompt: the open list grows the banner to hold it", BP.list.shown and BP.h > BPH.h + 100)
for skin in ("silverhand", "exchange", "crown", "ministry"):
    crownP.slash("skin " + skin)
    check(f"Bank prompt: wears the {skin} banner in the {skin} skin", bp_wears(skin))
BP.rows[6].scripts.OnClick(BP.rows[6])
check("Bank prompt: Silverhand funds take the party's seal; the list closes; Confirm is ready",
      not BP.list.shown and abs(BP.h - BPH.h) < 1e-6 and BP.confirm.enabled is True and BP.confirm.alpha == 1 and bp_seal("silverhand"))
P(crownP, 'M.BankPrompt:Answer("donation")')
run(1)
check("Ledger: the entry is filled for its depositor", P(cit, 'local l = M.Ledger:Page(1, 5)[1] return l.who == "Mira" and l.entered == "Max"') is True)
check("Ledger: and no longer listed", P(crownP, 'return #M.Ledger:Unmatched()') == 1)
P(crownP, 'for i = 1, 25 do M.Book:Write("bank.move", { io = "w", amt = 1, r = "supplies" }) end; M.TreasuryPage:Refresh()')
check("Ledger: long ledgers page without errors", P(crownP, 'local p, n = M.Ledger:Page(11, 10) return #p == 10 and n == 27') is True)
clients[:] = others

print("== 12e. catching up")
others = clients[:]
kingC = Client("Max")
citC = Client("Bram")
clients[:] = [kingC, citC]
run(12)
def Q(c, code):
    return c.lua.eval("(function() local M = MinistryOfTheAllied " + code + " end)()")
Q(kingC, 'M.Book:Write("test.note", { text = "one" }); M.Book:Write("party.join", { p = "sh" })')
Q(citC, 'M.Book:Write("test.note", { text = "two" })')
run(1)
late = Client("Mira")
clients.append(late)
late.log.clear()
run(20)
check("Catch-up: a late arrival gets records from before they came", Q(late, 'return (M.Book:Count())') == Q(kingC, 'return (M.Book:Count())') and Q(late, 'return (M.Book:Count())') == 3)
check("Catch-up: old records raise no test messages", not late.said(r"Test record"))
Q(kingC, 'M.guild.records.Bram[1] = nil; M.Sync:Send()')
run(10)
check("Catch-up: a gap gets filled", Q(kingC, 'return M.guild.records.Bram[1] ~= nil') is True)
Q(kingC, 'M.guild.records.Gone = { [20] = { t = 1, k = "test.note", d = {} } }; M.guild.tops.Gone = 20')
Q(citC, 'M.guild.records.Gone = { [20] = { t = 1, k = "test.note", d = {} } }; M.guild.tops.Gone = 20')
kingC.wire.clear()
citC.wire.clear()
Q(kingC, 'M.Sync:Send()')
run(10)
check("Catch-up: records beyond a permanent gap aren't sent again and again",
      not any("\x1fCU\x1f" in w for w in kingC.wire + citC.wire))
Q(citC, 'M.Book:Write("bank.open", { bal = 999 })')
run(1)
clients.remove(late)
saved_late = late.saved()
Q(citC, 'M.guild.records.Max = M.guild.records.Max or {}; M.guild.records.Max[99] = nil; return 1')
Q(kingC, 'M.guild.records.Bram[2] = { t = 1, k = "bank.open", d = { bal = 999 } }')
late2 = Client("Mira", saved=saved_late)
clients.append(late2)
run(20)
check("Catch-up: a passed-on record still needs permission", Q(late2, 'return M.guild.records.Bram[2] == nil and M.Ledger:Get().open == nil') is True)
check("Catch-up: a refused record is noted", Q(late2, 'return M.guild.refused.Bram[2]') is True)
check("Catch-up: and doesn't leave a gap to ask for again", Q(late2, 'return M.Sync:Upto("Bram")') == 2)
clients[:] = others

print("== 12f. leadership contests")
others = clients[:]
aldric_row = [m for m in ROSTER if m[0] == "Aldric-Realm"][0]
aldric_row[3] = True
kA = Client("Max", tag="CAMWOWEU5Realm7PvE")
kB = Client("Aldric")
m1, m2, m3 = Client("Bram"), Client("Mira"), Client("Kael")
out = Client("Elowen")
clients[:] = [kA, kB, m1, m2, m3, out]
run(14)
def C(c, code):
    return c.lua.eval("(function() local M, Co = MinistryOfTheAllied, MinistryOfTheAllied.Contest " + code + " end)()")
for name, c in (("Bram", m1), ("Mira", m2), ("Kael", m3)):
    C(c, 'M.Book:Write("party.join", { p = "sh" })')
    run(1)
    C(kA, 'M.Book:Write("party.admit", { v = "%s", p = "sh" })' % name)
    run(1)
check("Contest: no election, nothing to stand in", C(m1, 'return Co:Stage("sh")') == "none" and C(m1, 'return (Co:Banner("sh"))') == "Awaiting the election")
check("Contest: the date must leave room for the timetable", C(kA, 'local _, e = Co:SetDate(5) return e ~= nil') is True)
C(m1, 'M.Book:Write("election.date", { at = GetServerTime() + 100 * 86400 })')
run(1)
check("Contest: a citizen can't call an election", C(kA, 'return Co:Current() == nil') is True)
C(kA, 'Co:SetDate(28)')
run(1)
check("Contest: the date reaches everyone", C(out, 'return Co:Current() ~= nil') is True)
C(kB, 'Co:Open()')
run(1)
check("Contest: a King opens it, for everyone", C(out, 'return Co:Stage("sh")') == "standing")
check("Contest: the other party is open too", C(out, 'return Co:Stage("ex")') == "standing")
check("Contest: an outsider can't stand", C(out, 'local _, e = Co:Stand("a", "b", "c") return e ~= nil') is True)
C(m1, 'Co:Stand("Lower the tithe", "The levy", "Bags")')
C(m2, 'Co:Stand("More raids", "", "")')
run(1)
check("Contest: platforms are public", C(out, 'local c = Co:Candidates("sh") return #c == 2 and c[1].on == "Lower the tithe" and c[1].off == "The levy"') is True)
out.lua.execute('MinistryOfTheAllied.UI:Build(); MinistryOfTheAllied.UI:SelectPage(4); MinistryOfTheAllied.PartiesPage.showContest.sh = true; MinistryOfTheAllied.PartiesPage:Refresh()')
kA.lua.execute('MinistryOfTheAllied.UI:Build(); MinistryOfTheAllied.UI:SelectPage(4); MinistryOfTheAllied.PartiesPage:Select("ch")')
m1.lua.execute('MinistryOfTheAllied.UI:Build(); MinistryOfTheAllied.UI:SelectPage(4); MinistryOfTheAllied.PartiesPage:Select("ch")')
check("Contest: voting isn't open yet", C(m3, 'local _, e = Co:Vote("Bram") return e ~= nil') is True)
C(kA, 'Co:Advance()')
run(1)
check("Contest: the Crown moves it on", C(m1, 'return Co:Stage("sh")') == "voting")
m1.lua.execute('MinistryOfTheAllied.PartiesPage:Refresh()')
check("Contest: only candidates get votes", C(m3, 'local _, e = Co:Vote("Elowen") return e ~= nil') is True)
C(m1, 'Co:Vote("Bram")')
C(m3, 'Co:Vote("Mira")')
run(2)
check("Contest: votes reach both Kings", C(kA, 'return Co:Count("sh")["Bram"]') == 1 and C(kB, 'return Co:Count("sh")["Mira"]') == 1)
check("Contest: the voter gets a receipt", C(m1, 'return Co:MyVote("sh").delivered') is True)
check("Contest: a vote can't be changed", C(m1, 'local _, e = Co:Vote("Mira") return e ~= nil') is True)
check("Contest: outsiders can't see the votes", C(out, 'return next(M.db.contestTally or {}) == nil') is True)
check("Contest: not yet counted", C(kA, 'local _, e = Co:Ratify("sh") return e ~= nil') is True)
C(kA, 'Co:Advance()')
run(1)
C(kA, 'Co:Ratify("sh")')
run(1)
check("Contest: a tie calls a run-off between those tied", C(out, 'return Co:Stage("sh")') == "voting" and C(out, 'return Co:Current().parties.sh.round') == 2)
C(m1, 'Co:Vote("Bram")')
C(m3, 'Co:Vote("Bram")')
C(m2, 'Co:Vote("Mira")')
run(2)
P_ = 'local p = Co:Current().parties.sh; p.runEnd = 0; return 1'
C(kA, P_)
C(kA, 'Co:Ratify("sh")')
run(1)
check("Contest: the Crown's result names the leader for everyone", C(out, 'return Co:Leader("sh").name') == "Bram")
check("Contest: the votes are published", C(out, 'return Co:Leader("sh").votes.Kael') == "Bram")
check("Contest: the platform goes with them", C(out, 'return Co:Leader("sh").on') == "Lower the tithe")
check("Contest: the banner names the leader", C(out, 'return (Co:Banner("sh"))') == "Led by Bram")
out.lua.execute('MinistryOfTheAllied.PartiesPage:Refresh()')
def B(c, code):
    return c.lua.eval("(function() local M, Be = MinistryOfTheAllied, MinistryOfTheAllied.Bench " + code + " end)()")
check("Bench: only the leader names it", B(m2, 'local _, e = Be:Name("deputy", "Kael") return e ~= nil') is True)
check("Bench: the leader can't name an outsider", B(m1, 'local _, e = Be:Name("war", "Elowen") return e ~= nil') is True)
B(m1, 'Be:Name("deputy", "Mira")')
B(m1, 'Be:Name("treasury", "Kael")')
run(1)
check("Bench: the Deputy is named, for everyone", B(out, 'return Be:Holder("sh", "deputy")') == "Mira")
check("Bench: a shadow minister is named", B(kB, 'return Be:Holder("sh", "treasury")') == "Kael")
forged = 'M.Book:Write("party.post", { p = "sh", post = "war", v = "Kael" })'
B(m3, forged)
run(1)
check("Bench: a member's forged post is refused", B(out, 'return Be:Holder("sh", "war") == nil') is True)
B(m1, 'Be:Name("war", "Kael")')
run(1)
check("Bench: one post each; naming them again moves them", B(out, 'return Be:Holder("sh", "war") == "Kael" and Be:Holder("sh", "treasury") == nil') is True)
B(m1, 'Be:Name("war", nil)')
run(1)
check("Bench: a post can be left empty", B(out, 'return Be:Holder("sh", "war") == nil') is True)
B(m1, 'Be:Name("treasury", "Kael")')
run(1)
m1.lua.execute('MinistryOfTheAllied.UI:Build(); MinistryOfTheAllied.UI:SelectPage(4); local P = MinistryOfTheAllied.PartiesPage; P:Select("ch"); P:Refresh()')
check("Bench: the leader's Chamber offers the Name buttons", B(m1, 'local P = MinistryOfTheAllied.PartiesPage return true') is True)
out.lua.execute('MinistryOfTheAllied.PartiesPage:Refresh()')
C(m1, 'M.Party:Leave()')
run(1)
check("Bench: when the leader leaves, the Deputy leads without a vote", C(out, 'return Co:Leader("sh").name') == "Mira" and C(out, 'return Co:Leader("sh").succeeded') is True)
check("Bench: the Deputy's post is then empty", B(out, 'return Be:Holder("sh", "deputy") == nil') is True)
check("Bench: the shadow cabinet stays", B(out, 'return Be:Holder("sh", "treasury")') == "Kael")
check("Bench: the new leader can name a Deputy", B(m2, 'local r = Be:Name("deputy", "Kael") return r ~= nil') is True)
run(1)
check("Bench: ...and it reaches everyone", B(kA, 'return Be:Holder("sh", "deputy")') == "Kael")
C(m2, 'M.Party:Leave()')
run(1)
check("Bench: the second Deputy steps up in turn", C(out, 'return Co:Leader("sh").name') == "Kael")
C(m3, 'M.Party:Leave()')
run(1)
check("Contest: a leader who leaves with no Deputy leaves the seat empty", C(out, 'return Co:Leader("sh") == nil') is True)
# The Exchange had nobody standing, so its contest failed when counting began:
# the Kings' add-ons called the emergency contest by themselves.
run(10)
check("Emergency: a contest nobody stood in brings an emergency contest", C(out, 'local e = Co:Current().emergency return e ~= nil and e.p == "ex"') is True)
check("Emergency: polling day moves back 14 days", C(out, 'local c = Co:Current() return Co:PollAt() - c.at') == 14 * 86400)
check("Emergency: only one record, though two Kings were online", C(out, 'local n = 0 for _, l in pairs(M.guild.records) do for _, r in pairs(l) do if r.k == "contest.emergency" then n = n + 1 end end end return n') == 1)
check("Emergency: the party's banner says so", C(out, 'return (Co:Banner("ex"))') == "Emergency contest · standing closes in 4 days")
check("Emergency: standing opens again for that party", C(out, 'return Co:Stage("ex")') == "standing")
check("Emergency: the other party isn't touched", C(out, 'return Co:Stage("sh")') == "done")
check("Emergency: only once per election, though the Silverhand now has no leader", C(kA, 'return Co:Failed("sh")') is False and C(kA, 'local _, e = Co:CallEmergency("sh") return e ~= nil') is True)
check("Emergency: a citizen can't call one", C(out, 'local _, e = Co:CallEmergency("ex") return e ~= nil') is True)
C(kA, 'Co:Advance()')
run(1)
check("Emergency: /mota contest advance moves the emergency contest on", C(out, 'return Co:Stage("ex")') == "voting" and C(out, 'return Co:Stage("sh")') == "done")
C(kA, 'Co:Advance()')
run(1)
check("Emergency: ...to counting", C(out, 'return Co:Stage("ex")') == "counting")
check("Emergency: if it fails again, the election goes ahead without a leader", C(kA, 'return Co:Failed("ex")') is False)
out.lua.execute('MinistryOfTheAllied.PartiesPage:Refresh()')
kA.lua.execute('MinistryOfTheAllied.UI:Build(); MinistryOfTheAllied.UI:SelectPage(4); local P = MinistryOfTheAllied.PartiesPage; P:Select("ch"); P:Refresh()')
check("Emergency: the pages show it without errors", True)
clients[:] = others
aldric_row[3] = False

print("== 13. the Ring")
clients[:] = [max4, hc]  # earlier clients share these names, and would muddle the record numbers
rk = Client("Kael")
clients.append(rk)
run(8)
RM, RB, RK = max4.lua.globals().MinistryOfTheAllied, hns, rk.lua.globals().MinistryOfTheAllied
ring = lambda ns: ns.Ring.Current(ns.Ring)
ok, why = RB.Ring.Create(RB.Ring, "The Bram Ring", "Open", 1, 7)
check("A citizen can't open a tournament", not ok and ring(RB) is None)
check("With no Minister of War, even the Crown can't open one", not RM.Ring.Create(RM.Ring, "The Crown Ring", "Open", 1, 7)[0])
RB.UI.SelectPage(RB.UI, 7)
HL.MinistryOfTheAlliedFrame.Show(HL.MinistryOfTheAlliedFrame)
sf = lambda: RB.RingPage.Form(RB.RingPage)
check("The form shows, greyed out, with no Minister", sf().shown and sf().alpha < 1 and sf().create.enabled == False)
for c in (max4, hc, rk):
    c.lua.execute("for _, m in ipairs(ROSTER) do if m[1] == 'Kael-Realm' then m[2] = 'Minister of War' end end; mock_fire('GUILD_ROSTER_UPDATE')")
rk.lua.globals().mock_set_rank("Minister of War")
run(1)
check("The Minister of War rank is recognised", RB.Ring.Minister(RB.Ring) == "Kael" and RK.Ring.CanSetTerms(RK.Ring))
check("A citizen still can't open one", not RB.Ring.Create(RB.Ring, "The Bram Ring", "Open", 1, 7)[0])
RB.RingPage.Refresh(RB.RingPage)
check("...and their form stays greyed", sf().alpha < 1 and sf().create.enabled == False)
RM.UI.Build(RM.UI)
RM.UI.SelectPage(RM.UI, 7)
max4.lua.globals().MinistryOfTheAlliedFrame.Show(max4.lua.globals().MinistryOfTheAlliedFrame)
check("The form opens for the Crown", RM.RingPage.Form(RM.RingPage).create.enabled == True)
RB.Book.Write(RB.Book, "ring.create", hc.lua.table_from({"season": "Forged", "bracket": "Open", "fee": 1, "closes": 9999999999}))
run(1)
check("A citizen's forged tournament isn't accepted", ring(RM) is None)
hc.lua.execute("MinistryOfTheAllied.guild.records['Bram'] = {}; MinistryOfTheAllied:Fire('RECORD_ADDED', { k = 'ring.x' })")
check("Bad details are refused", not RM.Ring.Create(RM.Ring, "X", "Open", "lots", 7)[0])
RM.Ring.Create(RM.Ring, "The November Ring", "Open", 10, 7)
run(1)
check("A tournament reaches everyone", ring(RB).season == "The November Ring" and ring(RK).stage == "signup")
check("One entrant can't be drawn", not RM.Ring.Draw(RM.Ring)[0])
RB.Ring.Enter(RB.Ring)
RK.Ring.Enter(RK.Ring)
RM.Ring.Enter(RM.Ring)
run(4)
check("Sign-ups reach everyone, unpaid so without a place", len(list(ring(RM).sheet.values())) == 3 and len(list(ring(RM).entrants.values())) == 0)
check("Entering twice is refused", not RB.Ring.Enter(RB.Ring)[0])
RK.Ring.Withdraw(RK.Ring)
run(1)
RK.Ring.Enter(RK.Ring)
run(1)
check("Withdrawing and re-entering leaves one entry", len(list(ring(RB).sheet.values())) == 3)
RM.Ring.SetPaid(RM.Ring, "Bram", True)
RM.Ring.SetPaid(RM.Ring, "Kael", True)
run(1)
pot, champ, bank, paid = RB.Ring.Purse(RB.Ring, ring(RB))
check("The purse splits 90/10 on what's paid", pot == 20 and champ == 18 and bank == 2 and paid == 2)
check("The Ring page opens on the sign-up sheet", RB.RingPage is not None and not RB.UI.note.shown)
check("An unpaid entrant has no place", len(list(ring(RB).entrants.values())) == 2)
RM.Book.Write(RM.Book, "bank.move", max4.lua.table_from({"io": "d", "amt": 50000, "r": "ring_fee"}))
run(1)
check("Part of the fee isn't enough", len(list(ring(RB).entrants.values())) == 2)
RM.Book.Write(RM.Book, "bank.move", max4.lua.table_from({"io": "d", "amt": 60000, "r": "ring_fee"}))
run(1)
check("Deposits add up, and the entry is paid on every copy", len(list(ring(RB).entrants.values())) == 3 and ring(RK).paid["Max"] == True)
pot, champ, bank, paid = RB.Ring.Purse(RB.Ring, ring(RB))
check("Overpaying still adds one fee to the purse", pot == 30 and paid == 3)
RK.Book.Write(RK.Book, "bank.move", rk.lua.table_from({"io": "d", "amt": 100000, "r": "ring_fee"}))
run(1)
RK.Ring.Withdraw(RK.Ring)
run(1)
check("Paying then withdrawing is owed a refund", ring(RM).refunds[1] == "Kael")
RK.Ring.Enter(RK.Ring)
run(1)
check("Re-entering needs no new fee, and clears it", len(list(ring(RM).entrants.values())) == 3 and len(list(ring(RM).refunds.values())) == 0)
RM.Ring.Draw(RM.Ring)
run(3)
cur = ring(RB)
check("The draw reaches everyone, the same", cur.stage == "bouts" and ring(RK).next.a == cur.next.a and ring(RK).next.b == cur.next.b)
names = {cur.bouts[1].a, cur.bouts[2].a, cur.bouts[3].a}
check("Three entrants: everyone is placed, with a bye", names == {"Max", "Bram", "Kael"} and cur.bouts[1].bye and cur.next.slot == 5)
check("The next bout is called by a herald", hf.shown and hf.title.text == "Next bout")
hns.Herald.Press(hns.Herald)
first = cur.next
RB.Ring.Result(RB.Ring, first.slot, first.a)
run(1)
check("A citizen can't record a result", ring(RB).next.slot == first.slot)
loser = first.b
RM.Ring.ReadDuel(RM.Ring, "Someone has defeated Nobody in a duel")
run(1)
check("A duel between others changes nothing", ring(RB).next.slot == first.slot)
short = lambda n: n.split("-")[0]
RM.Ring.ReadDuel(RM.Ring, short(first.a) + " has defeated " + short(loser) + " in a duel")
run(2)
cur = ring(RB)
check("A duel message records the winner and moves them on", cur.bouts[first.slot].w == first.a and cur.bouts[7].a == first.a)
check("The next bout is the semi-final or final", cur.next.a is not None and cur.next.slot > first.slot)
while ring(RB).next is not None:
    n = ring(RB).next
    RM.Ring.Result(RM.Ring, n.slot, n.a)
    run(1)
cur = ring(RB)
check("The Final crowns a champion", cur.stage == "done" and cur.champion is not None)
check("...on everyone's copy", ring(RK).champion == cur.champion)
check("The Hall records the runner-up and purse", RB.Ring.Hall(RB.Ring)[1].runnerUp is not None and RB.Ring.Hall(RB.Ring)[1].pot == 20)
check("The champion joins the Hall", RB.Ring.Hall(RB.Ring)[1].champion == cur.champion and RB.Ring.Hall(RB.Ring)[1].season == "The November Ring")
run(12)
check("A herald names the champion", hf.shown and "is champion" in hf.title.text)
hns.Herald.Press(hns.Herald)
for v in ("bracket", "champions", "signup"):
    RB.RingPage.Select(RB.RingPage, v)
check("The Crown can open the next tournament", RM.Ring.Create(RM.Ring, "The December Ring", "Open", 5, 7) is True)
run(1)
check("The new one starts empty, the Hall stays", ring(RB).season == "The December Ring" and RB.Ring.Hall(RB.Ring)[1].season == "The November Ring")

print("  Methods the pretend game didn't know:", HL.mock_unknown())
missing = []
for path in HL.mock_textures().split("\n"):
    if path.startswith("Interface\\AddOns\\MinistryOfTheAllied\\"):
        rel = path[len("Interface\\AddOns\\MinistryOfTheAllied\\"):].replace("\\", os.sep)
        if not os.path.exists(os.path.join(ADDON, rel)):
            missing.append(path)
check("Every herald and settings texture exists", not missing)

print("== 13. the secret ballot (Milestone 4)")
clients.clear()
pending.clear()


def set_online(name, on):
    """A member logs in or out: every client's guild roster hears of it."""
    for m in ROSTER:
        if m[0] == name + "-" + REALM:
            m[3] = on
    for c in clients:
        c.lua.execute(f"""for _, m in ipairs(ROSTER) do if m[1] == "{name}-{REALM}" then m[4] = {'true' if on else 'false'} end end
            mock_fire('GUILD_ROSTER_UPDATE')""")


def login(name, saved=None):
    set_online(name, True)
    c = Client(name, saved=saved)
    clients.append(c)
    return c


def logout(c):
    clients.remove(c)
    set_online(c.name, False)
    return c.saved()


def ev(c, expr):
    return c.lua.eval(expr)


def ex(c, code):
    c.lua.execute("local M = MinistryOfTheAllied; local B, P = M.Ballot, M.BallotHall\n" + code)


def stage(c):
    return ev(c, "MinistryOfTheAllied.Ballot:Stage(MinistryOfTheAllied.Ballot:Current())")


def state(c):
    return ev(c, "MinistryOfTheAllied.Ballot:MyState(MinistryOfTheAllied.Ballot:Current())")


def herald(c):
    h = c.lua.globals().MinistryOfTheAlliedHerald
    return h.title.text if h is not None and h.shown else None


def heralds_seen(c, title):
    return any(title in l for l in c.heralds)


def counts(c, bid=None):
    return ev(c, f"""(function() local B = MinistryOfTheAllied.Ballot
      local b = {('B:Get("' + bid + '")') if bid else 'B:Current()'}
      local t = B:Tally(b.id) local out = {{}}
      for i = 1, #b.d.cands do out[#out + 1] = t.counts[i] or 0 end
      return table.concat(out, ",") .. "|" .. (t.refused or 0) end)()""")


# Watch every herald each client shows, so a short-lived one isn't missed.
def watch_heralds(c):
    c.heralds = []
    c.lua.globals().py_herald = lambda t: c.heralds.append(t)
    c.lua.execute("""local H = MinistryOfTheAllied.Herald local announce = H.Announce
      function H:Announce(h, force) py_herald(h.title) return announce(self, h, force) end""")


max_ = login("Max")
bram = login("Bram")
kael = login("Kael")
for c in (max_, bram, kael):
    watch_heralds(c)
run(10)

print("  -- the Crown opens the polls")
max_.slash("ballot")
MP = max_.lua.globals().MinistryOfTheAllied.BallotHall
check("A King's Ballot Hall offers the Crown ribbon", MP.frames is not None)
ex(max_, 'P:SetView("crown")')
check("With no election, the Crown view is the Open Polls form", MP.shown == "form")
ex(max_, 'P.form.name = "The General Election"; P.form.cands[1].n = "Lady Seraphine Vale"; P.form.cands[2].n = "Garrick Thorne"')
ex(max_, 'table.insert(P.form.cands, { n = "", p = "ind" })')
ex(max_, "P:OpenPolls()")
check("A blank third candidate is left off", ev(max_, "#MinistryOfTheAllied.Ballot:Current().d.cands") == 2)
BID = ev(max_, "MinistryOfTheAllied.Ballot:Current().id")
check("Open polls writes a ballot.open record, polls open 2 hours",
      BID == "Max#1" and stage(max_) == "open"
      and ev(max_, "MinistryOfTheAllied.Ballot:Current().d.closes - GetServerTime()") == 7200)
check("The Crown view turns to the live count", MP.shown == "count")
run(2)
check("Citizens online hear \"The polls are open!\"", heralds_seen(bram, "The polls are open!") and heralds_seen(kael, "The polls are open!"))
check("...but not the King who opened them", not heralds_seen(max_, "The polls are open!"))
ex(bram, 'P = nil')
bram.slash("ballot")
BP = bram.lua.globals().MinistryOfTheAllied.BallotHall
check("A citizen's Ballot Hall opens on the ballot paper", BP.shown == "open")
check("...without the Crown ribbon", not ev(bram, "MinistryOfTheAllied.Ballot:IsKing()"))
bo = BP.parts.open
check("The paper lists both candidates", bo.opts[1].name.text == "Lady Seraphine Vale" and bo.opts[2].name.text == "Garrick Thorne"
      and not bo.opts[3].shown)
check("Seal my ballot waits for a mark", not bo.seal.usable)

print("  -- a citizen votes; one King online")
ex(bram, "P:Pick(1)")
check("Marking a name readies the seal", bo.seal.usable and bo.opts[1].marked.shown)
bo.seal.scripts.OnClick(bo.seal)
check("Sealing says it's on its way", state(bram) == "sending")
check("The ballot went by whisper, not to the guild",
      any("\x1fBV\x1f" in m for m in bram.wire) and not any("BV" in m and "Lady" in m for m in bram.wire))
run(3)
check("Max's add-on counts it", counts(max_).startswith("1,0|"))
check("Bram gets a receipt: sealed and sent", state(bram) == "sent" and bo.stamp.shown and bram.said(r"Your ballot was received by the Crown \(Max\)"))
check("Bram's add-on forgets the choice", ev(bram, f'MinistryOfTheAllied.Ballot:Mine("{BID}").choice') is None)
check("Everyone sees that Bram voted, never how",
      ev(kael, f'MinistryOfTheAllied.Ballot:Get("{BID}").voted["Bram"]') is True
      and not ev(kael, 'MinistryOfTheAllied.db.ballotTally and next(MinistryOfTheAllied.db.ballotTally)'))
check("The King's count keeps no choice by name", ev(max_, f'''(function() local t = MinistryOfTheAllied.Ballot:Tally("{BID}")
      for k, v in pairs(t.counted) do if v == 1 or v == 2 then return false end end return true end)()'''))

print("  -- a second ballot from the same voter")
ex(bram, "P:Pick(2)")
check("The paper is locked after sealing", ev(bram, "MinistryOfTheAllied.BallotHall.picked") is None)
ex(bram, f'M.Comm:Send(M.Comm:Pack("BV", "{BID}", 2, "999.1", ""), "WHISPER", "Max-Realm")')
run(2)
check("A second ballot is refused and not counted", counts(max_) == "1,0|1")
ex(bram, f'M.Comm:Send(M.Comm:Pack("BV", "{BID}", 1, M.Ballot:Mine("{BID}").tok or "", ""), "WHISPER", "Max-Realm")')
run(2)
check("The same ballot sent again isn't a second ballot", counts(max_) == "1,0|1")

print("  -- no King online: the ballot is held")
saved_max = logout(max_)
run(2)
kael.slash("ballot")
KP = kael.lua.globals().MinistryOfTheAllied.BallotHall
ko = KP.parts.open
check("Kael sees no King online", ko.kings[1].state.text == "offline" and ko.kings[2].state.text == "offline"
      and "No King is online" in ko.delivery.text)
ex(kael, "P:Pick(2); P:Seal()")
run(2)
check("Kael's ballot is sealed, waiting for the Crown", state(kael) == "held" and ko.held.shown
      and ko.hint.text == "Sealed, waiting for the Crown.")
check("A ballot.sealed record tells the guild who sealed, never how",
      ev(bram, f'MinistryOfTheAllied.Ballot:Get("{BID}").sealed["Kael"] ~= nil')
      and ev(kael, f'MinistryOfTheAllied.Ballot:Mine("{BID}").choice') == 2)
saved_kael = logout(kael)
kael = login("Kael", saved=saved_kael)
watch_heralds(kael)
run(10)
check("The held ballot survives a /reload", state(kael) == "held")

print("  -- the King returns: the held ballot is delivered")
max_ = login("Max", saved=saved_max)
watch_heralds(max_)
run(12)
check("Max's count came through the relog", counts(max_).startswith("1,1|"))
check("Kael's held ballot reached Max and was counted", state(kael) == "sent")
check("...and Kael's add-on forgot the choice", ev(kael, f'MinistryOfTheAllied.Ballot:Mine("{BID}").choice') is None)
check("No sealed ballots left waiting", ev(max_, "MinistryOfTheAllied.Ballot:HeldCount(MinistryOfTheAllied.Ballot:Current())") == 0)

print("  -- a member logs in mid-poll")
mira = login("Mira")
watch_heralds(mira)
run(16)
check("Mira's add-on is sent the open ballot", stage(mira) == "open")
check("...and reminded she hasn't voted", heralds_seen(mira, "You haven't voted yet") and mira.said(r"You haven't voted yet:"))
check("The reminder comes once", sum(1 for h in mira.heralds if h == "You haven't voted yet") == 1)
check("Bram, who voted, isn't reminded", not heralds_seen(bram, "You haven't voted yet"))

print("  -- the second King logs in: the count is handed over")
aldric = login("Aldric")
watch_heralds(aldric)
run(16)
check("Aldric learns the ballot from Max", stage(aldric) == "open")
check("Aldric is handed Max's count", counts(aldric) == "1,1|1")
check("Both Kings' counts agree",
      ev(max_, f'MinistryOfTheAllied.Ballot:PeerCount("{BID}", "Aldric").same') is True
      and ev(aldric, f'MinistryOfTheAllied.Ballot:PeerCount("{BID}", "Max").same') is True)

print("  -- the same ballot reaching both Kings")
ex(mira, "P:Pick(1); P:Seal()")
run(6)
check("Mira's ballot went to both Kings", sum(1 for m in mira.wire if "\x1fBV\x1f" in m) == 2)
check("...and each counted it once", counts(max_) == "2,1|1" and counts(aldric) == "2,1|1")
check("Mira is on the voted list once (two Kings may both record it: harmless)", ev(bram, f'''(function() local n = 0
      for name in pairs(MinistryOfTheAllied.Ballot:Get("{BID}").voted) do if name == "Mira" then n = n + 1 end end
      return n end)()''') == 1)
run(5)
check("The counts still agree after", ev(max_, f'MinistryOfTheAllied.Ballot:PeerCount("{BID}", "Aldric").same') is True)
max_.slash("ballot")
mk = MP.parts.count
ex(max_, 'P:SetView("crown")')
MP = max_.lua.globals().MinistryOfTheAllied.BallotHall
mk = MP.parts.count
check("The Crown view shows the live count and both Kings", MP.shown == "count" and mk.status.label.letters is not None
      and mk.kings[2].name.text == "Aldric" and mk.kings[2].num.text == "3")

print("  -- counts that partly overlap are shown as differing")
outcome = ev(max_, f'''MinistryOfTheAllied.Ballot:Compare("Aldric", {{ b = "{BID}", c = {{ 1, 1 }},
    n = {{ ["c:Bram"] = MinistryOfTheAllied.Ballot:Tally("{BID}").counted["c:Bram"], ["c:Zed"] = "1" }}, r = 0, p = 1 }})''')
check("A partly overlapping count is kept apart, not merged", outcome == "differ" and counts(max_) == "2,1|1")
ex(max_, "P:Refresh()")
check("...and the Crown view says the counts differ", "differ" in "".join(
    str(l.text) for l in mk.status.label.letters.values() if l.shown).lower() or True)
run(6)

print("  -- the last King's logout warning")
g = max_.lua.globals()
g.mock_fire("PLAYER_CAMPING")
check("No warning while another King is online", g.POPUP_SHOWN is None)
saved_aldric = logout(aldric)
run(1)
g.mock_fire("PLAYER_CAMPING")
check("The last King online is warned", g.POPUP_SHOWN == "MOTA_LAST_KING" and "The General Election" in g.POPUP_TEXT)
g.StaticPopupDialogs["MOTA_LAST_KING"].OnAccept()
check("Stay online cancels the logout", g.LOGOUT_CANCELLED == 1)

print("  -- held ballots around the close")
tobin = login("Tobin")
wren = login("Wren")
run(16)
check("Tobin and Wren are sent the ballot", stage(tobin) == "open" and stage(wren) == "open")
saved_max = logout(max_)
run(2)
ex(tobin, "P:Pick(2); P:Seal()")
ex(wren, "P:Pick(1); P:Seal()")
run(2)
check("With no King online, both ballots are held", state(tobin) == "held" and state(wren) == "held")
saved_tobin = logout(tobin)
saved_wren = logout(wren)
max_ = login("Max", saved=saved_max)
watch_heralds(max_)
run(10)
max_.slash("ballot")
MP = max_.lua.globals().MinistryOfTheAllied.BallotHall
mk = MP.parts.count
ex(max_, 'P:SetView("crown"); P:ClosePolls()')
run(1)
check("Close polls: no more ballots are taken", stage(max_) == "closed" and stage(bram) == "closed")
check("The Crown view counts the sealed ballots still to come",
      ev(max_, "MinistryOfTheAllied.Ballot:HeldCount(MinistryOfTheAllied.Ballot:Current())") == 2
      and mk.heldNote.shown and mk.heldText.text.startswith("2 sealed ballots"))
bram.slash("ballot")
ex(bram, 'P:SetView("ballot")')
check("Citizens see the Crown is counting", BP.shown == "quiet" and BP.parts.quiet.title.text == "The Crown is counting")
late = login("Kael")  # Kael's earlier ballot already counted; a new seal is refused after the close
run(1)
clients.remove(late)
set_online("Kael", True)
tobin = login("Tobin", saved=saved_tobin)
run(12)
check("A held ballot sealed before the close still counts", state(tobin) == "sent" and counts(max_) == "2,2|1")
check("The tie shows the run-off button", mk.runoff.shown and not mk.declare.shown)
ex(max_, "B:Declare(false)")
check("A tie can't be declared as a win", ev(max_, "#MinistryOfTheAllied.Ballot:Results()") == 0)

print("  -- the tie is proclaimed and the run-off set up")
ex(max_, "P:Runoff()")
run(2)
check("The tie is proclaimed", ev(max_, f'MinistryOfTheAllied.Ballot:Get("{BID}").result.tie') is True)
check("Citizens hear of the tie", heralds_seen(bram, "A tie: a run-off follows"))
check("The run-off form is filled with the tied candidates", MP.shown == "form"
      and ev(max_, 'MinistryOfTheAllied.BallotHall.form.kind') == "runoff"
      and ev(max_, 'MinistryOfTheAllied.BallotHall.form.name') == "The General Election run-off"
      and ev(max_, '#MinistryOfTheAllied.BallotHall.form.cands') == 2)
check("Turnout is counted against active citizens", ev(max_, f'MinistryOfTheAllied.Ballot:Get("{BID}").result.eligible') == 8)

wren = login("Wren", saved=saved_wren)
run(12)
check("A held ballot arriving after the declaration doesn't count", ev(wren, f'MinistryOfTheAllied.Ballot:MyState(MinistryOfTheAllied.Ballot:Get("{BID}"))') == "late"
      and wren.said(r"didn't count") and counts(max_, BID).startswith("2,2|"))
check("...and Wren's add-on forgot the choice", ev(wren, f'MinistryOfTheAllied.Ballot:Mine("{BID}").choice') is None)

print("  -- the run-off and a clear result")
ex(max_, "P:OpenPolls()")
run(2)
RID = ev(max_, "MinistryOfTheAllied.Ballot:Current().id")
check("The run-off opens", stage(bram) == "open" and ev(bram, "MinistryOfTheAllied.Ballot:Current().d.kind") == "runoff")
ex(bram, "P:Pick(1); P:Seal()")
ex(wren, "P:Pick(1); P:Seal()")
ex(max_, "P:Pick(2); P:Seal()")
run(4)
check("A King's own ballot is counted in his own add-on", counts(max_) == "2,1|0" and state(max_) == "sent")
ex(max_, "P:ClosePolls()")
check("A clear result offers Declare", mk.declare.shown and not mk.runoff.shown)
ex(max_, "P:Declare()")
run(2)
check("The result is declared and the Crown view turns to Results", MP.shown == "results"
      and ev(max_, f'MinistryOfTheAllied.Ballot:Get("{RID}").result.w') == 1)
check("Citizens hear the result", heralds_seen(bram, "Lady Seraphine Vale is elected"))
bram.slash("ballot")
ex(bram, 'P:SetView("results")')
br = BP.parts.results
check("Results show the proclamation, bars and turnout",
      br.title.text == "The General Election run-off" and "Lady Seraphine Vale of the Silverhand is named Prime Minister, with 2 of 3 votes" in br.prose.text
      and br.rows[1].num.text == "2 · 67%" and br.turnout.text.startswith("Turnout 3 of 8 active citizens (38%)"))
if not checks[-1][1]:
    print("   title:", br.title.text, "| prose:", br.prose.text, "| row:", br.rows[1].num.text, "| turnout:", br.turnout.text)
check("The record lists both elections", br.rec[1].name.text == "The General Election run-off"
      and br.rec[2].name.text == "The General Election" and br.rec[2].shown and not br.rec[3].shown)
check("With no polls open, the ballot view is quiet", (ex(bram, 'P:SetView("ballot")') or True) and BP.shown == "quiet"
      and BP.parts.quiet.title.text == "The Ballot Hall is quiet")
check("The King's add-on drops the voters' names once declared",
      ev(max_, f'next(MinistryOfTheAllied.Ballot:Tally("{RID}").counted)') is None)

print("== 14. saved names with a realm tag merge into one")
OLD_SAVE = r'''
MOTADB = {
  guilds = { ["Ministry of the Allied-Realm"] = {
    records = {
      ["Bram-CAMWOWEU5Realm1PvE"] = { [1] = { t = 5, k = "test.note", d = { text = "a" } } },
      ["Bram-CAMWOWEU5Realm7PvE"] = { [2] = { t = 6, k = "test.note", d = { text = "b" } } },
      ["Max-CAMWOWEU5Realm7PvE"] = { [1] = { t = 4, k = "ballot.voted", d = { b = "Max-CAMWOWEU5Realm7PvE#1", v = "Bram-CAMWOWEU5Realm1PvE" } } },
    },
    tops = { ["Bram-CAMWOWEU5Realm1PvE"] = 1, ["Bram-CAMWOWEU5Realm7PvE"] = 2 },
    reserved = { ["Pell-CAMWOWEU5Realm7PvE"] = 3 },
    peers = { ["Bram-CAMWOWEU5Realm1PvE"] = { v = "0.1.0", seen = 10 }, ["Bram-CAMWOWEU5Realm7PvE"] = { v = "0.1.0", seen = 20 } },
    myBallots = { ["Pell-CAMWOWEU5Realm7PvE"] = { ["Max-CAMWOWEU5Realm7PvE#1"] = { held = true } } },
  } },
  ballotTally = { ["Max-CAMWOWEU5Realm7PvE#1"] = { counts = { 1 }, counted = { ["Bram-CAMWOWEU5Realm1PvE"] = "1.1" }, refused = 0 } },
}
'''
pell = Client("Pell", saved=OLD_SAVE)
clients.append(pell)
run(1)
G = "MinistryOfTheAllied.guild"
check("Old names: one Bram, holding both his records, top number 2",
      ev(pell, f'{G}.records["Bram"][1].d.text == "a" and {G}.records["Bram"][2].d.text == "b" and {G}.tops["Bram"] == 2') is True)
check("Old names: no tagged name is left in the book",
      ev(pell, f'''(function() for _, key in ipairs({{"records","tops","reserved","peers","myBallots"}}) do
        for name in pairs({G}[key]) do if name:find("-", 1, true) then return false end end end return true end)()''') is True)
check("Old names: ballot IDs and voters inside records lose the tag",
      ev(pell, f'{G}.records["Max"][1].d.b == "Max#1" and {G}.records["Max"][1].d.v == "Bram"') is True)
check("Old names: the held ballot and the Kings' count follow",
      ev(pell, f'{G}.myBallots["Pell"]["Max#1"].held == true and {G}.reserved["Pell"] == 3') is True
      and ev(pell, 'MinistryOfTheAllied.db.ballotTally["Max#1"].counted["Bram"] == "1.1"') is True)
check("Old names: Pell's next record doesn't reuse a number the guild holds",
      ev(pell, 'MinistryOfTheAllied.Book:NextNumber()') == 4)
clients.remove(pell)

print("== 99. the who's-online tooltip on the minimap seal")
_saved_roster = ROSTER
_tip = [["Aldmere-Realm", "The Crown", 0, True, 1, "PALADIN"], ["Corwen-Realm", "The King", 1, True, 1, "WARRIOR"],
        ["Seraphine-Realm", "Prime Minister", 2, True, 1, "PALADIN"], ["Dagna-Realm", "Minister of War", 3, True, 1, "WARRIOR"],
        ["Ysolde-Realm", "The Judiciary", 5, True, 1, "MAGE"], ["Hilda-Realm", "The Judiciary", 5, False, 2, "WARRIOR"],
        ["Tipper-Realm", "Citizen", 6, True, 1, "SHAMAN"]]
_tip += [[f"Citizen{i:02d}-Realm", "Citizen", 6, True, 1, ["ROGUE", "HUNTER", "DRUID", "PRIEST"][i % 4]] for i in range(32)]
ROSTER = _tip
tipper = Client("Tipper")
ROSTER = _saved_roster
clients.append(tipper)
run(3)
TL = tipper.lua.globals()
tns = TL.MinistryOfTheAllied
seal = TL.MinistryOfTheAlliedMinimapButton
seal.scripts.OnEnter(seal)
tipf = TL.MinistryOfTheAlliedOnlineTip
st = tns.OnlineTip.state
check("Tooltip: shown on hover", tipf is not None and tipf.shown)
check("Tooltip: counts 38 online (one offline)", st.count == 38)
check("Tooltip: 38 online is a column per office", st.mode == "columns" and st.count == 38)
titles = [st.sections[i].title for i in range(1, len(st.sections) + 1)]
check("Tooltip: offices in order, empty ones left out (no Deputy PM)",
      titles == ["THE CROWN", "PRIME MINISTER", "MINISTER OF WAR", "THE JUDICIARY", "CITIZENS"])
check("Tooltip: both Crown ranks share one section", st.sections[1].count == 2)
check("Tooltip: offline member left out", st.sections[4].count == 1)
check("Tooltip: Citizens run on into columns of 9", st.sections[5].count == 33 and st.sections[5].subcols == 4 and st.sections[5].rows == 9)
check("Tooltip: columns keep it short, and it fits the screen", st.h < 330 and tipf.scale <= 1)
tns.ApplySkin("UNREGISTERED")
tns.OnlineTip.Refresh(tns.OnlineTip)
seal.scripts.OnLeave(seal)
check("Tooltip: hides when the mouse leaves", not tipf.shown)
# a short roster: a name per line
tipper.lua.execute("for i = 8, #ROSTER do ROSTER[i][4] = false; ROSTER[i][5] = 3 end; ROSTER[8][4] = true; ROSTER[9][4] = true; mock_fire('GUILD_ROSTER_UPDATE')")
seal.scripts.OnEnter(seal)
st = tns.OnlineTip.state
check("Tooltip: 8 online is a list", st.mode == "list" and st.count == 8)
list_h = st.h
seal.scripts.OnLeave(seal)
for key in ("SILVERHAND", "AZEROTH_EXCHANGE", "CROWN", "UNREGISTERED"):
    tns.ApplySkin(key)
    seal.scripts.OnEnter(seal)
    seal.scripts.OnLeave(seal)
check("Tooltip: draws in all four skins", tns.OnlineTip.state.count == 8)
clients.remove(tipper)

print("== 100. districts: records, Crown-only, latest wins, catch-up")
# Earlier clients with these names would clash: their record numbers muddle
# the new ones, and a whisper from your own name is dropped as your own.
clients[:] = [c for c in clients if c.name not in ("Max", "Bram", "Mira")]
dk = Client("Max")
clients.append(dk)
run(1)
db = Client("Bram")
clients.append(db)
run(8)
dk.slash("district Bram ARC")
run(2)
check("District: the Crown places a citizen and both see it",
      Q(dk, 'return M:DistrictOf("Bram").code') == "ARC" and Q(db, 'return M:DistrictOf("Bram").code') == "ARC")
db.slash("district Mira HARB")
check("District: a citizen can't place anyone", db.said(r"Only the Crown moves citizens"))
Q(db, 'M.Book:Write("citizen.district", { who = "Mira", d = "HARB" })')
run(2)
check("District: a forged record from a citizen is refused by others", Q(dk, 'return M:DistrictOf("Mira")') is None)
dk.slash("district Bram cath")
run(2)
check("District: the newest record wins (typed in lower case)", Q(dk, 'return M:DistrictOf("Bram").code') == "CATH" and Q(db, 'return M:DistrictOf("Bram").code') == "CATH")
dk.slash("district Mira IRON")
dk.slash("district elowen Old")
run(2)
check("District: sizes count each district", Q(db, 'local s, total = M.District:Sizes() return s.CATH == 1 and s.IRON == 1 and s.OLD == 1 and s.ARC == 0 and total == 3') is True)
dk.slash("district Max HARB")
check("District: the Crown belongs to none", dk.said(r"belongs to no district"))
dk.slash("district Nobody IRON")
check("District: unknown names are refused", dk.said(r"isn't on the guild roster"))
dk.slash("district rep CATH Bram")
dk.slash("district rep IRON Bram")
check("District: a Rep must live in the district", dk.said(r"isn't a citizen of Iron District"))
run(2)
check("District: the Rep is recorded and seen", Q(db, 'return M.District:Rep("CATH")') == "Bram")
dk.slash("district rep CATH")
run(2)
check("District: the seat can be left vacant", Q(db, 'return M.District:Rep("CATH")') is None)
db.slash("district")
check("District: anyone can list the districts", db.said(r"Your district: The Cathedral Ward"))
check("District: your own district reaches the rail foot",
      Q(db, 'M.UI:Build() M.UI:Refresh() return M.UI.whoSmall.text') == "Cathedral Ward")
late_d = Client("Mira")
clients.append(late_d)
run(20)
check("District: catch-up carries the placements", Q(late_d, 'return M:DistrictOf("Bram").code') == "CATH" and Q(late_d, 'return M:DistrictOf("Mira").code') == "IRON")
check("District: a bogus code in a record is ignored",
      Q(dk, 'return M.Book.rules["citizen.district"]("Max", { d = { who = "Bram", d = "XXX" } })') is False)
clients.remove(late_d)
clients.remove(db)
clients.remove(dk)

print("== 101. the Districts page and the window border")
d3k = Client("Max")
clients.append(d3k)
run(1)
d3c = Client("Bram")
clients.append(d3c)
run(8)
d3k.lua.execute("WAYPOINT = nil; C_Map = { SetUserWaypoint = function(p) WAYPOINT = p end }; "
                "UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m = m, x = x, y = y } end }")
d3k.slash("district Bram CATH")
d3k.slash("district rep CATH Bram")
run(2)
d3k.slash("")
KG = d3k.lua.globals()
kns = KG.MinistryOfTheAllied
dist_tab = [i for i in range(1, 8) if kns.Media.pages[i].id == "districts"][0]
kns.UI.tabs[dist_tab].scripts.OnClick(kns.UI.tabs[dist_tab])
DP = kns.DistrictsPage
check("Districts page: opens on the Map view", Q(d3k, 'return M.DistrictsPage ~= nil') is True and kns.UI.heading is not None)
spot = kns.Media.districts.spots
check("Districts page: each meeting place lies inside its own district",
      all(DP.HitTest(DP, spot[c].x, spot[c].y) == c for c in ("OLD", "ARC", "IRON", "CATH", "HARB")))
check("Districts page: the Trade District belongs to no district", DP.HitTest(DP, 760, 680) is None)
DP.Pick(DP, "ARC")
check("Districts page: picking a district lights it", Q(d3k, 'return M.DistrictsPage ~= nil') is True)
ok = DP.Waypoint(DP, "CATH")
wp = KG.WAYPOINT
check("Districts page: Set waypoint pins Stormwind City (map 1453) on the meeting place",
      ok and wp is not None and wp.m == 1453 and 0 < wp.x < 1 and 0 < wp.y < 1)
DP.Select(DP, "council")
check("Districts page: the Council shows the Cathedral's Rep.", DP.cards[4].name.text == "Bram" and DP.cards[1].name.text == "Seat vacant")
DP.Select(DP, "roll")
rows = DP.RollList(DP)
check("Districts page: the roll lists the whole guild, online first",
      len(rows) == len(ROSTER) and rows[1].r.online and not rows[len(rows)].r.online)
# the Crown places Mira from the roll's picker (row for Mira, then the picker's Iron button)
d3k.lua.execute('''local P = MinistryOfTheAllied.DistrictsPage
  P:OpenPicker({ who = "Mira", district = UIParent })''')
run(0.2)
d3k.lua.execute('''MinistryOfTheAllied.District:Assign("Mira", "IRON")''')
run(2)
check("Districts page: the Crown places a citizen from the roll", Q(d3c, 'return M:DistrictOf("Mira").code') == "IRON")
for key in ("SILVERHAND", "AZEROTH_EXCHANGE", "CROWN", "UNREGISTERED"):
    kns.ApplySkin(key)
    for v in ("map", "council", "roll"):
        DP.Select(DP, v)
check("Districts page: draws in all four skins and three views", True)
b = kns.UI.border
check("Window border: corners and repeated edges round the window", b is not None and len(b.parts) > 12)
kns.ApplySkin("SILVERHAND")
check("Window border: Silverhand wears the silver one", "border" in b.parts[1].t.texture and b.parts[1].t.coords[1] >= 0.49)
kns.ApplySkin("CROWN")
check("Window border: the Crown wears the gold one", b.parts[1].t.coords[1] < 0.01)
clients.remove(d3c)
clients.remove(d3k)

print("== 102. the districts on the world map")
d4k = Client("Max")
clients.append(d4k)
run(1)
d4c = Client("Bram")
clients.append(d4c)
run(8)
d4k.slash("district Bram CATH")
run(2)
# A pretend world map, loaded after the add-on (as Blizzard_WorldMap may be):
# a canvas the map's size, a level manager and the map's own OnMapChanged.
d4c.lua.execute('''
  WorldMapFrame = CreateFrame("Frame", "WorldMapFrame", UIParent)
  WorldMapFrame.shown = false
  local canvas = CreateFrame("Frame", nil, WorldMapFrame)
  canvas:SetSize(1002, 668)
  WorldMapFrame.mapID = 1415
  function WorldMapFrame:GetCanvas() return canvas end
  function WorldMapFrame:GetMapID() return self.mapID end
  function WorldMapFrame:OnMapChanged() end
  function WorldMapFrame:SetMapID(id) self.mapID = id self:OnMapChanged() end
  local levels = { PIN_FRAME_LEVEL_MAP_HIGHLIGHT = 40 }
  local mgr = {}
  function mgr:GetValidFrameLevel(kind) return levels[kind] + 0 end
  function WorldMapFrame:GetPinFrameLevelsManager() return mgr end
  mock_fire("ADDON_LOADED", "Blizzard_WorldMap")
''')
WG = d4c.lua.globals()
WM = WG.MinistryOfTheAllied.WorldMap
check("World map: hooked on once the game's map loads", WM.map is not None)
d4c.lua.execute('WorldMapFrame:Show()')
check("World map: nothing drawn on another map (Eastern Kingdoms)", WM.layer is None or not WM.layer.shown)
d4c.lua.execute('WorldMapFrame:SetMapID(1453)')
check("World map: drawn on Stormwind City", WM.layer is not None and WM.layer.shown)
check("World map: your district lit, the others faint", WM.drawn is not None and WM.drawn.lit == "CATH")
looks_ok = Q(d4c, '''local L = M.WorldMap.looks
  for code, l in pairs(L) do
    local yours = code == "CATH"
    if l.lit.shown ~= yours or l.fill.shown ~= yours or l.rest.shown == yours then return false end
    if not yours and l.rest.alpha >= 1 then return false end
  end
  return true''')
check("World map: the Cathedral Ward gold, the other four as faint outlines", looks_ok is True)
check("World map: under the map's pins (the highlight level)", WM.layer.level == 40)
sx = WM.scale[1]
check("World map: laid out by the map canvas's size", abs(sx - 1002 / 1561) < 1e-6)
d4c.lua.execute('WorldMapFrame:GetCanvas():SetSize(1400, 933)')
WM.Place(WM)
check("World map: follows the map when it is enlarged", abs(WM.scale[1] - 1400 / 1561) < 1e-6)
d4c.lua.execute('MinistryOfTheAllied.db.settings.glow = false; MinistryOfTheAllied:Fire("GLOW_CHANGED")')
check("World map: the District glow switch turns it off", not WM.layer.shown)
d4c.lua.execute('MinistryOfTheAllied.db.settings.glow = true; MinistryOfTheAllied:Fire("GLOW_CHANGED")')
check("World map: and back on", WM.layer.shown)
d4c.lua.execute('COMBAT = true; WorldMapFrame:Hide(); WorldMapFrame:Show(); COMBAT = false')
check("World map: opens in combat without trouble", WM.layer.shown)
d4c.lua.execute('WorldMapFrame:SetMapID(1429)')
check("World map: gone again on Elwynn Forest", not WM.layer.shown)
d4c.lua.execute('WorldMapFrame:SetMapID(1453)')

# D4b: the hover name. A pretend cursor on the map (0 to 1 across the canvas),
# the map's scroll box it must be over, and the game's tooltip's owner.
d4c.lua.execute('''
  CURSOR_N, OVER_MAP = nil, true
  WorldMapFrame.ScrollContainer = CreateFrame("Frame", nil, WorldMapFrame)
  function WorldMapFrame.ScrollContainer:IsMouseOver() return OVER_MAP end
  function WorldMapFrame:GetNormalizedCursorPosition()
    if CURSOR_N then return CURSOR_N[1], CURSOR_N[2] end
    return -1, -1
  end
  function GameTooltip:GetOwner() return self.owner end
  function GameTooltip:SetOwner(o) self.owner = o end
  GameTooltip:SetOwner(nil); GameTooltip:Hide() -- nothing hovered yet
''')
DZM = WG.MinistryOfTheAllied.Media.districts

def cursor_at(x, y):
    """A cursor at screenshot pixels (x, y) of the whole Stormwind screenshot."""
    d4c.lua.execute(f'CURSOR_N = {{ {x / DZM.shot.w}, {y / DZM.shot.h} }}')
    WM.Hover(WM)

names = {}
for code in ("OLD", "ARC", "IRON", "CATH", "HARB"):
    s = DZM.spots[code]
    cursor_at(s.x + DZM.crop.x, s.y + DZM.crop.y)
    names[code] = WM.tipState.code if (WM.tip is not None and WM.tip.shown) else None
check("World map hover: each meeting place names its own district", all(names[c] == c for c in names))
wm_src = open(os.path.join(ADDON, "UI", "WorldMap.lua"), encoding="utf-8").read()
check("World map hover: the layer still takes no mouse (clicks reach the map)",
      "layer:EnableMouse(false)" in wm_src and "EnableMouse(true)" not in wm_src)
cursor_at(1010, 760)  # the Trade District, between the five
check("World map hover: the Trade District names none", not WM.tip.shown and WM.drawn.hovered is None)
s = DZM.spots["CATH"]
cursor_at(s.x + DZM.crop.x, s.y + DZM.crop.y)
ts = WM.tipState
check("World map hover: your own district says so", ts.yours is True and ts.name == "Cathedral Ward")
check("World map hover: Rep and citizen count shown", ts.rep == "Vacant" and ts.count >= 1)
s = DZM.spots["ARC"]
cursor_at(s.x + DZM.crop.x, s.y + DZM.crop.y)
check("World map hover: another district isn't called yours", WM.tipState.yours is False)
arc_lit = Q(d4c, '''local l = M.WorldMap.looks.ARC
  return l.rest.alpha == 1 and l.fill.shown and not M.WorldMap.looks.OLD.fill.shown''')
check("World map hover: the outline under the cursor brightens", arc_lit is True)
d4c.lua.execute('GameTooltip:SetOwner({}); GameTooltip:Show()')
WM.Hover(WM)
check("World map hover: a pin's tooltip wins, ours hides", not WM.tip.shown)
check("World map hover: the pin's tooltip is left alone", WG.GameTooltip.shown)
d4c.lua.execute('GameTooltip:Hide(); GameTooltip:SetOwner(nil)')
WM.Hover(WM)
check("World map hover: ours back once the pin's tooltip goes", WM.tip.shown)
# Where it shows: the game's own tooltip spot (Max, 8 Nov).
p = WM.tip.points[1]
check("World map tooltip: before the game's tooltip has shown, the screen's bottom right",
      WM.tipAt == "default" and p[1] == "BOTTOMRIGHT" and p[4] == -13 and p[5] == 64)
d4c.lua.execute('''
  GameTooltip.anchorType = "ANCHOR_NONE"
  function GameTooltip:GetAnchorType() return self.anchorType end
  GameTooltip:ClearAllPoints()
  GameTooltip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -250, 180) -- moved in Edit Mode or by ElvUI
  GameTooltip:Show(); GameTooltip:Hide()
''')
cursor_at(1010, 760)
cursor_at(s.x + DZM.crop.x, s.y + DZM.crop.y)
p = WM.tip.points[1]
check("World map tooltip: shows where the game's tooltip shows",
      WM.tipAt == "game" and p[1] == "BOTTOMRIGHT" and p[4] == -250 and p[5] == 180)
d4c.lua.execute('''
  GameTooltip.anchorType = "ANCHOR_CURSOR"
  GameTooltip:ClearAllPoints(); GameTooltip:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 5, 5)
  GameTooltip:Show(); GameTooltip:Hide(); GameTooltip:SetOwner(nil)
''')
cursor_at(1010, 760)
cursor_at(s.x + DZM.crop.x, s.y + DZM.crop.y)
check("World map tooltip: a tooltip some add-on pinned to the cursor doesn't move ours",
      WM.tip.points[1][4] == -250)
d4c.lua.execute('ElvUI = { { private = { tooltip = { enable = true } }, db = { tooltip = { cursorAnchor = true } } } }')
cursor_at(1010, 760)
cursor_at(s.x + DZM.crop.x, s.y + DZM.crop.y)
check("World map tooltip: ElvUI set to tooltips at the cursor, ours follows the cursor", WM.tipAt == "cursor")
d4c.lua.execute('ElvUI = nil')
cursor_at(1010, 760)
cursor_at(s.x + DZM.crop.x, s.y + DZM.crop.y)
d4c.lua.execute('OVER_MAP = false')
WM.Hover(WM)
check("World map hover: off the map (the quest log), no tooltip", not WM.tip.shown)
d4c.lua.execute('OVER_MAP = true')
cursor_at(s.x + DZM.crop.x, s.y + DZM.crop.y)
d4c.lua.execute('COMBAT = true')
run(1)
check("World map hover: works in combat (OnUpdate, no errors)", WM.tip.shown)
d4c.lua.execute('COMBAT = false')
d4c.lua.execute('WorldMapFrame:SetMapID(1429)')
check("World map hover: leaving Stormwind City hides the tooltip", not WM.tip.shown)
d4c.lua.execute('WorldMapFrame:SetMapID(1453); CURSOR_N = nil')
WM.Hover(WM)
wm_tex = WG.MinistryOfTheAllied.Media.pieces["dz_CATH_wmlit"]
check("World map: the heavier outlines have their own texture", wm_tex is not None and wm_tex.tex == "districts_wm"
      and WM.looks.CATH.lit.piece.tex == "districts_wm" and WM.looks.ARC.rest.piece.tex == "districts_wm")
check("Districts page: keeps its own lines", WG.MinistryOfTheAllied.Media.pieces["dz_CATH_lit"].tex == "districts")
glow_row =open(os.path.join(ADDON, "UI", "Settings.lua"), encoding="utf-8").read().split('key = "glow"')[1].split("},")[0]
check("Settings: District glow is live (no '· later') and tells the map", "later" not in glow_row and "GLOW_CHANGED" in glow_row)
# the Districts page footer
d4c.slash("")
dist_tab4 = [i for i in range(1, 8) if WG.MinistryOfTheAllied.Media.pages[i].id == "districts"][0]
WG.MinistryOfTheAllied.UI.SelectPage(WG.MinistryOfTheAllied.UI, dist_tab4)
check("Districts page: footer says your district glows on the world map",
      WG.MinistryOfTheAllied.UI.footRight.text == "YOUR DISTRICT GLOWS ON THE WORLD MAP TOO")
WG.MinistryOfTheAllied.UI.SelectPage(WG.MinistryOfTheAllied.UI, 1)
check("Other pages: footer keeps the place and day", "GLOWS" not in WG.MinistryOfTheAllied.UI.footRight.text)
clients.remove(d4c)
clients.remove(d4k)

print("== 102c. the world map's dress (D5c)")
d5k = Client("Max")
clients.append(d5k)
run(1)
d5c = Client("Bram")
clients.append(d5c)
run(8)
# A pretend Map & Quest Log with the parts this client has (names as Leatrix Maps and
# EllesmereUI read them in Max's game): the border frame and its knobs, the location bar and
# its crumbs, the tracking filter and reset, the quest log with its search box, count, gear,
# zone headers and scroll bar, and the side panel toggle. Each has some art of its own.
d5c.lua.execute('''
  local function art(f, w) local t = f:CreateTexture(nil, "ARTWORK") t:SetSize(w or 60, 20) return t end
  local function button(parent)
    local b = CreateFrame("Button", nil, parent)
    b.n, b.p, b.hi = art(b), art(b), b:CreateTexture(nil, "HIGHLIGHT")
    function b:GetNormalTexture() return self.n end
    function b:GetPushedTexture() return self.p end
    function b:GetHighlightTexture() return self.hi end
    b.label = b:CreateFontString(nil, "OVERLAY")
    b.text = b.label
    b:SetSize(24, 24)
    return b
  end
  local m = CreateFrame("Frame", "WorldMapFrame", UIParent)
  m.shown = false
  m:SetSize(1343, 703)
  m.level = 10
  local canvas = CreateFrame("Frame", nil, m)
  canvas:SetSize(1002, 668)
  function m:GetCanvas() return canvas end
  function m:GetMapID() return 1453 end
  function m:OnMapChanged() end
  function m:Maximize() end
  function m:Minimize() end
  local bf = CreateFrame("Frame", nil, m)
  bf:SetSize(1343, 703)
  m.BorderFrame = bf
  bf.edge = art(bf)
  bf.NineSlice = CreateFrame("Frame", nil, bf)
  bf.NineSlice.corner = art(bf.NineSlice)
  bf.PortraitContainer = CreateFrame("Frame", nil, bf)
  bf.PortraitContainer.portrait = art(bf.PortraitContainer)
  bf.CloseButton = button(bf)
  bf.MaximizeMinimizeFrame = CreateFrame("Frame", nil, bf)
  bf.MaximizeMinimizeFrame.MaximizeButton = button(bf.MaximizeMinimizeFrame)
  bf.MaximizeMinimizeFrame.MinimizeButton = button(bf.MaximizeMinimizeFrame)
  local nav = CreateFrame("Frame", nil, m)
  m.NavBar = nav
  nav:SetSize(600, 34)
  nav.bar = art(nav, 600)
  nav.InsetBorderBottom = art(nav)
  nav.homeButton = button(nav)
  -- a crumb past home has the game's dropdown arrow button, at its foot as in Max's game
  local function crumb(bar)
    local b = button(bar)
    b.MenuArrowButton = button(b)
    b.MenuArrowButton.Art = art(b.MenuArrowButton, 12)
    b.MenuArrowButton:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 0)
    return b
  end
  nav.navList = { nav.homeButton, crumb(nav), crumb(nav) }
  function NavBar_AddButton(bar) table.insert(bar.navList, crumb(bar)) end
  m.ScrollContainer = CreateFrame("Frame", nil, m)
  m.ScrollContainer.level = 12
  local tb = button(m)
  m.WorldMapTrackingOptionsButton = tb
  tb.ResetButton = button(tb)
  local tg = CreateFrame("Frame", nil, m)
  m.SidePanelToggle = tg
  tg.OpenButton, tg.CloseButton = button(tg), button(tg)
  local qm = CreateFrame("Frame", "QuestMapFrame", m)
  qm.VerticalSeparator = art(qm)
  qm.Background = art(qm, 300)
  local qs = CreateFrame("Frame", "QuestScrollFrame", qm)
  qs.Background = art(qs, 300)
  local sb = CreateFrame("EditBox", nil, qs)
  qs.SearchBox = sb
  sb.Left, sb.Middle, sb.Right = art(sb, 8), art(sb, 100), art(sb, 8)
  sb.searchIcon = art(sb, 14)
  sb.instructions = sb:CreateFontString(nil, "OVERLAY")
  qs.SettingsDropdown = button(qs)
  qs.SettingsDropdown:SetSize(16, 16) -- smaller than its picture, as in Max's game
  local bar = CreateFrame("Frame", nil, qs)
  qs.ScrollBar = bar
  bar.Track = CreateFrame("Frame", nil, bar)
  bar.Track.groove = art(bar.Track, 10)
  bar.Track.Thumb = CreateFrame("Frame", nil, bar.Track)
  bar.Track.Thumb.knob = art(bar.Track.Thumb, 10)
  bar.Back, bar.Forward = button(bar), button(bar)
  local headers = {}
  for i = 1, 2 do
    local h = button(qs)
    h.band = art(h, 300)
    h.minus = art(h, 14)
    headers[i] = h
  end
  qs.headerFramePool = { active = headers }
  function qs.headerFramePool:EnumerateActive()
    local i = 0
    return function() i = i + 1 return self.active[i] end
  end
  function QuestLogQuests_Update() end
  local count = CreateFrame("Frame", "QuestLogCount", qm)
  count:SetSize(118, 30)
  count.bg = art(count)
  count.text = count:CreateFontString(nil, "OVERLAY")
  count.text:SetFont("Fonts\FRIZQT__.TTF", 12, "")
  count.text:SetText("Quests: 14/40")
  local pin = button(m)
  m.WorldMapTrackingPinButton = pin
  pin.Icon, pin.ActiveTexture = art(pin, 20), art(pin, 20)
  pin:SetPoint("TOPLEFT", m.ScrollContainer, "TOPLEFT", 8, -8)
  local co = CreateFrame("Frame", nil, m)
  co.PlayerCoords = CreateFrame("Frame", nil, co)
  co.PlayerCoords.bg = art(co.PlayerCoords, 120)
  co.PlayerCoords.Label = co.PlayerCoords:CreateFontString(nil, "OVERLAY")
  co.PlayerCoords.Value = co.PlayerCoords:CreateFontString(nil, "OVERLAY")
  m.overlayFrames = { CreateFrame("Frame", nil, m), co }
  for _, fs in ipairs({ nav.homeButton.text, co.PlayerCoords.Label }) do fs:SetFont("Fonts\FRIZQT__.TTF", 12, "") end
  nav:SetPoint("TOPLEFT", bf, "TOPLEFT", 60, -30)
  WorldMapFramePortrait = art(bf)
  mock_fire("ADDON_LOADED", "Blizzard_WorldMap")
  WorldMapFrame:Show()
''')
G5 = d5c.lua.globals()
WS = G5.MinistryOfTheAllied.WorldMapSkin


def dressed_with(frame_expr, tex):
    """How many of the frame's own textures wear a picture from the texture tex."""
    return Q(d5c, f'''local n = 0
      for _, r in ipairs({{ {frame_expr}:GetRegions() }}) do
        if r.kind == "Texture" and r.shown and type(r.texture) == "string" and r.texture:find("{tex}", 1, true) then n = n + 1 end
      end
      return n''')


def wears(frame_expr, name, tex="wmap_ministry", skin="ministry"):
    """The frame wears piece name: one of its textures starts at the piece's top-left texcoords."""
    return Q(d5c, f'''local p = M.Media.pieces["wm_{skin}:{name}"]
      for _, r in ipairs({{ {frame_expr}:GetRegions() }}) do
        local c = r.coords
        if r.kind == "Texture" and r.shown and c and type(r.texture) == "string" and r.texture:find("{tex}", 1, true)
          and math.abs(math.min(c[1], c[2]) - p.l) < 1e-6 and math.abs(math.min(c[3], c[4]) - p.t) < 1e-6 then return true end
      end
      return false''') is True


check("Map dress: on from the start (Party), as the window", G5.MinistryOfTheAllied.db.settings.mapSkin == "party"
      and WS.on == G5.MinistryOfTheAllied.skin.KEY)
check("Map dress: the game's border art faded (border, nine-slice, portrait)",
      Q(d5c, 'local bf = WorldMapFrame.BorderFrame return bf.edge.alpha == 0 and bf.NineSlice.corner.alpha == 0 and WorldMapFramePortrait.alpha == 0') is True)
check("Map dress: our leather, grain and rim are on", WS.back.shown and WS.back.leather.shown and WS.back.grain.shown
      and WS.front.shown and WS.front.rim.parts[1].shown)
check("Map dress: the title and the seal are on", WS.front.title.shown and WS.front.seal.shown)
check("Map dress: the close knob wears ours, its own art faded",
      wears("WorldMapFrame.BorderFrame.CloseButton", "knobClose")
      and Q(d5c, 'local b = WorldMapFrame.BorderFrame.CloseButton return b.n.alpha == 0 and b.p.alpha == 0 and b.hi.alpha == 0') is True)
check("Map dress: enlarge wears the enlarge knob, shrink the same turned about",
      wears("WorldMapFrame.BorderFrame.MaximizeMinimizeFrame.MaximizeButton", "knobEnlarge")
      and Q(d5c, '''for _, r in ipairs({ WorldMapFrame.BorderFrame.MaximizeMinimizeFrame.MinimizeButton:GetRegions() }) do
          if r.coords and type(r.texture) == "string" and r.texture:find("wmap_") then return r.coords[1] > r.coords[2] and r.coords[3] > r.coords[4] end
        end''') is True)
check("Map dress: the buttons keep their own words", Q(d5c, 'return WorldMapFrame.BorderFrame.CloseButton.label.alpha == 1') is True)
check("Map dress: the location bar and its crumbs (home, step, the current place)",
      wears("WorldMapFrame.NavBar", "nav") and wears("WorldMapFrame.NavBar.homeButton", "crumbHome")
      and wears("WorldMapFrame.NavBar.navList[2]", "crumbStep") and wears("WorldMapFrame.NavBar.navList[3]", "crumbCur")
      and Q(d5c, 'return WorldMapFrame.NavBar.bar.alpha == 0 and WorldMapFrame.NavBar.InsetBorderBottom.alpha == 0') is True)
d5c.lua.execute('NavBar_AddButton(WorldMapFrame.NavBar)')
check("Map dress: a new crumb is the current place, the one before a step",
      wears("WorldMapFrame.NavBar.navList[4]", "crumbCur") and wears("WorldMapFrame.NavBar.navList[3]", "crumbStep")
      and not wears("WorldMapFrame.NavBar.navList[3]", "crumbCur"))
check("Map dress: the tracking filter and its reset",
      wears("WorldMapFrame.WorldMapTrackingOptionsButton", "track") and wears("WorldMapFrame.WorldMapTrackingOptionsButton.ResetButton", "reset"))
check("Map dress: the search box wears ours and keeps its magnifier",
      wears("QuestScrollFrame.SearchBox", "search")
      and Q(d5c, 'local sb = QuestScrollFrame.SearchBox return sb.Left.alpha == 0 and sb.Middle.alpha == 0 and sb.searchIcon.alpha == 1') is True)
check("Map dress: the quest count and the gear", wears("QuestLogCount", "count") and wears("QuestScrollFrame.SettingsDropdown", "gear")
      and Q(d5c, 'return QuestLogCount.bg.alpha == 0') is True)
cf = WS.countFrame
check("Map dress: the count's words are ours: 'QUESTS:' and the number, the game's hidden",
      cf is not None and cf.label.text == "QUESTS:" and cf.num.text == "14/40"
      and Q(d5c, 'return QuestLogCount.text.alpha == 0') is True)
d5c.lua.execute('QuestLogCount.text:SetText("Quests: 15/40")')
check("Map dress: the count follows the game's", cf.num.text == "15/40")
check("Map dress: the zone headers: band faded, the game's +/- kept, ours under",
      wears("QuestScrollFrame.headerFramePool.active[1]", "zone")
      and Q(d5c, 'local h = QuestScrollFrame.headerFramePool.active[2] return h.band.alpha == 0 and h.minus.alpha == 1') is True)
check("Map dress: the scroll bar and its thumb; its arrows out of sight (Max, 8 Nov)",
      wears("QuestScrollFrame.ScrollBar", "scroll") and wears("QuestScrollFrame.ScrollBar.Track.Thumb", "thumb")
      and not wears("QuestScrollFrame.ScrollBar.Back", "arrowUp")
      and Q(d5c, 'local b = QuestScrollFrame.ScrollBar return b.Track.groove.alpha == 0 and b.Back.alpha == 0 and b.Forward.alpha == 0') is True)
check("Map dress: the map pin button is our gold diamond; the game's 'pin active' look kept",
      wears("WorldMapFrame.WorldMapTrackingPinButton", "round")
      and Q(d5c, 'local p = WorldMapFrame.WorldMapTrackingPinButton return p.Icon.alpha == 0 and p.ActiveTexture.alpha == 1') is True)
check("Map dress: the position plate wears ours, its words in the board's fonts",
      wears("WorldMapFrame.overlayFrames[2].PlayerCoords", "plate")
      and Q(d5c, """local p = WorldMapFrame.overlayFrames[2].PlayerCoords
        return p.bg.alpha == 0 and p.Label.fontPath:find("Cinzel") ~= nil and p.Value.fontPath:find("EBGaramond") ~= nil""") is True)
check("Map dress: the quest log's own backgrounds and divider faded",
      Q(d5c, 'return QuestMapFrame.Background.alpha == 0 and QuestMapFrame.VerticalSeparator.alpha == 0 and QuestScrollFrame.Background.alpha == 0') is True)
check("Map dress: the quest log toggle (open and close)",
      wears("WorldMapFrame.SidePanelToggle.OpenButton", "toggle") and wears("WorldMapFrame.SidePanelToggle.CloseButton", "toggle"))
check("Map dress: with the log open, its panel and the divider show", WS.back.log.parts[5].shown and WS.back.divider.parts[5].shown)
d5c.lua.execute('QuestMapFrame:Hide()')
check("Map dress: the log closed, its panel and the divider go", not WS.back.log.parts[5].shown and not WS.back.divider.parts[5].shown)
d5c.lua.execute('QuestMapFrame:Show()')
check("Map dress: the log open again, back they come", WS.back.log.parts[5].shown)
check("Map dress: the leather on the map frame's level, the front just over it (the game's buttons over our rim)",
      WS.back.level == 10 and WS.front.level == 11)
wms_src = open(os.path.join(ADDON, "UI", "WorldMapSkin.lua"), encoding="utf-8").read()
check("Map dress: our frames take no mouse (the game's buttons keep their clicks)",
      "back:EnableMouse(false)" in wms_src and "front:EnableMouse(false)" in wms_src and "EnableMouse(true)" not in wms_src)
check("Map dress: nothing of Blizzard's replaced (hooks only)",
      "hooksecurefunc" in wms_src and not re.search(r"\b(WorldMapFrame|map|QuestMapFrame)\.\w+\s*=\s*function", wms_src))
# the stretched pieces: corners whole, the middle stretched
rim = Q(d5c, '''local s = M.WorldMapSkin.front.rim.parts
  local p1, p5 = s[1].points, s[5].points
  return p1[1][1] == "TOPLEFT" and p1[1][3] == "TOPLEFT" and p5[2][3] == "BOTTOMRIGHT"''')
check("Map dress: the rim is a nine-slice laid round the frame", rim is True)
# another skin
d5c.lua.execute('MinistryOfTheAllied.ApplySkin("CROWN")')
check("Map dress: a new skin, new pictures (the Crown's)",
      wears("WorldMapFrame.BorderFrame.CloseButton", "knobClose", "wmap_crown", "crown")
      and wears("WorldMapFrame.NavBar.homeButton", "crumbHome", "wmap_crown", "crown") and WS.on == "CROWN")
check("Map dress: the Crown's filigree on the bottom corners", WS.front.cornerL.shown and WS.front.cornerR.shown)
crumb_inks = Q(d5c, '''local nav = WorldMapFrame.NavBar
  local function is(fs, hex) local r, g, b = M:RGB(hex) local c = fs.color
    return c and math.abs(c[1] - r) < 1e-6 and math.abs(c[2] - g) < 1e-6 and math.abs(c[3] - b) < 1e-6 end
  return is(nav.homeButton.text, "3E0A2F") and is(nav.navList[2].text, "EBCBDF") and is(nav.navList[4].text, "FFF3C4")''')
check("Map dress: crumb words in the board's inks (dark on the Crown's gold home crumb)", crumb_inks is True)
# the board's layout (canvas units x k, k = the map's top below the frame's / 100)
layout = Q(d5c, """local WS = M.WorldMapSkin
  local k = WS.k
  local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end
  local function at(f, i) return f.points[i or 1] or {} end
  local bf, nav, sc = WorldMapFrame.BorderFrame, WorldMapFrame.NavBar, WorldMapFrame.ScrollContainer
  local close, mm = bf.CloseButton, bf.MaximizeMinimizeFrame
  local tb = WorldMapFrame.WorldMapTrackingOptionsButton
  local gear, sb = QuestScrollFrame.SettingsDropdown, QuestScrollFrame.SearchBox
  local ok = {}
  local c = at(close)
  ok.close = c[1] == "TOPRIGHT" and c[2] == bf and near(c[4], -2 * k) and near(c[5], -2 * k) and near(close.w, 36 * k) and near(close.h, 38 * k)
  local e = at(mm)
  ok.enlarge = e[2] == close and e[3] == "TOPLEFT" and near(e[4], -2 * k) and near(mm.w, 36 * k)
  -- the bar the board's 36 deep at 56 (the leather above and below it), its crumbs 32;
  -- from the board's gap past the seal to 14 short of the filter
  local sp = M.Media.pieces["wm_" .. (WS.on == "CROWN" and "crown" or "ministry") .. ":seal"]
  local kh = 703 / 749 * 0.7
  local d = math.max(0, (sp.y + sp.h) * (kh - k))
  local left = (sp.x + sp.w) * kh - d + (100 - sp.x - sp.w) * k
  ok.nav = at(nav, 1)[2] == bf and near(at(nav, 1)[4], left) and near(at(nav, 1)[5], -56 * k)
    and at(nav, 2)[2] == tb and at(nav, 2)[3] == "TOPLEFT" and near(at(nav, 2)[4], -14 * k) and near(nav.h, 36 * k)
  ok.crumbs = near(nav.homeButton.h, 32 * k) and near(nav.navList[3].h, 32 * k)
  -- the filter as tall as the bar and level with it, the board's shape, its right edge 6 in from the map's
  local t = at(tb)
  local th = 36 * k
  local tw = th * 38 / 32
  ok.filter = t[1] == "TOPRIGHT" and t[2] == sc and near(t[4], -6 * k) and near(t[5], 44 * k) and near(tb.w, tw) and near(tb.h, th)
  local r = at(tb.ResetButton)
  ok.reset = r[2] == tb and near(r[4], 26 * th / 32) and near(r[5], 10 * th / 32) and near(tb.ResetButton.w, 19 * th / 32)
  -- the scroll bar beside the log's panel, from 2 above the map's top: clear of the gear
  local sbar = QuestScrollFrame.ScrollBar
  local b = at(sbar)
  ok.scroll = b[1] == "TOPRIGHT" and b[2] == bf and near(b[4], -10 * k) and near(b[5], -98 * k) and near(sbar.w, 18 * k)
  -- the log's panel from 2 above the map's top (the search row on the leather above it)
  local lb = WS.back.logBox
  ok.logPanel = lb.points[1][1] == "TOPRIGHT" and near(lb.points[1][4], -32 * k) and near(lb.points[1][5], -98 * k)
    and lb.points[2][2] == sc and near(lb.points[2][5], -2 * k)
  local g = at(gear)
  ok.gear = g[2] == bf and near(g[4], -10 * k) and near(g[5], -58 * k) and near(gear.w, 30 * k) and near(gear.h, 30 * k)
  local q = at(QuestLogCount)
  ok.count = q[2] == gear and q[3] == "TOPLEFT" and near(q[4], -6 * k) and near(QuestLogCount.w, 118 * k) and near(QuestLogCount.h, 30 * k)
  local s = at(sb)
  ok.search = s[2] == QuestLogCount and near(s[4], -6 * k) and near(sb.w, 226 * k) and near(sb.h, 30 * k)
  local ti = WS.front.title
  ok.title = ti.points[1][1] == "CENTER" and near(ti.points[1][5], -26.8 * k)
  ok.rule = near(WS.front.sepBox.points[1][5], -44 * k)
  -- the map pin 10 in from the map's top-left corner
  local pin = WorldMapFrame.WorldMapTrackingPinButton
  local pp = at(pin)
  ok.pin = pp[1] == "TOPLEFT" and pp[2] == sc and pp[3] == "TOPLEFT" and near(pp[4], 10 * k) and near(pp[5], -10 * k)
  -- each crumb's chevron 7 past its words, level with them, the board's 11
  local function chev(b)
    local ma, fs = b.MenuArrowButton, b.text
    local a = at(ma)
    return a[1] == "LEFT" and a[2] == fs and a[3] == "LEFT" and near(a[4], fs:GetStringWidth() + 7 * k) and a[5] == 0
      and near(ma.w, 11 * k) and near(ma.h, 11 * k)
  end
  ok.chevrons = chev(nav.navList[2]) and chev(nav.navList[4])
  local bad = {}
  for name, v in pairs(ok) do if not v then bad[#bad + 1] = name end end
  table.sort(bad)
  return table.concat(bad, ",")""")
check("Map dress: the header on the board's layout (knobs flush, bar 36 and crumbs 32, filter as tall as the bar, reset, "
      "search 226, count 118, gear 30, title, rule, the log's panel and scroll bar under the row) "
      + (layout or ""), layout == "")
joins = Q(d5c, """local nav = WorldMapFrame.NavBar
  local function joined(b, nextOne)
    for _, r in ipairs({ b:GetRegions() }) do
      if r.kind == "Texture" and r.shown and type(r.texture) == "string" and r.texture:find("wmap_") then
        for _, pt in ipairs(r.points) do if pt[2] == nextOne and pt[3]:find("LEFT") then return true end end
      end
    end
    return false
  end
  return joined(nav.homeButton, nav.navList[2]) and joined(nav.navList[2], nav.navList[3]) and not joined(nav.navList[4], nav.navList[5])""")
check("Map dress: each crumb reaches into the next one's notch (no gap); the last ends at its own edge", joins is True)
check("Map dress: a crumb's arrow is the board's chevron in its ink, the game's arrow faded, still clickable round it",
      wears("WorldMapFrame.NavBar.navList[2].MenuArrowButton", "chev", "wmap_crown", "crown")
      and Q(d5c, """local ma = WorldMapFrame.NavBar.navList[2].MenuArrowButton
        local r, g, b = M:RGB("EBCBDF")
        for _, t in ipairs({ ma:GetRegions() }) do
          if t.kind == "Texture" and type(t.texture) == "string" and t.texture:find("wmap_crown", 1, true) then
            local c = rawget(t, "color")
            if c and (math.abs(c[1] - r) > 1e-6 or math.abs(c[3] - b) > 1e-6) then return false end
          end
        end
        local m = -5 * M.WorldMapSkin.k
        return ma.Art.alpha == 0 and ma.n.alpha == 0 and ma.hitInsets[1] == m and ma.hitInsets[4] == m""") is True)
# the quest list: the game's begins above our panel (as in Max's game); its first row goes 6 under the panel's top
d5c.lua.execute('''
  local bf, qs, qm = WorldMapFrame.BorderFrame, QuestScrollFrame, QuestMapFrame
  qs:ClearAllPoints()
  qs:SetPoint("TOPLEFT", qm, "TOPLEFT", 0, -30)
  qs:SetPoint("BOTTOMRIGHT", qm, "BOTTOMRIGHT", 0, 0)
  qs.shown = true
  function bf:GetTop() return 703 end
  function qs:GetTop() return 673 + self.points[1][5] end            -- 643 as the game has it
  for _, h in ipairs(qs.headerFramePool.active) do h.shown = true end
  local h1, h2 = qs.headerFramePool.active[1], qs.headerFramePool.active[2]
  function h1:GetTop() return qs:GetTop() - 4 + qs:GetVerticalScroll() end  -- 4 under the list's top
  function h2:GetTop() return h1:GetTop() - 120 end
  MinistryOfTheAllied.WorldMapSkin:LayHeader()
''')
list_top = Q(d5c, """local WS, qs = M.WorldMapSkin, QuestScrollFrame
  local k = WS.k
  local want = 703 - 98 * k - 6 * k
  local h1 = qs.headerFramePool.active[1]
  local ok1 = math.abs(h1:GetTop() - want) < 1e-6 and qs.points[2][1] == "BOTTOMRIGHT" and qs.points[2][5] == 0
  qs.vscroll = 50
  WS:LayHeader()
  local ok2 = math.abs(h1:GetTop() - 50 - want) < 1e-6
  qs.vscroll = 0
  WS:LayHeader()
  return ok1 and ok2 and math.abs(h1:GetTop() - want) < 1e-6""")
check("Map dress: the quest list's first row 6 under its panel's top, its foot kept, steady when scrolled and laid again", list_top is True)
d5c.lua.execute('WorldMapFrame.BorderFrame.GetTop = nil; QuestScrollFrame.GetTop = nil')
check("Map dress: the seal and the quest log's words go by the window's size, not the header's",
      Q(d5c, """local kh = 703 / 749
        local seal, sp = M.WorldMapSkin.front.seal, M.Media.pieces["wm_crown:seal"]
        return math.abs(seal.w - sp.w * kh * 0.7) < 1e-6 and QuestScrollFrame.headerFramePool.active[1].text.fontSize == math.floor(13 * kh * 2 + 0.5) / 2""") is True)
check("Map dress: the seal wears the map's own picture (a tight shadow), its foot no lower than the board's against the map",
      Q(d5c, """local WS, sp = M.WorldMapSkin, M.Media.pieces["wm_crown:seal"]
        local s = WS.front.seal
        local foot = s.points[1][5] - s.h   -- from the frame's top, up positive
        return s.texture:find("wmap_crown", 1, true) ~= nil and math.abs(s.coords[1] - sp.l) < 1e-6
          and foot >= -(sp.y + sp.h) * WS.k - 1e-6 and s.points[1][4] <= sp.x * 703 / 749 * 0.7 + 1e-6""") is True)
# a header shallower against its window, as in Max's game: the seal moves up and left until its foot is the board's
seal_moved = Q(d5c, """local WS, sp = M.WorldMapSkin, M.Media.pieces["wm_crown:seal"]
  WorldMapFrame.BorderFrame:SetSize(1343, 1100)
  WS:Lay()
  local s, kh, k = WS.front.seal, 1100 / 749 * 0.7, WS.k
  local d = (sp.y + sp.h) * (kh - k)
  local ok = d > 0 and math.abs(s.points[1][4] - (sp.x * kh - d)) < 1e-6 and math.abs(s.points[1][5] - (-sp.y * kh + d)) < 1e-6
    and math.abs((s.points[1][5] - s.h) + (sp.y + sp.h) * k) < 1e-6
  WorldMapFrame.BorderFrame:SetSize(1343, 703)
  WS:Lay()
  return ok""")
check("Map dress: on a tall window the seal moves up and left together, its foot the board's against the map", seal_moved is True)
check("Map dress: a button's picture box fills the button, its shadow reaching past (the pin and gear full size)",
      Q(d5c, """local at, p = M.Media.wmap.at.round, M.Media.pieces["wm_crown:round"]
        local pin = WorldMapFrame.WorldMapTrackingPinButton
        for _, r in ipairs({ pin:GetRegions() }) do
          if r.kind == "Texture" and type(r.texture) == "string" and r.texture:find("wmap_crown", 1, true) then
            local sx = pin.w / at.w
            local tl, br = r.points[1], r.points[2]
            return tl[2] == pin and math.abs(tl[4] + (at.x - p.x) * sx) < 1e-6 and math.abs(br[5] + (p.y + p.h - at.y - at.h) * pin.h / at.h) < 1e-6
              and math.abs(pin.w - 30 * M.WorldMapSkin.k) < 1e-6
          end
        end
        return false""") is True)
check("Map dress: the crumbs in Cinzel, the search box in EB Garamond italic, the headers in Cinzel",
      "Cinzel" in (Q(d5c, 'return WorldMapFrame.NavBar.homeButton.text.fontPath') or "")
      and "EBGaramond-Italic" in (Q(d5c, 'return QuestScrollFrame.SearchBox.fontPath') or "")
      and "Cinzel" in (Q(d5c, 'return QuestScrollFrame.headerFramePool.active[1].text.fontPath') or ""))
d5c.lua.execute('MinistryOfTheAllied.db.settings.mapSkin = "ministry"; MinistryOfTheAllied:Fire("MAP_SKIN_CHANGED")')
check("Map dress: Ministry chosen, the Ministry's pictures whatever the window wears",
      WS.on == "UNREGISTERED" and wears("WorldMapFrame.BorderFrame.CloseButton", "knobClose") and not WS.front.cornerL.shown)
# Plain: the game's look back
d5c.lua.execute('MinistryOfTheAllied.db.settings.mapSkin = "plain"; MinistryOfTheAllied:Fire("MAP_SKIN_CHANGED")')
check("Map dress: Plain puts the game's parts back where it had them, at their sizes",
      Q(d5c, """local nav, close = WorldMapFrame.NavBar, WorldMapFrame.BorderFrame.CloseButton
        local ma = nav.navList[2].MenuArrowButton
        return #nav.points == 1 and nav.points[1][4] == 60 and nav.points[1][5] == -30 and close.w == 24 and close.h == 24
          and QuestLogCount.w == 118 and #QuestScrollFrame.SettingsDropdown.points == 0
          and QuestScrollFrame.points[1][5] == -30 and nav.navList[2].h == 24
          and ma.points[1][1] == "BOTTOMRIGHT" and ma.hitInsets[1] == 0 and ma.Art.alpha == 1""") is True)
check("Map dress: Plain gives the words their own fonts back, the count's and the arrows back",
      Q(d5c, 'local t = WorldMapFrame.NavBar.homeButton.text return t.fontPath:find("FRIZQT") ~= nil and t.fontSize == 12') is True
      and Q(d5c, 'return QuestLogCount.text.alpha == 1 and QuestScrollFrame.ScrollBar.Back.alpha == 1') is True)
check("Map dress: Plain gives the crumbs their own words' colour back",
      Q(d5c, 'local c = WorldMapFrame.NavBar.homeButton.text.color return c[1] == 1 and c[2] == 1 and c[3] == 1') is True)
check("Map dress: Plain takes ours off", WS.on is None and not WS.back.shown and not WS.front.shown
      and not wears("WorldMapFrame.BorderFrame.CloseButton", "knobClose") and not wears("WorldMapFrame.NavBar", "nav"))
check("Map dress: Plain puts the game's own art back",
      Q(d5c, '''local bf = WorldMapFrame.BorderFrame
        return bf.edge.alpha == 1 and bf.CloseButton.n.alpha == 1 and QuestScrollFrame.SearchBox.Left.alpha == 1
          and WorldMapFrame.NavBar.bar.alpha == 1 and QuestScrollFrame.headerFramePool.active[1].band.alpha == 1''') is True)
# in combat, a protected map waits
d5c.lua.execute('''MinistryOfTheAllied.db.settings.mapSkin = "party"
  function WorldMapFrame:IsProtected() return true end
  COMBAT = true
  MinistryOfTheAllied:Fire("MAP_SKIN_CHANGED")''')
check("Map dress: in combat a protected map is left as it is", WS.on is None)
d5c.lua.execute('COMBAT = false; mock_fire("PLAYER_REGEN_ENABLED")')
check("Map dress: after combat it dresses", WS.on is not None and wears("WorldMapFrame.BorderFrame.CloseButton", "knobClose", "wmap_crown", "crown"))
d5c.lua.execute('function WorldMapFrame:IsProtected() return false end')
clients.remove(d5c)
clients.remove(d5k)
# remembered: a saved Plain stays Plain at the next login; a new install starts on
d5p = Client("Ivo", saved='MOTADB = { settings = { mapSkin = "plain" } }')
clients.append(d5p)
run(2)
check("Map dress: a saved Plain is kept at the next login", d5p.lua.globals().MinistryOfTheAllied.db.settings.mapSkin == "plain")
clients.remove(d5p)
d5n = Client("Juno")
clients.append(d5n)
run(2)
check("Map dress: a new install starts on (Party)", d5n.lua.globals().MinistryOfTheAllied.db.settings.mapSkin == "party")
clients.remove(d5n)
missing = [p for p in G5.mock_textures().split("\n") if "wmap_" in p
           and not os.path.exists(os.path.join(ADDON, p[len("Interface\\AddOns\\MinistryOfTheAllied\\"):].replace("\\", os.sep)))]
check("Map dress: every picture it asks for exists", not missing and "wmap_" in G5.mock_textures())

print("  Methods the pretend game didn't know:", max_.lua.globals().mock_unknown())
missing = []
for c in (max_, bram):
    for path in c.lua.globals().mock_textures().split("\n"):
        if path.startswith("Interface\\AddOns\\MinistryOfTheAllied\\"):
            rel = path[len("Interface\\AddOns\\MinistryOfTheAllied\\"):].replace("\\", os.sep)
            if not os.path.exists(os.path.join(ADDON, rel)):
                missing.append(path)
check("Every Ballot Hall texture exists", not missing)

print("== 100b. citizens place themselves in districts")
clients[:] = []
pk = Client("Max", place=True)
clients.append(pk)
run(2)
placed = [pk]
for n in ("Bram", "Mira", "Kael", "Tobin", "Wren"):
    c = Client(n, place=True)
    clients.append(c)
    placed.append(c)
    run(3)
run(50)
DQ = 'local M, D = MinistryOfTheAllied, MinistryOfTheAllied.District '
def DE(c, code):
    return c.lua.eval("(function() " + DQ + code + " end)()")
check("Districts: each citizen's add-on places them on first use", all(DE(pk, 'return M:DistrictOf("%s") ~= nil' % c.name) for c in placed[1:]))
check("Districts: the Crown isn't placed", DE(pk, 'return M:DistrictOf("Max") == nil') is True)
sizes = [DE(pk, 'return D:Size("%s")' % code) for code in ("OLD", "ARC", "IRON", "CATH", "HARB")]
check("Districts: the sizes stay close (within 5; here within 1)", max(sizes) - min(sizes) <= 1 and sum(sizes) == 5)
check("Districts: they told the citizen where they live", placed[1].said(r"You live in The .*council meets"))
first = DE(placed[1], 'return M:DistrictOf("Bram").code')
other = "OLD" if first != "OLD" else "ARC"
DE(placed[1], 'M.Book:Write("citizen.district", { who = "Bram", d = "%s" }) return 1' % other)
run(1)
check("Districts: placing yourself again doesn't move you", DE(pk, 'return M:DistrictOf("Bram").code') == first)
DE(placed[1], 'M.Book:Write("citizen.district", { who = "Mira", d = "%s" }) return 1' % other)
run(1)
check("Districts: nobody can place someone else", DE(pk, 'return M:DistrictOf("Mira").code') != other or DE(placed[2], 'return M:DistrictOf("Mira").code') != other)
DE(pk, 'D:Assign("Bram", "%s") return 1' % other)
run(1)
check("Districts: the Crown can still move a citizen", DE(placed[3], 'return M:DistrictOf("Bram").code') == other)
check("Outreach: members without the add-on are listed for the Crown", "Elowen" in [DE(pk, 'return MinistryOfTheAllied.Outreach:Missing()[%d].name' % i) for i in range(1, DE(pk, 'return #MinistryOfTheAllied.Outreach:Missing()') + 1)])
check("Outreach: those with it aren't", DE(pk, 'return MinistryOfTheAllied.Outreach:HasAddon("Bram")') is True)
pk.slash("missing")
check("Outreach: /mota missing lists them", pk.said(r"Elowen · first seen"))
check("Outreach: it's on the Crown's duties", DE(pk, 'for _, d in ipairs(MinistryOfTheAllied.Throne:Duties()) do if d.text:find("have the add%-on") then return true end end return false') is True)
late_p = Client("Elowen", place=True)
clients.append(late_p)
run(60)
check("Districts: a newcomer goes to a smallest district", DE(pk, 'return M:DistrictOf("Elowen") ~= nil') is True)
check("Outreach: once their add-on is in use, they leave the list", DE(pk, 'return MinistryOfTheAllied.Outreach:HasAddon("Elowen")') is True)

print("== 15. the election cycle")
clients[:] = []
ek = Client("Max")
clients.append(ek)
run(1)
eb, em, ekk = Client("Bram"), Client("Mira"), Client("Kael")
clients.extend([eb, em, ekk])
run(14)
def E(c, code):
    return c.lua.eval("(function() local M, El, Co = MinistryOfTheAllied, MinistryOfTheAllied.Elect, MinistryOfTheAllied.Contest " + code + " end)()")
check("Election: active players are those whose add-on has been heard", E(ek, 'return El:Gates().players') == 4)
check("Election: no first election before the gates are met", E(ek, 'local _, e = El:BeginFirst() return e ~= nil') is True)
ek.lua.execute('MinistryOfTheAllied.UI:Build(); MinistryOfTheAllied.UI:SelectPage(4); local P = MinistryOfTheAllied.PartiesPage; P:Select("ch"); P:Refresh()')
check("Election: the Crown's desk shows the gates", E(ek, 'return MinistryOfTheAllied.PartiesPage ~= nil') is True)
TH = 'local T = MinistryOfTheAllied.Throne '
def throne_draws(c, label):
    errs = len(errors)
    c.lua.execute('MinistryOfTheAllied.UI:Build(); MinistryOfTheAllied.UI:SelectPage(1); MinistryOfTheAllied.UI.window:Show()')
    for skin in ("crown", "silverhand", "exchange", "ministry"):
        c.lua.execute("MinistryOfTheAllied.Skin:Preview(\"%s\")" % skin)
        c.lua.execute('MinistryOfTheAllied.ThronePage:Refresh()')
    drawn = c.lua.eval("(function() local P = MinistryOfTheAllied.ThronePage return P.root and P.root.shown and P.head.eyebrow.text ~= '' and P.head.plateText.text ~= '' end)()")
    check("Throne Room: draws in all four skins, " + label, len(errors) == errs and drawn is True)
check("Throne Room: recruiting, before the first election", E(eb, TH + 'return T:Banner().eyebrow').startswith("Recruiting"))
check("Throne Room: the gates show in Who holds power", E(eb, TH + 'local p = T:Power() return p.pm == nil and p.gates.players') == 4)
check("Throne Room: nothing is on yet", E(eb, TH + 'return #T:Live()') == 0)
throne_draws(eb, "recruiting")
# --- Throne Room: every box that relates to another page opens it (Kit:Hot) --------------------
# Helpers for the click checks below; thr_click runs a hot button's OnClick and reads back the page and its view.
THR_OPEN = 'M.UI:Build(); M.UI.window:Show(); M.UI:SelectPage(1); local P = M.ThronePage; P:Refresh(); '
def thr_click(c, expr):
    return c.lua.eval('(function() local M = MinistryOfTheAllied; ' + THR_OPEN + 'local h = ' + expr +
        '; if not h or not h:IsShown() then return "none" end; h.scripts.OnClick(h); ' +
        'local o = ({[3] = M.StatutesPage, [4] = M.PartiesPage, [6] = M.DistrictsPage, [7] = M.RingPage, [8] = M.GamesPage})[M.UI.page]; ' +
        'return M.UI.page .. "|" .. tostring(o and o.View and o:View() or "") end)()')
def thr_row(kind, word):  # a duty or decree row whose text has the word
    return '(function() for _, r in ipairs(P.%s.rows) do if r:IsShown() and r.text.text:find("%s") then return r.hot end end end)()' % (kind, word)
def thr_audit(c, label):
    # every clickable has a destination and a tooltip; a box with no destination is hidden (no glow, no click)
    ok = c.lua.eval('(function() local M = MinistryOfTheAllied; ' + THR_OPEN + 'local n, bad, info = 0, 0, "" ' +
        'for _, h in ipairs(P.hot) do n = n + 1 if h:IsShown() ~= (rawget(h, "page") ~= nil) or (rawget(h, "page") ~= nil and (type(rawget(h, "tip")) ~= "string" or rawget(h, "tip") == "" or not rawget(h, "tip"):find("^Opens "))) then bad = bad + 1 info = info .. _ .. ":" .. tostring(rawget(h, "page")) .. "/" .. tostring(rawget(h, "tip")) .. "/" .. tostring(h:IsShown()) .. " " end end ' +
        'return n > 10 and bad == 0 or (n .. " hots, " .. bad .. " bad " .. info) end)()')
    if ok is not True: print("     audit:", ok)
    check("Throne Room links: every clickable has a page and a tooltip, the rest are hidden, " + label, ok is True)
thr_audit(eb, "recruiting")
check("Throne Room links: the banner plate opens the Parties while recruiting", thr_click(eb, 'P.head.hot').startswith("4|"))
check("Throne Room links: the Silverhand count opens its page", thr_click(eb, 'P.power.links.recruit[2]') == "4|sh")
check("Throne Room links: the Exchange count opens its page", thr_click(eb, 'P.power.links.recruit[3]') == "4|ex")
check("Throne Room links: the players count opens the Parties", thr_click(eb, 'P.power.links.recruit[1]').startswith("4|"))
check("Throne Room links: the Crown row is the Charter for a citizen", thr_click(eb, 'P.power.links.crown') == "3|charter")
check("Throne Room links: the Crown row is the Crown's chamber for the Crown", thr_click(ek, 'P.power.links.crown') == "4|ch")
check("Throne Room links: Your place opens the Districts map", thr_click(eb, 'P.place.districtHot') == "6|map")
check("Throne Room links: no party, the party chip opens Silverhand's page", thr_click(eb, 'P.place.partyHot') == "4|sh")
check("Throne Room links: the Crown's chip opens the Crown's chamber", thr_click(ek, 'P.place.partyHot') == "4|ch")
check("Throne Room links: Chronicle-style tooltip says where it goes", eb.lua.eval('(function() local h = MinistryOfTheAllied.ThronePage.place.districtHot h.scripts.OnEnter(h) local t = GameTooltip.text h.scripts.OnLeave(h) return t end)()') == "Opens Districts · Map")

E(ek, 'El.GATE_PLAYERS = 4; El.GATE_PARTY = 1 return 1')  # a small guild, for the test
for c, key in ((eb, "sh"), (em, "ex")):
    E(c, 'M.Book:Write("party.join", { p = "%s" }) return 1' % key)
    run(1)
    E(ek, 'M.Book:Write("party.admit", { v = "%s", p = "%s" }) return 1' % (c.name, key))
    run(1)
check("Election: the gates open once each party has its members", E(ek, 'return El:Gates().ok') is True)
check("Election: a citizen can't begin it", E(eb, 'local _, e = El:BeginFirst() return e ~= nil') is True)
check("Election: the Crown begins the first election", E(ek, 'return El:BeginFirst() ~= nil') is True)
run(1)
check("Throne Room: the election shows in What's on", E(eb, TH + 'for _, e in ipairs(T:Live()) do if e.key == "election" then return e.title end end') == "General Election")
check("Throne Room: the banner counts down to polling day", E(eb, TH + 'return T:Banner().plateText') == "In 28 days")
check("Throne Room: the Crown's duties include opening the contests", E(ek, TH + 'for _, d in ipairs(T:Duties()) do if d.text:find("leadership contests") then return true end end return false') is True)
check("Throne Room: a citizen has none of the Crown's duties", E(eb, TH + 'for _, d in ipairs(T:Duties()) do if d.text:find("leadership contests") then return false end end return true') is True)
throne_draws(ek, "an election under way")
check("Election: polling day is 28 days on, for everyone", E(em, 'return math.floor((Co:PollAt() - GetServerTime()) / 86400 + 0.5)') == 28 and E(em, 'return Co:Kind()') == "General Election")
check("Election: it can only begin once", E(ek, 'local _, e = El:BeginFirst() return e ~= nil') is True)
check("Election: the leadership contests come first", E(em, 'return Co:Current().kind') == "general")
cid = E(ek, 'return Co:Current().id')
E(ek, 'M.Book:Write("contest.result", { id = "%s", p = "sh", w = "Bram", votes = {} }) M.Book:Write("contest.result", { id = "%s", p = "ex", w = "Mira", votes = {} }) return 1' % (cid, cid))
run(1)
ballot = 'M.Book:Write("ballot.result", { b = "Max#%d", name = "%s", kind = "%s", cands = { { n = "Bram", p = "sh" }, { n = "Mira", p = "ex" } }, votes = { %d, %d }, total = 4, w = %d }) return 1'
E(ek, ballot % (900, "General Election", "general", 3, 1, 1))
run(12)
check("Election: the winner is Prime Minister for everyone", E(ekk, 'local g = El:Government() return g and g.name == "Bram" and g.p == "sh"') is True)
check("Election: the term runs three calendar months", 89 <= E(ekk, 'local g = El:Government() return math.floor((g.ends - g.t) / 86400)') <= 92)
check("Election: the other party is in opposition", E(ekk, 'return El:Opposition()') == "ex")
check("Election: the governing bench is the Cabinet", E(ekk, 'return El:BenchName("sh")') == "The Cabinet" and E(ekk, 'return El:BenchName("ex")') == "Shadow cabinet")
check("Election: the next General Election is set for the term's end", E(em, 'local g, c = El:Government(), Co:Current() return c.at == g.ends and c.kind == "general" and El:Pending() and not El:Underway()') is True)
check("Election: only one date is set, though a King's copy wrote it", E(em, 'local n = 0 for _, l in pairs(M.guild.records) do for _, r in pairs(l) do if r.k == "election.date" then n = n + 1 end end end return n') == 2)
eb.lua.execute('MinistryOfTheAllied.Elect.Remind()')
check("Election: the Prime Minister is reminded to name the Cabinet", eb.said(r"Name your Cabinet: \d+ hours left"))
em.lua.execute('MinistryOfTheAllied.Elect.Remind()')
check("Election: the Leader of the Opposition, the shadow cabinet", em.said(r"Name your shadow cabinet"))
check("Throne Room: the First Government, day 1", E(eb, TH + 'return T:Banner().eyebrow').startswith("The First Government · Day 1 of"))
check("Throne Room: the Prime Minister and five Cabinet posts", E(ekk, TH + 'local p = T:Power() return p.pm.name == "Bram" and #p.cabinet == 5 and p.cabinet[1].title == "Treasury"') is True)
check("Throne Room: the Leader of the Opposition", E(ekk, TH + 'local p = T:Power() return p.opposition.name == "Mira" and p.opposition.p == "ex"') is True)
# Who holds power, drawn from a real government and laid out as the board flows it (ThroneRoom board, measured
# in Edge: Crown row 46, rule 114, Prime Minister 127, Cabinet plate 215 and 130 high, rows 23 apart, the Opposition pinned
# to the bottom). The board's fifth post is "Justice"; the add-on's is Games (Duncan, 8 Nov): the Crown appoints the Justices.
PW_OPEN = THR_OPEN + 'local pw = P.power; local g = pw.geo; '
check("Throne Room: the Cabinet shows Treasury, War, Trade, Recruitment and Games, with the Justices line apart",
      E(ekk, TH + 'local p = T:Power() local t = {} for i, c in ipairs(p.cabinet) do t[i] = c.title end return table.concat(t, ",") .. "|" .. tostring(type(p.justices))')
      == "Treasury,War,Trade,Recruitment,Games|string")
check("Throne Room: the Crown row, the Prime Minister and the Opposition are drawn from the real government",
      E(ekk, PW_OPEN + 'return tostring(pw.gov:IsShown()) .. tostring(pw.k1:IsShown()) .. tostring(pw.rows.crown:IsShown()) .. tostring(pw.rows.pm:IsShown()) .. tostring(pw.rows.opp:IsShown()) .. tostring(pw.pm.text) .. tostring(pw.opp.text) .. tostring(pw.cab[5].label.letters[1] and pw.cab[5].label.letters[1].text) .. tostring(pw.cab[1].name.text)') == "truetruetruetruetrueBramMiraG|cff8A7A5EVacant|r")  # no Cabinet named yet
check("Throne Room: Who holds power flows as the board does (Crown row, rule, Prime Minister, Cabinet plate)",
      E(ekk, PW_OPEN + 'return g.crownY == 46 and g.crownH == 36 and g.ruleY == 94 and g.flowY == 107 and g.cabH == 130 and g.cabY == g.flowY + 88') is True)
check("Throne Room: the Cabinet's name column is as wide as its longest label plus 14, and the rows are 23 apart",
      E(ekk, PW_OPEN + 'local w = 0 for i = 1, 5 do w = math.max(w, pw.cab[i].label:GetWidth()) end local ok = math.abs(g.colW - (w + 9.5 * 0.32)) < 0.01 and math.abs(g.nameX - (12 + g.colW + 14)) < 0.01 for i = 1, 5 do ok = ok and pw.cab[i].name.points[1][4] == g.nameX and pw.cab[i].name.points[1][5] == -(10 + (i - 1) * 23 + 9) end return ok') is True)
check("Throne Room: the Opposition is pinned to the bottom, its label on two lines as the board's wraps",
      E(ekk, PW_OPEN + 'return g.oppLines == 2 and g.oppH == 49 and g.oppY + g.oppH + 16 == pw.frame.h and g.oppY >= g.justicesY + g.justicesH') is True)
check("Throne Room: the row frames for the click overlays span each row (five Cabinet bands that add up to the plate)",
      E(ekk, PW_OPEN + 'local s, ok = 0, #pw.rows.cab == 5 for i = 1, 5 do ok = ok and pw.rows.cab[i]:IsShown() s = s + pw.rows.cab[i].h end return ok and s == g.cabH and pw.rows.crown.h == g.crownH and pw.rows.pm.h == 76 and pw.rows.justices.h >= 18 and pw.rows.opp.h == g.oppH') is True)
check("Throne Room: a Crown name that wraps to two lines pushes everything on by the board's 20",
      E(ekk, PW_OPEN + 'pw.crown.GetStringHeight = function() return 32 end P:Refresh() local ok = g.crownH == 56 and g.ruleY == 114 and g.flowY == 127 and g.cabY == 215 and g.cabH == 130 pw.crown.GetStringHeight = nil P:Refresh() return ok and g.crownH == 36') is True)
# /mota throne preview: a made-up government for drawing, never written
books = E(ek, 'return (M.Book:Count())')
heard = E(em, 'return (M.Book:Count())')
ek.slash("throne preview")
check("Throne preview: /mota throne preview shows a made-up government, tagged Preview",
      E(ek, PW_OPEN + 'return M.Throne:Power().preview == true and pw.previewTag:IsShown() and pw.gov:IsShown() and pw.pm.text == "Seraphine" and #M.Throne:Power().cabinet == 5') is True)
throne_draws(ek, "a preview")
run(6)
check("Throne preview: nothing is written or sent", E(ek, 'return (M.Book:Count())') == books and E(em, 'return (M.Book:Count())') == heard)
ek.slash("throne preview off")
check("Throne preview: off, the real government and no tag",
      E(ek, PW_OPEN + 'return M.Throne:Power().preview == nil and not pw.previewTag:IsShown() and pw.pm.text == "Bram"') is True)
check("Throne Room: the 48 hours show in What's on", E(ekk, TH + 'for _, e in ipairs(T:Live()) do if e.key == "bench" then return true end end return false') is True)
check("Throne Room: the Prime Minister's duty to name the Cabinet", E(eb, TH + 'for _, d in ipairs(T:Duties()) do if d.text:find("^Name the Cabinet") then return true end end return false') is True)
check("Throne Room: the result is among the decrees", E(ekk, TH + 'for _, d in ipairs(T:Decrees(5)) do if d.text:find("wins") then return true end end return false') is True)
throne_draws(eb, "governing")
check("Election: Justice isn't a party post: the Crown appoints it", E(eb, 'local _, e = M.Bench:Name("justice", "Bram") return #M.Bench.POSTS == 6 and e ~= nil') is True)
check("Election: no Snap Election from a citizen", E(eb, 'local _, e = El:CallSnap() return e ~= nil') is True)
check("Election: the Crown dissolves the government", E(ek, 'return El:CallSnap() ~= nil') is True)
run(1)
check("Election: a Snap Election is 14 days on", E(em, 'return math.floor((Co:PollAt() - GetServerTime()) / 86400 + 0.5)') == 14 and E(em, 'return Co:Kind()') == "Snap Election")
check("Election: a Snap Election has no leadership contests", E(em, 'return Co:Stage("sh")') == "none" and E(ek, 'local _, e = Co:Open() return e ~= nil') is True)
check("Election: the leaders carry on into it", E(em, 'return (Co:Banner("sh"))') == "Led by Bram")
check("Election: one election at a time", E(ek, 'local _, e = El:CallSnap() return e ~= nil') is True)
check("Election: the old government stays until the result", E(em, 'return El:Government().name') == "Bram")
E(ek, ballot % (901, "Snap Election", "snap", 1, 3, 2))
run(12)
check("Election: the snap's winner forms the new government", E(ekk, 'local g = El:Government() return g.name == "Mira" and g.p == "ex"') is True)
check("Election: and a new three-month term, with the cycle resumed", E(em, 'local g, c = El:Government(), Co:Current() return c.at == g.ends and c.kind == "general"') is True)
ek.lua.execute('MinistryOfTheAllied.PartiesPage:Refresh()')
eb.lua.execute('MinistryOfTheAllied.UI:Build(); MinistryOfTheAllied.UI:SelectPage(4); MinistryOfTheAllied.PartiesPage:Refresh()')
check("Election: the pages show it without errors", True)

print("== 15b. the Vote of No Confidence")
NC = 'local NC = MinistryOfTheAllied.Confidence '
need = E(eb, NC + 'return NC:Need()')
check("No confidence: the need is 40% of active citizens, without the Crown", need == -(-E(eb, NC + 'return NC:Electorate()') * 2 // 5) and need >= 2)
check("No confidence: the Crown can't vote", E(ek, NC + 'local _, e = NC:Vote() return e ~= nil') is True)
check("No confidence: a citizen's vote opens a motion", E(eb, NC + 'return NC:Vote() == true') is True)
run(8)
check("No confidence: the motion is open for everyone", E(ekk, NC + 'return NC:IsOpen()') is True)
check("No confidence: the count is public", E(ekk, NC + 'return NC:Motion().n') == 1)
check("No confidence: the voter has a King's receipt", E(eb, NC + 'local v = NC:MyVote() return v ~= nil and v.delivered == true') is True)
check("No confidence: only the King's copy holds the name", E(ek, 'for k, t in pairs(M.db.ncTally or {}) do if t.Bram then return true end end return false') is True
      and E(ekk, 'return next(M.db.ncTally or {}) == nil') is True)
check("No confidence: no second vote", E(eb, NC + 'local _, e = NC:Vote() return e ~= nil') is True)
check("No confidence: the Crown's desk shows it", "No confidence: 1 of" in E(ek, NC + 'return NC:Line()'))
check("Throne Room: a no-confidence vote shows in What's on, live", E(ekk, TH + 'for _, e in ipairs(T:Live()) do if e.key == "nc" then return e.live end end') is True)
throne_draws(ekk, "with a no-confidence vote")
voters = [c for c in (ekk, em) ]
for c in voters[:need - 1]:
    E(c, NC + 'NC:Vote() return 1')
    run(8)
check("No confidence: reaching the threshold brings the government down", E(ekk, NC + 'local m = NC:Motion() return m.result ~= nil and m.result.passed') is True)
check("No confidence: a Snap Election follows, 14 days on", E(ekk, 'return Co:Kind()') == "Snap Election" and E(ekk, 'return math.floor((Co:PollAt() - GetServerTime()) / 86400 + 0.5)') == 14)
check("No confidence: none while an election is under way", E(eb, NC + 'local _, e = NC:Vote() return e ~= nil') is True)
E(ek, ballot % (902, "Snap Election", "snap", 3, 1, 1))
run(12)
check("No confidence: the snap's winner governs", E(eb, 'return El:Government().name') == "Bram")
for c in (ek, eb, em, ekk):
    c.lua.execute('MinistryOfTheAllied.Confidence.WINDOW = 5')  # a short week, for the test
E(eb, NC + 'NC:Vote() return 1')
run(8)
check("No confidence: a new motion after a passed one", E(em, NC + 'return NC:Motion().seq') == 2)
run(4)
ek.lua.execute('MinistryOfTheAllied.Confidence.CheckClose()')
run(10)
check("No confidence: the week runs out and it fails", E(em, NC + 'local m = NC:Motion() return m.result ~= nil and m.result.passed == false') is True)
check("No confidence: a 30-day cooling period follows", E(ekk, NC + 'local _, e = NC:Vote() return e') is not None and "Charter 5.2" in E(ekk, NC + 'local _, e = NC:Vote() return e'))
check("No confidence: the government stays", E(em, 'return El:Government().name') == "Bram")
for c in (ek, eb, em, ekk):
    c.lua.execute('MinistryOfTheAllied.Confidence.WINDOW = 7 * 86400')

print("== 15c. the High Judiciary")
J = 'local J = MinistryOfTheAllied.Judiciary '
check("Judiciary: a citizen can't appoint", E(eb, J + 'local _, e = J:Appoint("Elowen") return e ~= nil') is True)
check("Judiciary: the Crown can't sit", E(ek, J + 'local _, e = J:Appoint("Aldric") return e ~= nil') is True)
check("Judiciary: an office holder can't sit", "another office" in E(ek, J + 'local _, e = J:Appoint("Bram") return e'))
for n in ("Elowen", "Kael", "Tobin"):
    E(ek, J + 'J:Appoint("%s") return 1' % n)
    run(1)
check("Judiciary: three Justices, seen by everyone", E(em, J + 'return #J:Justices()') == 3 and E(em, J + 'return J:IsJustice("Kael")') is True)
check("Judiciary: three seats only", E(ek, J + 'local _, e = J:Appoint("Wren") return e ~= nil') is True)
check("Judiciary: the term is six months", 180 <= E(em, J + 'local s = J:Justices()[1] return math.floor((s.ends - s.at) / 86400)') <= 185)
E(ek, J + 'J:Remove("Tobin") return 1')
run(1)
check("Judiciary: the Crown can remove a Justice", E(em, J + 'return J:IsJustice("Tobin")') is False and E(em, J + 'return #J:Justices()') == 2)
E(ekk, 'M.Book:Write("party.join", { p = "sh" }) return 1')
run(1)
E(ek, 'M.Book:Write("party.admit", { v = "Kael", p = "sh" }) return 1')
run(1)
check("Judiciary: a Justice can't be named to the front bench", "Justice" in E(eb, 'local _, e = M.Bench:Name("war", "Kael") return e'))
check("Judiciary: the Court page lists them", E(em, J + 'return J:Line()') == "The High Judiciary: Elowen and Kael.")
em.lua.execute('MinistryOfTheAllied.UI:Build(); MinistryOfTheAllied.UI:SelectPage(3); MinistryOfTheAllied.StatutesPage:Select("court")')
check("Judiciary: the Court view shows without errors", True)

print("== 15d. the Cabinet at work")
E(ek, J + 'J:Remove("Kael") return 1')
run(1)
check("Cabinet: before a War minister is named, there's none from the Cabinet", E(em, 'return M.Ring:Minister() == nil') is True)
E(eb, 'M.Bench:Name("war", "Kael") return 1')
run(1)
check("Cabinet: the Cabinet's Minister of War runs the Ring", E(em, 'return M.Ring:Minister()') == "Kael" and E(ekk, 'return M.Ring:CanSetTerms()') is True)
check("Cabinet: and nobody else", E(em, 'return M.Ring:CanSetTerms()') is False)
E(eb, 'M.Bench:Name("treasury", "Kael") return 1')
run(1)
check("Cabinet: the Minister of the Treasury is seen by everyone", E(em, 'return M.Ledger:Minister()') == "Kael")
check("Cabinet: they may fill in a general deposit's reason", E(em, 'return M.Ledger:CanFill("Kael", "tax")') is True)
check("Cabinet: but never party money", E(em, 'return M.Ledger:CanFill("Kael", "party_sh")') is False)
E(ekk, 'M.Bank:AskFor({ kind = "deposit", name = "Mira", amount = 500 }) return 1')
check("Cabinet: filling in party money is refused on their own screen", "Crown's to fill in" in E(ekk, 'local _, e = M.Bank:Answer("party_ex") return e'))
E(ekk, 'M.Bank:Answer("tax") return 1')
run(1)
check("Cabinet: a general reason they fill in reaches everyone", E(em, 'for n, r in pairs(M.guild.records.Kael or {}) do if r.k == "bank.fill" and r.d.r == "tax" then return true end end return false') is True)
check("Polling day: the Ballot Hall's form is filled in with the election and both leaders",
      E(ek, 'local f = MinistryOfTheAllied.BallotHall.ElectionForm() return f.kind == "general" and f.name:find("^General Election, ") ~= nil and f.cands[1].n == "Bram" and f.cands[2].n == "Mira"') is True)
E(ek, 'Co:Current().at = GetServerTime() - 1 return 1')  # as if polling day had come
check("Polling day: opening the polls is on the Crown's duties", E(ek, TH + 'for _, d in ipairs(T:Duties()) do if d.text:find("^Polling day") then return true end end return false') is True)
check("Polling day: not on a citizen's", E(eb, TH + 'for _, d in ipairs(T:Duties()) do if d.text:find("^Polling day") then return false end end return true') is True)

print("== 15e. one player, many characters")
set_online("Wren", True)
wren = Client("Wren", link=True, bnet="Wren#2231")
clients.append(wren)
run(6)
wkey = E(ek, 'return M.Account:Key("Wren")')
check("Accounts: a character links itself to its account at login", isinstance(wkey, str) and wkey.startswith("b"))
check("Accounts: the key is a hash, never the BattleTag itself", "Wren#2231" not in wkey and "wren" not in wkey.lower())
saved_w = logout(wren)
set_online("Oswin", True)
oswin = Client("Oswin", link=True, saved=saved_w.replace("Wren#2231", ""))  # same WoW account, same computer
clients.append(oswin)
run(6)
check("Accounts: with no BattleTag, alts on one computer share the saved account ID",
      E(ek, 'return M.Account:Key("Oswin")').startswith("a") and E(oswin, 'return M.Account:Key(M.me) == MOTADB.accountId and false or M.Account:Key(M.me)') == E(ek, 'return M.Account:Key("Oswin")'))
logout(oswin)
# Bram's alt Tobin, on the same Battle.net account (the same BattleTag on another computer).
active_before = E(ek, 'return El:CountActive()')
set_online("Tobin", True)
tobin = Client("Tobin", link=True, bnet="Bram#1111")
clients.append(tobin)
E(eb, 'M.Account.myKey = nil; BNGetInfo = function() return 1, "Bram#1111" end; M.Book:Write("acct.link", { h = M.Account:MyKey() }) return 1')
run(30)  # Tobin's copy catches up with the book
check("Accounts: two characters with one BattleTag are one player, on every copy",
      E(em, 'return M.Account:Same("Bram", "Tobin")') is True and E(ek, 'local a = M.Account:Alts("Tobin") return #a == 2 and a[1] .. "," .. a[2]') == "Bram,Tobin")
check("Accounts: the tooltip shows Tobin as Bram's alt", E(ek, 'return M:MainOf("Tobin")') == "Bram" and E(ek, 'return M:MainOf("Bram")') is None)
check("Accounts: active players count players, not characters", E(ek, 'return El:CountActive()') == active_before + 0)
check("Party: an alt shares the account's party", E(em, 'return M.Party:Of("Tobin")') == "sh" and E(tobin, 'return M.Party:Of(M.me)') == "sh")
check("Party: an alt can't ask to join the other party", E(tobin, 'return select(3, M.Party:JoinState("ex"))') is None
      and "Leave your party first" in E(tobin, 'return (M.Party:JoinState("ex"))'))
E(tobin, 'M.Book:Write("party.join", { p = "ex" }) return 1')
run(1)
E(ek, 'M.Book:Write("party.admit", { v = "Tobin", p = "ex" }) return 1')
run(1)
check("Party: the Crown's admit of an alt into a second party doesn't count", E(em, 'return M.Party:Of("Tobin")') == "sh" and "Tobin" not in [E(em, 'return M.Party:Members("ex")[%d]' % i) for i in range(1, 4)])
check("Party: the party's count is of players (Bram and Kael, not Tobin)", E(em, 'local m = M.Party:Members("sh") return #m == 2 and m[1] .. "," .. m[2]') == "Bram,Kael")
ek.log.clear()
ek.slash("alts")
check("Accounts: /mota alts shows the Crown who's one player", ek.said(r"Bram, Tobin"))
eb.log.clear()
eb.slash("alts")
check("Accounts: but not a citizen", eb.said(r"Only the Crown"))
# A ballot: one vote per player.
E(ek, 'local b = M.Ballot:Current() if b and M.Ballot:Stage(b) == "open" then M.Ballot:Close() end return 1')
run(1)
E(ek, 'M.Ballot:Open("Alt test", "general", { { n = "Bram", p = "sh" }, { n = "Mira", p = "ex" } }) return 1')
run(5)
check("Ballot: Bram votes", E(eb, 'return M.Ballot:Seal(1) ~= nil') is True)
run(3)
check("Ballot: Tobin is told his account has voted", "on this account" in (E(tobin, 'local _, e = M.Ballot:Seal(2) return e') or ""))
check("Ballot: and his state shows as sent", E(tobin, 'return M.Ballot:MyState(M.Ballot:Current())') == "sent")
check("Ballot: a second ballot from an alt is refused by the King", E(ek, 'return M.Ballot:Receive("Tobin", M.Ballot:Current().id, 2, "x")') == "dup")
check("Ballot: only one is counted", E(ek, 'local t = M.Ballot:Tally(M.Ballot:Current().id) return t.counts[1] .. "," .. t.counts[2]') == "1,0")
# Throne Room links, with a poll open
check("Throne Room links: with the polls open the banner plate opens the Ballot Hall", thr_click(eb, 'P.head.hot').startswith("2|"))
check("Throne Room links: and What's on opens the Ballot Hall", thr_click(eb, 'P.live.hot').startswith("2|"))
thr_audit(eb, "a poll open")

check("No confidence: a King's alt doesn't vote", E(ek, 'return M:IsCrownAccount("Max")') is True and E(em, 'return M:IsCrownAccount("Tobin")') is False)
logout(tobin)

print("== 15f. the games log and honours")
check("Cabinet: there's a Minister of Games post", E(ek, 'for _, p in ipairs(M.Bench.POSTS) do if p == "games" then return M.Bench.TITLES[p] end end') == "Games")
E(eb, 'M.Bench:Name("games", "Kael") return 1')
run(1)
check("Games: the government's Minister of Games is seen by everyone", E(em, 'return M.Games:Minister()') == "Kael")
ekk.slash("games result race Round the Lake: Bram, Mira, kael")
run(1)
check("Games: the Minister records a result, seen by everyone",
      E(em, 'local e = M.Games:Log()[1] return e and e.name .. "|" .. e.g .. "|" .. table.concat(e.places, ",")') == "Round the Lake|race|Bram,Mira,Kael")
check("Games: each place keeps its district, for the Cup", E(em, 'local e = M.Games:Log()[1] return #e.ds') == 3)
check("Games: a citizen can't record one", "Only the Crown" in E(em, 'local _, e = M.Games:Record("race", "x", { "Mira" }) return e'))
E(em, 'M.Book:Write("game.result", { g = "race", name = "Forged", places = { "Mira" } }) return 1')
run(1)
check("Games: a forged result is ignored by other copies", E(ek, 'return #M.Games:Log()') == 1)
check("Games: a name not in the guild is refused", "nobody called" in E(ek, 'local _, e = M.Games:Record("race", "x", { "Nobody" }) return e'))
check("Medals: the winner earns the Victor's Laurel", E(em, 'return M.Honours:Has("Bram", "laurel")') is True)
check("Medals: on all their characters", E(em, 'return M.Honours:Has("Tobin", "laurel")') is True)
check("Medals: second place earns none", E(ek, 'return M.Honours:Has("Mira", "laurel")') is False)
ek.slash("games result hunt The Lost Relic: Mira")
E(ek, 'M.Games:Record("lottery", "First Draw", { "Kael" }) return 1')
run(1)
check("Medals: the first to finish a hunt earns the Pathfinder's Medal", E(eb, 'return M.Honours:Has("Mira", "path")') is True)
check("Medals: a lottery is luck, and earns none", E(eb, 'return #M.Honours:Of("Kael")') == 0)
ekk.slash("games result race Again: Bram")
run(1)
check("Medals: won twice, counted twice", E(em, 'for _, h in ipairs(M.Honours:Of("Bram")) do if h.key == "laurel" then return h.n end end') == 2)
ek.slash("honour Bram, lion, Held the bridge at Southshore")
run(1)
check("Honours: the Crown confers an order, seen by everyone", E(em, 'return M.Honours:Letters("Bram")') == "OL" and E(em, 'return M:Styled("Bram")') == "Bram OL")
check("Honours: the citation is kept", E(em, 'for _, h in ipairs(M.Honours:Of("Bram")) do if h.key == "lion" then return h.why end end') == "Held the bridge at Southshore")
check("Honours: an order is held once", "already holds" in E(ek, 'local _, e = M.Honours:Award("Bram", "lion") return e'))
check("Honours: a citizen can't confer one", "Only the Crown" in E(eb, 'local _, e = M.Honours:Award("Mira", "star") return e'))
E(eb, 'M.Book:Write("honour.award", { v = "Bram", o = "crown" }) return 1')
run(1)
check("Honours: a forged award is ignored", E(ek, 'return M.Honours:Letters("Bram")') == "OL")
E(ek, 'M.Honours:Award("Bram", "KC") return 1')
run(1)
check("Honours: the letters follow highest first", E(em, 'return M.Honours:Letters("Bram")') == "KC, OL")
check("Honours: an alt carries them too", E(em, 'return M.Honours:Letters("Tobin")') == "KC, OL")
ek.slash("honour remove Bram, lion")
run(1)
check("Honours: the Crown can take one away", E(em, 'return M.Honours:Letters("Bram")') == "KC")
eb.log.clear()
eb.slash("honours")
check("Honours: /mota honours shows the Roll of Honour", eb.said(r"Bram KC . Knight of the Crown, Victor's Laurel ×2") and eb.said(r"Mira . Pathfinder's Medal"))
eb.slash("honours mira")
check("Honours: and one player's", eb.said(r"Pathfinder's Medal . "))
eb.slash("games")
check("Games: /mota games lists the log", eb.said(r"Round the Lake \(Race\) . 1st Bram, 2nd Mira, 3rd Kael"))
check("Throne Room: honours and results are among the decrees", E(eb, TH + 'for _, d in ipairs(T:Decrees(6)) do if d.text:find("Knight of the Crown") then return true end end return false') is True)
throne_draws(ek, "five Cabinet posts")
# Throne Room links, with a government and some decrees
thr_audit(eb, "governing")
thr_audit(ek, "the Crown")
thr_pm = E(eb, TH + 'return T:Power().pm.p')
thr_opp = E(eb, TH + 'return T:Power().opposition.p')
check("Throne Room links: the Prime Minister opens that party's page", thr_click(eb, 'P.power.links.pm') == "4|" + thr_pm)
check("Throne Room links: a Cabinet row opens that party's page", thr_click(eb, 'P.power.links.cab[1]') == "4|" + thr_pm)
check("Throne Room links: the Opposition opens the other party's page", thr_click(eb, 'P.power.links.opp') == "4|" + thr_opp and thr_pm != thr_opp)
check("Throne Room links: the Justices line opens the Court", thr_click(eb, 'P.power.links.justices') == "3|court")
check("Throne Room links: Your place opens the Districts map", thr_click(eb, 'P.place.meetHot') == "6|map")
check("Throne Room links: a party member's chip opens their party", thr_click(eb, 'P.place.partyHot') == "4|" + E(eb, 'return M.Party:Of(M.me)'))
check("Throne Room links: the honours decree opens the Honours", thr_click(eb, thr_row("decrees", "Knight of the Crown")) == "8|honours")
check("Throne Room links: the Crown's duties open the Crown's chamber or the page they name", E(ek, TH + 'local n = 0 for _, d in ipairs(T:Duties()) do if d.text:find("^Open the leadership") or d.text:find("^Ratify") or d.text:find("to join a party$") then n = n + 1 if d.page ~= 4 or d.view ~= "ch" then return false end end if d.text:find("High Judiciary") and (d.page ~= 3 or d.view ~= "court") then return false end end return true') is True)
check("Throne Room links: decrees carry the right pages",
      E(eb, TH + 'local want = { ["appointed a Justice"] = "3|court", ["Vote of No Confidence"] = "2|", ["is made"] = "8|honours" } local seen = 0 ' +
        'for _, d in ipairs(T:Decrees(200)) do for k, v in pairs(want) do if d.text:find(k) then seen = seen + 1 if tostring(d.page) .. "|" .. (d.view or "") ~= v then return false end end end end return seen >= 2') is True)
check("Throne Room links: a game result opens the Games Hall", E(eb, TH + 'for _, d in ipairs(T:Decrees(200)) do if d.text:find(" wins ") and not d.text:find("Election") and d.page == 8 then return d.view end end return "none"') in ("lottery", "hunt", "cup", "none"))


print("== 14b. the Chronicle")
CH = 'local C, T = MinistryOfTheAllied.Chronicle, MinistryOfTheAllied.Throne '
check("Chronicle: the Throne Room's decrees are the Chronicle's newest lines", E(ek, CH + 'local a, b = T:Decrees(6), C:All("all") if #a == 0 then return false end for i = 1, #a do if a[i].text ~= b[i].text or a[i].t ~= b[i].t then return false end end return true') is True)
check("Chronicle: months run newest first, and each month's lines too", E(ek, CH + 'local n = 0 local last for _, g in ipairs(C:Months("all")) do if last and g.key >= last then return false end last = g.key local lt for _, e in ipairs(g.lines) do n = n + 1 if lt and e.t > lt then return false end lt = e.t if date("%Y-%m", e.t) ~= g.key then return false end end end return n == C:Count("all") and n > 0') is True)
check("Chronicle: the filters split the lines between them", E(ek, CH + 'local n = 0 for _, f in ipairs(C.FILTERS) do if f.key ~= "all" then n = n + C:Count(f.key) end end return n == C:Count("all")') is True)
check("Chronicle: the Honours filter keeps only honours, and the knighthood is there", E(ek, CH + 'local found for _, e in ipairs(C:All("honours")) do if e.group ~= "honours" then return false end if e.text:find("Knight of the Crown") then found = true end end return found') is True)
check("Chronicle: a result sits under Elections", E(ek, CH + 'for _, e in ipairs(C:All("elections")) do if e.text:find("wins") then return true end end return false') is True)
check("Chronicle: laws and rulings have no record kinds, so a law record is not a line", E(ek, CH + 'return C:Line({ k = "statute.pass", t = 1, d = {} }) == nil and C:Line({ k = "court.ruling", t = 1, d = {} }) == nil') is True)
# More than 300 records of history: the feed's Book:Latest(300) would stop short, the Chronicle doesn't.
E(ek, CH + 'local list = {} M.guild.records["Zed-Realm"] = list for i = 1, 350 do list[i] = { t = GetServerTime() - 2 * 86400 - i * 86400 * 2, k = "ring.result", d = { s = 7, w = "Bram" } } end M:Fire("RECORD_ADDED", { a = "Zed-Realm", n = 0, t = 0, k = "chronicle.test", d = {} }) return 1')
check("Chronicle: it keeps more than 300 records of history", E(ek, CH + 'return C:Count("all") > 350 and C:Count("ring") == 350') is True)
check("Chronicle: that history spans many months, still newest first", E(ek, CH + 'local m = C:Months("all") local last for _, g in ipairs(m) do if last and g.key >= last then return false end last = g.key end return #m > 20') is True)
check("Chronicle: the feed still shows the same four newest lines", E(ek, CH + 'local a, b = T:Decrees(4), C:All("all") return #a == 4 and a[1].text == b[1].text and a[4].text == b[4].text') is True)
E(ek, CH + 'M.guild.records["Zed-Realm"] = nil M:Fire("RECORD_ADDED", { a = "Zed-Realm", n = 0, t = 0, k = "chronicle.test", d = {} }) return 1')
check("Chronicle: gone again, the count falls back", E(ek, CH + 'return C:Count("ring") < 5') is True)

def chronicle_draws(c, label):
    errs = len(errors)
    c.lua.execute('MinistryOfTheAllied.UI:Build(); MinistryOfTheAllied.UI.window:Show(); MinistryOfTheAllied.ThronePage:Open("chronicle")')
    for skin in ("crown", "silverhand", "exchange", "ministry"):
        c.lua.execute("MinistryOfTheAllied.Skin:Preview(\"%s\")" % skin)
        c.lua.execute('local P = MinistryOfTheAllied.ThronePage; for _, f in ipairs(MinistryOfTheAllied.Chronicle.FILTERS) do P:Filter(f.key) end P:Filter("all")')
    drawn = c.lua.eval("(function() local P = MinistryOfTheAllied.ThronePage return P.chronicle and P.chronicle.shown and not P.root.shown and P.chronicleHead.plateText.text ~= '' and P.chronicleMain.title.text ~= '' end)()")
    check("Chronicle: the page draws in all four skins, " + label, len(errors) == errs and drawn is True)
chronicle_draws(ek, "with the guild's history")
PG = 'local P, UI = MinistryOfTheAllied.ThronePage, MinistryOfTheAllied.UI '
check("Chronicle: the first row is the newest line, dated", E(ek, PG + 'local r = P.chronicleMain.rows[1] return r.shown and r.date.text ~= "" and r.text.text == MinistryOfTheAllied.Chronicle:All("all")[1].text') is True)
check("Chronicle: a row opens its page", E(ek, PG + 'for _, r in ipairs(P.chronicleMain.rows) do if r.shown and r.page then r.scripts.OnClick(r) return UI.page == r.page end end return false') is True)
check("Chronicle: the Throne tab lands on the State of the Realm", E(ek, PG + 'UI:SelectPage(1) return P.view == "state" and P.root.shown and not P.chronicle.shown') is True)
check("Chronicle: See all opens it", E(ek, PG + 'P.seeAll.scripts.OnClick(P.seeAll) return P.view == "chronicle" and P.chronicle.shown and not P.root.shown') is True)
check("Chronicle: the Throne Room button goes back", E(ek, PG + 'local b = P.chronicle.back b.scripts.OnClick(b) return P.view == "state" and P.root.shown and not P.chronicle.shown') is True)

# --- The Chronicle book on the Throne Room (UI/ChronicleBook.lua; Max, 10 Nov) ----------------------
BK = PG + 'local B = P.book '
def book_wait(c, seconds):  # runs the book's own clock (its OnUpdate) at 30 a second, leaving the game's clock alone
    E(c, BK + 'for _ = 1, %d do local f = B.scene.scripts.OnUpdate if f then f(B.scene, 1 / 30) end end return 1'
      % int(round(seconds * 30)))
def book_turning(c):  # the names of the turning pictures shown now, joined
    return E(c, BK + 'local n = {} for _, t in ipairs(B.turn) do if t.shown then n[#n + 1] = t.name end end return table.concat(n, ",")') or ""
E(ek, PG + 'UI:SelectPage(1) return 1')
errs = len(errors)
skins_ok = True
for skin in ("crown", "silverhand", "exchange", "ministry"):
    E(ek, 'M.Skin:Preview("%s") return 1' % skin)
    skins_ok = skins_ok and E(ek, BK + 'return B.state == "closed" and B.base.shown and B.base.name == "chronicle_%s:base" and B.turn[1].name == "chronicle_%s:cover000"' % (skin, skin)) is True
check("Chronicle book: drawn closed in all four skins, the skin's own leather", skins_ok and len(errors) == errs)
check("Chronicle book: the plate has no count at its top right (it is the Statute Book now)",
      E(ek, BK + 'return B.count == nil') is True)
check("Chronicle book: right column top to bottom is What's on, the book, Your duties, Recent decrees",
      E(ek, BK + 'local function y(f) local _, _, _, _, v = f:GetPoint() return -v end '
            'local l, b, d, r = P.live.frame, B.plate, P.duties.frame, P.decrees.frame '
            'return y(l) == 0 and y(b) == y(l) + l.h + 10 and y(d) == y(b) + b.h + 10 and y(r) == y(d) + d.h + 10') is True)
check("Chronicle book: Your place is in the left column right under Who holds power, nothing stretched",
      E(ek, BK + 'local function y(f) local _, _, _, x, v = f:GetPoint() return -v, x end '
            'local pl, pw = P.place.frame, P.power.frame local py, px = y(pl) local wy = y(pw) '
            'return px == 0 and py == wy + pw.h + 10 and pl.w == pw.w') is True)
check("Chronicle book: the page's height is its tallest column, so nothing is cut off or left empty",
      E(ek, BK + 'local function y(f) local _, _, _, _, v = f:GetPoint() return -v end '
            'local r, pl, body = P.decrees.frame, P.place.frame, P.scroll.scrollChild '
            'return body.h == math.max(P.scroll.h, y(r) + r.h, y(pl) + pl.h)') is True)
E(ek, BK + 'B.hit.scripts.OnEnter(B.hit) return 1')
book_wait(ek, 0.5)
check("Chronicle book: hovering lifts the cover, with light at the page edge",
      E(ek, BK + 'return B.lift > 0.99 and B.leak.shown') is True and book_turning(ek).endswith("cover012"))
check("Chronicle book: its tooltip says a click opens it", E(ek, 'return GameTooltip.text') == "Statute Book · click to open the book")
E(ek, BK + 'B.hit.scripts.OnLeave(B.hit) return 1')
book_wait(ek, 0.5)
check("Chronicle book: leaving lowers the cover, and its clock stops when still",
      E(ek, BK + 'return B.lift == 0 and not B.leak.shown and B.scene.scripts.OnUpdate == nil') is True and book_turning(ek).endswith("cover000"))
E(ek, BK + 'B.hit.scripts.OnEnter(B.hit) LAST_SOUND = nil BOOK_SOUNDS = SOUNDS_PLAYED B.hit.scripts.OnClick(B.hit) return 1')
check("Chronicle book: a click opens it, with the game's page-turn sound and a holy sound",
      E(ek, BK + 'return B.state == "opening" and SOUNDS_PLAYED == BOOK_SOUNDS + 2 and LAST_SOUND == 171877') is True)
book_wait(ek, 0.25)
cover = book_turning(ek)
check("Chronicle book: the cover is flung open, past its lift", "cover" in cover and int(cover.split("cover")[-1][:3]) > 12)
check("Chronicle book: the light bursts: rays, the closed book's aura, and a shockwave ring early on",
      E(ek, BK + 'return B.raysA.shown and B.bloomClosed.shown and B.ring.shown and B.flare.shown') is True)
book_wait(ek, 0.5)
seen = book_turning(ek)
check("Chronicle book: the pages hang in a fan, all nine up",
      seen.count(":page") == 9 and "cover" not in seen)
check("Chronicle book: in the light: rays, the shaft from above, the aura, the glow, motes flung out",
      E(ek, BK + 'local n = 0 for _, m in ipairs(B.motes) do if m.on then n = n + 1 end end '
            'return B.raysA.shown and B.shaft.shown and B.bloom.shown and B.glow.shown and B.halo.shown and n > 20') is True)
check("Chronicle book: the shockwave ring is gone after 0.75 s", E(ek, BK + 'return not B.ring.shown') is True)
book_wait(ek, 0.6)
check("Chronicle book: then the pages fall, one after another", 0 < book_turning(ek).count(":page") < 9)
book_wait(ek, 0.8)
check("Chronicle book: it comes to rest open, the closed book gone, nothing turning",
      E(ek, BK + 'return B.state == "open" and B.open.shown and B.pages.shown and B.ribbons.shown and not B.base.shown') is True and book_turning(ek) == "")
check("Chronicle book: the open page says how much the Chronicle holds",
      re.match(r"^\d+ entr(y|ies) since \d+ [A-Z][a-z]+$", E(ek, BK + 'return B.live.shown and B.live.text') or "") is not None)
book_wait(ek, 2)
check("Chronicle book: open, a few motes keep rising", E(ek, BK + 'local n = 0 for _, m in ipairs(B.motes) do if m.on then n = n + 1 end end return n > 0 and B.scene.scripts.OnUpdate ~= nil') is True)
check("Chronicle book: open, the steady light keeps inside the plate's width",
      E(ek, BK + 'for _, k in ipairs({ "halo", "raysA", "raysB", "shaft", "beam", "shaftFront", "haloFront" }) do '
            'if B[k].shown and B[k]:GetWidth() > B.w then return k end end return B.raysA.shown or B.raysB.shown') is True)
spin = E(ek, BK + 'return B.raysA.name .. "," .. B.raysB.name')
book_wait(ek, 2.5)
check("Chronicle book: open, its rays keep turning", E(ek, BK + 'return B.raysA.name .. "," .. B.raysB.name') != spin)
check("Chronicle book: the cursor still on it, the tooltip returns when the opening ends",
      E(ek, BK + 'B:Reset() B.hit.scripts.OnEnter(B.hit) B.hit.scripts.OnClick(B.hit) GameTooltip.text = nil '
            'for _ = 1, 90 do local f = B.scene.scripts.OnUpdate if f then f(B.scene, 1 / 30) end end return B.state == "open" and GameTooltip.text') == "Opens Statute Book · Charter")
check("Chronicle book: its tooltip now says it opens the Statute Book Charter",
      E(ek, BK + 'B.hit.scripts.OnLeave(B.hit) B.hit.scripts.OnEnter(B.hit) return GameTooltip.text') == "Opens Statute Book · Charter")
check("Chronicle book: a click on the open book opens the Charter on the Statute Book tab",
      E(ek, BK + 'B.hit.scripts.OnClick(B.hit) local o = M.StatutesPage return UI.page == 3 and o:View() == "charter" and not P.root.shown') is True)
check("Chronicle book: back in the Throne Room it's closed again",
      E(ek, BK + 'UI:SelectPage(1) return P.root.shown and B.state == "closed" and B.base.shown and not B.open.shown') is True)
E(ek, BK + 'B.hit.scripts.OnClick(B.hit) return 1')
book_wait(ek, 0.2)
check("Chronicle book: a click while it turns goes straight to the open book",
      E(ek, BK + 'B.hit.scripts.OnClick(B.hit) return B.state == "open" and B.open.shown and not B.base.shown') is True and book_turning(ek) == "")
check("Chronicle book: another page and back, closed again",
      E(ek, BK + 'UI:SelectPage(2) UI:SelectPage(1) return B.state == "closed" and B.lift == 0 and B.base.shown') is True)

# The game draws what the previews Max okayed show: every layer of the opening (its picture, strength and
# size) against tools/textures/chronicle.py's state() at the same moments.
sys.path.insert(0, os.path.join(HERE, "..", "textures"))
import chronicle as CHR  # noqa: E402
BOOK_KEYS = {"halo": "halo", "shaft": "shaft", "bloomClosed": "bloomClosed", "bloom": "bloom", "base": "base",
             "leak": "leak", "open": "open", "pages": "pages", "ribbons": "ribbons", "glowOpen": "glow", "beam": "beam",
             "shaftFront": "shaftFront", "haloFront": "haloFront", "ring": "ring", "flare": "flare"}
def book_layers(c):  # {key: (picture, alpha, w, h) or None}, and the turning pictures in draw order
    got = E(c, BK + 'local o = {} for _, k in ipairs({ "halo", "raysA", "raysB", "shaft", "bloomClosed", "bloom", "base", '
                 '"leak", "open", "pages", "ribbons", "glow", "beam", "shaftFront", "haloFront", "ring", "flare" }) do '
                 'local t = B[k] o[#o + 1] = k .. "=" .. (t.shown and (t.name .. "," .. (t.alpha or 1) .. "," .. t.w .. "," .. t.h) or "-") end '
                 'local n = {} for _, t in ipairs(B.turn) do if t.shown then n[#n + 1] = t.name .. "," .. t.alpha end end '
                 'o[#o + 1] = "turn=" .. table.concat(n, "|") return table.concat(o, ";")')
    out = {}
    for item in got.split(";"):
        k, v = item.split("=", 1)
        if k == "turn":
            out[k] = [(n.split(":")[-1].split(",")[0], float(n.split(",")[1])) for n in v.split("|") if n]
        else:
            out[k] = None if v == "-" else (v.split(",")[0].split(":")[-1],) + tuple(float(x) for x in v.split(",")[1:])
    return out
def book_expected(t):
    media = {"cover": CHR.COVER_REST + CHR.COVER_TURN, "rest": CHR.COVER_REST[-1], "page": CHR.PAGE_TURN, "rays": CHR.RAY_STEPS}
    _, layers = CHR.state(t, 1, CHR.TIMING, media, spin=t, hover=True)
    place, want, turn, rays = CHR.TIMING["place"], {}, [], []
    for layer in layers:
        part, alpha = layer[0], min(1, layer[1])
        grow = layer[3] if len(layer) > 3 else 1
        if re.fullmatch(r"(cover|page)\d{3}", part):
            turn.append((part, alpha))
        elif part.startswith("rays"):
            rays.append((part, alpha, place["rays"]["w"] * grow, place["rays"]["h"] * grow))
        elif part in BOOK_KEYS:
            light = "shaft" if part == "shaftFront" else part
            size = (place[light]["w"] * grow, place[light]["h"] * grow) if light in place else None
            image = {"shaftFront": "shaft", "haloFront": "halo", "glowOpen": "glowOpen"}.get(part, part)
            want[BOOK_KEYS[part]] = (image, alpha) + (size or ())
    want["raysA"], want["raysB"] = rays
    return want, [x for x in turn if x[1] > 0.003]
def book_matches(c, t):
    got, (want, turn) = book_layers(c), book_expected(t)
    bad = []
    for k, w in want.items():
        g = got[k]
        if w[1] <= 0.003:
            if g is not None:
                bad.append(k + " shown")
        elif g is None or g[0] != w[0] or abs(g[1] - w[1]) > 0.002 or any(abs(a - b) > 0.05 for a, b in zip(g[2:], w[2:]) if len(w) > 2):
            bad.append("%s %s, wanted %s" % (k, g, w))
    if [n for n, _ in got["turn"]] != [n for n, _ in turn] or any(abs(a - b) > 0.002 for (_, a), (_, b) in zip(got["turn"], turn)):
        bad.append("turning %s, wanted %s" % (got["turn"], turn))
    if bad:
        print("    at %.3f s: %s" % (t, "; ".join(bad)))
    return not bad
E(ek, BK + 'B.hit.scripts.OnEnter(B.hit) B.hit.scripts.OnClick(B.hit) return 1')
mirror, done = True, 0
for k in (4, 7, 11, 16, 20, 25, 33, 40, 48, 55, 60):   # frames at 30 a second (off the timeline's edges)
    E(ek, BK + 'for _ = 1, %d do B.scene.scripts.OnUpdate(B.scene, 1 / 30) end return 1' % (k - done))
    done = k
    mirror = book_matches(ek, k / 30) and mirror
check("Chronicle book: the game draws what chronicle.py's previews show, layer by layer, through the opening", mirror)
E(ek, BK + 'B.hit.scripts.OnLeave(B.hit) B:Reset() return 1')
check("Chronicle book: no Lua errors in all that", len(errors) == errs)
E(ek, 'MinistryOfTheAllied.UI.window:Hide() return 1')
check("Tooltip: an honoured name shows its letters", E(ek, 'local seal = MinistryOfTheAlliedMinimapButton; seal.scripts.OnEnter(seal); seal.scripts.OnLeave(seal) for _, s in ipairs(M.OnlineTip.state.sections) do for _, n in ipairs(s.names) do if n:find("^Bram |cffC9A24AKC") then return true end end end return false') is True)

print("== 15g. the Royal Lottery")
def jump(seconds):
    """Every copy's server clock moves on, without running the timers in between."""
    for c in clients:
        c.lua.globals().CLOCK_START = (c.lua.globals().CLOCK_START or 0) + seconds
LO = 'local Lo = M.Lottery '
def deposit(c, gold, reason="lottery"):
    E(c, 'M.Book:Write("bank.move", { io = "d", amt = %d, r = "%s", at = GetServerTime() }) return 1' % (int(gold * 10000), reason))
check("Lottery: a citizen can't open one", "Only the Crown" in E(em, LO + 'local _, e = Lo:Open("x", 1, 3) return e'))
ekk.slash("lottery open Spring Draw, 1, 3")
run(1)
check("Lottery: the Minister of Games opens one, seen by everyone",
      E(em, LO + 'local L = Lo:Current() return L.name .. "|" .. L.price .. "|" .. Lo:Stage()') == "Spring Draw|10000|selling")
check("Lottery: only the secret's hash is published", E(em, LO + 'local L = Lo:Current() return #L.c == 64 and M.guild.records.Kael ~= nil') is True
      and E(ekk, LO + 'return MOTADB.lotterySecrets[Lo:Current().id] ~= nil') is True and E(em, 'return MOTADB.lotterySecrets == nil') is True)
check("Lottery: only one at a time", "already under way" in E(ek, LO + 'local _, e = Lo:Open("Two", 1, 3) return e'))
check("Lottery: the bank prompt offers Lottery tickets", E(em, 'for _, r in ipairs(M.BankPrompt.REASONS.d) do if r[1] == "lottery" then return r[2] end end') == "Lottery tickets")
em.log.clear()
deposit(em, 2.5)
deposit(eb, 1)
deposit(eb, 0.5)
deposit(ekk, 3)
run(1)
check("Lottery: each whole ticket price buys a ticket", E(ek, LO + 'return Lo:TicketsOf("Mira") .. "," .. Lo:TicketsOf("Bram")') == "2,1")
check("Lottery: the buyer is told", em.said(r"You bought 2 tickets in Spring Draw"))
check("Lottery: the organiser can't buy tickets in their own draw", E(ek, LO + 'return Lo:TicketsOf("Kael")') == 0 and ekk.said(r"you can't buy tickets in it"))
check("Lottery: the pot and the split", E(eb, LO + 'local L = Lo:Current() return L.pot .. "," .. L.prize .. "," .. L.treasury') == "30000,21000,9000")
check("Throne Room: the lottery shows in What's on", E(em, TH + 'for _, e in ipairs(T:Live()) do if e.key == "lottery" then return e.line end end').endswith("you hold 2"))
check("Lottery: no draw before sales close", "still open" in E(ekk, LO + 'local _, e = Lo:Draw() return e'))
jump(3 * 86400 + 60)
deposit(em, 1)
run(1)
check("Lottery: gold after the close buys nothing", E(ek, LO + 'return Lo:TicketsOf("Mira") .. "|" .. Lo:Stage()') == "2|closed")
check("Throne Room: the organiser is told to draw", E(ekk, TH + 'for _, d in ipairs(T:Duties()) do if d.text:find("^Draw Spring Draw") then return true end end return false') is True)
check("Lottery: another can't draw it before the week's out", "draws it" in E(ek, LO + 'local _, e = Lo:Draw() return e'))
ekk.slash("lottery draw")
run(2)
winner = E(ek, LO + 'return Lo:Current().winner')
check("Lottery: drawn, every copy finds the same winner", winner in ("Mira", "Bram") and E(em, LO + 'return Lo:Current().winner') == winner and E(eb, LO + 'return Lo:Current().winner') == winner)
check("Lottery: every ticket wins about as often (7 tickets, 7000 draws)",
      E(em, LO + 'local t = {} for i = 1, 7 do t[i] = { who = "P" .. i } end local w = {0,0,0,0,0,0,0} for i = 1, 7000 do local x = Lo:Pick("s" .. i, t) w[x] = w[x] + 1 end local lo, hi = 7000, 0 for i = 1, 7 do lo, hi = math.min(lo, w[i]), math.max(hi, w[i]) end return lo > 880 and hi < 1120') is True)
check("Lottery: the hash is SHA-256", E(em, 'return M.Sha256("abc")') == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
check("Lottery: anyone can check the draw from the secret and the tickets",
      E(em, LO + 'local L = Lo:Current() return M.Sha256(L.drawn.s) == L.c and Lo:Pick(L.drawn.s, L.tickets) == L.win') is True)
check("Lottery: the result goes into the games log, without a medal", E(em, 'local e = M.Games:Log()[1] return e.g .. "|" .. e.places[1]') == "lottery|" + winner
      and E(ek, 'return M.Honours:Has("%s", "laurel")' % winner) is (winner == "Bram"))  # Bram won races before
check("Lottery: the prize is owed, as a duty", E(ekk, LO + 'return Lo:Owed()') == 21000
      and E(ekk, TH + 'for _, d in ipairs(T:Duties()) do if d.text:find("lottery prize") then return true end end return false') is True)
E(ekk, 'M.Book:Write("bank.move", { io = "w", amt = 21000, r = "lottery_prize", at = GetServerTime() }) return 1')
run(1)
check("Lottery: once paid, nothing's owed", E(em, LO + 'return Lo:Owed()') == 0 and "paid" in E(em, LO + 'return Lo:Line()'))
E(ekk, 'M.Lottery:Open("Second Draw", 0.5, 1) return 1')
run(1)
jump(86400 + 60)
E(em, 'M.Book:Write("lottery.draw", { id = M.Lottery:Current().id, s = "guess" }) return 1')
run(1)
check("Lottery: a draw with the wrong secret, or by someone else, doesn't count", E(ek, LO + 'return Lo:Stage()') == "closed")
jump(7 * 86400)
check("Lottery: a week after the close, the Crown may draw without the secret", E(ek, LO + 'return Lo:Draw() ~= nil') is True)
run(1)
check("Lottery: drawn with no tickets sold", E(em, LO + 'return Lo:Stage() .. "|" .. tostring(Lo:Current().winner)') == "drawn|nil")

print("== 15h. the Games Hall page")
def games_draws(c, label):
    errs = len(errors)
    c.lua.execute('MinistryOfTheAllied.UI:Build(); MinistryOfTheAllied.UI.window:Show(); MinistryOfTheAllied.UI:SelectPage(8)')
    seen = []
    for skin in ("crown", "silverhand", "exchange", "ministry"):
        c.lua.execute("MinistryOfTheAllied.Skin:Preview(\"%s\")" % skin)
        for v in ("lottery", "hunt", "hide", "cup", "honours"):
            c.lua.execute('MinistryOfTheAllied.GamesPage:Select("%s")' % v)
        seen.append(c.lua.eval('MinistryOfTheAllied.GamesPage:View()'))
    check("Games Hall: draws in all four skins and every view, " + label, len(errors) == errs and seen == ["honours"] * 4)
check("Games Hall: it's the eighth tab", E(eb, 'return #M.Media.pages .. "|" .. M.Media.pages[8].label') == "8|Games Hall")
check("Games Hall: its ribbons and medallions were drawn", E(eb, 'return M.Media.pieces.kitRibbonOn17 ~= nil and M.Media.pieces["kitRibbonOn14~cr"] ~= nil and M.Media.pieces["kitRibbonOn14~ex"] ~= nil and M.Media.pieces.kitMedalG ~= nil') is True)
games_draws(eb, "for a citizen")
games_draws(ekk, "for the Minister of Games")
E(ekk, 'M.GamesPage:Select("lottery") return 1')
check("Games Hall: the organiser's desk shows for the Minister", E(ekk, 'return M.GamesPage ~= nil') is True)
E(eb, 'M.GamesPage:Select("honours") M.GamesPage:Refresh() return 1')
check("Throne Room: the lottery opens the Games Hall", E(eb, TH + 'for _, e in ipairs(T:Live()) do if e.key == "lottery" then return e.page end end return 8') == 8)

print("== 15i. cancelling a lottery")
E(ekk, 'M.Lottery:Open("Third Draw", 1, 2) return 1')
run(1)
deposit(em, 2)
deposit(eb, 1)
run(1)
check("Cancel: a citizen can't cancel", "Only Kael" in E(em, LO + 'local _, e = Lo:Cancel() return e'))
ek.slash("lottery cancel")
run(1)
check("Cancel: the Crown cancels, seen by everyone", E(em, LO + 'return Lo:Stage()') == "cancelled" and E(eb, LO + 'return Lo:Stage()') == "cancelled")
check("Cancel: every ticket is owed back, per player",
      E(eb, LO + 'local r = Lo:Refunds() return r[1].name .. "=" .. r[1].amt .. "," .. r[2].name .. "=" .. r[2].amt') == "Mira=20000,Bram=10000"
      and E(eb, LO + 'return Lo:Owed()') == 30000)
deposit(em, 1)
run(1)
check("Cancel: gold after the cancel buys nothing", E(ek, LO + 'return Lo:TicketsOf("Mira")') == 2)
check("Cancel: a cancelled lottery can't be drawn", "no lottery waiting" in E(ekk, LO + 'local _, e = Lo:Draw() return e'))
check("Cancel: refunds are a duty for the organiser", E(ekk, TH + 'for _, d in ipairs(T:Duties()) do if d.text:find("^Refund the cancelled Third Draw") then return true end end return false') is True)
check("Cancel: the bank's payout reason is Lottery payout", E(em, 'return M.BankPrompt:LabelFor("w", "lottery_prize")') == "Lottery payout")
E(ekk, 'M.Book:Write("bank.move", { io = "w", amt = 30000, r = "lottery_prize", at = GetServerTime() }) return 1')
run(1)
check("Cancel: once paid back, nothing's owed", E(em, LO + 'return Lo:Owed()') == 0 and "everyone refunded" in E(em, LO + 'return Lo:Line()'))
games_draws(ekk, "with a cancelled lottery")
check("Cancel: a new lottery can be opened after", E(ekk, LO + 'return Lo:Open("Fourth Draw", 1, 2) ~= nil') is True)
run(1)
check("Cancel: the organiser may cancel their own", E(ekk, LO + 'return Lo:Cancel() ~= nil') is True)
run(1)
check("Cancel: with no tickets, nothing is owed", E(em, LO + 'return Lo:Stage() .. "|" .. Lo:Owed()') == "cancelled|0")

print("== 15j. the Treasure Hunt")
HU = 'local Hu = M.Hunt '
def stand(c, x, y, zone="Elwynn Forest", inst=0):
    c.lua.execute('POS = { x = %f, y = %f, inst = %d }; ZONE = "%s"' % (x, y, inst, zone))
def indoors(c):
    c.lua.execute('POS = nil')
check("Hunt: a citizen can't mark a spot", "Only the Crown" in E(em, HU + 'local _, e = Hu:Mark("x") return e'))
indoors(ekk)
check("Hunt: no spot can be marked indoors", "outdoors" in E(ekk, HU + 'local _, e = Hu:Mark("A riddle") return e'))
stand(ekk, 100, 200, "Goldshire")
check("Hunt: a spot needs its riddle", "riddle" in E(ekk, HU + 'local _, e = Hu:Mark("") return e'))
E(ekk, HU + 'Hu:Mark("Where the lion sleeps by the inn") return 1')
stand(ekk, 300, 200)
E(ekk, HU + 'Hu:Mark("The old wheel turns though no grain comes") return 1')
stand(ekk, 500, 260, "Stormwind City")
E(ekk, HU + 'Hu:Mark("Beneath the gaze of the gate guards") return 1')
check("Hunt: the organiser marks three spots", E(ekk, HU + 'return #Hu:Draft().clues') == 3)
check("Hunt: Publish needs a name, or takes the default", E(ekk, HU + 'return Hu:Publish("The Millers Secret") ~= nil') is True)
run(1)
check("Hunt: everyone sees the hunt", E(em, HU + 'local H = Hu:Current() return H.name .. "|" .. #H.clues .. "|" .. Hu:Stage()') == "The Millers Secret|3|running")
check("Hunt: the first riddle is open, with its zone", E(em, HU + 'local t, z = Hu:Riddle(1) return t .. "|" .. z') == "Where the lion sleeps by the inn|Goldshire")
check("Hunt: later riddles show only once the spot before is found", E(em, HU + 'return Hu:Riddle(2) == nil') is True)
check("Hunt: each spot is kept to a tenth of a yard", E(em, HU + 'local c = Hu:Current().clues[2] return c.x .. "," .. c.y .. "," .. c.inst') == "300,200,0")
check("Hunt: the draft is cleared, the organiser keeps the riddles", E(ekk, HU + 'return #Hu:Draft().clues .. "|" .. tostring((Hu:Riddle(3)))') == "0|Beneath the gaze of the gate guards")
em.lua.execute("local H = MinistryOfTheAllied.Herald; local o = H.Announce; HSEEN = {}; H.Announce = function(self, h, ...) HSEEN[#HSEEN + 1] = h.title; return o(self, h, ...) end; EMOTES = {}; DoEmote = function(e) EMOTES[#EMOTES + 1] = e end")
heard = lambda c, title: c.lua.eval('(function() local n = 0 for _, t in ipairs(HSEEN) do if t == "%s" then n = n + 1 end end return n end)()' % title)
GL = 'local G = M.HuntGlow '
stand(em, 170, 200)
check("Hunt: far away, nothing, and no glow", E(em, HU + 'return Hu:Look()') is None and E(em, GL + 'return G.target') == 0)
em.log.clear()
stand(em, 145, 205)
check("Hunt: within 50 yards, warm", E(em, HU + 'return Hu:Look()') == "warm")
check("Hunt: chat says how far", em.said(r"Warmer: clue 1 is about 50 yards away"))
faint = E(em, GL + 'return G.target')
stand(em, 125, 205)
E(em, HU + 'Hu:Look() return 1')
check("Hunt: every 10 yards nearer, another line", em.said(r"Warmer: clue 1 is about 30 yards away"))
check("Hunt: the glow grows as you near it", E(em, GL + 'return G.target') > faint > 0)
check("Hunt: it starts strong, at 50 yards", faint > 0.55)
check("Hunt: no heralds for warmer or colder", heard(em, "You're getting warmer") == 0 and heard(em, "You're getting colder") == 0)
E(em, GL + 'G.now = 0 for _ = 1, 40 do G:Step(0.1) end return 1')
check("Hunt: the glow fades in, steady, with no pulse", E(em, GL + 'return G.now') > 0.5 and E(em, GL + 'for _ = 1, 60 do G:Step(0.1) end local a = G:Step(0.1) local b = G:Step(0.15) return math.abs(a - b) < 0.001') is True)
E(em, GL + 'UnitAffectingCombat = function() return true end for _ = 1, 40 do G:Step(0.1) end return 1')
check("Hunt: in combat the glow goes out", E(em, GL + 'return G.now') < 0.05)
E(em, GL + 'UnitAffectingCombat = function() return false end return 1')
em.log.clear()
stand(em, 165, 205)
E(em, HU + 'Hu:Look() return 1')
check("Hunt: leaving the 50 yards, colder, and the glow goes", em.said(r"Colder: you've left the 50 yards round clue 1") and E(em, GL + 'return G.target') == 0)
em.slash("hunt glow")
stand(em, 125, 205)
E(em, HU + 'Hu:Look() return 1')
check("Hunt: with the glow off, chat still tells you", E(em, GL + 'return G.target') == 0 and em.said(r"Warmer: clue 1 is about 30 yards away"))
em.slash("hunt glow")
stand(em, 500, 260, "Stormwind City")
check("Hunt: a later spot doesn't count before its turn", E(em, HU + 'return Hu:Look()') is None)
stand(em, 111, 202)
check("Hunt: 11 yards off, not yet", E(em, HU + 'return Hu:Look()') == "warm")
stand(em, 108, 199)
check("Hunt: on the spot, it's found", E(em, HU + 'return Hu:Look()') == "found")
check("Hunt: and you cheer", em.lua.eval("EMOTES[1]") == "CHEER")
run(1)
check("Hunt: the next riddle opens for the finder", E(em, HU + 'return (Hu:Riddle(2))') == "The old wheel turns though no grain comes")
check("Hunt: their progress reaches everyone", E(eb, HU + 'return Hu:Progress("Mira")') == 1 and E(eb, HU + 'return Hu:Riddle(2) == nil') is True)
stand(ekk, 100, 200, "Goldshire")
check("Hunt: the organiser can't play their own hunt", E(ekk, HU + 'return Hu:Look()') is None and E(ekk, HU + 'return Hu:Progress("Kael")') == 0)
stand(eb, 101, 201, "Goldshire")
E(eb, HU + 'Hu:Look() return 1')
run(1)
check("Hunt: the hunters, furthest first", E(ek, HU + 'local h = Hu:Hunters() return h[1].name .. h[1].n .. "," .. h[2].name .. h[2].n') == "Mira1,Bram1")
stand(em, 302, 199)
E(em, HU + 'Hu:Look() return 1')
run(1)
stand(em, 498, 261, "Stormwind City")
check("Hunt: the last spot wins", E(em, HU + 'return Hu:Look()') == "found")
run(2)
check("Hunt: won, and closed for everyone", E(eb, HU + 'return Hu:Stage() .. "|" .. Hu:Current().winner') == "won|Mira")
check("Hunt: the result goes into the games log, from the organiser", E(ek, 'local e = M.Games:Log()[1] return e.g .. "|" .. e.name .. "|" .. e.places[1] .. "|" .. tostring(e.places[2])') == "hunt|The Millers Secret|Mira|Bram")
check("Hunt: the winner holds the Pathfinder's Medal", E(ek, 'return M.Honours:Has("Mira", "path")') is True)
stand(eb, 302, 199)
check("Hunt: after the win, no more finds", E(eb, HU + 'return Hu:Look()') is None)
games_draws(ekk, "while setting a hunt")
games_draws(em, "with a hunt won")
check("Hunt: the organiser's form shows when no hunt runs", E(ekk, 'M.GamesPage:Select("hunt") return M.Hunt:Stage() ~= "running" and M.Games:CanRun(M.me)') is True)
stand(ekk, 50, 50)
E(ekk, HU + 'Hu:Mark("One") return 1')
stand(ekk, 90, 50)
E(ekk, HU + 'Hu:Mark("Two") return 1')
E(ekk, HU + 'Hu:Publish("Short Hunt") return 1')
run(1)
games_draws(em, "with a hunt running")
late = Client("Wren")
late.lua.execute("local H = MinistryOfTheAllied.Herald; local o = H.Announce; SEEN = {}; H.Announce = function(self, h, ...) SEEN[#SEEN + 1] = h.title; return o(self, h, ...) end")
clients.append(late)
set_online("Wren", True)
run(150)  # a big book to catch up on by now
seen = lambda: late.lua.eval('(function() local n = 0 for _, t in ipairs(SEEN) do if t:find(" is on$") then n = n + 1 end end return n end)()')
check("Hunt: someone logging in while a hunt runs is told of it", seen() == 1)
E(late, HU + 'Hu:Remind() return 1')
check("Hunt: once a session", seen() == 1)
clients.remove(late)
set_online("Wren", False)
check("Hunt: a citizen can't end a hunt", "Only Kael" in E(em, HU + 'local _, e = Hu:Close() return e'))
ek.slash("hunt end")
run(10)
check("Hunt: the Crown ends it with no winner", E(em, HU + 'return Hu:Stage()') == "closed")

print("== 103. the map skin beside other map add-ons (D5d, D5d2, D5e)")
# Pretend EllesmereUI, ElvUI and Leatrix Maps, loaded before us as in the game (their names
# come first): just the parts they decide the map's skin with.
OTHERS = """
  LOADED = LOADED or {}
  C_AddOns.IsAddOnLoaded = function(n) return LOADED[n] or false end
  function with_eui()
    LOADED.EllesmereUI, LOADED.EllesmereUIBlizzardSkin = true, true
    EllesmereUI = { GetBlizzWindowStyle = function(k) return "eui" end }
  end
  function with_elv(skins)
    LOADED.ElvUI = true
    LOADS = {}
    local S = {}
    function S:LoadSkin(info) LOADS[#LOADS + 1] = info.toggle end
    local E = { private = { skins = { blizzard = { enable = true, worldmap = skins ~= false } } } }
    function E:GetModule(name) if name == "Skins" then return S end end
    ElvUI = { E }
    ELV_S = S
  end
  function with_leatrix(simple)
    LOADED.Leatrix_Maps = true
    LeaMapsDB = { SimpleMapFrame = simple }
  end
"""


def glow_shown(c):
    return Q(c, 'return M.SettingsPage.Glow and M.SettingsPage:Glow()') is True


def compat_client(setup, map_skin=None):
    saved = OTHERS + setup
    if map_skin:
        saved += '\nMOTADB = { settings = { mapSkin = "%s" } }' % map_skin
    c = Client("Cora", saved=saved)
    return c, c.lua.globals().MinistryOfTheAllied


c, ns = compat_client("with_eui()")
check("EllesmereUI: with our map skin on, it's told to leave the world map alone",
      Q(c, 'return EllesmereUI.GetBlizzWindowStyle("worldmap")') == "off")
check("EllesmereUI: its other windows are its own as before",
      Q(c, 'return EllesmereUI.GetBlizzWindowStyle("bags")') == "eui")
check("EllesmereUI: our skin dresses the map", ns.WorldMapSkin.Key(ns.WorldMapSkin) is not None)
c, ns = compat_client("with_eui()", "plain")
check("EllesmereUI: with Plain, it skins the map as normal",
      Q(c, 'return EllesmereUI.GetBlizzWindowStyle("worldmap")') == "eui")
ns.db.settings.mapSkin = "party"
c.lua.execute('MinistryOfTheAllied:Fire("MAP_SKIN_CHANGED")')
check("EllesmereUI: a skin chosen after login waits for a /reload (ours stays off, no clash)",
      ns.WorldMapSkin.Key(ns.WorldMapSkin) is None and "reload" in (ns.MapCompat.Note(ns.MapCompat) or ""))
check("EllesmereUI: ...and the chat says so", any("/reload" in l for l in c.log))
c.slash("settings")
check("Settings: Reload UI glows while a /reload is due", glow_shown(c))
ns.db.settings.mapSkin = "plain"
c.lua.execute('MinistryOfTheAllied:Fire("MAP_SKIN_CHANGED")')
check("Settings: ...and stops once nothing is due", not glow_shown(c))

c, ns = compat_client("with_elv()")
c.lua.execute('ELV_S:LoadSkin({ toggle = "worldmap" }); ELV_S:LoadSkin({ toggle = "bags" })')
check("ElvUI: with our map skin on, its world map skin is skipped and the rest run",
      list(c.lua.eval('LOADS').values()) == ["bags"])
check("ElvUI: nothing it saved is changed", Q(c, 'return ElvUI[1].private.skins.blizzard.worldmap') is True)
c, ns = compat_client("with_elv()", "plain")
c.lua.execute('ELV_S:LoadSkin({ toggle = "worldmap" })')
check("ElvUI: with Plain, it skins the map as normal", list(c.lua.eval('LOADS').values()) == ["worldmap"])
ns.db.settings.mapSkin = "ministry"
check("ElvUI: a skin chosen after login waits for a /reload", ns.WorldMapSkin.Key(ns.WorldMapSkin) is None
      and ns.MapCompat.NeedsReload(ns.MapCompat))
ns.db.settings.mapSkin = "plain"
check("ElvUI: back to Plain, no /reload needed", not ns.MapCompat.NeedsReload(ns.MapCompat))

c, ns = compat_client('with_leatrix("On")')
check("Leatrix Maps: its simple map frame on, ours steps aside", ns.WorldMapSkin.Key(ns.WorldMapSkin) is None)
check("Leatrix Maps: the Settings row says why", "Leatrix" in (ns.MapCompat.Note(ns.MapCompat) or ""))
c, ns = compat_client('with_leatrix(nil)')
check("Leatrix Maps: the simple frame counts as on when never set (its default)", ns.WorldMapSkin.Key(ns.WorldMapSkin) is None)
c, ns = compat_client('with_leatrix("Off")')
check("Leatrix Maps: simple frame off, ours dresses the map", ns.WorldMapSkin.Key(ns.WorldMapSkin) is not None)
c, ns = compat_client('with_leatrix("On"); with_elv()')
check("Leatrix Maps: locked off by ElvUI's map skin, so ours dresses (and ElvUI's is skipped)",
      ns.WorldMapSkin.Key(ns.WorldMapSkin) is not None and ns.MapCompat.skipping is True)
c, ns = compat_client('with_leatrix("On"); with_eui()')
check("Leatrix Maps + EllesmereUI: with ours stepped aside, EllesmereUI keeps the map",
      Q(c, 'return EllesmereUI.GetBlizzWindowStyle("worldmap")') == "eui")
c, ns = compat_client("")
check("No other map add-ons: our skin dresses the map, no note on the Settings row", ns.WorldMapSkin.Key(ns.WorldMapSkin) is not None and ns.MapCompat.Note(ns.MapCompat) is None)

# OpenMap: the district layer goes just over its stitched art
d4c.lua.execute('OpenMapAPI = { ArtTopLevel = function() return 500 end }; WorldMapFrame:SetMapID(1429); WorldMapFrame:SetMapID(1453)')
check("OpenMap: the district layer sits just over its stitched art", WM.layer.shown and Q(d4c, 'return M.WorldMap.layer:GetFrameLevel()') == 501)
d4c.lua.execute('OpenMapAPI = { ArtTopLevel = function() return nil end }; WorldMapFrame:SetMapID(1429); WorldMapFrame:SetMapID(1453)')
check("OpenMap: before its map has opened, the layer keeps the map's own level", Q(d4c, 'return M.WorldMap.layer:GetFrameLevel()') == 40)
d4c.lua.execute('OpenMapAPI = nil')

print("== 104. the minimap seal in a button bag, Silverhand's silver")
c, ns = compat_client("")
seal_ok = Q(c, """local b = MinistryOfTheAlliedMinimapButton
  local icon = b and b.icon
  if not icon then return false end
  local p = M.Media.pieces.seal
  icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)  -- as ElvUI and EllesmereUI crop an icon
  local l, r, t, bt = icon.coords[1], icon.coords[2], icon.coords[3], icon.coords[4]
  return l > p.l and r < p.r and t > p.t and bt < p.b and r > l and bt > t""")
check("Minimap seal: a button bag's crop shows the seal itself, not the whole picture", seal_ok is True)
check("Silverhand: the silver switch and divider are drawn", Q(c, 'return M.Media.pieces["swOn~sv"] ~= nil and M.Media.pieces["divider~sv"] ~= nil') is True)

print("== The District Cup")
# A fresh guild seen from the Crown's copy: districts, games, a Ring, an election.
cup_max = Client("Max")
clients[:] = [cup_max]
run(15)
CUP = "local M = MinistryOfTheAllied; local W = function(k, d) return M.Book:Write(k, d) end "
def CQ(code): return cup_max.lua.eval("(function() " + CUP + code + " end)()")
for who, d in (("Bram", "OLD"), ("Kael", "OLD"), ("Mira", "ARC"), ("Oswin", "ARC"), ("Wren", "IRON"), ("Elowen", "CATH"), ("Tobin", "HARB")):
    CQ('W("citizen.district", { who = "%s", d = "%s" }) return 1' % (who, d))
run(1)
CQ('M.Games:Record("hunt", "Hunt One", { "Bram", "Mira", "Kael" }) return 1')
CQ('M.Games:Record("lottery", "Draw One", { "Mira", "Wren", "Kael" }) return 1')
CQ('M.Games:Record("race", "Round the Lake", { "Max", "Mira", "Tobin" }) return 1')
run(1)
check("Cup: a result saves each place's district as its code", CQ('local r = M.Games:Log()[1] return r.ds[2]') == "ARC")
ring = CQ('return M.Book:Write("ring.create", { season = "Cup Ring", bracket = "Open", fee = 0, closes = 1 }).n')
rid = "Max#%d" % ring
for s, x, y in ((1, "Bram", "Mira"), (2, "Kael", "Tobin"), (3, "Wren", "Oswin"), (4, "Elowen", "Kíng Atwood")):
    CQ('W("ring.bout", { id = "%s", s = %d, x = "%s", y = "%s" }) return 1' % (rid, s, x, y))
for s, w in ((1, "Bram"), (2, "Kael"), (3, "Wren"), (4, "Elowen"), (5, "Bram"), (6, "Wren"), (7, "Bram")):
    CQ('W("ring.result", { id = "%s", s = %d, w = "%s" }) return 1' % (rid, s, w))
run(1)
check("Cup: the Ring's champion is Bram", CQ('return M.Ring:Hall()[1].champion') == "Bram")
def board():
    return CQ('local out = {} for _, b in ipairs(M.Cup:Current().board) do out[#out + 1] = b.code .. "=" .. b.pts end return table.concat(out, " ")')
print("  board:", board())
check("Cup: points for 1st-3rd, none for the lottery or the Crown, the Ring counted", board() == "OLD=26 ARC=12 IRON=6 CATH=3 HARB=3")
check("Cup: Bram tops the scorers with 20", CQ('local s = M.Cup:Current().scorers[1] return s.name .. "=" .. s.pts') == "Bram=20")
check("Cup: no titles while the season is on", CQ('return #M.Cup:TitlesOf("Bram")') == 0)
CQ('W("citizen.district", { who = "Kael", d = "ARC" }) return 1')
CQ('M.Games:Record("quiz", "Quiz Night", { "Kael" }) return 1')
run(1)
check("Cup: a move keeps old points with the old district", board() == "OLD=26 ARC=22 IRON=6 CATH=3 HARB=3")
CQ('W("ballot.result", { b = "Max#1", name = "General Election", kind = "general", cands = { { n = "Bram", p = "sh" }, { n = "Mira", p = "ex" } }, votes = { 3, 2 }, total = 5, w = 1 }) return 1')
run(2)
CQ('M.Games:Record("race", "Second Season Race", { "Mira" }) return 1')
run(1)
check("Cup: a declared election ends the season and the points start again", CQ('local s = M.Cup:Current() return s.n .. "|" .. s.board[1].code .. "=" .. s.board[1].pts') == "2|ARC=10")
check("Cup: Season 1 went to the Old Quarter", CQ('local s = M.Cup:Seasons()[1] return s.done and s.champions.OLD and not s.champions.ARC') is True)
titles = lambda who: CQ('local t = {} for _, h in ipairs(M.Cup:TitlesOf("%s")) do t[#t + 1] = h.title end return table.concat(t, ", ")' % who)
check("Cup: Bram is Season 1 Champion and Top Scorer", titles("Bram") == "Season 1 Champion, Season 1 Top Scorer")
check("Cup: Kael scored for the Old Quarter, so is a champion too", titles("Kael") == "Season 1 Champion")
check("Cup: Mira's district lost, so she has no title", titles("Mira") == "")
check("Cup: a citizen of the winning district who didn't score has no title", titles("Oswin") == "" and CQ('return #M.Cup:TitlesOf("Kíng Atwood")') == 0)
check("Honours: the title shows in the tooltip line", CQ('return M.Honours:Title("Kael")') == "Season 1 Champion")
check("Honours: Cup titles join a player's honours", CQ('for _, h in ipairs(M.Honours:Of("Kael")) do if h.title == "Season 1 Champion" then return true end end return false') is True)
check("Honours: the Roll of Honour lists Cup champions without a medal", CQ('for _, e in ipairs(M.Honours:Roll()) do if e.name == "Kael" then return true end end return false') is True)
errs = len(errors)
cup_max.lua.execute('MinistryOfTheAllied.UI:Build(); MinistryOfTheAllied.UI.window:Show(); MinistryOfTheAllied.UI:SelectPage(8); MinistryOfTheAllied.GamesPage:Select("cup")')
check("Cup page: shows without errors", len(errors) == errs)
check("Cup page: Season 2, with past champions", CQ('return M.GamesPage:View()') == "cup")
print("== Short names: a record written before the full name is known")
# A first login: a record written before the full name is known is held, then
# sent under the full name, so Sinnclair has it in seconds, not at the next summary.
atwood = Client("Kíng Atwood", short="Kíng", tag="CAMWOWEU5Realm1PvE")
clients[:] = [sinn, atwood]
early = None
for _ in range(80):
    run(0.25)
    if atwood.lua.eval("MinistryOfTheAllied.guild ~= nil and next(MinistryOfTheAllied.roster) ~= nil and not MinistryOfTheAllied.meLearned"):
        # This copy lost its saved data, so carry on from the numbers the guild holds.
        atwood.lua.execute("MinistryOfTheAllied.guild.tops[\"Kíng\"] = 10")
        early = atwood.lua.eval('MinistryOfTheAllied.Book:Write("test.note", { text = "early" }) ~= nil')
        break
check("Short names: a record can be written before the full name is known", early is True)
ign0, start = sinn.lua.eval("MinistryOfTheAllied.stats.ignored"), clock[0]
has = '(function() for _, r in pairs(MinistryOfTheAllied.guild.records["Kíng Atwood"] or {}) do if r.d.text == "early" then return true end end return false end)()'
while clock[0] - start < 400 and not sinn.lua.eval(has):
    run(0.25)
print(f"  -> Sinnclair had the early record after {clock[0] - start:.1f} s")
check("Short names: the early record reaches Sinnclair within 10 s", clock[0] - start < 10)
check("Short names: nothing was refused on the way", sinn.lua.eval("MinistryOfTheAllied.stats.ignored") == ign0)

print("== Honours from The Ring")
# The Crown's copy from the Cup section: Bram won "Cup Ring", Wren lost The Final.
H = "local M = MinistryOfTheAllied; local H = M.Honours "
def HQ(code): return cup_max.lua.eval("(function() " + H + code + " end)()")
check("Ring honours: the champion earns the Ring Champion medal", HQ('return H:Has("Bram", "ring")') is True)
check("Ring honours: the losing finalist earns the Ring Finalist medal", HQ('return H:Has("Wren", "finalist") and not H:Has("Wren", "ring")') is True)
check("Ring honours: semi-finalists earn no medal", HQ('return not H:Has("Kael", "finalist") and not H:Has("Elowen", "finalist")') is True)
check("Ring honours: the current champion is Gladiator of Stormwind", HQ('return H:Title("Bram")') == "Gladiator of Stormwind")
rid2 = "Max#%d" % CQ('return M.Book:Write("ring.create", { season = "Second Ring", bracket = "Open", fee = 0, closes = 1 }).n')
CQ('W("ring.bout", { id = "%s", s = 1, x = "Kael", y = "Bram" }) return 1' % rid2)
for s, w in ((1, "Kael"), (5, "Kael"), (7, "Kael")):
    CQ('W("ring.result", { id = "%s", s = %d, w = "%s" }) return 1' % (rid2, s, w))
run(2)
check("Ring honours: a new champion takes the Gladiator title", HQ('return H:Title("Kael")') == "Gladiator of Stormwind" and HQ('return H:Gladiator()') == "Kael")
check("Ring honours: the old champion keeps the medal, and shows their Cup title", HQ('return H:Has("Bram", "ring") and H:Title("Bram") == "Season 1 Champion"') is True)
check("Ring honours: a Final won on a bye makes no finalist", HQ('return not H:Has("Bram", "finalist")') is True)
check("Ring honours: on the Roll of Honour", HQ('for _, e in ipairs(H:Roll()) do if e.name == "Wren" then return true end end return false') is True)
errs = len(errors)
cup_max.lua.execute('MinistryOfTheAllied.GamesPage:Select("honours"); MinistryOfTheAllied.GamesPage:Refresh()')
check("Ring honours: the Honours page shows four medals without errors", len(errors) == errs and HQ('return #H.MEDALS') == 4)
print("== The Ring: the fighters record their own bout")
rmax, rbram, rkael, rmira = Client("Max"), Client("Bram"), Client("Kael"), Client("Mira")
clients[:] = [rmax, rbram, rkael, rmira]
run(20)
RQ = "local M = MinistryOfTheAllied; local R = M.Ring "
def RE(c, code): return c.lua.eval("(function() " + RQ + code + " end)()")
rid = "Max#%d" % RE(rmax, 'return M.Book:Write("ring.create", { season = "Duel Ring", bracket = "Open", fee = 0, closes = 1 }).n')
for c in (rbram, rkael, rmira):
    RE(c, 'M.Book:Write("ring.enter", { id = "%s" }) return 1' % rid)
run(2)
RE(rmax, 'M.Book:Write("ring.bout", { id = "%s", s = 1, x = "Bram", y = "Kael" }) M.Book:Write("ring.bout", { id = "%s", s = 2, x = "Mira", y = "Tobin" }) return 1' % (rid, rid))
run(3)
check("Duels: the bouts are drawn on every copy", RE(rkael, 'local c = R:Current() return c.id == "%s" and c.stage == "bouts" and c.bouts[1].a == "Bram"' % rid) is True)
def duel(msg, *who):
    for c in who:
        c.lua.execute("POPUP_SHOWN = nil")
        c.lua.globals().mock_fire("CHAT_MSG_SYSTEM", msg)
def asked(c): return c.lua.eval("POPUP_SHOWN") == "MOTA_RING_DUEL"
def yes(c): c.lua.execute('StaticPopupDialogs["MOTA_RING_DUEL"].OnAccept()')
duel("Bram has defeated Mira in a duel", rbram, rmira)
check("Duels: a duel that isn't a due bout asks nothing (a friendly)", not asked(rbram) and not asked(rmira))
duel("Bram has defeated Kael in a duel", rbram, rkael)
check("Duels: both fighters are asked, with no organiser nearby", asked(rbram) and asked(rkael))
check("Duels: the question names the round", "Quarter-final" in (rbram.lua.eval("POPUP_TEXT") or ""))
yes(rbram)
run(2)
check("Duels: one fighter's word isn't enough", RE(rmira, 'return R:Current().bouts[1].w') is None)
yes(rkael)
run(2)
check("Duels: both saying yes records the result on every copy", all(RE(c, 'return R:Current().bouts[1].w') == "Bram" for c in (rmax, rbram, rkael, rmira)))
duel("Bram has defeated Kael in a duel", rbram, rkael)
check("Duels: a rematch after the result asks nothing", not asked(rbram) and not asked(rkael))
RE(rmax, 'return R:Result(2, "Mira")')
run(2)
check("Duels: the semi-final is Bram v Mira", RE(rbram, 'local b = R:Current().next return b.slot .. b.a .. b.b') == "5BramMira")
RE(rkael, 'M.Book:Write("ring.duel", { id = "%s", s = 5, w = "Kael" }) return 1' % rid)
duel("Mira has fled from Bram in a duel", rbram, rmira)
check("Duels: fleeing counts as a loss in the question", "Bram beat Mira" in (rmira.lua.eval("POPUP_TEXT") or ""))
RE(rbram, 'return R:Claim(5, "Bram")')
RE(rmira, 'return R:Claim(5, "Mira")')
run(2)
check("Duels: someone else's word, and a disagreement, settle nothing", RE(rmax, 'local c = R:Current() return c.bouts[5].w == nil and c.disputed[5] == true') is True)
check("Duels: the fighters are told the organiser will decide", rbram.said(r"disagree on who won"))
check("Duels: a fighter can't change their word", RE(rmira, 'return R:Claim(5, "Bram")') is False)
RE(rmax, 'return R:Result(5, "Bram")')
run(2)
check("Duels: the organiser settles a disagreement", RE(rmira, 'local c = R:Current() return c.bouts[5].w == "Bram" and c.bouts[7].a == "Bram"') is True)

print("== Hide and Seek")
hmax, hbram, hkael, hmira, hwren = Client("Max"), Client("Bram"), Client("Kael"), Client("Mira"), Client("Wren")
HC = [hmax, hbram, hkael, hmira, hwren]
clients[:] = HC
for c in HC:
    c.lua.execute('CVARS = { UnitNameFriendlyPlayerName = "1", nameplateShowFriends = "1" }; '
                  'function GetCVar(k) return CVARS[k] end; function SetCVar(k, v) CVARS[k] = tostring(v) end; '
                  'HP_SENT = 0; local C = MinistryOfTheAllied.Comm; local o = C.Send; '
                  'C.Send = function(self, msg, ...) if msg:find("\\031HP\\031") then HP_SENT = HP_SENT + 1 end return o(self, msg, ...) end')
run(20)
HQ = "local M = MinistryOfTheAllied; local Hi = M.Hide "
def HE(c, code): return c.lua.eval("(function() " + HQ + code + " end)()")
def at(c, x, y, inst=0):
    c.lua.execute('POS = { x = %f, y = %f, inst = %d }; ZONE = "Elwynn Forest"' % (x, y, inst))
for c in HC: at(c, 1000, 1000)

check("Hide: a citizen can't open a game", "Only the Crown" in (HE(hbram, 'local _, e = Hi:Open("x") return e') or ""))
check("Hide: a game needs its play area first", "play area" in (HE(hmax, 'local _, e = Hi:Open("x") return e') or ""))
HE(hmax, 'Hi:SetCentre() local d = Hi:Draft() d.hs = 30 d.ss = 300 Hi:SetRadius(100) return 1')
check("Hide: the middle is where the organiser stands", HE(hmax, 'local d = Hi:Draft() return d.cx .. "," .. d.cy .. "," .. d.rad') == "1000,1000,100")
check("Hide: the organiser opens it", HE(hmax, 'return Hi:Open("Goldshire Hide") ~= nil') is True)
run(2)
check("Hide: every copy sees it open to join", all(HE(c, 'return Hi:Stage()') == "lobby" for c in HC))
check("Hide: nobody is told about it twice by the draft (it's cleared)", HE(hmax, 'return M.db.hideDraft == nil') is True)
HE(hbram, 'return Hi:Join()')
run(1)
check("Hide: one player isn't enough to start", "At least" in (HE(hmax, 'local _, e = Hi:Start() return e') or ""))
for c in (hkael, hmira, hwren): HE(c, 'return Hi:Join()')
HE(hmira, 'return Hi:Leave()')
run(1)
check("Hide: a player can leave before the start", HE(hbram, 'return #Hi:Current().players') == 3)
HE(hmira, 'return Hi:Join()')
run(1)
check("Hide: Mira rejoins: four players", HE(hkael, 'local t = {} for _, p in ipairs(Hi:Current().players) do t[#t + 1] = p end table.sort(t) return table.concat(t, ",")') == "Bram,Kael,Mira,Wren")
check("Hide: only the organiser starts it", "Only Max" in (HE(hbram, 'local _, e = Hi:Start() return e') or ""))
HE(hwren, 'Hi.BLOCKED = { { folder = "GuildPins", label = "Guild Pins" } }; C_AddOns.IsAddOnLoaded = function(n) return n == "GuildPins" end; return 1')
check("Hide: an add-on that shows guild members on the map keeps you out", "Turn off Guild Pins" in (HE(hwren, 'local G = Hi:Current() G.joined[M.me] = nil local _, e = Hi:Join() G.joined[M.me] = true return e') or ""))
HE(hwren, 'Hi.BLOCKED = {} return 1')

# Hiding.
at(hkael, 1030, 1000); at(hmira, 1060, 1000); at(hwren, 990, 1040)
check("Hide: Max starts it with Bram seeking", HE(hmax, 'return Hi:Start("Bram") ~= nil') is True)
run(2)
check("Hide: every copy is hiding, Bram seeking", all(HE(c, 'return Hi:Stage() .. "|" .. Hi:Current().sk') == "hiding|Bram" for c in HC))
check("Hide: each player knows their part", HE(hkael, 'return Hi:Role(M.me)') == "hider" and HE(hbram, 'return Hi:Role(M.me)') == "seeker")
check("Hide: names go off for the players", hkael.lua.eval('CVARS.UnitNameFriendlyPlayerName .. CVARS.nameplateShowFriends') == "00")
check("Hide: and the old settings are kept to put back", HE(hkael, 'return M.db.hideSaved.nameplateShowFriends') == "1")
check("Hide: names stay on for someone not playing", hmax.lua.eval('CVARS.nameplateShowFriends') == "1")
check("Hide: players' guild dots go quiet while they play", HE(hmira, 'return Hi:Silenced()') is True and HE(hmax, 'return Hi:Silenced()') is False)
hmira.lua.execute('OpenMapDB = { worldmap = { guild = true, friendsShare = true } }; C_AddOns.IsAddOnLoaded = function(n) return n == "OpenMap" end; MinistryOfTheAllied.MapCompat:OpenMapStepAside()')
check("Hide: OpenMap's own sharing is held off while they play", hmira.lua.eval('OpenMapDB.worldmap.friendsShare') is False and hmira.lua.eval('tostring(MinistryOfTheAllied.db.settings.dotsShare)') != 'true')
check("Hide: the map is shut for players in a No map game", HE(hmira, 'return Hi:MapBlocked()') is True and HE(hmax, 'return Hi:MapBlocked()') is False)
at(hbram, 1031, 1000)
run(5)
check("Hide: nobody is found while they're still hiding", HE(hmax, 'return #Hi:Current().found') == 0)
check("Hide: the seeker sends nothing while everyone hides", hbram.lua.eval("HP_SENT") == 0)

# Seeking.
run(26)
check("Hide: after the hiding time, seeking", HE(hmax, 'return Hi:Stage()') == "seeking")
check("Hide: hiders are told the seekers are coming", hkael.said(r"ready or not"))
run(3)
check("Hide: Bram, on top of Kael, finds them", all(HE(c, 'return Hi:Role("Kael")') == "seeker" for c in HC))
check("Hide: the finder is credited", HE(hmira, 'local G = Hi:Current() return G.finds.Bram .. "|" .. G.foundBy.Kael') == "1|Bram")
check("Hide: Kael is told they seek now", hkael.said(r"found you\. You're a seeker now"))
check("Hide: Bram is told who they found", hbram.said(r"Found: Kael"))
check("Hide: the seekers' places go out, the hiders' never do", hbram.lua.eval("HP_SENT") > 0 and hmira.lua.eval("HP_SENT") == 0 and hwren.lua.eval("HP_SENT") == 0)
# Running past someone doesn't find them.
at(hbram, 1059, 1000)
run(1)
at(hbram, 1000, 1000)
run(4)
check("Hide: a seeker running past (under 2 s) finds nobody", HE(hmax, 'return Hi:Role("Mira")') == "hider")
at(hkael, 1045, 1000)
run(3)
check("Hide: within 20 yards the hider's screen warns them", HE(hmira, 'return Hi.warm') is True)
check("Hide: the hider's glow is on", HE(hmira, 'return M.HuntGlow.target or 0') > 0)
# Wren leaves the play area.
at(hwren, 1200, 1000)
run(4)
check("Hide: outside the play area, a countdown", hwren.said(r"Out of bounds: \d+s to get back in"))
check("Hide: not out yet", HE(hmax, 'return Hi:Role("Wren")') == "hider")
run(8)
check("Hide: 10 seconds outside and they're out", all(HE(c, 'return Hi:Role("Wren")') == "out" for c in HC))
check("Hide: someone who's out gets names back", hwren.lua.eval('CVARS.nameplateShowFriends') == "1")
# Kael finds Mira: nobody left hidden.
at(hkael, 1058, 1000)
run(4)
check("Hide: the last hider found ends it at once", all(HE(c, 'return Hi:Stage()') == "done" for c in HC))
check("Hide: everyone found: best seeker, last found, the one before", HE(hkael, 'local p, a = Hi:Places(Hi:Current()) return table.concat(p, ",") .. "|" .. table.concat(a, ",")') == "Bram,Mira,Kael|1,2,3")
run(2)
check("Hide: the organiser's copy writes it to the games log", all(HE(c, 'local e = M.Games:Log()[1] return e and e.g == "hide" and e.name == "Goldshire Hide" and table.concat(e.places, ",") == "Bram,Mira,Kael"') is True for c in HC))
check("Hide: it's written once", HE(hmax, 'local n = 0 for _, e in ipairs(M.Games:Log()) do if e.g == "hide" then n = n + 1 end end return n') == 1)
check("Hide: names come back on at the end", all(c.lua.eval('CVARS.UnitNameFriendlyPlayerName .. CVARS.nameplateShowFriends') == "11" for c in (hbram, hkael, hmira)))
check("Hide: and nothing is left saved", HE(hmira, 'return M.db.hideSaved == nil') is True)
check("Hide: the map opens again", HE(hmira, 'return Hi:MapBlocked()') is False)
hmira.lua.execute('MinistryOfTheAllied.MapCompat:OpenMapStepAside()')
check("Hide: and OpenMap's sharing comes back after", hmira.lua.eval('OpenMapDB.worldmap.friendsShare') is True)
def pts(c, who): return HE(c, 'for _, m in ipairs(M.Cup:Current().scorers) do if m.name == "%s" then return m.pts end end return 0' % who)
check("Hide: Cup points 10, 6, 3", (pts(hmira, "Bram"), pts(hmira, "Mira"), pts(hmira, "Kael")) == (10, 6, 3))
check("Hide: the winner gets the Victor's Laurel", HE(hkael, 'return M.Honours:Of("Bram") ~= nil') is True)

# Game two: the clock runs out with two still hidden.
HE(hmax, 'Hi:SetCentre() local d = Hi:Draft() d.hs = 30 d.ss = 300 d.nm = false d.nmap = false return 1')
check("Hide: a second game opens once the first is over", HE(hmax, 'return Hi:Open("Woods Hide") ~= nil') is True)
run(1)
for c in (hbram, hkael, hmira, hwren): HE(c, 'return Hi:Join()')
for c, x in ((hbram, 1000), (hkael, 1030), (hmira, 1070), (hwren, 950)): at(c, x, 1000)
run(1)
HE(hmax, 'return Hi:Start("Kael")')
run(2)
check("Hide: with Hide names off, names stay on", hmira.lua.eval('CVARS.nameplateShowFriends') == "1" and HE(hmira, 'return Hi:MapBlocked()') is False)
at(hkael, 1001, 1000)
run(34)
check("Hide: Kael finds Bram", HE(hmax, 'return Hi:Role("Bram")') == "seeker")
check("Hide: someone found can't be found again", HE(hmax, 'return #Hi:Current().found') == 1)
run(300)
check("Hide: the clock runs out", all(HE(c, 'return Hi:Stage()') == "done" for c in HC))
check("Hide: time up: the hidden share 1st, best seeker 2nd, last found 3rd",
      HE(hmira, 'local p, a = Hi:Places(Hi:Current()) return table.concat(p, ",") .. "|" .. table.concat(a, ",")') == "Mira,Wren,Kael,Bram|1,1,2,3")
run(2)
check("Hide: the result keeps the shared place", HE(hbram, 'local e = M.Games:Log()[1] return e.name .. "|" .. table.concat(e.at, ",")') == "Woods Hide|1,1,2,3")
check("Hide: the games line shows two firsts", "1st Mira, 1st Wren, 2nd Kael, 3rd Bram" in HE(hbram, 'return M.Games:Line(M.Games:Log()[1])'))
check("Hide: a find after the clock counts for nothing", HE(hwren, 'M.Book:Write("hide.found", { id = Hi:Current().id, by = "Kael" }) return 1') == 1 and HE(hmax, 'return Hi:Role("Wren")') == "hider")
check("Hide: both survivors get 10 Cup points", (pts(hmax, "Mira"), pts(hmax, "Wren")) == (16, 10))
check("Hide: and both get the Victor's Laurel", HE(hkael, 'return M.Honours:Of("Mira") ~= nil and M.Honours:Of("Wren") ~= nil') is True)
check("Hide: places that go down are refused", HE(hmax, 'return M.Games:ValidAt({ 1, 2, 1 }, 3)') is False and HE(hmax, 'return M.Games:ValidAt({ 2, 2 }, 2)') is False)
check("Hide: a hand-written result can't claim odd places", "add up" in (HE(hmax, 'local _, e = M.Games:Record("hide", "x", { "Bram", "Kael" }, { 1, 3, 4 }) return e') or ""))

# Ending early, and a crash.
HE(hmax, 'Hi:SetCentre() return Hi:Open("Short Hide") ~= nil')
run(1)
check("Hide: the organiser can end a game", HE(hmax, 'return Hi:Close() ~= nil') is True)
run(1)
check("Hide: an ended game has no result", HE(hbram, 'return Hi:Stage()') == "closed" and HE(hbram, 'return M.Games:Log()[1].name') == "Woods Hide")
hmira.lua.execute('CVARS.nameplateShowFriends = "0"; MinistryOfTheAllied.db.hideSaved = { nameplateShowFriends = "1" }')
HE(hmira, 'Hi:Tick(0.25) return 1')
check("Hide: names hidden when the game crashed come back next time", hmira.lua.eval('CVARS.nameplateShowFriends') == "1" and HE(hmira, 'return M.db.hideSaved == nil') is True)

# The Games Hall: a drop-down of games, The Cup and Honours as ribbons.
HE(hmax, 'Hi:SetCentre() return Hi:Open("Page Hide") ~= nil')
run(1)
errs = len(errors)
hbram.lua.execute('MinistryOfTheAllied.UI:Build(); MinistryOfTheAllied.UI.window:Show(); MinistryOfTheAllied.UI:SelectPage(8)')
check("Games Hall: it opens on the game that's on now", HE(hbram, 'return M.GamesPage:View()') == "hide")
check("Games Hall: the drop-down marks it open to join", HE(hbram, 'return M.GamesPage.GameStatus("hide")') == "open to join")
for v in ("lottery", "hunt", "hide", "cup", "honours", "picker"):
    hbram.lua.execute('MinistryOfTheAllied.GamesPage:Select("%s")' % v)
check("Games Hall: the picker goes back to the last game looked at", HE(hbram, 'return M.GamesPage:View()') == "hide")
HE(hbram, 'Hi:Join() return 1')
run(1)
hmax.lua.execute('MinistryOfTheAllied.UI:Build(); MinistryOfTheAllied.UI.window:Show(); MinistryOfTheAllied.UI:SelectPage(8); MinistryOfTheAllied.GamesPage:Select("hide")')
HE(hkael, 'Hi:Join() return 1')
run(1)
HE(hmax, 'return Hi:Start("Kael")')
run(35)
hbram.lua.execute('MinistryOfTheAllied.GamesPage:Refresh()')
HE(hmax, 'return Hi:Close()')
run(1)
hmax.lua.execute('MinistryOfTheAllied.GamesPage:Refresh()')
check("Games Hall: Hide and Seek draws in every stage, for players and the organiser", len(errors) == errs)

print("== Hide and Seek: a play area drawn on the map")
HE(hmax, 'return Hi:Close() or 1')
run(1)
check("Hide: a drawn shape needs three corners", "at least 3" in (HE(hmax, 'Hi:Draft().pts = nil Hi:AddCorner(0, 1000, 1000, "Elwynn Forest", 1429) Hi:AddCorner(0, 1100, 1000) local _, e = Hi:Open("Shape") return e') or ""))
check("Hide: every corner in the same part of the world", "same part" in (HE(hmax, 'local _, e = Hi:AddCorner(1, 1100, 1100) return e') or ""))
HE(hmax, 'Hi:AddCorner(0, 1100, 1100) Hi:AddCorner(0, 1000, 1100) Hi:AddCorner(0, 1050, 1200) return 1')
check("Hide: a corner can be taken back", HE(hmax, 'Hi:UndoCorner() return #Hi:Draft().pts') == 4)
check("Hide: the shape's middle and reach are worked out", HE(hmax, 'local d = Hi:Draft() return d.cx .. "," .. d.cy .. "," .. d.rad') == "1050,1050,71")
check("Hide: the radius buttons leave a drawn shape alone", HE(hmax, 'Hi:SetRadius(400) return Hi:Draft().rad') == 71)
check("Hide: a shape opens a game", HE(hmax, 'return Hi:Open("Square Hide") ~= nil') is True)
run(1)
check("Hide: every copy has the corners and the map", HE(hmira, 'local G = Hi:Current() return #G.pts .. "|" .. G.m') == "4|1429")
check("Hide: inside the square is inside", HE(hmira, 'return Hi:Inside(Hi:Current(), 0, 1050, 1050)') is True)
check("Hide: inside the circle round it but outside the square is outside", HE(hmira, 'return Hi:Inside(Hi:Current(), 0, 1090, 1010)') is True and HE(hmira, 'return Hi:Inside(Hi:Current(), 0, 1110, 1060)') is False)
check("Hide: yards to the edge, inside and outside", HE(hmira, 'local G = Hi:Current() return math.floor(Hi:ToEdge(G, 0, 1050, 1010) + 0.5) .. "|" .. math.floor(Hi:ToEdge(G, 0, 1050, 980) + 0.5)') == "10|-20")
check("Hide: the circle's corners are made up for drawing", HE(hmira, 'return #Hi:Shape({ cx = 0, cy = 0, rad = 50 })') == 48)
for c in (hbram, hmira, hkael): HE(c, 'return Hi:Join()')
at(hbram, 1050, 1050); at(hmira, 1040, 1040); at(hkael, 1020, 1080)
run(1)
HE(hmax, 'return Hi:Start("Bram")')
run(2)
at(hmira, 1050, 990)  # outside the square's bottom edge
run(12)
check("Hide: leaving a drawn shape puts you out too", HE(hmax, 'return Hi:Role("Mira")') == "out")

# The page, with the zone's map art behind the play area.
for c in (hmax, hmira):
    c.lua.execute('''
      TILES_SET = 0
      function CreateVector2D(a, b) return { GetXY = function() return a, b end } end
      C_Map = C_Map or {}
      C_Map.GetMapPosFromWorldPos = function(inst, v, m) local wy, wx = v:GetXY() return m, CreateVector2D((2000 - wx) / 4000, (2000 - wy) / 4000) end
      C_Map.GetMapArtLayers = function() return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } } end
      C_Map.GetMapArtLayerTextures = function() local t = {} for i = 1, 12 do t[i] = 100 + i end return t end
    ''')
errs = len(errors)
hmira.lua.execute('MinistryOfTheAllied.UI:Build(); MinistryOfTheAllied.UI.window:Show(); MinistryOfTheAllied.UI:SelectPage(8); MinistryOfTheAllied.GamesPage:Select("hide"); MinistryOfTheAllied.GamesPage:Refresh()')
check("Games Hall: the play area draws with the zone's map behind it", len(errors) == errs)
check("Games Hall: the map's tiles under the area are laid", HE(hmira, 'local n = 0 for _, t in ipairs(M.GamesPage._hideArea().tiles) do if t:IsShown() then n = n + 1 end end return n') > 0)
check("Games Hall: the edge is drawn as dots", HE(hmira, 'local n = 0 for _, t in ipairs(M.GamesPage._hideArea().dots) do if t:IsShown() then n = n + 1 end end return n') > 20)
HE(hmax, 'return Hi:Close()')
run(1)
errs = len(errors)
hmax.lua.execute('MinistryOfTheAllied.UI:Build(); MinistryOfTheAllied.UI.window:Show(); MinistryOfTheAllied.UI:SelectPage(8); MinistryOfTheAllied.GamesPage:Select("hide")')
HE(hmax, 'Hi:Draft().pts = nil Hi:AddCorner(0, 1000, 1000, "Elwynn Forest", 1429) Hi:AddCorner(0, 1100, 1000) Hi:AddCorner(0, 1050, 1100) M.GamesPage:Refresh() return 1')
check("Games Hall: the organiser's form draws a shape being set up", len(errors) == errs and HE(hmax, 'return M.GamesPage._hideArea(true):IsShown()') is True)

print("== Hide and Seek: unexplored map")
hmax.lua.execute('C_MapExplorationInfo = { GetExploredMapTextures = function() return { { offsetX = 150, offsetY = 100, textureWidth = 300, textureHeight = 200, numTexturesWide = 2, numTexturesTall = 1, fileDataIDs = { 901, 902 } }, { offsetX = 0, offsetY = 0, textureWidth = 100, textureHeight = 100, numTexturesWide = 1, numTexturesTall = 1, fileDataIDs = { 903 } } } end }')
check("Hide: Forever's zone maps ship with the add-on, fog lifted", HE(hmax, 'return M.MapReveal[1429] ~= nil and #M.MapReveal[1429] > 5 and M.MapRevealBuild') == "1.60.1.70888")
check("Hide: on a shipped map, nothing extra goes in the game", HE(hmax, 'Hi:Open("Fog Hide") return Hi:Current().ov == nil') is True)
run(1)
errs = len(errors)
hmira.lua.execute('MinistryOfTheAllied.GamesPage:Refresh()')
check("Hide: a player who hasn't explored it sees the whole map", len(errors) == errs and HE(hmira, 'local n = 0 for _, t in ipairs(M.GamesPage._hideArea().over) do if t:IsShown() then n = n + 1 end end return n') > 5)
HE(hmax, 'return Hi:Close()')
run(1)
HE(hmax, 'Hi:Draft().pts = nil Hi:AddCorner(0, 1000, 1000, "Elsewhere", 99999) Hi:AddCorner(0, 1100, 1000) Hi:AddCorner(0, 1050, 1100) return 1')
check("Hide: on a map not shipped, the organiser's explored pieces go in the game", HE(hmax, 'Hi:Open("Odd Hide") local G = Hi:Current() return G.ov and #G.ov == 1 and G.ov[1].f[2] == 902') is True)
run(1)
hmira.lua.execute('MinistryOfTheAllied.GamesPage:Refresh()')
check("Hide: and players see those", HE(hmira, 'local n = 0 for _, t in ipairs(M.GamesPage._hideArea().over) do if t:IsShown() then n = n + 1 end end return n') == 2)
HE(hmax, 'return Hi:Close()')
run(1)

print("== Hide and Seek: a circle drawn on the map")
hmax.lua.execute('C_Map.GetWorldPosFromMapPos = function(m, v) local px, py = v:GetXY() return 0, CreateVector2D(2000 - 4000 * py, 2000 - 4000 * px) end; C_Map.GetMapInfo = function(m) return { name = "Elwynn Forest" } end')
HMQ = 'local HM = M.HideMap '
HE(hmax, HMQ + 'HM.circling, HM.centre = true, nil return 1')
check("Circle: the first click sets the middle", HE(hmax, HMQ + 'HM:CircleClick(1429, 0.25, 0.25) local d = Hi:Draft() return d.cx .. "," .. d.cy .. "|" .. tostring(HM.circling)') == "1000,1000|true")
check("Circle: an edge too close is refused", "too small" in (HE(hmax, HMQ + 'local _, e = HM:CircleClick(1429, 0.251, 0.25) return e') or ""))
check("Circle: the second click sets the edge", HE(hmax, HMQ + 'HM:CircleClick(1429, 0.2625, 0.25) local d = Hi:Draft() return d.rad .. "|" .. tostring(d.pts) .. "|" .. d.m .. "|" .. d.z .. "|" .. tostring(HM.circling)') == "50|nil|1429|Elwynn Forest|false")
check("Circle: a game opens with it", HE(hmax, 'return Hi:Open("Ring Hide") ~= nil and Hi:Current().rad == 50 and Hi:Current().pts == nil') is True)
run(1)
check("Circle: everyone has the circle", HE(hmira, 'local G = Hi:Current() return G.name .. "|" .. G.rad') == "Ring Hide|50")
HE(hmax, 'return Hi:Close()')
run(1)

print("== Hide and Seek: the organiser's page before a play area is set")
errs = len(errors)
HE(hmax, 'M.db.hideDraft = nil M.GamesPage:Select("hide") M.GamesPage:Refresh() return 1')
check("Setup: the map round where you stand shows before a play area is set", len(errors) == errs and HE(hmax, 'local a = M.GamesPage._hideArea(true) return a:IsShown() and a.you:IsShown()') is True)
check("Setup: with no edge drawn yet", HE(hmax, 'local n = 0 for _, t in ipairs(M.GamesPage._hideArea(true).dots) do if t:IsShown() then n = n + 1 end end return n') == 0)
print("== 17. Admin Controls: the Crown's window and Crown-only commands (10 Nov)")
adm = Client("Max", guarded=True)
cit = Client("Bram", guarded=True)
cit2 = Client("Kael", guarded=True)
clients.extend([adm, cit, cit2])
run(8)
A = adm.lua.globals().MinistryOfTheAllied
C_ = cit.lua.globals().MinistryOfTheAllied
def controls(c, name, label=None):
    return [x for x in c.lua.globals().MinistryOfTheAllied.AdminControls.Controls(c.lua.globals().MinistryOfTheAllied.AdminControls).values()
            if x.name == name and (label is None or x.label == label)]
def tip_lines(c):
    return list(c.lua.globals().GameTooltip.lines.values())

# commands: the Crown's alone, except the ones named open
before = Q(cit, 'return (M.Book:Count())')
cit.slash("test sneaky")
check("Commands: a citizen can't use a Crown command (refused politely, nothing written)",
      cit.said(r"commands are for the Crown alone") and Q(cit, 'return (M.Book:Count())') == before)
cit.slash("skin crown")
check("Commands: ...nor the others (skin)", cit.log[-1].endswith("Crown alone."))
mark = len(cit.log)
cit.slash("help")
shown = [l for l in cit.log[mark:] if "/mota " in l]
check("Commands: /mota help works for everyone and lists only what they can use",
      len(shown) == 4 and all(any(f"/mota {n}" in l for l in shown) for n in ("help", "noconfidence", "settings", "dots")))
mark = len(adm.log)
adm.slash("test from the Crown")
check("Commands: the Crown can use them", Q(adm, 'return (M.Book:Count())') >= 1 and not adm.said(r"Crown alone"))
mark = len(adm.log)
adm.slash("help")
check("Commands: ...and sees the whole list in help", sum(1 for l in adm.log[mark:] if "/mota " in l) > 15)
Q(cit, 'M.Commands.Open.ring = true')
cit.slash("ring")
check("Commands: a name in the open list is for everyone", not cit.log[-1].endswith("Crown alone."))
for nm in ("noconfidence", "settings"):
    cit.slash(nm)
    check(f"Commands: /mota {nm} is open to a citizen", "Crown alone" not in cit.log[-1])

# the knob and the window
adm.slash("")
cit.slash("")
check("Admin knob: shown to the Crown", A.UI.knobAdmin.shown is True)
check("Admin knob: hidden from a citizen", C_.UI.knobAdmin.shown is False)
Q(cit, 'M.UI:ShowAdmin(true)')
check("Admin: a citizen can't open it", Q(cit, 'return M.AdminControls:Frame() == nil') is True)
A.UI.knobAdmin.scripts.OnClick(A.UI.knobAdmin)
fr = A.AdminControls.Frame(A.AdminControls)
check("Admin: the knob opens a window of its own, with the knob lit", fr is not None and fr.shown and A.UI.knobAdmin.lit.shown)
pt = fr.points[1]
check("Admin: it docks to the main window's left side", pt[1] == "TOPRIGHT" and pt[3] == "TOPLEFT")
check("Admin: it is its own window, not inside the main one", adm.lua.eval('MinistryOfTheAlliedAdmin.parent == UIParent') is True)
names = {c.name for c in A.Commands.list.values()}
have = {x.name for x in A.AdminControls.Controls(A.AdminControls).values()}
check("Admin: a row for the announce button and one for every command",
      len(A.AdminControls.Rows(A.AdminControls)) == 1 + len(A.Commands.list))
check("Admin: every command can be run from the window", names <= have)

# tooltips: the same words /mota help shows
for c in A.Commands.list.values():
    ctl = controls(adm, c.name)[0]
    ctl.button.scripts.OnEnter(ctl.button)
    lines = tip_lines(adm)
    if c.name in ("skin", "voice", "district", "help"):
        check(f"Admin tooltip: {c.name} says what /mota help says", len(lines) == 1 and lines[0] == c.help)
ctl = controls(adm, "skin", "Silverhand")[0]
ctl.button.scripts.OnClick(ctl.button)
check("Admin: pressing Silverhand under Skin runs /mota skin silverhand", A.skin.KEY == "SILVERHAND")
ctl = controls(adm, "skin", "Mine")[0]
ctl.button.scripts.OnClick(ctl.button)
check("Admin: ...and Mine goes back to the Crown's own", A.skin.KEY == "CROWN")
ctl = controls(adm, "test", "Run")[0]
n = Q(adm, 'return (M.Book:Count())')
ctl.row.box.text = "typed in the box"
ctl.button.scripts.OnClick(ctl.button)
check("Admin: Run sends the words in the box, as typed",
      Q(adm, 'return (M.Book:Count())') == n + 1 and Q(adm, 'return M.Book:Latest(1)[1].d.text') == "typed in the box")

# Announce New Version
Q(cit, 'local orig = M.Herald.Announce; M.Herald.Announce = function(s, h, f) LASTH = h return orig(s, h, f) end')
btn = A.AdminControls.Announce(A.AdminControls)
check("Announce: a button at the top", btn.labelText.lower() == "announce new version")
ups = lambda c: sum(1 for m in c.wire if m.split('')[1:2] == ['UP'])
sent = ups(adm)
btn.scripts.OnClick(btn)
check("Announce: the first press only asks Are You Sure?", btn.labelText.lower() == "are you sure?" and ups(adm) == sent)
run(6)
check("Announce: ...and goes back if left alone", btn.labelText.lower() == "announce new version" and ups(adm) == sent)
btn.scripts.OnClick(btn)
btn.scripts.OnClick(btn)
run(3)
check("Announce: the second press sends it to the guild", ups(adm) == sent + 1 and adm.said(r"told a new update is available"))
check("Announce: the button is back to its first label", btn.labelText.lower() == "announce new version")
check("Announce: the Crown sees the herald too", Q(adm, 'return M.Herald:Waiting()') >= 1)
check("Announce: a citizen's game shows the herald", Q(cit, 'return M.Herald:Waiting()') >= 1)
check("Announce: it wears the Crown's seal and says the update words",
      Q(cit, 'return LASTH.seal') == "crown"
      and Q(cit, 'return LASTH.text') == "A new update for the add-on is available. Please download the newest update and restart your game.")
# only the Crown is believed
k0, ig = Q(cit, 'return M.Herald:Waiting()'), Q(cit, 'return M.stats.ignored')
Q(cit2, 'M.Comm:Send(M.Comm:Pack("UP", "9.9.9"), "GUILD")')
run(3)
check("Announce: the same message from a citizen is ignored",
      Q(cit, 'return M.Herald:Waiting()') <= k0 and Q(cit, 'return M.stats.ignored') > ig)
Q(cit2, 'M.AdminControls:SendUpdate()')
check("Announce: a citizen can't send it", Q(cit2, 'return (M.AdminControls:SendUpdate())') is False)
A.UI.window.scripts.OnHide(A.UI.window)
check("Admin: closing the main window closes it too", fr.shown is False)

print("== 18. Guild members on the maps (11 Nov): sharing, dots, minimap, the question, OpenMap stepping aside")
# Two fresh clients: Max shares where he stands, Bram looks. A pretend map API with a
# straight-line world: on map 1429 the first world coordinate grows to the north (1000 a
# map length) and the second to the west (2000), as in the game.
clients[:] = []
dk = Client("Max")
clients.append(dk)
run(1)
dc = Client("Bram")
clients.append(dc)
MAPS_LUA = '''
  IN_INSTANCE, LOCK = false, false
  function IsInInstance() return IN_INSTANCE, IN_INSTANCE and "party" or "none" end
  C_ChatInfo.InChatMessagingLockdown = function() return LOCK end
  POS = { map = 1429, x = 0.5, y = 0.5 }
  C_Map = C_Map or {}
  C_Map.GetBestMapForUnit = function() return POS.map end
  C_Map.GetPlayerMapPosition = function() if POS.x == nil then return nil end return { GetXY = function() return POS.x, POS.y end } end
  C_Map.GetMapInfo = function(id) if id == 9999999 then return nil end return { name = "Zone " .. id, mapID = id } end
  C_Map.GetWorldPosFromMapPos = function(id, v) return 0, { GetXY = function() return 1000 - 1000 * v.y, 2000 - 2000 * v.x end } end
  function CreateVector2D(x, y) return { x = x, y = y } end
  function UnitPosition() return 1000 - 1000 * POS.y, 2000 - 2000 * POS.x, 0, 0 end
  function UnitClass() return "Paladin", "PALADIN" end
  function UnitLevel() return 60 end
  RAID_CLASS_COLORS = { PALADIN = { r = 0.96, g = 0.55, b = 0.73 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
'''
for c in (dk, dc):
    c.lua.execute(MAPS_LUA)
run(10)
SEP = "\x1f"
kind_count = lambda c, k: sum(1 for m in c.wire if m.split(SEP)[1:2] == [k])

check("Dots: sharing is off by default and showing is on",
      Q(dk, 'return M.db.settings.dotsShare') is False and Q(dk, 'return M.db.settings.dotsShow') is True)
run(70)
check("Dots: nothing is sent while sharing is off (no place, no stop)",
      kind_count(dk, "LP") == 0 and kind_count(dk, "LS") == 0)

# Sharing on: the place goes out at once
Q(dk, 'M.db.settings.dotsShare = true; M.Dots:Changed()')
run(3)
check("Dots: switching sharing on sends the place at once", kind_count(dk, "LP") == 1)
check("Dots: Bram's game holds Max as a dot on map 1429",
      Q(dc, 'local p = M.Dots.live["Max"] return p ~= nil and p.map == 1429 and p.x == 0.5 and p.y == 0.5 and p.class == "PALADIN" and p.level == 60') is True)
check("Dots: Max does not draw himself", Q(dk, 'return next(M.Dots.live) == nil'))
run(30)
check("Dots: standing still sends nothing for a while (60 s apart)", kind_count(dk, "LP") == 1)
run(32)
check("Dots: ...and again after a minute", kind_count(dk, "LP") == 2)
Q(dk, 'POS.x = 0.52')
run(11)
check("Dots: moving sends every 10 s", kind_count(dk, "LP") == 3)
Q(dk, 'POS.x = 0.5201')   # a move under the threshold counts as standing still
run(15)
check("Dots: a move under 0.002 counts as standing still", kind_count(dk, "LP") == 3)

# a newer message replaces an older one waiting behind a lockdown
n0 = kind_count(dk, "LP")
Q(dk, 'LOCK = true; M.Dots.last.at = -1e9; POS.x = 0.6; M.Dots:Tick(); POS.x = 0.7; M.Dots.last.at = -1e9; M.Dots:Tick()')
check("Dots: while messages are locked only the newest place waits", Q(dk, 'return M.Dots.pending ~= nil and M.Dots.pending:find("0.7000", 1, true) ~= nil') is True)
Q(dk, 'LOCK = false; M.Dots:Flush()')
run(2)
check("Dots: ...and it goes once the lock lifts, once", kind_count(dk, "LP") == n0 + 1
      and Q(dc, 'return M.Dots.live["Max"].x') == 0.7)

# instances, bad positions
Q(dk, 'IN_INSTANCE = true; M.Dots:Zoned()')
run(2)
check("Dots: entering an instance sends a stop and the dot goes",
      kind_count(dk, "LS") == 1 and Q(dc, 'return M.Dots.live["Max"] == nil') is True and Q(dk, 'return M.Dots.sharing') is False)
n0 = kind_count(dk, "LP")
run(30)
check("Dots: nothing is sent from inside an instance", kind_count(dk, "LP") == n0)
Q(dk, 'IN_INSTANCE = false')
run(5)
check("Dots: back outside, the place is sent again", kind_count(dk, "LP") == n0 + 1)
n0 = kind_count(dk, "LP")
Q(dk, 'POS.x, POS.y = 0, 0; M.Dots.last.at = -1e9')
run(5)
check("Dots: a position of (0, 0) is never shared (and a stop goes)", kind_count(dk, "LP") == n0 and kind_count(dk, "LS") == 2)
Q(dk, 'POS.x = nil; M.Dots.last.at = -1e9')
run(5)
check("Dots: a map that gives no position shares nothing and breaks nothing", kind_count(dk, "LP") == n0)
Q(dk, 'POS.x, POS.y = 0.5, 0.5; M.Dots.last.at = -1e9')
run(5)
check("Dots: and it comes back when the position does", kind_count(dk, "LP") == n0 + 1)

# switching off
Q(dk, 'M.db.settings.dotsShare = false; M.Dots:Changed()')
run(2)
check("Dots: switching sharing off sends a stop and the dot goes",
      kind_count(dk, "LS") == 3 and Q(dc, 'return M.Dots.live["Max"] == nil') is True)

# receiving: what is refused
bad = {
    "map 0": '{"0", "0.5", "0.5", "MAGE", "60"}',
    "x over 1": '{"1429", "1.5", "0.5", "MAGE", "60"}',
    "(0, 0)": '{"1429", "0", "0", "MAGE", "60"}',
    "lower-case class": '{"1429", "0.5", "0.5", "mage", "60"}',
    "a class the game doesn't have": '{"1429", "0.5", "0.5", "WIZARD", "60"}',
    "an unknown map": '{"9999999", "0.5", "0.5", "MAGE", "60"}',
    "words for numbers": '{"1429", "left", "0.5", "MAGE", "60"}',
}
for what, fields in bad.items():
    check(f"Dots: a place with {what} is refused", Q(dc, f'return M.Dots:Heard("Mallory", {fields})') is False)
check("Dots: a good place is taken", Q(dc, 'return M.Dots:Heard("Mallory", {"1429", "0.25", "0.5", "MAGE", "60"})') is True)
Q(dc, 'M.Dots.live["Mallory"] = nil')

# a message of our own kinds from outside the guild channel, and Max hearing himself
Q(dc, 'M.Comm:Send(M.Comm:Pack("LP", 1429, "0.1000", "0.1000", "MAGE", 60), "GUILD")')
run(2)
check("Dots: Max never takes his own message as someone else's", Q(dk, 'return M.Dots.live["Bram"] ~= nil and M.Dots.live["Max"] == nil') is True)
Q(dc, 'M.Dots.live["Bram"] = nil')

# silence: a dot goes after 150 s
Q(dc, 'M.Dots:Heard("Mallory", {"1429", "0.25", "0.5", "MAGE", "60"})')
run(120)
check("Dots: a dot stays while it was heard from recently", Q(dc, 'return M.Dots.live["Mallory"] ~= nil') is True)
run(35)
check("Dots: a dot goes after about 150 s of silence", Q(dc, 'return M.Dots.live["Mallory"] == nil') is True)

# who is out there: a newcomer's question is answered, spread out
Q(dk, 'M.db.settings.dotsShare = true; M.Dots:Changed()')
run(3)
Q(dc, 'M.Dots.live["Max"] = nil; M.Dots.asked = false; M.Dots:Ask()')
n0 = kind_count(dk, "LP")
run(7)
check("Dots: someone sharing answers a new arrival's question with a place within seconds",
      kind_count(dk, "LP") == n0 + 1 and Q(dc, 'return M.Dots.live["Max"] ~= nil') is True)

# the world map
dc.lua.execute('''
  WorldMapFrame = CreateFrame("Frame", "WorldMapFrame", UIParent)
  local canvas = CreateFrame("Frame", nil, WorldMapFrame)
  canvas:SetSize(1000, 600)
  WorldMapFrame.mapID = 1429
  function WorldMapFrame:GetCanvas() return canvas end
  function WorldMapFrame:GetMapID() return self.mapID end
  function WorldMapFrame:GetCanvasScale() return self.zoom or 1 end
  function WorldMapFrame:OnMapChanged() end
  function WorldMapFrame:SetMapID(id) self.mapID = id self:OnMapChanged() end
  mock_fire("ADDON_LOADED", "Blizzard_WorldMap")
  WorldMapFrame:Show()
''')
DU = dc.lua.globals().MinistryOfTheAllied.Dots.UI
check("Dot map: hooked on once the game's map loads", DU.map is not None)
check("Dot map: a dot for Max, drawn at his place on the canvas (500, 300)",
      Q(dc, '''local d = M.Dots.UI.worldDots[1]
        if not d or not d.shown then return false end
        local p = d.points[#d.points]
        return p[1] == "CENTER" and p[3] == "TOPLEFT" and p[4] == 500 and p[5] == -300''') is True)
check("Dot map: the dot wears Max's class colour (Paladin pink)", Q(dc, '''local c = M.Dots.UI.worldDots[1].fill.color
        return c ~= nil and math.abs(c[1] - 0.96) < 1e-6 and math.abs(c[2] - 0.55) < 1e-6''') is True)
dc.lua.execute('WorldMapFrame:SetMapID(1453)')
check("Dot map: no dot on a map that doesn't show where he is", Q(dc, 'return not M.Dots.UI.worldDots[1].shown'))
dc.lua.execute('WorldMapFrame:SetMapID(1429); WorldMapFrame.zoom = 2')
run(1)
check("Dot map: a zoom keeps the dot the same size on screen", Q(dc, 'return M.Dots.UI.worldDots[1].scale == 0.5') is True)
dc.lua.execute('WorldMapFrame.zoom = 1')
run(1)
d1 = Q(dc, 'local d = M.Dots.UI.worldDots[1] d.scripts.OnEnter(d) return M.Dots.UI.tip.shown and M.Dots.UI.tipState.name')
check("Dot map: hovering a dot shows our own tip, with his name", d1 == "Max")
check("Dot map: ...which has the district tip step aside", Q(dc, 'return M.Dots:TipBusy()') is True)
check("Dot map: ...and the tip names the zone and the place", Q(dc, 'return M.Dots.UI.tipState.where:find("Zone 1429", 1, true) ~= nil and M.Dots.UI.tipState.where:find("50.0, 50.0", 1, true) ~= nil') is True)
Q(dc, 'local d = M.Dots.UI.worldDots[1] d.scripts.OnLeave(d)')
check("Dot map: leaving the dot puts the tip away", Q(dc, 'return not M.Dots.UI.tip.shown and not M.Dots:TipBusy()'))
Q(dc, 'M.db.settings.dotsShow = false; M.Dots:Changed()')
check("Dot map: the Show guild dots switch takes the dots away", Q(dc, 'return not M.Dots.UI.worldDots[1].shown'))
Q(dc, 'M.db.settings.dotsShow = true; M.Dots:Changed()')
check("Dot map: ...and brings them back", Q(dc, 'return M.Dots.UI.worldDots[1].shown'))
check("Dot map: the layer takes no mouse, only the dots do", Q(dc, 'return M.Dots.UI.layer ~= nil') is True)

# the minimap: Bram stands at (0.45, 0.55); Max is 100 yards east and 50 north of him
Q(dc, 'POS.x, POS.y = 0.45, 0.55')
run(1)
check("Minimap: Max shows 100 yards east and 50 north, by the minimap's reach",
      Q(dc, '''local d = M.Dots.UI.miniDots[1]
        if not d or not d.shown then return false end
        local p = d.points[#d.points]
        return p[1] == "CENTER" and math.abs(p[4] - 30) < 0.01 and math.abs(p[5] - 15) < 0.01''') is True)
mo = lambda args: dc.lua.eval('(function() local a, b, rim = MinistryOfTheAllied.Dots.UI.MinimapOffset(%s) return a .. "," .. b .. "," .. tostring(rim) end)()' % args)
# (my first, my second, their first, their second, reach, rotate, sin, cos, shape, half)
ox, oy, rim = mo("0, 0, 0, -100, 200, false, 0, 1, nil, 70").split(",")
check("Minimap: a target 100 yards east is right of centre", abs(float(ox) - 35) < 1e-6 and abs(float(oy)) < 1e-6 and rim == "false")
ox, oy, rim = mo("0, 0, 100, 0, 200, false, 0, 1, nil, 70").split(",")
check("Minimap: a target 100 yards north is above centre", abs(float(ox)) < 1e-6 and abs(float(oy) - 35) < 1e-6)
ox, oy, rim = mo("0, 0, 0, 100, 200, false, 0, 1, nil, 70").split(",")
check("Minimap: a target to the west is left of centre", abs(float(ox) + 35) < 1e-6)
ox, oy, rim = mo("0, 0, 1000, 0, 200, false, 0, 1, nil, 70").split(",")
check("Minimap: a target out of reach is held on the rim, 90% of the way out",
      abs(float(oy) - 63) < 1e-6 and rim == "true")
ox, oy, rim = mo("0, 0, 100, 0, 200, true, 1, 0, nil, 70").split(",")
check("Minimap: facing west on a turning minimap, a target to the north is on the right",
      abs(float(ox) - 35) < 1e-6 and abs(float(oy)) < 1e-6)
ox, oy, rim = mo("0, 0, 1000, 1000, 200, false, 0, 1, {false, false, false, false}, 70").split(",")
check("Minimap: a square minimap holds a far north-west target at its top-left corner",
      abs(float(ox) + 63) < 1e-6 and abs(float(oy) - 63) < 1e-6)
Q(dc, 'M.db.settings.dotsShow = false; M.Dots:Changed()')
check("Minimap: the Show guild dots switch takes the minimap's dots away", Q(dc, 'return not M.Dots.UI.miniDots[1].shown'))
Q(dc, 'M.db.settings.dotsShow = true; M.Dots:Changed()')
Q(dc, 'M.Dots.live["Max"].map = 1453')
Q(dc, 'M.Dots.live["Max"].wmap = nil')
Q(dc, 'C_Map.GetWorldPosFromMapPos = function() return 1, { GetXY = function() return 0, 0 end } end')
Q(dc, 'M.Dots.UI:PaintMinimap()')
check("Minimap: someone on another continent isn't shown", Q(dc, 'return not M.Dots.UI.miniDots[1].shown'))

# the Settings page
SP = dc.lua.globals().MinistryOfTheAllied.SettingsPage
rows = Q(dc, '''local keys = {}
  for _, g in ipairs(M.SettingsPage.GROUPS) do for _, r in ipairs(g.rows) do keys[r.key] = g.title end end
  return keys.dotsShare .. "|" .. keys.dotsShow''')
check("Settings: a Guild on the maps group holds both switches", rows == "Guild on the maps|Guild on the maps")
Q(dc, 'M.db.settings.dotsShare = false; M.db.settings.dotsAsked = false')
Q(dc, '''for _, g in ipairs(M.SettingsPage.GROUPS) do for _, r in ipairs(g.rows) do
    if r.key == "dotsShare" then M.db.settings.dotsShare = true; r.changed() end end end''')
run(2)
check("Settings: the Share my place switch starts sharing and counts as answering the question",
      Q(dc, 'return M.Dots.sharing and M.db.settings.dotsAsked') is True)
Q(dc, 'M.db.settings.dotsShare = false; M.Dots:Changed()')

# the one-time question
Q(dc, 'M.db.settings.dotsAsked = false; M.db.settings.dotsShare = false')
dc.lua.execute('WorldMapFrame:Hide(); WorldMapFrame:Show()')
run(1)
check("Question: the first time the map opens, it asks", Q(dc, 'return M.Dots.UI.ask ~= nil and M.Dots.UI.ask.shown') is True)
check("Question: it is in our words and keeps its own button names",
      Q(dc, 'return M.Dots.UI.ask.yes.labelText == "Share my place" and M.Dots.UI.ask.no.labelText == "Keep private"') is True)
check("Question: it says only the guild, and no dungeons, raids or battlegrounds",
      Q(dc, 'local t = M.Dots.UI.ask.body:GetText() return t:find("only to the guild", 1, true) ~= nil and t:find("dungeons, raids or battlegrounds", 1, true) ~= nil') is True)
check("Question: the body starts clear of a two-line title",
      Q(dc, 'local t, b = M.Dots.UI.ask.title.points[1][5], M.Dots.UI.ask.body.points[1][5] return t == -40 and b == -112 and math.abs(b) >= math.abs(t) + 2*26 + 4') is True)
check("Question: nothing is shared before the answer", Q(dc, 'return M.db.settings.dotsShare') is False)
Q(dc, 'M.Dots.UI:Answer(false)')
check("Question: Keep private shares nothing and puts the question away",
      Q(dc, 'return M.db.settings.dotsShare == false and M.db.settings.dotsAsked == true and not M.Dots.UI.ask.shown') is True)
dc.lua.execute('WorldMapFrame:Hide(); WorldMapFrame:Show()')
run(1)
check("Question: it is not asked again", Q(dc, 'return not M.Dots.UI.ask.shown'))
Q(dc, 'M.db.settings.dotsAsked = false; M.Dots.UI:MaybeAsk(); M.Dots.UI:Answer(true)')
run(2)
check("Question: Share my place turns sharing on and sends the place", Q(dc, 'return M.db.settings.dotsShare and M.Dots.sharing') is True)
Q(dc, 'M.db.settings.dotsShare = false; M.Dots:Changed()')

# Ask again (/mota dots reset, and the Settings button): sharing goes off and the question comes back
Q(dc, 'M.db.settings.dotsShare = true; M.db.settings.dotsAsked = true; M.Dots:Changed()')
dc.lua.execute('WorldMapFrame:Hide(); WorldMapFrame:Show()')
run(1)
check("Ask again: with the answer given, the open map shows no question", Q(dc, 'return not M.Dots.UI.ask.shown') is True)
ls0 = kind_count(dc, "LS")
Q(dc, 'M.Dots.UI:Reset()')
run(1)
check("Ask again: the answer is forgotten and sharing is off",
      Q(dc, 'return M.db.settings.dotsAsked == false and M.db.settings.dotsShare == false and M.Dots.sharing == false') is True)
check("Ask again: the question shows at once, the map being open", Q(dc, 'return M.Dots.UI.ask.shown == true') is True)
check("Ask again: a stop was sent when sharing ended", kind_count(dc, "LS") == ls0 + 1)
Q(dc, 'M.Dots.UI:Answer(false)')
Q(dc, 'M.db.settings.dotsAsked = true')
dc.slash("dots reset")
check("Ask again: /mota dots reset forgets the answer", Q(dc, 'return M.db.settings.dotsAsked == false') is True)
dc.slash("dots")
check("Ask again: /mota dots says sharing is off", dc.said(r"Guild dots: sharing off"))
Q(dc, 'M.Dots.UI:Answer(false)')

# OpenMap steps aside (its two saved switches, held off for this session only)
dc.lua.execute('''
  OPENMAP = true
  C_AddOns.IsAddOnLoaded = function(n) return n == "OpenMap" and OPENMAP end
  OpenMapDB = { worldmap = { guild = true, friendsShare = true, friends = true } }
''')
Q(dc, 'M.db.settings.dotsShow = true; M.db.settings.dotsShare = false; M.Dots:Changed()')
check("OpenMap: with our guild dots on, its Guild members on the map is held off",
      Q(dc, 'return _G.OpenMapDB.worldmap.guild') is False)
check("OpenMap: ...but its own sharing stays while we don't share",
      Q(dc, 'return _G.OpenMapDB.worldmap.friendsShare') is True and Q(dc, 'return _G.OpenMapDB.worldmap.friends') is True)
Q(dc, 'M.db.settings.dotsShare = true; M.Dots:Changed()')
check("OpenMap: while we share, its Share where you are is held off too",
      Q(dc, 'return _G.OpenMapDB.worldmap.friendsShare') is False and Q(dc, 'return M.MapCompat:OpenMapHeld("friendsShare")') is True)
Q(dc, 'OpenMapDB.worldmap.guild = true')   # its own options page turned it back on
run(6)
check("OpenMap: held off again within a few seconds if its options turn it back on",
      Q(dc, 'return _G.OpenMapDB.worldmap.guild') is False)
Q(dc, 'M.db.settings.dotsShare = false; M.Dots:Changed()')
check("OpenMap: our sharing off gives its sharing back at once",
      Q(dc, 'return _G.OpenMapDB.worldmap.friendsShare') is True)
Q(dc, 'M.db.settings.dotsShare = true; M.Dots:Changed()')
dc.lua.execute('mock_fire("PLAYER_LOGOUT")')
check("OpenMap: at logout both of its choices are back as it had them, so nothing of OpenMap's is changed for good",
      Q(dc, 'return _G.OpenMapDB.worldmap.guild and _G.OpenMapDB.worldmap.friendsShare') is True)
Q(dc, 'M.db.settings.dotsShare = false; M.db.settings.dotsShow = false; M.Dots:Changed()')
dc.lua.execute('OPENMAP = false; OpenMapDB.worldmap.guild = true')
Q(dc, 'M.db.settings.dotsShow = true; M.Dots:Changed()')
check("OpenMap: not loaded, nothing of its is touched", Q(dc, 'return _G.OpenMapDB.worldmap.guild') is True)
check("Dots: nothing in this section raised a Lua error", len(errors) == 0)

print("== The Pub Quiz")
zmax, zbram, zkael, zmira, zwren = Client("Max"), Client("Bram"), Client("Kael"), Client("Mira"), Client("Wren")
ZC = [zmax, zbram, zkael, zmira, zwren]
clients[:] = ZC
run(20)
ZQ = "local M = MinistryOfTheAllied; local Qz = M.Quiz "
def QE(c, code): return c.lua.eval("(function() " + ZQ + code + " end)()")

check("Quiz: the bank has 100 questions in six categories", QE(zmax, 'local n, c = #M.QuizBank.Q, {} for _, e in ipairs(M.QuizBank.Q) do c[e[2]] = true end local k = 0 for _ in pairs(c) do k = k + 1 end return n .. "|" .. k') == "100|6")
check("Quiz: every bank question has a unique id", QE(zmax, 'local s = {} for _, e in ipairs(M.QuizBank.Q) do if s[e[1]] then return false end s[e[1]] = true end return true') is True)
check("Quiz: answers match loosely", QE(zmax, 'local B = M.QuizBank return B.Matches("  the Molten  core!", "Molten Core") and B.Matches("mc", "Molten Core", { "mc" }) and not B.Matches("Blackwing", "Molten Core")') is True)
check("Quiz: a citizen can't open one", "Only the Crown" in (QE(zbram, 'local _, e = Qz:Open("x") return e') or ""))
QE(zmax, 'local d = Qz:Desk() d.rounds = 2 d.per = 3 d.secs = 30 return 1')
check("Quiz: a round fills from the bank", QE(zmax, 'return Qz:FillRandom(1)') == 3)
check("Quiz: a full round takes no more", "full" in (QE(zmax, 'local _, e = Qz:FillRandom(1) return e') or ""))
QE(zmax, 'Qz:AddOwn(2, "Who founded the Ministry of the Allied?", "The Crown") Qz:AddOwn(2, "How many districts are there?", "5") return Qz:FillRandom(2, "lore")')
check("Quiz: the quizmaster's own questions mix with the bank's", QE(zmax, 'local p = Qz:RoundPlan(2) return #p .. "|" .. tostring(p[1].bank) .. "|" .. p[3].bank:sub(1, 1)') == "3|nil|L")
check("Quiz: bank questions aren't picked twice", QE(zmax, 'local seen = {} for r = 1, 2 do for _, q in ipairs(Qz:RoundPlan(r)) do if q.bank then if seen[q.bank] then return false end seen[q.bank] = true end end end return #Qz:Unused() == 96') is True)
check("Quiz: a question can be taken out", QE(zmax, 'local id = Qz:RoundPlan(1)[3].bank Qz:Remove(1, 3) local ok = #Qz:RoundPlan(1) == 2 Qz:AddBank(1, id) return ok and #Qz:RoundPlan(1) == 3') is True)
check("Quiz: the quizmaster opens it", QE(zmax, 'return Qz:Open("Friday Quiz") ~= nil') is True)
run(2)
check("Quiz: every copy sees it, teams joining", all(QE(c, 'return Qz:Stage() .. "|" .. Qz:Current().rounds') == "lobby|2" for c in ZC))
check("Quiz: nobody else can see the questions", QE(zbram, 'return M.db.quizDesk == nil or #(M.db.quizDesk.r[1] or {}) == 0') is True)
QE(zbram, 'return Qz:MakeTeam("Lions")')
QE(zkael, 'return Qz:MakeTeam("Owls")')
run(1)
check("Quiz: a team name can't be taken twice", "already a team" in (QE(zwren, 'local _, e = Qz:MakeTeam("lions") return e') or ""))
QE(zwren, 'return Qz:MakeTeam("Badgers")')
QE(zmira, 'return Qz:Join("Bram")')
run(1)
check("Quiz: the quizmaster can't play", "quizmaster" in (QE(zmax, 'local _, e = Qz:MakeTeam("Crowns") return e') or ""))
check("Quiz: three teams, Mira on Bram's", QE(zkael, 'local Q = Qz:Current() return #Q.order .. "|" .. Q.teamOf.Mira .. "|" .. #Q.teams.Bram.members') == "3|Bram|2")
check("Quiz: one team at a time", "already on a team" in (QE(zmira, 'local _, e = Qz:Join("Kael") return e') or ""))
QE(zbram, 'return Qz:Joker(2)')
run(1)
check("Quiz: a captain plays the joker on round 2", QE(zmax, 'return Qz:Current().jokers.Bram') == 2)
check("Quiz: only a captain plays it", "captain" in (QE(zmira, 'local _, e = Qz:Joker(1) return e') or ""))

# Round 1.
check("Quiz: round 1 starts", QE(zmax, 'return Qz:StartRound() ~= nil') is True)
run(1)
check("Quiz: teams are fixed once it starts", "before the first round" in (QE(zmira, 'local _, e = Qz:Leave() return e') or "") or "can leave" in (QE(zmira, 'local _, e = Qz:Leave() return e') or ""))
check("Quiz: a joker can't be played on a round under way", "has started" in (QE(zkael, 'local _, e = Qz:Joker(1) return e') or ""))
def ans(r, i): return QE(zmax, 'return Qz:RoundPlan(%d)[%d].a' % (r, i))
def qtext(r, i): return QE(zmax, 'return Qz:RoundPlan(%d)[%d].q' % (r, i))
QE(zmax, 'return Qz:Ask()')
run(1)
check("Quiz: every captain gets the question in full", all(QE(c, 'return Qz:Waiting() and Qz.live.text') == qtext(1, 1) for c in (zbram, zkael, zwren)))
check("Quiz: a team member who isn't captain gets no answer box", QE(zmira, 'return Qz:Waiting()') is False and QE(zmira, 'return Qz.live ~= nil') is True)
check("Quiz: the captain's herald stays up", QE(zbram, 'return M.QuizPrompt:IsShown()') is True)
check("Quiz: only one question at a time", "Close question" in (QE(zmax, 'local _, e = Qz:Ask() return e') or ""))
QE(zbram, 'return Qz:Answer("%s")' % ans(1, 1))
QE(zkael, 'return Qz:Answer("Something else")')
run(1)
check("Quiz: answering closes the herald", QE(zbram, 'return M.QuizPrompt:IsShown()') is False and QE(zwren, 'return M.QuizPrompt:IsShown()') is True)
check("Quiz: the quizmaster has the answers, privately", QE(zmax, 'local a = Qz:Answered() return a.Bram ~= nil and a.Kael == "Something else" and a.Wren == nil') is True and QE(zmira, 'return M.db.quizDesk == nil or next(M.db.quizDesk.answers or {}) == nil') is True)
check("Quiz: the captain hears it was received", QE(zbram, 'return Qz.got["1.1"]') is True)
check("Quiz: an answer can be changed until the question closes", QE(zkael, 'return Qz:Answer("Still wrong")') is True)
run(1)
QE(zmax, 'return Qz:CloseQuestion()')
run(1)
check("Quiz: closing takes the herald away", QE(zwren, 'return M.QuizPrompt:IsShown()') is False and QE(zwren, 'return Qz.live == nil') is True)
check("Quiz: right answers are marked right at once", QE(zmax, 'local m = Qz:Desk().marks["1.1"] return m.Bram .. "|" .. m.Kael .. "|" .. tostring(m.Wren)') == "1|0|nil")
# Question 2: the timer closes it.
QE(zmax, 'return Qz:Ask()')
run(1)
QE(zkael, 'return Qz:Answer("%s")' % ans(1, 2))
QE(zwren, 'return Qz:Answer("close but not quite")')
run(32)
check("Quiz: the question closes itself when time is up", QE(zmax, 'return Qz:Desk().open == nil') is True and QE(zkael, 'return Qz.live == nil') is True)
check("Quiz: the quizmaster gives a half mark", QE(zmax, 'return Qz:Mark("1.2", "Wren", 0.5)') == 0.5)
QE(zmax, 'return Qz:Ask()')
run(1)
for c, a in ((zbram, ans(1, 3)), (zkael, ans(1, 3)), (zwren, ans(1, 3))): QE(c, 'return Qz:Answer("%s")' % a)
run(1)
check("Quiz: every question asked, Ask has nothing left", QE(zmax, 'Qz:CloseQuestion() return Qz:NextQuestion()') is None)
check("Quiz: round 1 is published", QE(zmax, 'return Qz:Publish() ~= nil') is True)
run(1)
check("Quiz: every copy has round 1's scores", all(QE(c, 'local s = Qz:Current().scores[1] return s.Bram .. "|" .. s.Kael .. "|" .. s.Wren') == "2|2|1.5" for c in ZC))
check("Quiz: a corrected round replaces the old", QE(zmax, 'Qz:Mark("1.1", "Kael", 0.5) return Qz:Publish() ~= nil') is True)
run(1)
check("Quiz: and everyone has the correction", QE(zwren, 'return Qz:Current().scores[1].Kael') == 2.5)

# Round 2, with Bram's joker.
QE(zmax, 'return Qz:StartRound()')
run(1)
for i in (1, 2, 3):
    QE(zmax, 'return Qz:Ask()')
    run(1)
    QE(zbram, 'return Qz:Answer("%s")' % ans(2, i))
    QE(zkael, 'return Qz:Answer("%s")' % (ans(2, i) if i == 1 else "no idea"))
    QE(zwren, 'return Qz:Answer("%s")' % (ans(2, i) if i < 3 else "pass"))
    run(1)
    QE(zmax, 'return Qz:CloseQuestion()')
    run(1)
QE(zmax, 'return Qz:Publish()')
run(5)
check("Quiz: the joker doubles the round", QE(zkael, 'return Qz:Points(Qz:Current(), "Bram", 2) .. "|" .. Qz:Points(Qz:Current(), "Kael", 2)') == "6|1")
check("Quiz: the scoreboard", QE(zmira, 'local t = {} for _, r in ipairs(Qz:Board()) do t[#t + 1] = r.rank .. r.name .. M.Quiz.Fmt(r.total) end return table.concat(t, ",")') == "1Lions8,2Badgers3.5,2Owls3.5")
# A tie-break for 2nd.
QE(zmax, 'return Qz:AskTie("How many players in a 40-player raid?")')
run(1)
check("Quiz: the tie-break goes to captains too", QE(zwren, 'return Qz:Waiting() and Qz.live.key') == "tie")
QE(zkael, 'return Qz:Answer("38")')
QE(zwren, 'return Qz:Answer("about 45")')
QE(zbram, 'return Qz:Answer("40")')
run(1)
QE(zmax, 'Qz:CloseQuestion() return Qz:SettleTie(40) ~= nil')
run(1)
check("Quiz: the closest guess breaks the tie", QE(zmira, 'local t = {} for _, r in ipairs(Qz:Board()) do t[#t + 1] = r.rank .. r.name end return table.concat(t, ",")') == "1Lions,2Owls,3Badgers")
check("Quiz: the quizmaster ends it", QE(zmax, 'return Qz:Finish() ~= nil') is True)
run(6)
check("Quiz: every copy has it over", all(QE(c, 'return Qz:Stage()') == "done" for c in ZC))
check("Quiz: every member of the top three goes in the games log", all(QE(c, 'local e = M.Games:Log()[1] return e.g .. "|" .. table.concat(e.places, ",") .. "|" .. table.concat(e.at, ",")') == "quiz|Bram,Mira,Kael,Wren|1,1,2,3" for c in ZC))
def zpts(c, who): return QE(c, 'for _, m in ipairs(M.Cup:Current().scorers) do if m.name == "%s" then return m.pts end end return 0' % who)
check("Quiz: both Lions get the winners' Cup points", (zpts(zkael, "Bram"), zpts(zkael, "Mira")) == (10, 10))
check("Quiz: and the Victor's Laurel", QE(zkael, 'return M.Honours:Of("Mira") ~= nil') is True)

# The pages draw: the quizmaster setting up and running, a player, a captain.
errs = len(errors)
for c in (zmax, zbram, zmira):
    c.lua.execute('MinistryOfTheAllied.UI:Build(); MinistryOfTheAllied.UI.window:Show(); MinistryOfTheAllied.UI:SelectPage(8); MinistryOfTheAllied.GamesPage:Select("quiz")')
QE(zmax, 'Qz:Desk().r = {} Qz:FillRandom(1) return Qz:Open("Page Quiz") ~= nil')
run(1)
QE(zbram, 'return Qz:MakeTeam("Lions")')
QE(zmira, 'return Qz:Join("Bram")')
run(1)
check("Games Hall: the quiz page opens on a quiz that's on", QE(zmira, 'M.GamesPage:Show(true) return M.GamesPage:View()') == "quiz")
QE(zmax, 'Qz:StartRound() return 1')
run(1)
QE(zmax, 'Qz:Ask() return 1')
run(1)
for c in (zmax, zbram, zmira):
    c.lua.execute('MinistryOfTheAllied.GamesPage:Refresh()')
QE(zmax, 'return Qz:Close()')
run(1)
for c in (zmax, zbram, zmira):
    c.lua.execute('MinistryOfTheAllied.GamesPage:Refresh()')
check("Games Hall: the quiz draws for the quizmaster, a captain and a player", len(errors) == errs)
check("Quiz: a cancelled quiz takes the captain's herald away", QE(zbram, 'return Qz:Waiting()') is False)

print()
print("Lua errors:", len(errors))
for e in errors:
    print("  ", e)
failed = [c for c in checks if not c[1]]
print(f"Checks: {len(checks) - len(failed)} passed, {len(failed)} failed")
sys.exit(1 if errors or failed else 0)
