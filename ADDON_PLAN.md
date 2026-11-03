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
| Elections & Votes | General elections, district elections, law votes, votes of no confidence |
| Offices & Ranks | Knows who holds which office (PM, Cabinet, Treasurer, Reps); applies guild promote/demote after results |
| Laws | Register of active laws, their three-month expiry, renewal |
| Parties | Party pages, members, manifestos, district bases |
| Treasury | Elected treasury owner, balance and spending records |
| Districts & Map | Each citizen's district, highlighted on the Stormwind map |

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

## 4. Open questions / to test after launch

- **Auto promote/demote:** test once WoW Forever is live (launches 2026-11-04). The game only lets a character whose rank has promote/demote permission do it, so the result is probably applied by a Crown/officer client. It may need a button click rather than happening fully on its own.
- **Addon message limits:** check the throttle on message size and rate, and whether the Midnight-era restrictions block addon messages in instances or combat. This decides how often we sync and how compact the data must be.
- **Vote integrity:** anyone running the add-on could send forged data. We need to decide how votes are verified, e.g. one vote per character, cross-checked by every client, with the result confirmed by the Crown.
- **Interface (TOC) version number** for the Forever client: read it in game with `/dump (select(4, GetBuildInfo()))`.

## 5. Game client (researched 2026-11-03)

WoW: Forever is a **Classic-era game (levels 1–60, original Azeroth) running on the modern retail ("Mainline") engine and add-on API**, reported as Midnight / 12.1.x-era. In practice:

- Write the add-on against the **modern retail API**, not the Classic Era API. Classic Era add-ons don't load in Forever.
- Modern UI tools are available: modern map API (`WorldMapFrame` data providers / pins), Settings panel, `C_ChatInfo`, modern templates and atlases.
- Midnight added combat restrictions for add-ons. They mostly affect combat UI, which this add-on doesn't need, but see the testing items in section 4.
- The add-on goes in the Forever client's own `Interface/AddOns` folder.
- Sources are mostly fan guides from launch week, so confirm the details in game.

## 6. Pages (screens) to design

**Rule: one page per subject.** Related screens live together on one page, as sub-views that swap in and out inside that page (sub-tabs, a toggle, or a pop-out). Members never have to hunt through lots of separate windows. *(Decided 2026-11-03)*

The add-on is **one window with six pages**. Every page shares the same frame: parchment body, royal blue and gold border, wax-seal accents, and the Alliance crest in the top-left corner.

1. **The Throne Room (home).** The first page when you open the add-on. It shows the state of the realm at a glance:
   - who holds power: the Crown, the PM and Cabinet, the Leader of the Opposition
   - the countdown to the next election
   - any vote open right now, with a button to go and vote
   - your own district and party
   - a short feed of recent decrees, such as a law passed or a result announced
2. **The Ballot Hall (all voting).** Everything to do with votes, on one page.
   - **Ballot** (shown by default while a vote is open): the parchment ballot paper. You seal your vote with the wax-seal "Cast Vote" button.
   - **Results** (shown by default when no vote is open): the Crown's proclamation of the last result, plus past elections.
   - **No-confidence petition:** progress towards the 40% threshold and the days left in the seven-day window. When a vote of no confidence is open it can be signed here, replacing the in-game mail to the Crown.
3. **The Statute Book (laws and the court).**
   - **In force:** active laws, each with a countdown to its three-month expiry.
   - **Awaiting Royal Assent / up for renewal:** laws waiting on the Crown, or on the new government to renew them.
   - **Rulings of the High Judiciary:** censures, fines and other judgements on public record.
4. **The Parties.**
   - **Public face:** each party's crest, colours, leader, members and manifesto. Everyone can see this.
   - **Party Chamber:** the private side, with plans, notes and whip notices. Only verified members of that party can see it (see section 7).
5. **The Treasury.** The ledger in an old accounts-book style: the Treasurer, the balance, gold in and out, and taxes.
6. **The Districts.**
   - **Map:** the Stormwind map with your district glowing in its colour, plus a pin on your council meeting spot.
   - **Regional Council:** the five Representatives and their districts' records.
   - **Citizen Roll:** every citizen with their district, party and office.

**Small extras:**
- **Minimap seal:** a wax-seal button that opens the add-on.
- **Herald pop-ups:** live notices such as "Polls are open!" (see section 8).
- **Citizen card:** a small card shown when you hover over a guild member, with their district, party, offices held, and whether they have voted (never how they voted).
- **Settings panel:** the add-on's options in the standard game settings.

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

## 10. Questions raised by the design

- **Treasurer: elected or appointed?** Max wants the treasury owner elected. The Charter (2.2) says the PM appoints the Minister of the Treasury. Pick one and update the Charter or the plan.
- **The real map:** the Districts board uses an illustrated Stormwind chart. In game, the glow is drawn over the real Stormwind map using zone coordinates, so district shapes need tracing against the live map after launch.
