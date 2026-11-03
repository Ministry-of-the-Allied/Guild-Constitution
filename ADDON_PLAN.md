# Ministry of the Allied — Add-on Plan

The single source of truth for the guild add-on. Read this before working on the add-on; update it whenever a decision is made.

Last updated: 2026-11-03

---

## 1. What the add-on is

One master add-on, **Ministry of the Allied**, that runs the guild's political system in game (see `CHARTER.md`, `CONSTITUENCIES.md`, `README.md`). It is built as one core with separate feature modules inside it, so new features can be added later without reworking the base.

Planned modules:

| Module | What it does |
|---|---|
| Core / Sync | Shares every member's add-on data with the rest of the guild, keeps everyone up to date |
| Elections & Votes | General elections (direct, guild-wide), district Representative elections, law votes, votes of no confidence; runs the election timeline itself |
| Citizens | Who counts as an active voter, alt links (one person, one vote), district assignment and transfers |
| Offices & Ranks | Knows who holds which office (Crown, PM, Cabinet, Justices, Reps); applies guild promote/demote after results; each office holder's duties |
| Laws & Court | Register of active laws, their three-month expiry and renewal; rulings and punishments |
| Parties | Party pages, members, manifestos, district bases, membership donations |
| Treasury | Minister of the Treasury (appointed by the PM), the automatic ledger, taxes |
| Districts & Map | Each citizen's district, highlighted on the Stormwind map |
| Chronicle & Honours | The realm's permanent history; honours and titles awarded by the Crown |
| Gladiator's Ring | Monthly 1v1 duelling tournament |
| Letters & Sharing | Personal sealed letters, and text ready to paste into Discord |

## 2. Order of work

1. **Design the UI first** in Claude Design: the full visual theme, textures and every screen, before any code. One consistent theme from day one, so nothing has to be reskinned later.
2. **Plan each system in detail**, one module at a time. Each module gets its own file in `plan/` (see section 13), linked from here.
3. **Build** the add-on.

## 3. Decisions made

- **Syncing uses WoW's built-in addon messages** (`C_ChatInfo.SendAddonMessage` on the `GUILD` channel). They're hidden from chat, only reach guild members, and need no custom channel. A custom chat channel was rejected because anyone on the realm could join it and post fake data. Each client sends its own data periodically and reads everyone else's. *(Decided 2026-11-03)*
- **A citizen's district and other add-on details live in the add-on's own synced data, not in guild notes.** Officer notes can only be read by ranks with permission, and this leaves public and officer notes free for members to use as normal. *(Decided 2026-11-03)*
- **District map highlights:** a citizen's own district is drawn as a highlighted area on the Stormwind city map. *(Decided 2026-11-03)*
- **Visual theme:** regal Stormwind/Alliance. Parchment, wax seals, royal blue and gold. It must feel premium and ceremonial, not basic. *(Decided 2026-11-03)*
- **Universal window crest:** the Stormwind Alliance crest (gold lion-head shield on royal blue, crossed swords, hammer on top, gold filigree) sits at the **top-left corner of every add-on window**, breaking out over the frame border, as the shared mark of the whole UI. Reference image: `design/reference/alliance-crest.png`. In game, check for a built-in texture/atlas of the crest before shipping our own. *(Decided 2026-11-03)*
- **Voting is direct, not by constituency.** The Prime Minister is elected in one guild-wide count, and every citizen's vote counts the same (the Charter: "direct popular vote of all citizens"). Votes of No Confidence are guild-wide too. A citizen's district never changes the weight of their vote. Districts only matter when electing each district's Regional Representative (Charter 8.2). *(Confirmed 2026-11-03)*
- **The Treasurer is appointed by the PM**, as the Minister of the Treasury (Charter 2.2), not elected. *(Decided 2026-11-03)*
- **No waiting period for brand-new members.** The 10-day rule in 11.2 only applies to citizens returning from inactivity. *(Decided 2026-11-03)*
- **Ballots stay on the guild channel, counted by every member (11.3).** Claude pointed out that someone running their own script could log who voted for what, since add-on messages always carry the sender's name. Max judged that unlikely and kept the simpler design; ballots aren't routed through private scrutineers. *(Decided 2026-11-03)*
- **Everyone's add-on reads the guild bank money log** (11.9), not just the Treasurer's. *(Decided 2026-11-03)*
- **Debates happen on Discord voice chat, not in game chat.** The add-on doesn't run in-game debate tools (11.17). *(Noted 2026-11-03)*

