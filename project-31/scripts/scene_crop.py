"""Reiter-Szene mit Chiemsee-Panorama aus poster-gold.png (ohne Poster-Typo)."""
import sys
from PIL import Image, ImageDraw

src, dst = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGB")
d = ImageDraw.Draw(im)
d.rectangle((660, 0, 1254, 325), fill=(254, 250, 244))  # "It's POLO TIME" + Pinselstrich entfernen
d.rectangle((690, 295, 1254, 336), fill=(254, 250, 244))  # Rest des Unterstrichs
im.crop((0, 170, 800, 990)).save(dst)
print("saved", dst)
