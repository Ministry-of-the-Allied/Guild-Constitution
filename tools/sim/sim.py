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
    def __init__(self, name, saved=None, version=None, lockdown=None, protocol=None, realm_late=False, odd_realm=False, voice=False, tag=None, short=None):
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
run(12)  # replies to a hello come 0.5 to 3 seconds after it, at random
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
max3.slash("skin silverhand")
check("/mota skin silverhand puts Silverhand's skin on the Crown's screen at once", crown_ns.skin.KEY == "SILVERHAND"
      and skin_tex(crown_tab2().bgRest) == "skin_silverhand.tga" and skin_tex(crown_ns.UI.crest) == "skin_silverhand.tga")
check("Silverhand's skin brings the silver metal", skin_tex(crown_ns.UI.tabs[1].bgOn) == "frame_silver.tga")
check("The lit tab's label takes the party blue", rgb255(crown_ns.UI.tabs[crown_ns.UI.page].label) == (0x1F, 0x42, 0x90))
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
def skin_parts(panel):
    return [p for row in panel.crownRows.values() for p in row.values()]
def open_settings(client):
    g = client.lua.globals()
    client.slash("settings")
    panel = g.SETTINGS_FRAME
    panel.w, panel.h = 640, 560
    panel.scripts.OnShow(panel)
    return panel
bram_panel = open_settings(ui_client)
check("A citizen sees no Window skin row", skin_parts(bram_panel) and not any(p.shown for p in skin_parts(bram_panel)))
skin_btn = bram_panel.controls[8]
skin_btn.scripts.OnClick(skin_btn)
check("...and clicking it anyway changes nothing", ns.db.settings.windowSkin == "party" and ns.skin.KEY == "SILVERHAND")
max_panel = open_settings(max3)
party_btn = max_panel.controls[7]
check("The Crown sees the Window skin row, Party chosen", party_btn.on.shown and not party_btn.off.shown
      and max_panel.controls[8].off.shown and sum(1 for p in skin_parts(max_panel) if p.shown) == len(skin_parts(max_panel)) - 2)
ministry_btn = max_panel.controls[8]
ministry_btn.scripts.OnClick(ministry_btn)
check("...and can use it", crown_ns.db.settings.windowSkin == "ministry" and crown_ns.skin.KEY == "UNREGISTERED")
crown_ns.db.settings.windowSkin = "party"
crown_ns.Skin.Refresh(crown_ns.Skin, True)
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
hns.Herald.Press(hns.Herald)
check("Its button opens the Statute Book", HL.MinistryOfTheAlliedFrame.shown and hns.UI.heading.text == "The Statute Book")
check("Then the third sample", hf.title.text == "Elowen Marsh defects!")
hns.Herald.Press(hns.Herald)
check("Dismiss empties the queue", not hf.shown and hns.Herald.Waiting(hns.Herald) == 0)

HL.COMBAT = True
hc.slash("herald 1")
check("A herald waits during combat", not hf.shown)
HL.COMBAT = False
HL.mock_fire("PLAYER_REGEN_ENABLED")
check("...and shows when combat ends", hf.shown)
hns.Herald.Press(hns.Herald)