## 4. Open questions / to test after launch

- **Auto promote/demote:** test once WoW Forever is live (launches 2026-11-04). The game only lets a character whose rank has promote/demote permission do it, so the result is probably applied by a Crown/officer client. It may need a button click rather than happening fully on its own.
- **Addon message limits:** check the throttle on message size and rate, and whether the Midnight-era restrictions block addon messages in instances or combat. This decides how often we sync and how compact the data must be.
- **Vote integrity:** answered by alt links (11.1), the active roll (11.2) and the independent count (11.3); the Crown confirms every result. Accepted risk: see section 3 on ballots.
- **Honour titles:** check that the add-on can still add text to friendly nameplates and the mouseover tooltip in the Midnight-era client (11.5).
- **Chat tags:** check that the add-on can still change how guild chat lines are displayed (11.6).
- **Duel results:** expected to work, since "X has defeated Y in a duel" is an ordinary chat system message. Quick check after launch (11.8).
- **Guild bank money log:** check which guild ranks can see it, and how many entries the game keeps before old ones drop off (11.9).
- **Trade window warning:** check the add-on can show a warning when a trade window opens with a citizen under embargo (11.15).
- **Interface (TOC) version number** for the Forever client: read it in game with `/dump (select(4, GetBuildInfo()))`.

## 5. Game client (researched 2026-11-03)

WoW: Forever is a **Classic-era game (levels 1–60, original Azeroth) running on the modern retail ("Mainline") engine and add-on API**, reported as Midnight / 12.1.x-era. In practice:

- Write the add-on against the **modern retail API**, not the Classic Era API. Classic Era add-ons don't load in Forever.
- Modern UI tools are available: modern map API (`WorldMapFrame` data providers / pins), Settings panel, `C_ChatInfo`, modern templates and atlases.
- Midnight added combat restrictions for add-ons. They mostly affect combat UI, which this add-on doesn't need, but see the testing items in section 4.
- The add-on goes in the Forever client's own `Interface/AddOns` folder.
- **Forever has a guild bank**, with the game's money log (confirmed by Max, 2026-11-03). See 11.9.
- Sources are mostly fan guides from launch week, so confirm the details in game.

## 6. Pages (screens) to design

**Rule: one page per subject.** Related screens live together on one page, as sub-views that swap in and out inside that page (sub-tabs, a toggle, or a pop-out). Members never have to hunt through lots of separate windows. *(Decided 2026-11-03)*

The add-on is **one window with seven pages**. Every page shares the same frame: parchment body, royal blue and gold border, wax-seal accents, and the Alliance crest in the top-left corner. During an election, a phase banner runs across the top of every page (11.10).

1. **The Throne Room (home).** The first page when you open the add-on. It shows the state of the realm at a glance:
   - who holds power: the Crown, the PM and Cabinet, the Leader of the Opposition
   - the countdown to the next election
   - any vote open right now, with a button to go and vote
   - your own district and party
   - **your duties**, if you hold an office (11.14), and **your letters** (11.18)
   - a short feed of recent decrees, such as a law passed or a result announced, opening into the full **Chronicle** (11.4)
2. **The Ballot Hall (all voting).** Everything to do with votes, on one page.
   - **Ballot** (shown by default while a vote is open): the parchment ballot paper. You seal your vote with the wax-seal "Cast Vote" button.
   - **Nominations:** standing for PM, with the candidacy check (11.11).
   - **Results** (shown by default when no vote is open): the Crown's proclamation of the last result, plus past elections. Shows the independent count check (11.3).
   - **No-confidence petition:** progress towards the 40% threshold and the days left in the seven-day window, or the cooling period after a failed one (11.12). When a vote of no confidence is open it can be signed here, replacing the in-game mail to the Crown.
3. **The Statute Book (laws, the court and treaties).**
   - **In force:** active laws, each with a countdown to its three-month expiry.
   - **Awaiting Royal Assent / up for renewal / Council consultation** (11.13).
   - **Rulings of the High Judiciary:** censures, fines and other judgements on public record (11.15).
   - **Treaties:** the diplomacy register (11.20).
4. **The Parties.**
   - **Public face:** each party's crest, colours, leader, members, manifesto and published donation total (11.19). Everyone can see this.
   - **Party Chamber:** the private side, with plans, notes and whip notices. Only verified members of that party can see it (see section 7).
