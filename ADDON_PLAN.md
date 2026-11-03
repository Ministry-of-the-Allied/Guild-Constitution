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
| Elections & Votes | General elections (direct, guild-wide), district Representative elections, law votes, votes of no confidence |
| Citizens | Who counts as an active voter, alt links (one person, one vote) |
| Offices & Ranks | Knows who holds which office (PM, Cabinet, Treasurer, Reps); applies guild promote/demote after results |
| Laws | Register of active laws, their three-month expiry, renewal |
| Parties | Party pages, members, manifestos, district bases, party skins for the world map (11.10) |
| Treasury | Elected treasury owner, balance and spending records |
| Districts & Map | Each citizen's district, highlighted on the Stormwind map |
| Chronicle & Honours | The realm's permanent history; honours and titles awarded by the Crown |
| Gladiator's Ring | Monthly 1v1 duelling tournament |

## 2. Order of work

1. **Design the UI first** in Claude Design: the full visual theme, textures and every screen, before any code. One consistent theme from day one, so nothing has to be reskinned later.
2. **Plan each system in detail**, one module at a time, in this file.
3. **Build** the add-on.

## 3. Decisions made

- **Syncing uses WoW's built-in addon messages** (`C_ChatInfo.SendAddonMessage` on the `GUILD` channel). They're hidden from chat, only reach guild members, and need no custom channel. A custom chat channel was rejected because anyone on the realm could join it and post fake data. Each client sends its own data periodically and reads everyone else's. *(Decided 2026-11-03)*
- **A citizen's district and other add-on details live in the add-on's own synced data, not in guild notes.** Officer notes can only be read by ranks with permission, and this leaves public and officer notes free for members to use as normal. *(Decided 2026-11-03)*
- **District map highlights:** a citizen's own district is drawn as a highlighted area on the Stormwind city map. *(Decided 2026-11-03)*
- **Visual theme:** regal Stormwind/Alliance. Parchment, wax seals, royal blue and gold. It must feel premium and ceremonial, not basic. *(Decided 2026-11-03)*
- **Universal window crest:** the Stormwind Alliance crest (gold lion-head shield on royal blue, crossed swords, hammer on top, gold filigree) sits at the **top-left corner of every add-on window**, breaking out over the frame border, as the shared mark of the whole UI. Reference image: `design/reference/alliance-crest.png`. In game, check for a built-in texture/atlas of the crest before shipping our own. *(Decided 2026-11-03)*
- **World map skins:** the game's world map window is reskinned to match the player's party (or the Crown), with the party seal in the top-left corner in place of the Alliance crest. Details in 11.10. *(Decided 2026-11-03)*
- **Voting is direct, not by constituency.** The Prime Minister is elected in one guild-wide count, and every citizen's vote counts the same (the Charter: "direct popular vote of all citizens"). Votes of No Confidence are guild-wide too. A citizen's district never changes the weight of their vote. Districts only matter when electing each district's Regional Representative (Charter 8.2). *(Confirmed 2026-11-03)*

## 4. Open questions / to test after launch

- **Auto promote/demote:** test once WoW Forever is live (launches 2026-11-04). The game only lets a character whose rank has promote/demote permission do it, so the result is probably applied by a Crown/officer client. It may need a button click rather than happening fully on its own.
- **Addon message limits:** check the throttle on message size and rate, and whether the Midnight-era restrictions block addon messages in instances or combat. This decides how often we sync and how compact the data must be.
- **Vote integrity:** anyone running the add-on could send forged data. We need to decide how votes are verified, e.g. one vote per character, cross-checked by every client, with the result confirmed by the Crown. Partly answered by section 11: alt links (11.1), the active roll (11.2) and the independent count (11.3).
- **Honour titles:** check that the add-on can still add text to friendly nameplates and the mouseover tooltip in the Midnight-era client (11.5).
- **Chat tags:** check that the add-on can still change how guild chat lines are displayed (11.6).
- **Duel results:** check that the "has defeated … in a duel" message reaches add-ons, so the Gladiator's Ring bracket can update itself (11.8).
- **Guild bank money log:** check which guild ranks can see it, and how many entries the game keeps before old ones drop off (11.9).
- **World map window:** check that the Forever client uses the modern world map window (with the quest log docked beside it), that the party skin (11.10) stays on when the map is enlarged or shrunk, and that opening the map in combat causes no errors.
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

