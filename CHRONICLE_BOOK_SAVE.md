# Chronicle book: explosive holy light (save, 10 Nov 2026)

## Done (uncommitted)
- `tools/textures/chronicle.py`: explosive light. Timings: cover flung open in 0.3 s; 9 pages flung up into a fan (144 to 36 degrees), hanging about 0.6 to 1.2 s, then falling slowly one by one; done at 2.05 s. Page angles every 6 degrees (29 pictures; chronicle.tga stays 1024 x 2048). The light on the pages settles sooner ("front" timing), so the fan shows. Lights are centred on the book as it slides. The steady light shrinks to fit inside the plate ("rest" sizes). Motes: a burst flung out in an upward fan, then a few rising. The preview now shows the real surroundings (Recent decrees above, page to the left, scroll bar) and cuts the light where the game's scroll area does (the plate's right edge and its foot).
- Previews (sent to Max): `C:\Users\maxim\AppData\Local\Temp\claude\79dfcd584e5346a3\d7f9ab66-73fd-42b5-8943-695bd32e300b\scratchpad\send\` (before/after GIF and steps, plus all four skins). Rendered pictures: `...\scratchpad\book3` (`--reuse` works from there).
- `UI/ChronicleBook.lua`: mirrors state() (pageAngle, the shockwave ring, rest sizes, front timing, the "here" box, motes burst and fling, MOTES 56, TURNING 10). Holy sound: the first the game plays of Bastion celebration, Kyrian renown, legendary loot, artifact gold trait, epic loot, level-up. `Book:Ready()` guard: with old Media.lua there is no book, so no errors.
- `Commands.lua`: `/mota booksound [n]` lists the holy sounds, or plays one and chooses it.
- `tools/sim/mock_ui.lua`: Bastion sound kit; PlaySound returns true.
- `tools/sim/sim.py`: book checks updated and new ones added: the count, the burst, the fan, the ring gone, the fall, the steady light inside the plate, the rays turning, and a layer-by-layer mirror check against chronicle.py. **Not run yet** (needs the rebuild).
- Backups for the rebuild check: `...\scratchpad\Media.before.lua`, `tga.before.sha1`.

## Next steps (after Max's ok)
1. In PowerShell, run `python tools/textures/build.py` in the background (about 5 minutes). Then run `python <old scratchpad>\media_diff.py <Media.before.lua> addon/MinistryOfTheAllied/Media.lua` (the old scratchpad is `...\c6b7c92c-...\scratchpad`). Only chronicle pieces may be new; none may be lost; the other .tga files must match `tga.before.sha1`.
2. Run `python tools/sim/sim.py`: the baseline was 894 passed, 0 failed. Fix any failing book checks.
3. Records: ADDON_SPEC.md 10.3 paragraph (line ~638, still says "seven pages ... 1.8 s ... never flashes") plus the 3D bullet (pages at 29 angles), 19.1 bullet (line ~1221: what to check, including /mota booksound); a DESIGN_CHANGES_PLAN.md progress-log entry; ThroneRoom.dc.html: add the count at the plate's top right, logged under Canvas sync debt. chronicle-closed/open.png are unchanged (no regeneration needed). Update the notes folder file `chronicle-book.md`.
4. Tell Max what to check in game: the burst, the fan and fall, the sound, `/mota booksound`, the four skins, the count, frame rate. Do not commit.

## Questions for Max (answer before building)
1. Are the new previews okay to build into the game, or does something need changing?
2. The burst breaks out over the page above and to the left, but the game's scroll area cuts it flat at the plate's right edge and its foot. Is that fine as it is?
3. The holy sound was chosen by name, unheard. Is that okay as the default, to be checked in game with `/mota booksound`?