5. **The Treasury.** The ledger in an old accounts-book style: the Minister of the Treasury, the balance, gold in and out, and taxes. Filled in automatically from the guild bank's money log (11.9).
6. **The Districts.**
   - **Map:** the Stormwind map with your district glowing in its colour, plus a pin on your council meeting spot.
   - **Regional Council:** the five Representatives and their districts' records.
   - **Citizen Roll:** every citizen with their district, party and office.
   - **Assignments & transfers** (11.16).
7. **The Gladiator's Ring.** The monthly 1v1 duelling tournament: Sign-up, the Bracket, and the Hall of Champions (see 11.8).

**Small extras:**
- **Minimap seal:** a wax-seal button that opens the add-on.
- **Herald pop-ups:** live notices such as "Polls are open!" (see section 8).
- **Sealed letters:** personal notices you break open (11.18).
- **Citizen card:** a small card shown when you hover over a guild member, with their district, party, offices held, honours, any unpaid fine or embargo, and whether they have voted (never how they voted).
- **Settings panel:** the add-on's options in the standard game settings.

## 7. Party privacy (secret party information)

The goal is that neither party can see the other party's private chamber. Joining a party and quickly switching sides to spy shouldn't be possible.

Proposed design *(to confirm with Max; also needs matching to Charter 3.2, see section 10)*:

- **Party membership is public, party business is private.** Who belongs to which party is visible to all, like real politics. The Party Chamber is not.
- **Only the party's leadership can admit members.** The Party Leader is registered with the Crown, as the Charter already requires. The leader can name a few **Whips** who can also admit members. A citizen applies, then the leader or a whip approves. Nobody can flag themselves into a party.
- **"Crossing the floor" is slow and public.** Leaving a party is announced to the whole guild by herald, and access to the old chamber ends at once. There's then a cooling-off period, for example 14 days, before another party can admit that person. Quick spy-switching becomes impossible, and a defection becomes a visible political event.
- **Chamber data never goes on the guild channel.** It's sent only by private add-on whisper to characters on that party's verified roster. Members of the other party never receive it at all, so there's nothing to snoop on.
- **Changes to the party roster are only accepted from the leader's or a whip's character.** WoW tells the receiver the real sender of every add-on message, and that can't be faked, so every client can check who issued each change.
- **Honest limits.** A real defector keeps whatever they already read, which is a spy, and that's good roleplay. A player skilled enough to rewrite the add-on's code could still cause trouble, so this is strong guild-level security, not bank-level.

## 8. Live herald pop-ups

- When something happens (polls open, a result is declared, a law passes, someone crosses the floor, a petition reaches its threshold), the add-on that triggered it sends a guild add-on message. Every online member gets it **instantly**: a herald pop-up slides in with a fanfare from the game's own sounds.
- Members who are offline see missed notices when they next log in and sync.
- Pop-ups wait until you're out of combat, and they can be toned down in settings.

## 9. Design work

The visual design is done in Claude Design. Style brief: `design/STYLE_BRIEF.md`.

- **Design canvas:** https://claude.ai/artifact/V6ZmxpJtw85SrWT9S87acJ (private until shared from its Share menu). It has the style guide, the pages as a clickable prototype, and the small extras.
- **Textures and seals:** `design/textures/` holds the parchment, leather, filigree, divider and four wax seals, as SVG. These get converted to game textures (TGA/BLP) at build time.
- **Canvas source:** `design/canvas-source/` holds a copy of the boards and the shared stylesheet.
- Names, gold amounts, vote counts and laws on the boards are sample data.
- **To update on the boards:** the Treasury board still says the Treasurer was "Elected"; change it to appointed by the PM.

## 10. Open items (to come back to)

Kept open on purpose. Max will come back to these later.

