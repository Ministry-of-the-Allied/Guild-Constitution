# 1 · Core / Sync — detailed plan

Part of the add-on plan (`ADDON_PLAN.md`, section 13). Core / Sync is the base every other module stands on: how the add-on stores the guild's records, shares them between members, and decides which records to trust.

Status: **in progress**, first draft 2026-11-03. Items marked *(to test)* need checking in game after launch on 2026-11-04.

---

## 1. The big idea: a shared book of records

Everything that happens in the Ministry is written down as a **record**: "Max cast a ballot", "the Crown gave Royal Assent to the Raid Tithe Act", "Bram deposited 5g", "Aldric beat Mira in a duel".

- Records are **only ever added, never edited or deleted.** A correction is a new record ("the Crown voided ballot 41"). This makes syncing simple: two members' books are merged by putting together every record either of them has.
- Every page in the add-on is worked out from the records. The current PM, the laws in force, the treasury balance, the Gladiator bracket: all of it is calculated by reading the book from start to finish.
- Every member's add-on keeps its own full copy of the book. If anyone stops playing, nothing is lost.

### What a record holds

| Field | Example | Notes |
|---|---|---|
| Author | `Max-Realm` | The character who created it |
| Number | `57` | The author's own running count: their 1st record, 2nd, 3rd… |
| Time | `1793812345` | The realm's server time (`GetServerTime()`), so every member agrees on deadlines |
| Type | `ballot.cast` | What happened (full list in each module's plan) |
| Details | `{election=12, choice=2}` | Kept as short as possible |

Author + Number is the record's unique ID ("Max's record 57"). No two records share one.

## 2. Storage

- Saved with WoW's normal add-on storage (SavedVariables), account-wide, so alts on the same account share one book.
- The game only writes this to disk on logout or `/reload`. A crash can lose the last session's records from that computer, but they'll come back from other members at the next sync.
- **Size budget:** a busy guild of 100 members might create a few thousand records a year. Kept compact, that's well within what add-ons normally store. Old ballot details can be folded into a single "result" record after the result is declared and the appeal window has passed, so the book doesn't grow forever.

## 3. Sending messages

- One add-on message prefix, `MotA`, registered with `C_ChatInfo.RegisterAddonMessagePrefix`.
- **Channels:**
  - `GUILD` for almost everything.
  - `WHISPER` for private things: Party Chamber business (section 7 of the main plan) and catching up a single member.
- **Limits** *(to test)*: each message can carry at most 255 characters, and the game throttles how fast an add-on can send (roughly a burst of about 10, then about one a second per prefix). So:
  - Records are packed tightly, compressed, and split into pieces when they're too long.
  - Everything goes through one send queue that stays under the limit, with live news (herald events) jumping the queue ahead of background catch-up.
- **Libraries:** use the standard, widely used community libraries rather than writing our own: **Ace3** (AceComm for split messages and the queue, AceDB for storage, AceConfig for settings), **LibSerialize** and **LibDeflate** for packing and compressing. All have permissive licences that allow shipping them inside the add-on.

## 4. Keeping everyone in step

### Live news

When a member does something (casts a ballot, opens a vote), their add-on writes the record and sends it straight away to the guild. Everyone online gets it within a second or two, and any herald pop-up fires.

### Catching up

Members who were offline need everything they missed. The add-on does this with a **summary**:

1. On login, and then every few minutes, an add-on sends a short summary: for each author, the highest record number it has ("Max: 57, Bram: 112, …").
2. Anyone who hears a summary compares it with their own book. If they have records the other member is missing, they offer to send them.
3. To stop 40 members all answering at once, each waits a short random moment first. If someone else starts sending the same records, the others stand down.
4. The missing records are sent by whisper to that member only, through the slow queue, so catch-up never crowds out live news.

### Fresh installs

A member installing the add-on for the first time has an empty book. They catch up the same way; it just takes a little longer. The Throne Room shows "Catching up with the realm… 64%" until it's done.

## 5. Trust: which records count

Add-on messages always carry the real name of the character who sent them, and that can't be faked. Everything about trust is built on that.

### Records sent by their own author

Accepted, as long as the author is **allowed** to create that type of record (see the rules below). A citizen can cast their own ballot; only the Crown can give Royal Assent.

### Records passed on by someone else

During catch-up, members pass on other people's records, so the sender isn't the author. A forged record could slip in this way. Rule:

- A passed-on record is held as **unconfirmed** until either its author sends it themselves, or two different members have passed on an identical copy.
- Unconfirmed records are shown greyed out where it matters (for example, a ballot that hasn't been confirmed isn't counted yet).

### Who is allowed to do what

Permission comes from the book itself, rooted in something the game controls: **guild rank**.

- **The Crown** is defined by guild rank, which only the Guild Master can set, so nobody can claim it through the add-on. *To decide at setup: which rank(s) mean "the Crown" (the Guild Master's rank plus the co-monarch's rank).*
- Every other office comes from records the Crown or the voters created. The PM is whoever won the last declared election; Cabinet ministers are whoever the PM appointed; Justices are whoever the Crown appointed; and so on.
- So when a record arrives, the add-on checks: "at the time of this record, did its author hold an office that allows it?" If not, it's ignored.

Each module's plan lists its own record types and who may create them.

### Honest limits

This is strong protection against ordinary mischief, not bank-level security. A player who rewrote the add-on could still send odd records under their own name, but they can't pretend to be someone else, and they can't act with an office they don't hold.

## 6. Time and deadlines

- Every record uses the realm's server time, so a vote that closes "at 8pm" closes at the same moment for everyone, whatever their computer's clock or time zone says.
- Displayed times are shown in each member's own local time.

## 7. Versions

- Every message carries a **protocol version** number.
- If a member's add-on is out of date, it shows a notice: "A newer version of the Ministry add-on is in use. Please update." It keeps reading what it can understand, but won't send records in an old format.
- New record types are added so older add-ons can safely skip ones they don't know about.

## 8. Combat and instances *(to test)*

- If the Midnight-era client blocks add-on messages in combat or inside instances, the send queue simply waits and sends when it can.
- Herald pop-ups already wait until you're out of combat (main plan, section 8).

## 9. Privacy of personal records

- Records that are only meant for one person (official letters, a court summons) still travel on the guild channel so they reach the person even after being offline. The add-on only **shows** them to the person they're for.
- This matches the decision on ballots (main plan, section 3): someone running their own script could read these. Max judged that unlikely. Party Chamber business is the exception: it only ever travels by whisper to that party's members.

## 10. Commands and troubleshooting

- `/mota` opens the window. `/mota sync` shows sync status: how many records you have, how many are unconfirmed, and when you last caught up.
- A "Resync" button in settings asks the guild to send everything again, for when something looks wrong.

## 11. Open questions

- Which guild rank(s) mean "the Crown" (section 5).
- Message size and throttle limits in the Forever client (section 3) *(to test)*.
- Whether add-on messages are blocked in combat or instances (section 8) *(to test)*.
