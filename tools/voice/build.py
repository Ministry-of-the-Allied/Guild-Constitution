"""Builds the add-on's voice clips and Charter text.

  python tools/voice/build.py charter          CHARTER.md -> Charter.lua
  python tools/voice/build.py audio <folder>   the narrator's MP3s -> Media/Voice/voice_NN.ogg

Audio needs Python with imageio-ffmpeg and mutagen, and prints each clip's
length for VOICE_CLIPS in Data.lua (the game can't report a sound's length).
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "MinistryOfTheAllied"

SOURCES = [
    "Introduction", "Part 1 - The Crown", "Part 2 - The Government", "Part 3 - The Parties",
    "Part 4 - Legislation", "Part 5 - Vote of No Confidence", "Part 6 - The High Judiciary",
    "Part 7 - Punitive Measures", "Part 8 - Citenzenship and the Districts", "Welcome to the Realm",
]


def audio(folder):
    import imageio_ffmpeg
    import mutagen
    out = ADDON / "Media" / "Voice"
    out.mkdir(parents=True, exist_ok=True)
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    for i, name in enumerate(SOURCES, 1):
        target = out / f"voice_{i:02d}.ogg"
        subprocess.run([ffmpeg, "-y", "-v", "error", "-i", str(Path(folder) / f"{name}.mp3"), "-vn", "-map_metadata", "-1",
                        "-ar", "44100", "-c:a", "libvorbis", "-q:a", "5", str(target)], check=True)
        print(f"{target.name}  {mutagen.File(target).info.length:.1f}s  {target.stat().st_size // 1024} KB  {name}")


def clean(text):
    text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)
    text = re.sub(r"(?<!\w)\*(.+?)\*(?!\w)", r"\1", text)
    text = re.sub(r"\[(.+?)\]\(.+?\)", r"\1", text)
    return text.replace("`", "").strip()


def charter():
    blocks = []
    for line in (ROOT / "CHARTER.md").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line == "---" or re.fullmatch(r"\|[-| :]+\|", line):
            continue
        if line.startswith("### "):
            blocks.append(("section", clean(line[4:])))
        elif line.startswith("## "):
            blocks.append(("part", clean(line[3:])))
        elif line.startswith("# "):
            continue  # the page has its own heading
        elif line.startswith("|"):
            cells = [clean(c) for c in line.strip("|").split("|")]
            blocks.append(("body", " · ".join(cells)))
        elif re.match(r"[-*] ", line):
            blocks.append(("body", "•  " + clean(line[2:])))
        elif re.match(r"\*[^*].*\*$", line):
            blocks.append(("note", clean(line)))
        else:
            blocks.append(("body", clean(line)))
    quote = lambda s: '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'
    lines = ["-- Generated from CHARTER.md by tools/voice/build.py. Don't edit by hand.", "",
             "local _, MOTA = ...", "", "MOTA.Charter = {"]
    lines += [f"  {{ {quote(k)}, {quote(t)} }}," for k, t in blocks]
    lines.append("}")
    (ADDON / "Charter.lua").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(len(blocks), "blocks written to Charter.lua")


if __name__ == "__main__":
    if sys.argv[1:2] == ["charter"]:
        charter()
    elif sys.argv[1:2] == ["audio"] and len(sys.argv) == 3:
        audio(sys.argv[2])
    else:
        sys.exit(__doc__)