- **The real map:** the Districts board uses an illustrated Stormwind chart. In game, the glow is drawn over the real Stormwind map using zone coordinates, so district shapes need tracing against the live map after launch.
- **Party membership (Charter 3.2, added 2026-11-03) and section 7:** joining a party now means paying at least 5g to the party's designated officer, and party members elect their leader by internal vote. To decide: (1) the designated officer admits members in the add-on once the 5g arrives, replacing "leader or whip approves"; (2) the internal leadership vote runs inside the Party Chamber; (3) keep a cooling-off period (e.g. 14 days) before someone who leaves can join the other party.
- **Ledger privacy (11.9):** the add-on shows the guild bank money log on the Treasury page to every citizen, including ranks the game wouldn't normally let see it. So everyone would see lines like "Bram withdrew 50g". Decide: show every entry with names (fully public accounts), or show deposits by name but withdrawals only as totals.
- **AI voiceovers (in progress with Max):** spoken lines for the herald, e.g. a town crier calling "Hear ye! The polls are open!" when a pop-up appears. Notes so far:
  - The game can only play sound files that ship inside the add-on's folder, so lines are recorded in advance. Fixed lines work ("The polls are open", "The Crown has declared the result"). Lines with names or numbers in them would need a clip for every name, so those stay as text.
  - The game also has its own text-to-speech that can read any text aloud, but in a flat computer voice. A possible fallback; check it still works for add-ons in the Midnight-era client.
  - The voice must be an original AI voice, not a copy of a Blizzard character or a real actor, and the voice tool's licence must allow sharing the files inside the add-on.
  - Needs an on/off switch and volume in settings, like the herald pop-ups.
- **The Court (Charter 6 and 7):** how accusations, defences, rulings and appeals work in the add-on. Explained to Max 2026-11-03; waiting on his answer.

## 11. Features added after the first design pass

Agreed with Max on 2026-11-03. Each one lives inside an existing page, apart from the Gladiator's Ring, which is a new subject and so gets its own page.

### 11.1 One person, one vote (alt links)

- Players link their alts to their main character in the add-on. A link only counts once it's confirmed from the alt itself (log in on the alt and accept), so nobody can claim someone else's character.
- Only the main gets a ballot. Every client refuses a vote or petition signature sent from a linked alt.
- Honest limit: an alt that nobody has declared can't be spotted automatically. The activity rules in 11.2 and the Crown's power to rule on disputed votes cover the rest.

### 11.2 Who counts as an active citizen

- A citizen who hasn't logged in for **30 days or more** drops off the active roll. The add-on reads "last online" from the game's guild roster. This matches Charter 5.3, and the add-on publishes the count the Crown would otherwise keep by hand.
- Inactive citizens don't count towards any threshold or turnout figure, including the 40% needed for a Vote of No Confidence.
- **Coming back doesn't restore the vote straight away.** A citizen who returns fewer than **10 days before a vote opens** can't vote in it, or sign a no-confidence petition opened in that time. They're back on the roll for the next one. This stops dormant characters being woken up to cast phantom votes.
- Brand-new members can vote straight away (section 3).

### 11.3 Independent count check

- Every member's add-on counts all the ballots itself. The Results view shows how many agree, e.g. "Count agreed by 31 of 31 members".
- If any count disagrees, the Crown sees which ballots differ before declaring the result.

### 11.4 The Chronicle

- A permanent, dated history of the realm: elections and results, laws passed and lapsed, court rulings, defections, honours and Gladiator champions.
- Written automatically from the same events that trigger the herald pop-ups (section 8), and synced, so new members get the whole history.
- Lives in the Throne Room: the recent decrees feed gets a "See all" that opens the Chronicle, browsable by month.

### 11.5 Honours and titles

- The Crown awards honours: orders and titles such as "Order of the Lion". Each one is announced by herald and written into the Chronicle.
- Honours show as ribbons on the citizen card, alongside offices held and terms served.
- Max wants titles shown like a normal WoW title, above the character's head or in front of their name. What the game allows:
  - The name the game draws above a character's head, and real in-game titles, come from Blizzard's servers. No add-on can change or grant them.
  - The add-on **can** put the title in front of the name in the mouseover tooltip, in guild chat (with the chat tags in 11.6), on the citizen card and on the Citizen Roll.
  - The add-on **can** show the title above the head on the **friendly nameplate** (the bar over other players when friendly nameplates are switched on). Only people running the add-on see it, only with friendly nameplates on, and the game blocks it inside dungeons and raids. Stormwind is open world, so it works where the guild meets.
  - Both need testing after launch (section 4).

### 11.6 Chat tags

- In guild chat, each name gets a small tag for their office and party (e.g. [PM] in party colours), plus their honour title if they have one.
- It only changes how chat looks for people running the add-on, and it can be turned off in settings.

### 11.7 Reminders

- On login: any ballot you haven't cast yet, with the time left ("Polls close in 6 hours").
- Shortly before your district's council meeting, before a debate on Discord, and before your bout in the Gladiator's Ring.
- Same rules as the herald pop-ups: they wait until you're out of combat and can be toned down in settings.

