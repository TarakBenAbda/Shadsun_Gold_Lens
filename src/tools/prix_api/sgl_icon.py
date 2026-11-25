# -*- coding: utf-8 -*-
"""
Shadsun Gold Lens — icône de l'application (.ico) à partir du logo.
Auteur : Tarak Ben Abda – novembre 2026
- 64 à 256 px : logo complet (assets/logo.png) ;
- 16 à 48 px : la gemme de l'œil seule (assets/gemme.png), lisible en petit
  (barre des tâches, zone de notification).
Usage : python sgl_icon.py [sortie.ico]
"""
import os
import sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))


def build(out):
    logo = Image.open(os.path.join(HERE, "assets", "logo.png")).convert("RGBA")
    gem = Image.open(os.path.join(HERE, "assets", "gemme.png")).convert("RGBA")
    small, large = [16, 24, 32, 48], [64, 128, 256]
    imgs = [gem.resize((s, s), Image.LANCZOS) for s in small] + [logo.resize((s, s), Image.LANCZOS) for s in large]
    big = imgs[-1]
    big.save(out, format="ICO", sizes=[(s, s) for s in small + large], append_images=imgs[:-1])
    return out


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "ShadsunGoldLens.ico"
    build(out)
    print("Icône écrite : " + out)
