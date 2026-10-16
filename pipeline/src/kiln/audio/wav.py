"""A small WAV writer and reader: 16-bit PCM, mono or stereo. A sound that loops gets a
`smpl` chunk marking all of it as one forward loop, which Godot's importer (with its loop
mode left on "Detect From WAV") and most samplers read, so it loops with no import settings.

Godot plays a loop up to its end frame and wraps there, so the end written is the first frame
after the loop, and the first few frames of the loop are written again after it: a player
that reads ahead to interpolate finds the loop's start there, and one that plays the end frame
too (as the format's documents have it) repeats one frame, which can't be heard."""
from __future__ import annotations

import struct

import numpy as np

# The frames of a loop's start written again after its end.
RUN_ON = 8


def write(path: str, samples: np.ndarray, rate: int, loop: bool) -> None:
    """Writes `samples` (about -1 to 1, shape (n,) or (2, n)) as 16-bit PCM at `rate`."""
    channels = 1 if samples.ndim == 1 else samples.shape[0]
    frames = samples.shape[-1]
    if loop:
        samples = np.concatenate([samples, np.take(samples, np.arange(RUN_ON) % frames, axis=-1)], axis=-1)
    pcm = np.clip(np.round(samples * 32767.0), -32768, 32767).astype("<i2")
    data = (pcm if channels == 1 else pcm.T).tobytes()
    fmt = struct.pack("<HHIIHH", 1, channels, rate, rate * channels * 2, channels * 2, 16)
    chunks = [(b"fmt ", fmt)]
    if loop:
        # Manufacturer, product, sample period (ns), MIDI unity note, pitch fraction, SMPTE
        # format and offset, one loop, no sampler data; then the loop: its cue id, forward,
        # from the first frame to the frame after it, no fraction, playing for ever.
        smpl = struct.pack("<9I", 0, 0, round(1e9 / rate), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, frames, 0, 0)
        chunks.append((b"smpl", smpl))
    chunks.append((b"data", data))
    body = b"WAVE" + b"".join(kind + struct.pack("<I", len(content)) + content + (b"\0" if len(content) % 2 else b"")
                              for kind, content in chunks)
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", len(body)) + body)


def read(path: str) -> tuple[int, np.ndarray, tuple[int, int] | None]:
    """Reads a WAV written by `write`: (rate, samples from -1 to 1, the loop's first frame and
    the frame after it, or None). A loop's samples are the loop's alone, without the run-on."""
    with open(path, "rb") as f:
        blob = f.read()
    if blob[:4] != b"RIFF" or blob[8:12] != b"WAVE":
        raise ValueError(f"{path} isn't a WAV file")
    at, rate, channels, samples, loop = 12, 0, 1, None, None
    while at + 8 <= len(blob):
        kind, size = blob[at:at + 4], struct.unpack_from("<I", blob, at + 4)[0]
        content = blob[at + 8:at + 8 + size]
        if kind == b"fmt ":
            pcm, channels, rate, _, _, bits = struct.unpack_from("<HHIIHH", content)
            if pcm != 1 or bits != 16:
                raise ValueError(f"{path} isn't 16-bit PCM")
        elif kind == b"smpl" and struct.unpack_from("<I", content, 28)[0] > 0:
            loop = struct.unpack_from("<II", content, 36 + 8)
        elif kind == b"data":
            samples = np.frombuffer(content, dtype="<i2").astype(float) / 32767.0
        at += 8 + size + (size % 2)
    if samples is None:
        raise ValueError(f"{path} has no samples")
    if channels > 1:
        samples = samples.reshape(-1, channels).T
    if loop is not None:
        samples = samples[..., loop[0]:loop[1]]
    return rate, samples, loop