### 11.8 The Gladiator's Ring (monthly 1v1 duels)

- A monthly duelling tournament, for fun and for raising gold.
- **Its own page (page 7)** with sub-views: Sign-up, Bracket and Hall of Champions.
- **Organiser:** the **Minister of War**. They open sign-ups, set the entry fee and the level brackets, start the draw and confirm results.
- **Level brackets:** each bracket is its own knockout tournament with its own champion, so low-level characters aren't matched against level 60s. The Minister of War sets the bands (for example 20–29, 30–39 … 60).
- **Sign-up:** citizens enter during the sign-up window and pay the **entry fee** into the guild bank. The ledger (11.9) records it, so the add-on can see who has paid.
- **The pot:** **90% to the winner, 10% stays in the guild bank.** The pot is paid out of the guild bank to the champion after the final; the ledger records it.
- **Bracket:** the add-on draws a knockout bracket and shows it on the page. A herald pop-up calls each bout ("Next bout: Aldric v Mira, Old Town").
- **Results:** the game prints "X has defeated Y in a duel" to everyone nearby. The organiser's add-on reads it and moves the winner on. The Minister of War can also click the winner by hand.
- **Venue:** Old Town, home of the Old Quarter, the warriors' and PvP district.
- **Champion:** gets the title "Gladiator of Stormwind" for the month (via 11.5), a Chronicle entry and a place in the Hall of Champions.

### 11.9 Automatic treasury ledger

WoW: Forever has a guild bank, and the game keeps a money log of every deposit, withdrawal and repair.

- **Everyone's add-on reads the log** (decided, section 3). Whenever any member opens the guild bank, their add-on reads the money log and shares any entries the guild doesn't have yet.
- **Entries are confirmed, not just trusted.** An entry counts as confirmed once two different members' add-ons have reported it, or once it matches the change in the bank's balance. Until then it shows as "awaiting confirmation". This stops one member's add-on inventing entries.
- **No double counting.** The log only gives rough times ("3 hours ago"), so two readings of the same entry won't match exactly. Readings are lined up by their order in the log, so each deposit is counted once.
- **Balance check.** Every reader also reports the bank's gold. Money in minus money out must equal the change in the balance. If it doesn't, an entry is missing and the Treasury page says so.
- **Missed entries.** The log is short, so entries drop off if nobody opens the bank during a busy spell. More readers make this rarer, and the balance check flags any gap.
- **Rank permissions.** Some ranks may not be able to see the money log at all, so they can't help read it.
- **The Minister of the Treasury adds the reasons.** The log shows who moved how much, never why. Only the Minister can add a note such as "raid repairs".
- **Still open:** how public the withdrawals are (section 10).

### 11.10 Elections run themselves

- The add-on follows the Charter's timeline (3.3) without anyone driving it: two weeks of campaigning, then 48 hours of voting, then the Crown declares the result, then the new PM takes office within 24 hours.
- A **phase banner** runs across the top of every page during an election, e.g. "Campaign period: 9 days to polling".
- **Ties:** a run-off between the tied candidates is called automatically, within 48 hours (Charter 2.1).
- **Snap elections:** the Crown can dissolve the government with one sealed act, or a successful no-confidence petition triggers one. The Crown sets the shorter campaign length (Charter 3.5).

### 11.11 Candidacy check

- Standing for PM happens in the Ballot Hall (Nominations). The add-on checks the requirements in force (Charter 3.4): good standing, two weeks as a citizen, and later level 60, raids led and treasury contributions (from the ledger, 11.9).
- Which stage's requirements apply (early, mid or late game) is set by the Crown in settings.
- The Crown can still rule a candidate eligible or ineligible by hand where it's disputed.

### 11.12 No-confidence cooling period

- After a failed Vote of No Confidence, the petition is locked for 30 days (Charter 5.2). The button shows the time left, e.g. "Cooling period: 12 days left".

### 11.13 Laws: renewal, consultation and the Law Registry

- **Renewal list:** when a new PM takes office, they get a list of every law that will lapse, with a two-week countdown (Charter 4.2). They tick the ones to renew; the rest expire.
- **Council consultation:** a law marked as mainly affecting one district shows "Awaiting Council consultation" until that district's Representative has been consulted, before it goes to the Crown for Royal Assent (Charter 8.2).
- **Law Registry:** the add-on produces the registry (laws, dates, authors, expiry) as text the Minister of Justice can copy and publish to the guild's GitHub (Charter 4.3), using 11.21.

