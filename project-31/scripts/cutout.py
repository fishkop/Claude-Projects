"""Rider-Freisteller aus poster-red.png erzeugen (rote Schrift entfernen, Hintergrund transparent)."""
import sys
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

src, dst = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGB").crop((0, 250, 830, 1060))
a = np.array(im).astype(int)
r, g, b = a[..., 0], a[..., 1], a[..., 2]
bg = np.array([252, 249, 238])

# 1) gesaettigtes Rot/Orange (Schrift, Pinselspritzer) -> Hintergrund
red = (r > 170) & (r - g > 100) & (r - b > 110)
red = ndimage.binary_dilation(red, iterations=2)
a[red] = bg

# 2) hintergrundnahe Pixel, die mit dem Rand verbunden sind -> transparent
near = np.abs(a - bg).sum(-1) < 60
lab, _ = ndimage.label(near)
edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
bgmask = np.isin(lab, list(edge))

alpha = np.where(bgmask, 0, 255).astype(np.uint8)
# Reste der Poster-Typo (rechts oben) und den See (rechts unten) abschneiden
alpha[:540, 760:] = 0
alpha[600:712, 735:] = 0
alpha = np.array(Image.fromarray(alpha).filter(ImageFilter.GaussianBlur(1.2)))
out = np.dstack([a.clip(0, 255).astype(np.uint8), alpha])
Image.fromarray(out, "RGBA").save(dst)
print("saved", dst, out.shape)
