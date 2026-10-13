#!/usr/bin/env python3
"""Gera o ícone do SnapLens para Windows (.ico multi-tamanho) — mesma arte "Musgo" de Tools/make_icon.swift (variante 4).
Uso: python Tools/make_icon_windows.py windows/SnapLens/Assets/SnapLens.ico [saida.png]"""
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024
inset, radius = 100, 185
rect = (inset, inset, S - inset, S - inset)
cx = cy = S / 2


def rgba(r, g, b, a=1.0):
    return (round(r * 255), round(g * 255), round(b * 255), round(a * 255))


def circle(d, r, fill, at=(cx, cy)):
    d.ellipse((at[0] - r, at[1] - r, at[0] + r, at[1] + r), fill=fill)


def vgradient(size, top, bottom):
    w, h = size
    g = Image.new("RGBA", (1, h))
    for y in range(h):
        t = y / max(1, h - 1)
        g.putpixel((0, y), tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(4)))
    return g.resize((w, h))


img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# Sombra suave do corpo
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle((rect[0], rect[1] + 12, rect[2], rect[3] + 12), radius, fill=(0, 0, 0, 90))
img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(28)))

body = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(body)
d.rectangle(rect, fill=rgba(0.373, 0.478, 0.208))
w = rect[2] - rect[0]
body.alpha_composite(vgradient((w, w), rgba(1, 1, 1, 0.07), rgba(0, 0, 0, 0.10)), (inset, inset))

# Cantos de captura (moldura areia)
sand = rgba(0.953, 0.933, 0.894)
f0, f1, L, lw = inset + 150, S - inset - 150, 140, 50
for pts in (
    [(f0, f0 + L), (f0, f0), (f0 + L, f0)],
    [(f1 - L, f0), (f1, f0), (f1, f0 + L)],
    [(f1, f1 - L), (f1, f1), (f1 - L, f1)],
    [(f0 + L, f1), (f0, f1), (f0, f1 - L)],
):
    d.line(pts, fill=sand, width=lw, joint="curve")
    for p in (pts[0], pts[2], pts[1]):
        circle(d, lw / 2, sand, p)

# Lente: anel marrom + vidro areia + pupila musgo escuro + reflexo
circle(d, 190, rgba(0.541, 0.416, 0.235))
circle(d, 140, sand)
circle(d, 78, rgba(0.235, 0.302, 0.129))
circle(d, 22, rgba(1, 1, 1, 0.85), (cx - 32, cy - 34))

# Brilho superior sutil
body.alpha_composite(vgradient((w, w // 2), rgba(1, 1, 1, 0.18), rgba(1, 1, 1, 0)), (inset, inset))

mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle(rect, radius, fill=255)
img.paste(body, (0, 0), mask)

out = sys.argv[1] if len(sys.argv) > 1 else "SnapLens.ico"
img.save(out, sizes=[(16, 16), (20, 20), (24, 24), (32, 32), (40, 40), (48, 48), (64, 64), (128, 128), (256, 256)])
if len(sys.argv) > 2:
    img.save(sys.argv[2])
print("ok ->", out)
