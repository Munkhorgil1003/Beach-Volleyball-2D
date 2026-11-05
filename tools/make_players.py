# Generates recolored player variants from assets/BVA2/player*.png.
# Usage: python3 tools/make_players.py [preview.png]
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from png_rgba import read_png, write_png

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "assets", "BVA2")
OUT = os.path.join(ROOT, "assets", "players")

# sheet name -> frame width
SHEETS = {
    "playerIdle": 32,
    "playerRun": 32,
    "playerReception": 32,
    "playerBlock": 32,
    "playerSmash": 32,
    "playerSlide": 43,
}

BLACK = (0x00, 0x00, 0x00)
SKIN_BASE = (0xff, 0x96, 0x5f)
SKIN = {(0xff, 0x96, 0x5f), (0xfe, 0x9f, 0x6e), (0xda, 0x81, 0x52), (0xff, 0xb5, 0x7d),
        (0xfd, 0xa9, 0x7d), (0xff, 0x95, 0x5e), (0xd8, 0x97, 0x51)}
# white/gray shades used by both shirt and shoes, mapped to ramp index
WHITES = {(0xff, 0xff, 0xff): 0, (0xec, 0xee, 0xec): 1, (0xd0, 0xd3, 0xd2): 2,
          (0xc5, 0xc2, 0xc5): 2, (0xb3, 0xbb, 0xbb): 3, (0x84, 0x7e, 0x87): 3}
EYE = (0xfc, 0xf8, 0xfc)
SHORTS = {(0x10, 0xd3, 0x19): 0, (0x0e, 0xa9, 0x15): 1, (0x88, 0xa5, 0x5a): 2, (0x33, 0x55, 0x39): 3}
SHIRT_MIN_PIXELS = 30


def hexrgb(s):
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))


def scale(c, f):
    return tuple(min(255, max(0, round(v * f))) for v in c)


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def shirt_ramp(base):
    # highlight, base, shade, dark
    return [mix(base, (255, 255, 255), 0.35), base, scale(base, 0.8), scale(base, 0.6)]


def shorts_ramp(base):
    # base, shade, muted fold, dark
    return [base, scale(base, 0.8), mix(scale(base, 0.8), (128, 128, 128), 0.4), scale(base, 0.4)]


PLAYERS = [
    # name, skin base, hair, shirt, shorts
    ("p1", "ff965f", None, "e03030", "203080"),
    ("p2", "ffc49a", "e8c050", "2f6fe0", "f0d020"),
    ("p3", "8d5436", None, "f0d020", "303030"),
    ("p4", "d98a58", "6a4020", "8a3fc8", "ff8a20"),
    ("p5", "ffc49a", "c04820", "383838", "e03030"),
    ("p6", "6a3c24", "3a2414", "ff8a20", "20b0b0"),
]


def blobs(px, x0, x1, h, test, neighbors):
    # connected components of pixels passing test, within one frame
    found = []
    seen = set()
    for sy in range(h):
        for sx in range(x0, x1):
            if (sx, sy) in seen or not test(sx, sy):
                continue
            blob = []
            stack = [(sx, sy)]
            seen.add((sx, sy))
            while stack:
                x, y = stack.pop()
                blob.append((x, y))
                for dx, dy in neighbors:
                    nx, ny = x + dx, y + dy
                    if x0 <= nx < x1 and 0 <= ny < h and (nx, ny) not in seen and test(nx, ny):
                        seen.add((nx, ny))
                        stack.append((nx, ny))
            found.append(blob)
    return found


def centroid(points):
    return (sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points))


def dist(a, b):
    return ((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2) ** 0.5


def hair_mask(px, x0, x1, h):
    # hair is the largest solid black mass; its 1px border stays black as outline
    def solid(x, y):
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                nx, ny = x + dx, y + dy
                if not (x0 <= nx < x1 and 0 <= ny < h) or px[ny][nx][3] == 0 or px[ny][nx][:3] != BLACK:
                    return False
        return True

    found = blobs(px, x0, x1, h, solid, ((1, 0), (-1, 0), (0, 1), (0, -1)))
    if not found:
        return set()
    return set(max(found, key=len))


def shirt_mask(px, x0, x1, h, head):
    # white blobs closer to the head than the shorts are belong to the shirt;
    # shoes always sit on the far side of the shorts
    def white(x, y):
        return px[y][x][3] > 0 and px[y][x][:3] in WHITES

    found = blobs(px, x0, x1, h, white, ((1, 0), (-1, 0), (0, 1), (0, -1)))
    shorts = [(x, y) for y in range(h) for x in range(x0, x1)
              if px[y][x][3] > 0 and px[y][x][:3] in SHORTS]
    mask = set()
    for blob in found:
        if shorts and head:
            is_shirt = dist(centroid(blob), head) < dist(centroid(shorts), head)
        else:
            is_shirt = len(blob) >= SHIRT_MIN_PIXELS
        if is_shirt:
            mask.update(blob)
    return mask


def recolor(w, h, px, frame_w, player):
    _, skin, hair, shirt, shorts = player
    skin_f = [hexrgb(skin)[i] / SKIN_BASE[i] for i in range(3)]
    shirt_r = shirt_ramp(hexrgb(shirt))
    shorts_r = shorts_ramp(hexrgb(shorts))
    hair_c = hexrgb(hair) if hair else None
    out = [list(row) for row in px]
    for x0 in range(0, w, frame_w):
        x1 = min(w, x0 + frame_w)
        hair_px = hair_mask(px, x0, x1, h)
        head = centroid(hair_px) if hair_px else None
        shirt_px = shirt_mask(px, x0, x1, h, head)
        if not hair_c:
            hair_px = set()
        for y in range(h):
            for x in range(x0, x1):
                r, g, b, a = px[y][x]
                c = (r, g, b)
                if a == 0:
                    continue
                if c in SKIN:
                    new = tuple(min(255, round(c[i] * skin_f[i])) for i in range(3))
                elif c in SHORTS:
                    new = shorts_r[SHORTS[c]]
                elif c in WHITES and (x, y) in shirt_px:
                    new = shirt_r[WHITES[c]]
                elif (x, y) in hair_px:
                    new = hair_c
                else:
                    continue
                out[y][x] = new + (a,)
    return out


def main():
    preview_rows = []
    for player in PLAYERS:
        folder = os.path.join(OUT, player[0])
        os.makedirs(folder, exist_ok=True)
        for name, frame_w in SHEETS.items():
            w, h, px = read_png(os.path.join(SRC, name + ".png"))
            out = recolor(w, h, px, frame_w, player)
            write_png(os.path.join(folder, name + ".png"), w, h, out)
            if name == "playerIdle":
                preview_rows.append((w, h, out))
        print("wrote", folder)

    if len(sys.argv) > 1:
        # stack each player's idle sheet, scaled 3x, for a quick visual check
        s = 3
        w = preview_rows[0][0]
        rows = []
        for _, h, px in preview_rows:
            for y in range(h * s):
                rows.append([px[y // s][x // s] for x in range(w * s)])
        write_png(sys.argv[1], w * s, len(rows), rows)


if __name__ == "__main__":
    main()
