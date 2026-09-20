#!/usr/bin/env python3
# Print the PNG test data used by harness.sh.

import base64
import struct
import zlib


def chunk(kind, data):
    content = kind + data
    return (struct.pack(">I", len(data)) + content
            + struct.pack(">I", zlib.crc32(content)))


def png(width, height, rgb):
    raw = b"".join(b"\x00" + bytes(rgb) * width for _ in range(height))
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


print("_PNG_SQUARE=" + base64.b64encode(png(64, 64, (255, 0, 0))).decode())
print("_PNG_WIDE=" + base64.b64encode(png(100, 40, (0, 255, 0))).decode())
