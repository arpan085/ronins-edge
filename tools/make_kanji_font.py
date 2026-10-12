#!/usr/bin/env python3
"""v0.16: subset Noto Serif CJK JP Black to the kanji the HUD and the
technique screen draw (perilous-attack warning, path and technique names).
Noto Serif CJK is SIL OFL 1.1, like the other two fonts in assets/fonts.
Usage: python3 tools/make_kanji_font.py [out.ttf]"""
import sys, glob
from fontTools.ttLib import TTCollection
from fontTools import subset

CHARS = ("危武士道忍術霊縁技心眼不動居合見切忍足暗殺煙玉連霊狐癒魂刃影歩"
         "修行習得未解放必要点" "!?！？・")
src = None
for path in sorted(glob.glob("/usr/share/fonts/google-noto-cjk/NotoSerifCJK-Black.ttc")):
    src = path
if src is None:
    sys.exit("Noto Serif CJK Black not found")
col = TTCollection(src)
font = None
for f in col.fonts:
    names = " ".join(str(n) for n in f["name"].names)
    if "JP" in names:
        font = f
        break
if font is None:
    sys.exit("no JP face in " + src)
out = sys.argv[1] if len(sys.argv) > 1 else "game/assets/fonts/Kanji.ttf"
opts = subset.Options()
opts.name_IDs = ["*"]
opts.notdef_outline = True
opts.layout_features = ["*"]
sub = subset.Subsetter(opts)
sub.populate(text="".join(sorted(set(CHARS))))
sub.subset(font)
font.save(out)
cmap = font.getBestCmap()
missing = [c for c in set(CHARS) if ord(c) not in cmap]
print(out, "glyphs:", len(font.getGlyphOrder()), "missing:", "".join(missing))
