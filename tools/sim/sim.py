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
]

errors = []
pending = []  # (deliver_at, client, args)
clock = [0.0]


class Client:
    def __init__(self, name, saved=None, version=None, lockdown=None, protocol=None, realm_late=False, odd_realm=False, voice=False):
        self.name = name
        self.full = name + "-" + REALM
        self.log = []
        self.wire = []  # every message this client handed to the game
        self.tokens = 10.0
        self.last = clock[0]
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        g = self.lua.globals()
        g.PLAYER, g.REALM, g.GUILD = name, REALM, GUILD
        g.ROSTER = self.lua.table_from([self.lua.table_from(m) for m in ROSTER])
        g.ROSTER_READY = False
        g.ADDON_VERSION = version
        g.LOCKDOWN = lockdown
        g.REALM_LATE = realm_late
        g.ODD_REALM = odd_realm
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
                pending.append((now + 0.1, c, (prefix, msg, "GUILD", self.full, "")))
        elif channel == "WHISPER":
            for c in clients:
                if c.full == target:
                    pending.append((now + 0.1, c, (prefix, msg, "WHISPER", self.full, c.name)))
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
      and any(a == "Kael-Realm" for a in bram.lua.eval("(function() local t = {} for a in pairs(MinistryOfTheAllied.guild.records) do t[#t+1] = a end return table.concat(t, ',') end)()").split(",")))
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

print("  Methods the pretend game didn't know:", HL.mock_unknown())
missing = []
for path in HL.mock_textures().split("\n"):
    if path.startswith("Interface\\AddOns\\MinistryOfTheAllied\\"):
        rel = path[len("Interface\\AddOns\\MinistryOfTheAllied\\"):].replace("\\", os.sep)
        if not os.path.exists(os.path.join(ADDON, rel)):
            missing.append(path)
check("Every herald and settings texture exists", not missing)

print()
print("Lua errors:", len(errors))
for e in errors:
    print("  ", e)
failed = [c for c in checks if not c[1]]
print(f"Checks: {len(checks) - len(failed)} passed, {len(failed)} failed")
sys.exit(1 if errors or failed else 0)