### 11.14 Duties panel

- Anyone holding an office sees their own to-do list on the Throne Room. For example:
  - **Crown:** laws awaiting Royal Assent, results to declare, appeals to decide.
  - **PM:** laws to renew, Cabinet posts to fill.
  - **Minister of the Treasury:** ledger entries with no reason yet.
  - **Minister of War:** the Gladiator's Ring (sign-ups, draw, results).
  - **Minister of Recruitment:** new citizens to assign to a district.
  - **Regional Representatives:** consultations and transfer requests.
  - **Justices:** open cases.

### 11.15 Punishments enforced

- When the High Judiciary rules (Charter 7.1), the add-on applies what it can:
  - **Public censure:** written into the Chronicle and the Rulings list permanently.
  - **Treasury fine:** shows on the citizen card as unpaid until the payment shows up in the guild bank ledger (11.9).
  - **Trade embargo:** shown on the citizen card and tooltip. A warning appears if anyone opens a trade window with that citizen. Guild bank access itself has to be removed by an officer through guild ranks.
  - **Suspension from office:** the add-on removes the office straight away.
  - **Exile:** needs the Crown's sign-off; the add-on records it, and an officer removes the character from the guild.
- The 48-hour appeal window to the Crown (Charter 7.2) shows on the ruling.

### 11.16 District assignment and transfers

- **New members** appear in the Minister of Recruitment's duties (11.14). The Minister assigns their district, taking into account class, main activity and what the citizen asked for (CONSTITUENCIES.md).
- **Transfers:** a citizen can apply to move district after one full term. The request needs approval from both Representatives (the old district's and the new one's). Approval is done in the add-on and the move happens automatically.
- **District sizes:** the Minister of Recruitment sees how many citizens each district has, to keep them balanced.

### 11.17 Debates (on Discord)

- The campaign debate is held on Discord voice chat, not in game.
- The add-on announces it: the time goes on the election timeline, a herald pop-up and a reminder (11.7) go out before it starts, and the result of the debate night goes into the Chronicle.

### 11.18 Official letters

- Personal notices arrive as a sealed letter you break open (with a wax-seal crack), rather than a pop-up everyone sees. Examples: a letter of appointment to the Cabinet, a summons from the High Judiciary, a fine, a transfer approved, a party membership accepted.
- Unread letters show on the Throne Room. Guild-wide news stays as herald pop-ups (section 8).

### 11.19 Party membership donations

- Charter 3.2: joining a party costs at least 5g, paid to the party's designated officer. When the gold is traded or mailed to that officer, the officer's add-on records it automatically (who, how much, when).
- At the close of each campaign period the add-on publishes each party's donation total on the Parties page, as the Charter requires.
- How membership itself is granted is still open (section 10).

### 11.20 Diplomacy register

- A list of the guild's relations with other guilds (allied, friendly, neutral, rival) and any treaties, kept by the PM's government. Lives in the Statute Book, under Treaties.
- Members of those guilds get a small relation tag on their tooltip, e.g. "Allied guild: Treaty of Goldshire".

### 11.21 Share to Discord

- Results, laws, rulings, the Law Registry and Gladiator champions can be turned into ready-formatted text. You copy it from a box in the add-on and paste it into Discord (or GitHub).
- Add-ons can't post to Discord themselves, so this is copy and paste.

## 12. Parked (kept on the plan, not being built yet)

- **Notice board:** citizens can have a notice (a rally, a meeting, an event) pinned on the Throne Room. Notices go up only by request and the Crown can take them down. *Agreed 2026-11-03, but not in the first build.*

## 13. Detailed system plans

Each module is planned in detail in its own file, before it's built. Order: Core / Sync first, because every other module depends on it.

| # | Module | File | Status |
|---|---|---|---|
| 1 | Core / Sync | `plan/01-core-sync.md` | In progress |
| 2 | Citizens | — | Not started |
| 3 | Offices & Ranks | — | Not started |
| 4 | Elections & Votes | — | Not started |
| 5 | Laws & Court | — | Not started |
| 6 | Parties | — | Not started |
| 7 | Treasury | — | Not started |
| 8 | Districts & Map | — | Not started |
| 9 | Chronicle, Honours, Letters & Sharing | — | Not started |
| 10 | Gladiator's Ring | — | Not started |
