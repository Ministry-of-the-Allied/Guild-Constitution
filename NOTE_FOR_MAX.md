# Note for Max (and Max's Claude), from Duncan, 7 November 2026

Duncan worked through how parties, leaders and party money should work. **The rules below are Duncan's proposal. The Charter wording needs your agreement as the other King**, so `CHARTER.md` itself hasn't changed. Nothing here is built yet except a test command.

## Party leaders
- **Not a guild rank.** Leaders live in the addon's records, so spare ranks stay free for something fun. The Crown and Minister of War still use ranks.
- **Contests are built into each General Election**, not Snap Elections. A King opens them ceremonially about 28 days out. If nobody does within 2 days, the system opens them.
- **Timetable:** 4 days to stand, 7 days to vote (whenever members log in), and a leader in place by 14 days out. The campaign then runs and never resets.
- **Open ballot:** votes are hidden until the Kings ratify the count, then published to the whole guild.
- **Ties:** a 48-hour run-off, then a King's public `/roll`.
- **Deputy:** the leader's own pick, not the runner-up. They take over without a vote.
- **No leader or deputy:** election day moves back 14 days for an emergency contest, once only per election, so a government can't stay in power by leaving its seat empty.

## The Crown
Apolitical: Kings can't join, lead, fund or campaign for a party, but they do vote in General Elections. **This affects you personally if you planned to join a party.**

## Party money
- Donations, including the 5g to join, go to the **guild bank**, not an officer. The designated officer role goes.
- The ledger keeps public accounts for the Treasury, Silverhand and Exchange. Rival parties can watch each other's money live.
- Kings pay out party money when a leader requests it. The addon can't block a withdrawal, so misuse is exposed on the ledger and is an offence.
- Deposits and withdrawals raise a pop-up asking why, which stays until answered. The Minister of the Treasury can fill in unlabelled general deposits, but can't touch party donations.

## What to look at
- `ADDON_SPEC.md`: 10.16 (leaders) and 10.7 (money)
- `CHARTER_AMENDMENTS_DRAFT.md`: the wording for you both to agree
- `/mota probe bank` (version 0.1.3): a read-only test of what Forever's guild bank lets the addon see. It's worth running at the bank on your rank too. The results decide whether the money system can work as planned.

## Also recently
`2bd68e0` fixed each copy of the addon thinking it was plain "Kíng". You've both since tested the handshake and a live ballot, and they work.

## Built since this note was first written
- **0.2.0:** the party roll (`Party.lua`) and the bank reason prompt (`Bank.lua`, `UI/BankPrompt.lua`). Joining hasn't been tried in game: test it with Duncan, using a citizen-rank character.
- **0.3.0:** the Treasury page and ledger (`Ledger.lua`, `UI/Treasury.lua`). Duncan simplified the plan in spec 10.7: the ledger is the reasons people give, with exact times, and the money log and balance only check it. The books are already open on Duncan's copy, but you won't have that record if you were offline, so the Treasury may say they aren't open. Catch-up is the fix.

Both need a full WoW restart after pulling. Every bank deposit or withdrawal now raises a prompt.

## Next to build
Catch-up, so offline members don't miss records, then automatic Ring fees and leader contests. Please tell Duncan if you disagree with any of this.
