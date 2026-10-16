"""A small PNG writer and reader, so kiln's images come out the same byte for byte on every
build and the tests can read them without Blender. 8-bit grey, RGB and RGBA, and 16-bit grey."""
from __future__ import annotations

import struct
import zlib

# Colour type by channel count.
COLOR_TYPES = {1: 0, 3: 2, 4: 6}


def write(path: str, data: bytes, width: int, height: int, channels: int, bit_depth: int = 8) -> None:
    """Writes `data`, rows from the top, each row's samples left to right (16-bit samples
    big-endian), as a PNG at `path`."""
    if channels not in COLOR_TYPES or bit_depth not in (8, 16) or (bit_depth == 16 and channels != 1):
        raise ValueError(f"can't write {channels} channels at {bit_depth} bits")
    stride = width * channels * bit_depth // 8
    if len(data) != stride * height:
        raise ValueError(f"{len(data)} bytes for a {width}x{height} image of {stride} bytes a row")
    rows = b"".join(b"\0" + data[y * stride:(y + 1) * stride] for y in range(height))
    header = struct.pack(">IIBBBBB", width, height, bit_depth, COLOR_TYPES[channels], 0, 0, 0)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        for kind, body in ((b"IHDR", header), (b"IDAT", zlib.compress(rows, 9)), (b"IEND", b"")):
            f.write(struct.pack(">I", len(body)) + kind + body)
            f.write(struct.pack(">I", zlib.crc32(kind + body)))


def read(path: str) -> tuple[int, int, int, int, bytes]:
    """Reads a PNG written by `write`: (width, height, channels, bit depth, data)."""
    with open(path, "rb") as f:
        blob = f.read()
    if blob[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} isn't a PNG")
    at, idat, header = 8, b"", None
    while at < len(blob):
        length, kind = struct.unpack_from(">I4s", blob, at)
        body = blob[at + 8:at + 8 + length]
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        at += 12 + length
    width, height, bit_depth, color_type = header[:4]
    channels = {v: k for k, v in COLOR_TYPES.items()}[color_type]
    stride = width * channels * bit_depth // 8
    raw = zlib.decompress(idat)
    rows = []
    for y in range(height):
        start = y * (stride + 1)
        if raw[start] != 0:
            raise ValueError(f"{path}: row {y} uses a PNG filter this reader doesn't undo")
        rows.append(raw[start + 1:start + 1 + stride])
    return width, height, channels, bit_depth, b"".join(rows)
