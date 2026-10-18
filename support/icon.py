# draws support/Clipcat.icns (and icon.png to look at): =^.^= on a cream tile.
# run: python3 support/icon.py
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).parent
SCALE = 4  # draw big, shrink down, for smooth edges
S = 1024 * SCALE

PAGE = (253, 255, 236, 255)
PINK = (227, 70, 133, 255)

def px(n):
    return int(n * SCALE)

img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

# apple's icon grid: an 824 tile in a 1024 canvas. no line or shadow of our own:
# macos crops icons to its own rounded shape and adds its edge, and anything drawn
# near ours gets cut off unevenly.
box = [px(100), px(100), px(924), px(924)]
d.rounded_rectangle(box, px(185), fill=PAGE)

font = ImageFont.truetype(str(HERE / "fonts" / "iosevka-rabbits-regular.ttf"), px(300))
text = "=^.^="
l, t, r, b = d.textbbox((0, 0), text, font=font)
w, h = r - l, b - t
cx = (box[0] + box[2]) / 2
cy = (box[1] + box[3]) / 2
d.text((cx - w / 2 - l, cy - h / 2 - t), text, font=font, fill=PINK)

icon = img.resize((1024, 1024), Image.LANCZOS)
icon.save(HERE / "icon.png")
icon.save(HERE / "Clipcat.icns", sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