The add-on is **one window with seven pages** (the seventh, the Gladiator's Ring, was added after the first design pass). Every page shares the same frame: parchment body, royal blue and gold border, wax-seal accents, and the Alliance crest in the top-left corner.

1. **The Throne Room (home).** The first page when you open the add-on. It shows the state of the realm at a glance:
   - who holds power: the Crown, the PM and Cabinet, the Leader of the Opposition
   - the countdown to the next election
   - any vote open right now, with a button to go and vote
   - your own district and party
   - a short feed of recent decrees, such as a law passed or a result announced, opening into the full **Chronicle** (11.4)
2. **The Ballot Hall (all voting).** Everything to do with votes, on one page.
   - **Ballot** (shown by default while a vote is open): the parchment ballot paper. You seal your vote with the wax-seal "Cast Vote" button.
   - **Results** (shown by default when no vote is open): the Crown's proclamation of the last result, plus past elections. Shows the independent count check (11.3).
   - **No-confidence petition:** progress towards the 40% threshold and the days left in the seven-day window. When a vote of no confidence is open it can be signed here, replacing the in-game mail to the Crown.
3. **The Statute Book (laws and the court).**
   - **In force:** active laws, each with a countdown to its three-month expiry.
   - **Awaiting Royal Assent / up for renewal:** laws waiting on the Crown, or on the new government to renew them.
   - **Rulings of the High Judiciary:** censures, fines and other judgements on public record.
4. **The Parties.**
   - **Public face:** each party's crest, colours, leader, members and manifesto. Everyone can see this.
   - **Party Chamber:** the private side, with plans, notes and whip notices. Only verified members of that party can see it (see section 7).
5. **The Treasury.** The ledger in an old accounts-book style: the Treasurer, the balance, gold in and out, and taxes. Filled in automatically from the guild bank's money log (11.9).
6. **The Districts.**
   - **Map:** the Stormwind map with your district glowing in its colour, plus a pin on your council meeting spot.
   - **Regional Council:** the five Representatives and their districts' records.
   - **Citizen Roll:** every citizen with their district, party and office.
7. **The Gladiator's Ring.** The monthly 1v1 duelling tournament: Sign-up, the Bracket, and the Hall of Champions (see 11.8). *Added 2026-11-03; not designed yet.*

**Small extras:**
- **Minimap seal:** a wax-seal button that opens the add-on.
- **Herald pop-ups:** live notices such as "Polls are open!" (see section 8).
- **Citizen card:** a small card shown when you hover over a guild member, with their district, party, offices held, and whether they have voted (never how they voted).
- **Settings panel:** the add-on's options in the standard game settings, including the world map skin choice (11.10).
- **World map skins:** the party, Crown and Ministry skins for the game's own map window (11.10). Needs a design board.

## 7. Party privacy (secret party information)

The goal is that neither party can see the other party's private chamber. Joining a party and quickly switching sides to spy shouldn't be possible.

Proposed design *(to confirm with Max)*:

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

- **Design canvas (first pass, 2026-11-03):** https://claude.ai/artifact/V6ZmxpJtw85SrWT9S87acJ (private until shared from its Share menu). It has the style guide, all six pages as a clickable prototype, and the small extras.
- **Textures and seals:** `design/textures/` holds the parchment, leather, filigree, divider and four wax seals, as SVG. These get converted to game textures (TGA/BLP) at build time.
- **Canvas source:** `design/canvas-source/` holds a copy of the boards and the shared stylesheet.
- Names, gold amounts, vote counts and laws on the boards are sample data.

## 10. Open items (to come back to)

Kept open on purpose. Max will come back to these later.

- **Treasurer: elected or appointed?** Max wants the treasury owner elected. The Charter (2.2) says the PM appoints the Minister of the Treasury. Pick one and update the Charter or the plan.
- **The real map:** the Districts board uses an illustrated Stormwind chart. In game, the glow is drawn over the real Stormwind map using zone coordinates, so district shapes need tracing against the live map after launch.
- **New members and the 10-day rule:** should someone who has only just joined the guild also wait 10 days before voting? The reason is the same as in 11.2: it stops new alts being made just to vote.
- **Gladiator's Ring details:** level brackets (60s only, or level bands?), the entry fee, how much of the pot goes to the winner, and who organises it.
- **Automatic treasury ledger (11.9):** should anyone's add-on read the guild bank money log, rather than just the Treasurer's? Max leans yes, and Claude agrees: the log is short and old entries drop off, so more readers means fewer missed entries, and the ledger doesn't depend on one person. The downsides and their fixes are listed in 11.9: faked entries (two-reader confirmation), double counting (lining readings up), missed entries (balance check), rank permissions, and the log never saying why money moved. The biggest open point is **privacy**: every member's withdrawals would be shown to the whole guild. Decide later.
- **Party membership (Charter 3.2, added 2026-11-03):** joining a party now means paying at least 5g to the party's designated officer, and party members elect their leader by internal vote. Section 7 hasn't been updated to match yet; left open until Max decides. A likely fit: the designated officer admits members once the 5g arrives, and the leadership vote runs inside the Party Chamber.
- **AI voiceovers:** spoken lines for the herald, e.g. a town crier calling "Hear ye! The polls are open!" when a pop-up appears. Nothing decided yet. Notes so far:
  - The game can only play sound files that ship inside the add-on's folder, so lines are recorded in advance. Fixed lines work ("The polls are open", "The Crown has declared the result"). Lines with names or numbers in them would need a clip for every name, so those stay as text.
  - The game also has its own text-to-speech that can read any text aloud, but in a flat computer voice. A possible fallback; check it still works for add-ons in the Midnight-era client.
  - The voice must be an original AI voice, not a copy of a Blizzard character or a real actor, and the voice tool's licence must allow sharing the files inside the add-on.
  - Needs an on/off switch and volume in settings, like the herald pop-ups.

## 11. Features added after the first design pass

Agreed with Max on 2026-11-03. Each one lives inside an existing page, with two exceptions. The Gladiator's Ring is a new subject, so it gets its own page. The party map skins (11.10) change the game's own world map window rather than a page.

### 11.1 One person, one vote (alt links)

- Players link their alts to their main character in the add-on. A link only counts once it's confirmed from the alt itself (log in on the alt and accept), so nobody can claim someone else's character.
- Only the main gets a ballot. Every client refuses a vote or petition signature sent from a linked alt.
- Honest limit: an alt that nobody has declared can't be spotted automatically. The activity rules in 11.2 and the Crown's power to rule on disputed votes cover the rest.

### 11.2 Who counts as an active citizen

- A citizen who hasn't logged in for **30 days or more** drops off the active roll. The add-on reads "last online" from the game's guild roster.
- Inactive citizens don't count towards any threshold or turnout figure, including the 40% needed for a Vote of No Confidence. The Charter already says "40% of the active citizen population"; this is what defines "active".
- **Coming back doesn't restore the vote straight away.** A citizen who returns fewer than **10 days before a vote opens** can't vote in it, or sign a no-confidence petition opened in that time. They're back on the roll for the next one. This stops dormant characters being woken up to cast phantom votes.

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
- Shortly before your district's council meeting, and before your bout in the Gladiator's Ring.
- Same rules as the herald pop-ups: they wait until you're out of combat and can be toned down in settings.

### 11.8 The Gladiator's Ring (monthly 1v1 duels)

- A monthly duelling tournament, for fun and for raising gold.
- **Its own page (page 7).** It's a subject of its own, so it follows the one-page-per-subject rule with sub-views: Sign-up, Bracket and Hall of Champions. Needs a design board.
- **Sign-up:** citizens enter on the page during the sign-up window and pay the entry fee to the Treasurer.
- **Bracket:** the add-on draws a knockout bracket and shows it on the page. A herald pop-up calls each bout ("Next bout: Aldric v Mira, Old Town").
- **Results:** the game prints "X has defeated Y in a duel" to everyone nearby. The organiser's add-on reads it and moves the winner on. If that doesn't work in game, the organiser clicks the winner instead.
- **Venue:** Old Town, home of the Old Quarter, the warriors' and PvP district.
- **Champion:** gets the title "Gladiator of Stormwind" for the month (via 11.5), a Chronicle entry and a place in the Hall of Champions.
- **Money:** entry fees and donations go to the Treasury and appear in its ledger. Still to decide: the fee, and whether part of the pot goes to the winner (section 10).

### 11.9 Automatic treasury ledger (open decision, see section 10)

WoW: Forever has a guild bank, and the game keeps a money log of every deposit, withdrawal and repair.

- **Anyone's add-on reads the log, not just the Treasurer's.** Whenever any member opens the guild bank, their add-on reads the money log and shares any entries the guild doesn't have yet. Max's reasoning: more readers keep the ledger most accurate.
- **Entries are confirmed, not just trusted.** An entry counts as confirmed once two different members' add-ons have reported it, or once it matches the change in the bank's balance. Until then it shows as "awaiting confirmation". This stops one member's add-on inventing entries.
- **No double counting.** The log only gives rough times ("3 hours ago"), so two readings of the same entry won't match exactly. Readings are lined up by their order in the log, so each deposit is counted once.
- **Balance check.** Every reader also reports the bank's gold. Money in minus money out must equal the change in the balance. If it doesn't, an entry is missing and the Treasury page says so.
- **Missed entries.** The log is short, so entries drop off if nobody opens the bank during a busy spell. More readers make this rarer, and the balance check flags any gap.
- **Rank permissions.** Some ranks may not be able to see the money log at all, so they can't help read it.
- **The Treasurer adds the reasons.** The log shows who moved how much, never why. Only the Treasurer can add a note such as "raid repairs".
- **Open point:** the add-on would show the whole money log to every citizen, including ranks the game wouldn't normally let see it. Decide whether that's wanted (public accounts) or whether withdrawals should be summarised.
- Test after launch: which ranks can see the log, and how many entries it keeps (section 4).

### 11.10 Party map skins

*Agreed with Max on 2026-11-03.*

- The game's own world map window gets a frame in the player's party style. Only the window around the map changes. The map itself, its pins and the district highlights (Districts & Map module) are left alone.
- **What gets skinned (for now):** the whole window: the border, the title bar, the close and resize buttons, the location bar along the top (e.g. "Eastern Kingdoms > Elwynn Forest > Stormwind City") and the quest log docked beside the map. If that turns out to be too much, cut it back later.
- **The skins.** Each one is a version of the one Ministry theme: the same frame shape and materials, with the metal, wax and emblem swapped.
  - **Silverhand:** silver metalwork, argent wax and the blue hand. The party colour (`#1F4290`) is almost the Ministry's own blue, so the silver has to set it apart from the default.
  - **Azeroth Exchange:** deep crimson (`#9E1B22`) and gold, with the coin-scale.
  - **The Crown:** a skin of its own, built around the Crown seal (royal blue wax, gold lion). The Ministry default uses the same blue and gold, so the Crown's must look clearly grander. Details to be designed.
  - **Ministry default:** the royal blue and gold theme, for citizens who aren't in a party (membership is voluntary, Charter 3.2).
- **The corner seal.** On the map, the party's seal takes the top-left corner instead of the Alliance crest, and the Crown has the Crown seal. Citizens who aren't in a party keep the Alliance crest. This is the one exception to the universal crest rule (section 3).
- **Player choice.** Settings offers Party (the default), Ministry or Blizzard's plain map. Under Party, the Crown sees the Crown skin and citizens who aren't in a party see the Ministry default.
- **It follows membership.** Joining or leaving a party (section 7) switches the skin straight away, so crossing the floor shows on the defector's map at once.
- **Only on your own screen.** Each player sees only their own skin, and party membership is public anyway (section 7), so nothing private is shown.
- **How it's built:**
  - The map's border is made of corner and edge pieces, like the tab frame on the design canvas. The add-on swaps those pictures and recolours the rest. It never replaces Blizzard's own map code, which keeps it clear of "taint" (the error that breaks the game's own buttons when add-ons interfere).
  - The game redraws the border whenever the map is enlarged or shrunk, so the add-on puts the skin back on each time.
  - The skins are kept in one list, one entry per party, so a new party or a reworked skin only needs new artwork.
  - Before skinning, the add-on checks that each part of the window is there. If a Blizzard patch has changed the window, the plain map is left alone instead of throwing errors.
  - If another map add-on is running (ElvUI, Leatrix Maps, Mapster), ours steps back and leaves the map to it.
- **Design first:** needs a board on the design canvas showing all four skins before any code is written.
- Test after launch (section 4).

## 12. Parked (kept on the plan, not being built yet)

- **Notice board:** citizens can have a notice (a rally, a meeting, an event) pinned on the Throne Room. Notices go up only by request and the Crown can take them down. *Agreed 2026-11-03, but not in the first build.*
