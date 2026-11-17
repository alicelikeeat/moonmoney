"""Pixel pet sprite sheets for MoonMoney (20x20 grids).

Edit the grids here, then run:
  python3 tools/pet_sprites.py preview out.png   # render a preview sheet
  python3 tools/pet_sprites.py swift Shared/PetSprites.swift

Cell codes:  . empty  o outline  b body  l light (belly)  s shade/stripe
             p pink   h horn/accent  y yellow  w wing  t tail
"""
import sys

SPECIES = {
"rabbit": {
  "name": "小月兔",
  "palette": {"o": "#3A2E4F", "b": "#FFFFFF", "l": "#F3EEFF", "s": "#D9D2EA", "p": "#FF9EC4", "y": "#FFD95A"},
  "body": [
    "......oo....oo......",
    ".....obbo..obbo.....",
    ".....obpo..opbo.....",
    ".....obpo..opbo.....",
    ".....obpo..opbo.....",
    ".....obbo..obbo.....",
    "....oobbooooobboo...",
    "...obbbbbbbbbbbbbo..",
    "..obbbbbbbbbbbbbbbo.",
    "..obbbbbbbbbbbbbbbo.",
    "..obbbbbbbbbbbbbbbo.",
    "..obbbbbbbbbbbbbbbo.",
    "..obbbbbbbbbbbbbbbo.",
    "...obbbbbbbbbbbbbo..",
    "....obbbllllllbbo...",
    "...obbbllllllllbbo..",
    "...obbbllllllllbbo..",
    "....obbbllllllbbo...",
    "....................",
    "....................",
  ],
  "eyes": [(10, 6), (10, 13)], "mouth": (12, 9), "cheeks": [(12, 4), (12, 15)],
  "feet": {"a": [(18, 5, 7), (18, 12, 14)], "b": [(17, 4, 6), (18, 12, 14)]},
  "accessory": [  # crescent moon above the head (adult)
    (0, 9, "y"), (0, 10, "y"), (1, 8, "y"), (1, 9, "y"), (2, 8, "y"), (2, 9, "y"), (3, 9, "y"), (3, 10, "y")],
},
"cat": {
  "name": "招财猫",
  "palette": {"o": "#3B2A20", "b": "#FFB04A", "l": "#FFF1D6", "s": "#E8862A", "p": "#FF9EC4", "y": "#FFD24A", "h": "#E04B4B"},
  "body": [
    "....................",
    "....................",
    "...oo.........oo....",
    "...obo.......obo....",
    "...obbo.....obbo....",
    "...opbbooooobbpo....",
    "...obbbbbbbbbbbbo...",
    "..obbsbbbbbbbsbbbo..",
    "..obbbbbbbbbbbbbbo..",
    "..obbbbbbbbbbbbbbo..",
    "..obbbbbbbbbbbbbbo..",
    "..olllbbbbbbbblllo..",
    "..obllllllllllllbo..",
    "...obbllllllllbbo...",
    "...ohhhhhhhhhhhho...",
    "...obbllllllllbbo..t",
    "...obbllllllllbbo.ot",
    "....obbbbbbbbbbo..o.",
    "....................",
    "....................",
  ],
  "eyes": [(9, 6), (9, 12)], "mouth": (11, 9), "cheeks": [(11, 4), (11, 14)],
  "feet": {"a": [(18, 5, 7), (18, 11, 13)], "b": [(17, 4, 6), (18, 11, 13)]},
  "accessory": [  # gold coin bell on the collar (adult)
    (14, 8, "y"), (14, 9, "y"), (14, 10, "y"), (15, 8, "y"), (15, 9, "o"), (15, 10, "y"), (16, 9, "y")],
},
"dragon": {
  "name": "小金龙",
  "palette": {"o": "#1F3324", "b": "#5BC77A", "l": "#FFE59A", "s": "#3FA35E", "p": "#FF9EC4", "y": "#FFD24A", "h": "#FFF4C2", "w": "#8BE0A4", "t": "#3FA35E"},
  "body": [
    "....................",
    "....h........h......",
    "....hh......hh......",
    ".....ho....oh.......",
    "....obbooooobbo.....",
    "...obbbbbbbbbbbo....",
    "..obbbbbbbbbbbbbo...",
    "..obbbbbbbbbbbbbo...",
    "..obbbbbbbbbbbbbo...",
    "..obbbbbbbbbbbbbo...",
    "..obbbbbbbbbbbbbo...",
    "...obbbbbbbbbbbo....",
    "ww..obbllllllbo..ww.",
    "wwwobbllllllllbbowww",
    ".wwobbllllllllbbow..",
    "...obbllllllllbbo...",
    "....obbllllllbbo.tt.",
    ".....obbbbbbbbo.tto.",
    "....................",
    "....................",
  ],
  "eyes": [(8, 5), (8, 11)], "mouth": (10, 8), "cheeks": [(10, 3), (10, 13)],
  "feet": {"a": [(18, 5, 7), (18, 10, 12)], "b": [(17, 4, 6), (18, 10, 12)]},
  "accessory": [  # little flame crown (adult)
    (0, 7, "y"), (0, 9, "y"), (1, 7, "y"), (1, 8, "y"), (1, 9, "y"), (2, 7, "h"), (2, 8, "y"), (2, 9, "h")],
},
}

