"""Makes "Ministry Decorative" from Cinzel Decorative (SIL OFL 1.1).

Cinzel Decorative joins some letter pairs on purpose with very large kerning:
"h" runs into the next capital-height letter (so "the" reads as "tHE" with the H
and E sharing a stroke) and "oo" interlocks (so "Book" shows one double-O).
Max asked for normal spacing for the "h" joins but liked the interlocking "oo"
(8 Nov 2026), so this copy sets every kerning adjustment of JOIN or more to zero,
except the pairs in KEEP, and keeps everything else.

The OFL reserves the name "Cinzel", so the changed font is renamed.

    python tools/fonts/make_ministry_decorative.py
"""
from pathlib import Path

from fontTools.ttLib import TTFont

FONTS = Path(__file__).resolve().parents[2] / "addon" / "MinistryOfTheAllied" / "Media" / "Fonts"
JOIN = -300  # the joins are -384 to -560; ordinary kerning in these fonts stays above -130
KEEP = {("o", "o")}  # glyph names: the interlocking double O stays
FILES = {"CinzelDecorative-Bold.ttf": "MinistryDecorative-Bold.ttf",
         "CinzelDecorative-Black.ttf": "MinistryDecorative-Black.ttf"}


def unjoin(value):
    """Zeroes a ValueRecord's advance if it is a join; returns 1 if it changed."""
    if value is not None and getattr(value, "XAdvance", 0) and value.XAdvance <= JOIN:
        value.XAdvance = 0
        return 1
    return 0


def patch(font):
    n = 0
    for lookup in font["GPOS"].table.LookupList.Lookup:
        subs = lookup.SubTable
        if lookup.LookupType == 9:
            subs = [s.ExtSubTable for s in subs]
        for st in subs:
            if not hasattr(st, "Coverage") or not hasattr(st, "Format") or not (hasattr(st, "PairSet") or hasattr(st, "Class1Record")):
                continue
            if st.Format == 1:
                for first, ps in zip(st.Coverage.glyphs, st.PairSet):
                    for rec in ps.PairValueRecord:
                        if (first, rec.SecondGlyph) not in KEEP:
                            n += unjoin(rec.Value1)
            elif st.Format == 2:
                for c1 in st.Class1Record:
                    for c2 in c1.Class2Record:
                        n += unjoin(c2.Value1)
    return n


def rename(font):
    for rec in font["name"].names:
        s = rec.toUnicode()
        t = s.replace("Cinzel Decorative", "Ministry Decorative").replace("CinzelDecorative", "MinistryDecorative")
        if rec.nameID in (1, 3, 4, 6, 16, 17, 18, 21, 22) and t != s:
            rec.string = t
    font["name"].setName("Ministry Decorative is Cinzel Decorative by Natanael Gama, changed for Ministry of the Allied "
                         "(the 'h' joins spaced normally; the double O kept). SIL Open Font License 1.1.", 5, 3, 1, 0x409)


if __name__ == "__main__":
    for src, dst in FILES.items():
        font = TTFont(FONTS / src)
        changed = patch(font)
        rename(font)
        font.save(FONTS / dst)
        print(f"{dst}: {changed} joins spaced normally")
