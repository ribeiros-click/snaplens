#!/usr/bin/env python3
"""Gera favicon.ico (16/32/48, entradas PNG), favicon-32.png e apple-touch-icon.png a partir de um PNG 1024."""
import struct, subprocess, sys, os, tempfile
src, outdir = sys.argv[1], sys.argv[2]
os.makedirs(outdir, exist_ok=True)
def resize(size, dest):
    subprocess.run(["sips", "-z", str(size), str(size), src, "--out", dest], check=True, capture_output=True)
tmp = tempfile.mkdtemp()
pngs = []
for s in (16, 32, 48):
    p = os.path.join(tmp, f"{s}.png"); resize(s, p); pngs.append((s, open(p, "rb").read()))
# ICO: header + diretório + imagens PNG embutidas
header = struct.pack("<HHH", 0, 1, len(pngs))
offset = 6 + 16 * len(pngs); entries = b""; data = b""
for s, blob in pngs:
    entries += struct.pack("<BBBBHHII", s % 256, s % 256, 0, 0, 1, 32, len(blob), offset)
    data += blob; offset += len(blob)
open(os.path.join(outdir, "favicon.ico"), "wb").write(header + entries + data)
resize(32, os.path.join(outdir, "favicon-32.png"))
resize(180, os.path.join(outdir, "apple-touch-icon.png"))
print("favicon ok")
