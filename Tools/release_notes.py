#!/usr/bin/env python3
"""Extrai do CHANGELOG.md a seção de uma versão e grava as notas da release.

Uso: python3 Tools/release_notes.py 1.11 notas.md
Sem seção para a versão, grava um arquivo vazio (o workflow usa as notas automáticas do GitHub).
"""
import sys

version, out = sys.argv[1].lstrip("v"), sys.argv[2]
lines, inside = [], False
with open("CHANGELOG.md", encoding="utf-8") as f:
    for line in f:
        if line.startswith("## "):
            if inside:
                break
            inside = line[3:].strip() == version
            continue
        if inside:
            lines.append(line)
body = "".join(lines).strip()
if body:
    body += (
        "\n\n**macOS:** se o macOS bloquear na primeira vez, clique com o botão direito → Abrir."
        "\n**Windows:** se o SmartScreen avisar, clique em Mais informações → Executar assim mesmo.\n"
    )
with open(out, "w", encoding="utf-8") as f:
    f.write(body)
