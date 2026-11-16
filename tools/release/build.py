"""Builds the published (CurseForge) copy of the add-on.

The repo is the dev space: comments there keep who decided what and when.
The published copy carries none of that. This script:

  1. copies addon/MinistryOfTheAllied to release/MinistryOfTheAllied,
  2. strips every comment from our own Lua files and the .toc
     (third-party libraries under Libs/ are left exactly as they are),
  3. refuses to finish if any name in NAMES is still found in our files,
  4. zips it as release/MinistryOfTheAllied-<version>.zip, ready to upload.

From the repo root:  python tools/release/build.py
Then check it:       python tools/sim/sim.py release/MinistryOfTheAllied
"""
import os, re, shutil, sys, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(ROOT, "addon", "MinistryOfTheAllied")
OUT_DIR = os.path.join(ROOT, "release")
DST = os.path.join(OUT_DIR, "MinistryOfTheAllied")

# Names that must never reach the published copy (whole words). "Max" is matched
# with its capital only, so the code word "max" (math.max, prof.max) isn't flagged.
NAME_RE = re.compile(r"\b((?i:duncan|duncp|claude|anthropic)|Max)\b")


def long_bracket(src, i):
    """If src[i] opens a [[ or [==[ long bracket, return its level, else None."""
    m = re.match(r"\[(=*)\[", src[i:])
    return len(m.group(1)) if m else None


def strip_lua(src):
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == "-" and src.startswith("--", i):
            j = i + 2
            lvl = long_bracket(src, j) if j < n and src[j] == "[" else None
            if lvl is not None:
                close = "]" + "=" * lvl + "]"
                end = src.find(close, j)
                end = n if end < 0 else end + len(close)
                out.append("\n" * src.count("\n", i, end))  # keep line numbers
                i = end
            else:
                end = src.find("\n", i)
                i = n if end < 0 else end
            continue
        if c in "'\"":
            j = i + 1
            while j < n and src[j] != c:
                j += 2 if src[j] == "\\" else 1
            out.append(src[i:j + 1]); i = j + 1
            continue
        if c == "[":
            lvl = long_bracket(src, i)
            if lvl is not None:
                close = "]" + "=" * lvl + "]"
                end = src.find(close, i)
                end = n if end < 0 else end + len(close)
                out.append(src[i:end]); i = end
                continue
        out.append(c); i += 1
    # Drop trailing spaces and the blank runs left behind, but keep line count.
    return "\n".join(l.rstrip() for l in "".join(out).split("\n"))


def strip_toc(src):
    keep = [l for l in src.splitlines() if l.startswith("##") or not l.lstrip().startswith("#")]
    return "\n".join(keep).strip("\n") + "\n"


def ours(rel):
    return not rel.replace("\\", "/").startswith("Libs/")


def main():
    if os.path.isdir(DST):
        shutil.rmtree(DST)
    shutil.copytree(SRC, DST)

    problems, version = [], None
    for base, _, files in os.walk(DST):
        for f in files:
            path = os.path.join(base, f)
            rel = os.path.relpath(path, DST)
            if not ours(rel) or not f.endswith((".lua", ".toc", ".xml", ".txt")):
                continue
            text = open(path, encoding="utf-8").read()
            if f.endswith(".lua"):
                text = strip_lua(text)
            elif f.endswith(".toc"):
                text = strip_toc(text)
                m = re.search(r"^## Version:\s*(\S+)", text, re.M)
                version = m and m.group(1)
            with open(path, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(text)
            for no, line in enumerate(text.splitlines(), 1):
                if NAME_RE.search(line):
                    problems.append(f"{rel}:{no}: {line.strip()[:120]}")

    if problems:
        print("Names still in the published copy; fix these in the source first:")
        print("\n".join(problems))
        sys.exit(1)

    zpath = os.path.join(OUT_DIR, f"MinistryOfTheAllied-{version or 'dev'}.zip")
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for base, _, files in os.walk(DST):
            for f in files:
                p = os.path.join(base, f)
                z.write(p, os.path.relpath(p, OUT_DIR))
    print(f"Built {os.path.relpath(zpath, ROOT)} (version {version}). No names found.")


if __name__ == "__main__":
    main()
