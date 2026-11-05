# Minimal RGBA 8-bit PNG reader/writer (no dependencies).
import struct
import zlib


def read_png(path):
    data = open(path, "rb").read()
    pos = 8
    idat = b""
    plte = b""
    trns = b""
    while pos < len(data):
        length, = struct.unpack(">I", data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", body[:10])
            assert depth == 8 and ctype in (3, 6), "only 8-bit RGBA or indexed supported"
        elif kind == b"PLTE":
            plte = body
        elif kind == b"tRNS":
            trns = body
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    raw = zlib.decompress(idat)
    bpp = 4 if ctype == 6 else 1
    stride = w * bpp
    rows = []
    prev = bytearray(stride)
    i = 0
    for _ in range(h):
        ftype = raw[i]
        line = bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if ftype == 1:
                line[x] = (line[x] + a) & 255
            elif ftype == 2:
                line[x] = (line[x] + b) & 255
            elif ftype == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif ftype == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[x] = (line[x] + pred) & 255
        rows.append(line)
        prev = line
    if ctype == 6:
        pixels = [[tuple(r[x * 4:x * 4 + 4]) for x in range(w)] for r in rows]
    else:
        palette = []
        for k in range(len(plte) // 3):
            alpha = trns[k] if k < len(trns) else 255
            palette.append(tuple(plte[k * 3:k * 3 + 3]) + (alpha,))
        pixels = [[palette[i] for i in r] for r in rows]
    return w, h, pixels


def write_png(path, w, h, pixels):
    raw = b"".join(b"\x00" + bytes(v for p in row for v in p) for row in pixels)

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    out = b"\x89PNG\r\n\x1a\n"
    out += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    out += chunk(b"IDAT", zlib.compress(raw, 9))
    out += chunk(b"IEND", b"")
    open(path, "wb").write(out)
