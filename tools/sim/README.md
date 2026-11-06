# The pretend game client

Runs the add-on in several pretend WoW clients at once, in real Lua 5.1 (the Lua the game uses), and checks what happens: the guild handshake, records, AceComm splitting long messages, relogging, a newer version arriving, a message lockdown, the window, heralds and settings, the Charter narration, and the secret ballot (two Kings, held ballots, hand-over, ties and run-offs).

- `mock.lua`: just enough of the game's API (time, events, guild roster, add-on messages).
- `mock_ui.lua`: pretend frames, textures and fonts, plus what AceComm and ChatThrottleLib need and a pretend `C_EncodingUtil`.
- `sim.py`: starts the clients, passes messages between them and runs the checks.

It needs Python and `lupa` (Python's Lua bridge): `pip install lupa`, or set `MOTA_PYLIB` to a folder holding it. Then, from the repo root:

```bash
python tools/sim/sim.py
```

It ends with `Checks: N passed, 0 failed` and `Lua errors: 0` when all is well. A check passing here doesn't replace testing in the game: the pretend client only knows what it's been taught.
