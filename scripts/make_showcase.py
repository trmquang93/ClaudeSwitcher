#!/usr/bin/env python3
"""Compose README showcase images from real UI crops (docs/menu.png, docs/menu.png),
the app icon and a generated wallpaper. Output: docs/showcase-*.png (2560x1600)."""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
W, H = 2560, 1600
FONT = "/System/Library/Fonts/HelveticaNeue.ttc"


def font(size, bold=False):
    return ImageFont.truetype(FONT, size, index=1 if bold else 0)


def wallpaper():
    img = Image.open("assets/wallpaper.png").convert("RGB")
    scale = max(W / img.width, H / img.height)
    img = img.resize((int(img.width * scale), int(img.height * scale)), Image.LANCZOS)
    left, top = (img.width - W) // 2, (img.height - H) // 2
    return img.crop((left, top, left + W, top + H)).convert("RGBA")


def rounded(img, radius):
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, img.width - 1, img.height - 1], radius, fill=255)
    out = img.convert("RGBA")
    out.putalpha(m)
    return out


def shadowed(base, img, xy, blur=40, offset=24, alpha=150):
    sh = Image.new("RGBA", base.size, (0, 0, 0, 0))
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.width - 1, img.height - 1], 36, fill=alpha)
    sh.paste((0, 0, 0, alpha), (xy[0], xy[1] + offset), mask)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    base.alpha_composite(sh)
    base.alpha_composite(img, xy)


def menubar(base, highlight_x=None):
    d = ImageDraw.Draw(base, "RGBA")
    d.rectangle([0, 0, W, 56], fill=(20, 20, 28, 170))
    f = font(28)
    d.text((40, 12), "Claude", font=font(28, True), fill=(255, 255, 255, 235))
    for t, x in [("File", 170), ("Edit", 255), ("View", 345), ("Window", 445), ("Help", 585)]:
        d.text((x, 12), t, font=f, fill=(255, 255, 255, 220))
    d.text((W - 330, 12), "Fri 13 Nov  09:41", font=f, fill=(255, 255, 255, 235))
    icon = Image.open("/tmp/cs-icon-1024.png").resize((40, 40), Image.LANCZOS)
    x = highlight_x or (W - 420)
    d.rounded_rectangle([x - 12, 6, x + 52, 50], 10, fill=(255, 255, 255, 60))
    base.alpha_composite(icon, (x, 8))
    return x


def text_block(base, x, y, title, sub, tsize=104):
    d = ImageDraw.Draw(base, "RGBA")
    for line in title.split("\n"):
        d.text((x, y), line, font=font(tsize, True), fill=(255, 255, 255, 255))
        y += int(tsize * 1.15)
    y += 24
    for line in sub.split("\n"):
        d.text((x, y), line, font=font(46), fill=(255, 255, 255, 205))
        y += 68
    return y


def hero():
    base = wallpaper()
    x = menubar(base)
    menu = rounded(Image.open("docs/menu.png"), 30)
    menu = menu.resize((int(menu.width * 1.9), int(menu.height * 1.9)), Image.LANCZOS)
    shadowed(base, menu, (W - menu.width - 60, 74))
    icon = Image.open("/tmp/cs-icon-1024.png").resize((220, 220), Image.LANCZOS)
    base.alpha_composite(icon, (140, 330))
    text_block(base, 140, 600, "Switch Claude accounts\nfrom your menu bar",
               "One click between separate Claude profiles.\nEach keeps its own login, chats and settings.")
    base.convert("RGB").save("docs/showcase-hero.png")


def card(d, base, x, y, w, h, title, dot, rows):
    sh = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([x, y + 20, x + w, y + h + 20], 44, fill=(0, 0, 0, 140))
    base.alpha_composite(sh.filter(ImageFilter.GaussianBlur(36)))
    d = ImageDraw.Draw(base, "RGBA")
    d.rounded_rectangle([x, y, x + w, y + h], 44, fill=(24, 24, 34, 235), outline=(255, 255, 255, 40), width=2)
    d.ellipse([x + 56, y + 62, x + 96, y + 102], fill=dot)
    d.text((x + 120, y + 48), title, font=font(60, True), fill=(255, 255, 255, 255))
    yy = y + 170
    for k, v in rows:
        d.text((x + 56, yy), k, font=font(32), fill=(255, 255, 255, 140))
        d.text((x + 56, yy + 42), v, font=ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 34),
               fill=(255, 255, 255, 235))
        yy += 130


def how_it_works():
    base = wallpaper()
    menubar(base)
    d = ImageDraw.Draw(base, "RGBA")
    d.text((140, 150), "How it works", font=font(104, True), fill=(255, 255, 255, 255))
    d.text((140, 290), "Each profile is a separate Claude data folder and Claude Code config.",
           font=font(46), fill=(255, 255, 255, 205))
    cw, ch = 900, 640
    card(d, base, 170, 560, cw, ch, "Claude", (150, 150, 160, 255), [
        ("--user-data-dir", "default profile"),
        ("CLAUDE_CONFIG_DIR", "~/.claude"),
        ("Account", "work@example.com")])
    card(d, base, W - 170 - cw, 560, cw, ch, "Claude Personal", (80, 220, 100, 255), [
        ("--user-data-dir", "~/Library/.../Claude-2"),
        ("CLAUDE_CONFIG_DIR", "~/.claude-personal"),
        ("Account", "me@example.com")])
    icon = Image.open("/tmp/cs-icon-1024.png").resize((380, 380), Image.LANCZOS)
    base.alpha_composite(icon, ((W - 380) // 2, 690))
    d = ImageDraw.Draw(base, "RGBA")
    d.multiline_text((W // 2, 1100), "Claude Switcher\nlaunches the\nprofile you pick", font=font(38),
                     fill=(255, 255, 255, 220), align="center", spacing=10, anchor="ma")
    base.convert("RGB").save("docs/showcase-how-it-works.png")


hero()
how_it_works()
print("ok")