EGG = [
  "....................",
  "....................",
  "....................",
  ".......oooooo.......",
  "......obbbbbbo......",
  ".....obbbbbbbbo.....",
  ".....obbssbbbbo.....",
  "....obbbssbbbbbo....",
  "....obbbbbbbssbo....",
  "....obbbbbbbssbo....",
  "....obssbbbbbbbo....",
  "....obssbbbbbbbo....",
  "....obbbbbbssbbo....",
  "....obbbbbbssbbo....",
  ".....obbbbbbbbo.....",
  "......obbbbbbo......",
  ".......oooooo.......",
  "....................",
  "....................",
  "....................",
]

def validate():
    for key, sp in SPECIES.items():
        assert len(sp["body"]) == 20, key
        for i, row in enumerate(sp["body"]):
            assert len(row) == 20, (key, i, len(row))
    for i, row in enumerate(EGG):
        assert len(row) == 20, ("egg", i, len(row))

def compose(sp, expression="normal", feet="a", adult=False):
    grid = [list(r) for r in sp["body"]]
    for (r, c) in sp["eyes"]:
        if expression in ("sleep", "blink"):
            grid[r + 1][c] = "o"; grid[r + 1][c + 1] = "o"
        elif expression == "happy":
            grid[r][c] = "o"; grid[r][c + 1] = "o"; grid[r + 1][c - 1] = "o"; grid[r + 1][c + 2] = "o"
        else:
            grid[r][c] = "o"; grid[r + 1][c] = "o"; grid[r][c + 1] = "o"; grid[r + 1][c + 1] = "o"
    mr, mc = sp["mouth"]
    if expression == "eat":
        grid[mr][mc] = "o"; grid[mr][mc + 1] = "o"; grid[mr + 1][mc] = "p"; grid[mr + 1][mc + 1] = "p"
    else:
        grid[mr][mc] = "o"; grid[mr][mc + 1] = "o"
    for (r, c) in sp["cheeks"]:
        grid[r][c] = "p"; grid[r][c + 1] = "p"
    for (r, c0, c1) in sp["feet"][feet]:
        for c in range(c0, c1 + 1):
            grid[r][c] = "o"
    if adult:
        for (r, c, code) in sp["accessory"]:
            grid[r][c] = code
    return grid

def preview(path):
    from PIL import Image
    validate()
    scale = 8
    cols = [("normal", "a", False), ("blink", "a", False), ("happy", "b", False), ("eat", "a", False), ("sleep", "a", False), ("normal", "a", True)]
    img = Image.new("RGB", (len(cols) * 22 * scale, (len(SPECIES) + 1) * 22 * scale), (40, 44, 80))
    for row, (key, sp) in enumerate(SPECIES.items()):
        pal = sp["palette"]
        for col, (expr, feet, adult) in enumerate(cols):
            g = compose(sp, expr, feet, adult)
            for r, line in enumerate(g):
                for c, code in enumerate(line):
                    if code == "." or code not in pal: continue
                    color = pal[code]
                    rgb = tuple(int(color[i:i + 2], 16) for i in (1, 3, 5))
                    x0 = (col * 22 + 1 + c) * scale; y0 = (row * 22 + 1 + r) * scale
                    for dx in range(scale):
                        for dy in range(scale):
                            img.putpixel((x0 + dx, y0 + dy), rgb)
    pal = {"o": "#3A2E4F", "b": "#FFF4E0", "s": "#FF9EC4"}
    for r, line in enumerate(EGG):
        for c, code in enumerate(line):
            if code in pal:
                rgb = tuple(int(pal[code][i:i + 2], 16) for i in (1, 3, 5))
                for dx in range(scale):
                    for dy in range(scale):
                        img.putpixel(((1 + c) * scale + dx, (len(SPECIES) * 22 + 1 + r) * scale + dy), rgb)
    img.save(path)

def swift(path):
    validate()
    out = ["// Generated by tools/pet_sprites.py — edit the grids there, not here.", "", "enum PetSprites {"]
    for key, sp in SPECIES.items():
        out.append(f"    static let {key} = PetSpriteSheet(")
        out.append("        body: [")
        out += [f'            "{r}",' for r in sp["body"]]
        out.append("        ],")
        pal = ", ".join(f'"{k}": "{v}"' for k, v in sp["palette"].items())
        out.append(f"        palette: [{pal}],")
        out.append("        eyes: [" + ", ".join(f"PetCell(row: {r}, col: {c})" for r, c in sp["eyes"]) + "],")
        mr, mc = sp["mouth"]
        out.append(f"        mouth: PetCell(row: {mr}, col: {mc}),")
        out.append("        cheeks: [" + ", ".join(f"PetCell(row: {r}, col: {c})" for r, c in sp["cheeks"]) + "],")
        fa = ", ".join(f"PetFoot(row: {r}, from: {a}, to: {b})" for r, a, b in sp["feet"]["a"])
        fb = ", ".join(f"PetFoot(row: {r}, from: {a}, to: {b})" for r, a, b in sp["feet"]["b"])
        out.append(f"        feetA: [{fa}],")
        out.append(f"        feetB: [{fb}],")
        acc = ", ".join(f'PetPaint(row: {r}, col: {c}, code: "{code}")' for r, c, code in sp["accessory"])
        out.append(f"        accessory: [{acc}]")
        out.append("    )")
    out.append("")
    out.append("    static let egg: [String] = [")
    out += [f'        "{r}",' for r in EGG]
    out.append("    ]")
    out.append("}")
    open(path, "w").write("\n".join(out) + "\n")

if __name__ == "__main__":
    {"preview": preview, "swift": swift}[sys.argv[1]](sys.argv[2])
