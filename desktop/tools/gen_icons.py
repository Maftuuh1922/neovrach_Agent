#!/usr/bin/env python3
"""Generate Neovarch Agent desktop icons from the brand app icon.

Source: assets/brand/app_icon.png of the Neovarch Flutter app (halo-N on red).
Outputs (relative to apps/desktop): assets/icon*.{png,ico,icns}, assets/appx/*,
assets/icon.icon/Assets/*, public/apple-touch-icon.png, public/neovarch-mark*.png,
packaging/dmg-volume.icns.
"""
import os, sys
from PIL import Image, ImageDraw

SRC = sys.argv[1]
APP = sys.argv[2]
INK = (20, 6, 7, 255)

base = Image.open(SRC).convert('RGBA').resize((1024, 1024), Image.LANCZOS)

def squircle(img, radius_ratio=0.225, inset=0):
    size = img.size[0]
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    inner = size - 2 * inset
    im = img.resize((inner, inner), Image.LANCZOS)
    mask = Image.new('L', (inner * 4, inner * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, inner * 4 - 1, inner * 4 - 1), radius=int(inner * 4 * radius_ratio), fill=255)
    mask = mask.resize((inner, inner), Image.LANCZOS)
    canvas.paste(im, (inset, inset), mask)
    return canvas

rounded = squircle(base)
mac = squircle(base, inset=100)  # macOS grid: art inside a ~824px squircle

def save_png(img, rel, size=None):
    path = os.path.join(APP, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    (img.resize((size, size), Image.LANCZOS) if size else img).save(path)

ICO_SIZES = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
for name in ('icon', 'icon-dark'):
    save_png(rounded, f'assets/{name}.png')
    rounded.save(os.path.join(APP, f'assets/{name}.ico'), sizes=ICO_SIZES)
    mac.save(os.path.join(APP, f'assets/{name}.icns'))
save_png(mac, 'assets/icon-mac.png')
mac.save(os.path.join(APP, 'packaging/dmg-volume.icns'))
save_png(rounded, 'public/apple-touch-icon.png')
save_png(rounded, 'public/neovarch-mark.png', 256)
save_png(rounded, 'public/neovarch-mark-dark.png', 256)
save_png(rounded, 'build-icons/icon-512.png', 512)
save_png(rounded, 'build-icons/icon-256.png', 256)
# Linux desktop entry icon set (electron-builder reads a directory of NxN.png)
for s in (16, 32, 48, 64, 128, 256, 512):
    save_png(rounded, f'assets/linux/{s}x{s}.png', s)
# Icon Composer layers (macOS 26): full-bleed art; system applies the mask.
for layer in ('art-light', 'art-dark', 'mono'):
    p = os.path.join(APP, f'assets/icon.icon/Assets/{layer}.png')
    if os.path.exists(p):
        w, h = Image.open(p).size
        img = base if layer != 'mono' else base.convert('LA').convert('RGBA')
        img.resize((w, h), Image.LANCZOS).save(p)
# MSIX tiles: keep every existing file name and size.
appx = os.path.join(APP, 'assets/appx')
for f in sorted(os.listdir(appx)):
    p = os.path.join(appx, f)
    w, h = Image.open(p).size
    if w == h:
        img = base.resize((w, w), Image.LANCZOS)
        if 'unplated' in f:
            img = rounded.resize((w, w), Image.LANCZOS)
    else:
        img = Image.new('RGBA', (w, h), base.getpixel((8, 8)))
        logo = base.resize((h, h), Image.LANCZOS)
        img.paste(logo, ((w - h) // 2, 0))
    img.save(p)
print('icons generated')
