#!/usr/bin/env python3
"""Variantes de la mascotte Goody (couleurs + accessoires) -> mascot/variants.png (8 x 32 px)."""
from PIL import Image, ImageDraw
src = Image.open("mascot/goody.png").convert("RGBA").crop((0, 0, 32, 32))
BASE = {"body": (77, 225, 180), "shade": (47, 184, 143), "light": (170, 247, 220)}
DARK = (14, 17, 22, 255)
V = [  # (corps, accessoire)
    ((77, 225, 180), None),
    ((255, 143, 177), "bow"),
    ((106, 168, 255), "headphones"),
    ((255, 162, 77), "glasses"),
    ((181, 139, 255), "beanie"),
    ((255, 216, 77), "antenna"),
    ((255, 107, 107), "crown"),
    ((201, 209, 218), "shades"),
]
def px(d, x, y, w, h, c): d.rectangle([x, y, x + w - 1, y + h - 1], fill=c)
def mix(c, k): return tuple(max(0, min(255, int(v * k))) for v in c)
sheet = Image.new("RGBA", (32 * len(V), 32), (0, 0, 0, 0))
for i, (body, acc) in enumerate(V):
    im = src.copy(); pix = im.load()
    sh = mix(body, 0.78); li = tuple(min(255, int(v + (255 - v) * 0.5)) for v in body)
    for y in range(32):
        for x in range(32):
            r, g, b, a = pix[x, y]
            if a and (r, g, b) == BASE["body"]: pix[x, y] = body + (a,)
            elif a and (r, g, b) == BASE["shade"]: pix[x, y] = sh + (a,)
            elif a and (r, g, b) == BASE["light"]: pix[x, y] = li + (a,)
    d = ImageDraw.Draw(im); c = body + (255,); acc_c = mix(body, 0.55) + (255,)
    if acc == "headphones":
        px(d, 8, 4, 16, 1, DARK); px(d, 7, 5, 1, 4, DARK); px(d, 24, 5, 1, 4, DARK)
        px(d, 4, 10, 3, 7, DARK); px(d, 25, 10, 3, 7, DARK); px(d, 5, 11, 1, 5, c); px(d, 26, 11, 1, 5, c)
    elif acc == "glasses":
        for x0 in (9, 18):
            px(d, x0, 13, 5, 1, (255, 255, 255, 255)); px(d, x0, 19, 5, 1, (255, 255, 255, 255))
            px(d, x0, 13, 1, 7, (255, 255, 255, 255)); px(d, x0 + 4, 13, 1, 7, (255, 255, 255, 255))
        px(d, 14, 15, 4, 1, (255, 255, 255, 255))
    elif acc == "beanie":
        px(d, 8, 3, 16, 4, acc_c); px(d, 7, 6, 18, 2, (255, 255, 255, 255)); px(d, 14, 1, 4, 2, (255, 255, 255, 255))
    elif acc == "bow":
        px(d, 19, 3, 3, 3, (255, 255, 255, 255)); px(d, 23, 3, 3, 3, (255, 255, 255, 255)); px(d, 22, 4, 1, 1, c)
    elif acc == "antenna":
        px(d, 15, 3, 2, 5, acc_c); px(d, 14, 0, 4, 3, (255, 255, 255, 255))
    elif acc == "crown":
        px(d, 9, 5, 14, 3, (255, 214, 120, 255))
        for x0 in (9, 15, 21): px(d, x0, 2, 2, 3, (255, 214, 120, 255))
        px(d, 15, 6, 2, 1, c)
    elif acc == "shades":
        px(d, 9, 14, 5, 4, DARK); px(d, 18, 14, 5, 4, DARK); px(d, 14, 14, 4, 1, DARK)
        px(d, 10, 14, 1, 1, (255, 255, 255, 255)); px(d, 19, 14, 1, 1, (255, 255, 255, 255))
    sheet.paste(im, (32 * i, 0))
sheet.save("mascot/variants.png"); print(len(V), "variantes")