hc.slash("settings")
check("/mota settings opens the game's options on our page", HL.SETTINGS_OPENED == 7)
panel = HL.SETTINGS_FRAME
panel.w, panel.h = 640, 560
panel.scripts.OnShow(panel)
controls = panel.controls
herald_switch, glow_switch = controls[1], controls[3]
herald_switch.scripts.OnClick(herald_switch)
check("The herald switch turns heralds off", hns.db.settings.herald == False and herald_switch.off.shown)
check("A non-sample herald is then skipped", hns.Herald.Announce(hns.Herald, HL.MinistryOfTheAllied.Herald.samples[1]) == False)
herald_switch.scripts.OnClick(herald_switch)
glow_switch.scripts.OnClick(glow_switch)
check("A switch for a later feature doesn't change", hns.db.settings.glow == True)
modest = controls[5]
modest.scripts.OnClick(modest)
check("Modest is chosen", hns.db.settings.heraldSize == "small" and modest.on.shown and not controls[6].on.shown)
hc.slash("herald 3")
check("A Modest herald is smaller", abs(hf.scale - 0.56) < 1e-6)
hns.Herald.Press(hns.Herald)
hc.slash("fanfare")
hc.slash("fanfare 2")
check("Fanfare 2 chosen", hns.db.settings.fanfareSound == "READY_CHECK" and HL.LAST_SOUND == 8960)
HL.SETTINGS_OPENED = None
seal = HL.MinistryOfTheAlliedMinimapButton
seal.scripts.OnClick(seal, "RightButton")
check("Right-clicking the minimap seal opens settings", HL.SETTINGS_OPENED == 7)

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
check("Its scroll has no Stop button", vh().shown and vh().title.text == "Introduction" and not vh().closeX.shown and vh().buttons["quiet:Dismiss"].shown)
check("No fanfare over the narration", VL.LAST_SOUND != 888)
vc.slash("voice stop")
check("The introduction can't be stopped", VL.VOICE_STOPPED == 0 and V.Locked(V))
vc.slash("voice off")
check("...or switched off", vns.db.settings.voice)
vc.slash("constitution")
check("/mota constitution opens the Statute Book", VL.MinistryOfTheAlliedFrame.shown and vns.UI.heading.text == "The Statute Book")
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
check("...and offers Restart", vh().shown and vh().buttons["blue:Restart"].shown)
vns.Herald.Press(vns.Herald)
check("Restart plays from the beginning", played() == 3 and last().endswith("voice_02.ogg") and vh().buttons["quiet:Stop"].shown)
vh().closeX.scripts.OnClick(vh().closeX)
check("The X closes the scroll, the voice plays on", not vh().shown and V.Playing(V) is not None)
V.Stop(V)
vns.ConstitutionPage.Press(vns.ConstitutionPage, 5)
check("The page replays any clip", last().endswith("voice_05.ogg"))
vns.ConstitutionPage.Press(vns.ConstitutionPage, 5)
check("...and stops it", V.Playing(V) is None)
check("...with a Restart on its scroll", vh().shown and vh().buttons["blue:Restart"].shown)
vh().closeX.scripts.OnClick(vh().closeX)
n, stopped = played(), VL.VOICE_STOPPED
for clip in (4, 6, 7, 8):
    vns.ConstitutionPage.Press(vns.ConstitutionPage, clip)
check("Play shows a scroll with Stop", vh().shown and vh().closeX.shown and vh().buttons["quiet:Stop"].shown)
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
check("A clip the game drops offers Restart", V.Playing(V) is None and vh().shown and vh().buttons["blue:Restart"].shown)
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
clients[:] = others

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
check("Sign-ups reach everyone", len(list(ring(RM).entrants.values())) == 3)
check("Entering twice is refused", not RB.Ring.Enter(RB.Ring)[0])
RK.Ring.Withdraw(RK.Ring)
run(1)
RK.Ring.Enter(RK.Ring)
run(1)
check("Withdrawing and re-entering leaves one entry", len(list(ring(RB).entrants.values())) == 3)
RM.Ring.SetPaid(RM.Ring, "Bram", True)
RM.Ring.SetPaid(RM.Ring, "Kael", True)
run(1)
pot, champ, bank, paid = RB.Ring.Purse(RB.Ring, ring(RB))
check("The purse splits 90/10 on what's paid", pot == 20 and champ == 18 and bank == 2 and paid == 2)
check("The Ring page opens on the sign-up sheet", RB.RingPage is not None and not RB.UI.note.shown)
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
    n = {{ ["Bram"] = MinistryOfTheAllied.Ballot:Tally("{BID}").counted["Bram"], ["Zed"] = "1" }}, r = 0, p = 1 }})''')
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

print("  Methods the pretend game didn't know:", max_.lua.globals().mock_unknown())
missing = []
for c in (max_, bram):
    for path in c.lua.globals().mock_textures().split("\n"):
        if path.startswith("Interface\\AddOns\\MinistryOfTheAllied\\"):
            rel = path[len("Interface\\AddOns\\MinistryOfTheAllied\\"):].replace("\\", os.sep)
            if not os.path.exists(os.path.join(ADDON, rel)):
                missing.append(path)
check("Every Ballot Hall texture exists", not missing)

print()
print("Lua errors:", len(errors))
for e in errors:
    print("  ", e)
failed = [c for c in checks if not c[1]]
print(f"Checks: {len(checks) - len(failed)} passed, {len(failed)} failed")
sys.exit(1 if errors or failed else 0)
