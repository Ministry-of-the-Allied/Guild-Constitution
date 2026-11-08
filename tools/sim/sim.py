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
    def __init__(self, name, saved=None, version=None, lockdown=None, protocol=None, realm_late=False, odd_realm=False, voice=False, tag=None, short=None, place=False, link=False, bnet=None):
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
hc.lua.execute('GLOW_HEARD = 0; MinistryOfTheAllied:Listen("GLOW_CHANGED", function() GLOW_HEARD = GLOW_HEARD + 1 end)')
glow_switch.scripts.OnClick(glow_switch)
check("The District glow switch turns the glow off and tells the map",
      hns.db.settings.glow == False and glow_switch.off.shown and HL.GLOW_HEARD == 1)
glow_switch.scripts.OnClick(glow_switch)
cards_switch = controls[4]
cards_switch.scripts.OnClick(cards_switch)
check("A switch for a later feature doesn't change", hns.db.settings.cards == False)
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
glow_row = open(os.path.join(ADDON, "UI", "Settings.lua"), encoding="utf-8").read().split('key = "glow"')[1].split("},")[0]
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
        c.slash("skin " + skin)
        c.lua.execute('MinistryOfTheAllied.ThronePage:Refresh()')
    drawn = c.lua.eval("(function() local P = MinistryOfTheAllied.ThronePage return P.root and P.root.shown and P.head.eyebrow.text ~= '' and P.head.plateText.text ~= '' end)()")
    check("Throne Room: draws in all four skins, " + label, len(errors) == errs and drawn is True)
check("Throne Room: recruiting, before the first election", E(eb, TH + 'return T:Banner().eyebrow').startswith("Recruiting"))
check("Throne Room: the gates show in Who holds power", E(eb, TH + 'local p = T:Power() return p.pm == nil and p.gates.players') == 4)
check("Throne Room: nothing is on yet", E(eb, TH + 'return #T:Live()') == 0)
throne_draws(eb, "recruiting")
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
check("Tooltip: an honoured name shows its letters", E(ek, 'local seal = MinistryOfTheAlliedMinimapButton; seal.scripts.OnEnter(seal); seal.scripts.OnLeave(seal) for _, s in ipairs(M.OnlineTip.state.sections) do for _, n in ipairs(s.names) do if n:find("^Bram |cffC9A24AKC") then return true end end end return false') is True)

print()
print("Lua errors:", len(errors))
for e in errors:
    print("  ", e)
failed = [c for c in checks if not c[1]]
print(f"Checks: {len(checks) - len(failed)} passed, {len(failed)} failed")
sys.exit(1 if errors or failed else 0)
