"""Ogg Vorbis, for sounds too long to keep as WAV (music): ffmpeg encodes it, which must be
installed. The encoding is bit-exact, so the same samples give the same file. An Ogg file
carries no loop points: the game marks a looping one to loop (in Godot, `loop=true` in its
`.import` file)."""
from __future__ import annotations

import shutil
import subprocess

import numpy as np

# Vorbis quality, -1 to 10: 6 is about 190 kb/s for stereo music, and transparent.
QUALITY = 6


def version() -> str:
    """ffmpeg's version line, or that it is missing."""
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        return "no ffmpeg"
    out = subprocess.run([ffmpeg, "-version"], capture_output=True, text=True).stdout
    return out.splitlines()[0].split(" Copyright")[0] if out else "ffmpeg"


def write(path: str, samples: np.ndarray, rate: int) -> None:
    """Writes `samples` (about -1 to 1, shape (n,) or (2, n)) as Ogg Vorbis at `rate`."""
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        raise RuntimeError("writing Ogg Vorbis needs ffmpeg, which isn't installed")
    channels = 1 if samples.ndim == 1 else samples.shape[0]
    pcm = np.clip(np.round(samples * 32767.0), -32768, 32767).astype("<i2")
    data = (pcm if channels == 1 else pcm.T).tobytes()
    command = [ffmpeg, "-loglevel", "error", "-y", "-f", "s16le", "-ar", str(rate), "-ac", str(channels), "-i", "-",
               "-c:a", "libvorbis", "-q:a", str(QUALITY), "-fflags", "+bitexact", "-flags:a", "+bitexact",
               "-map_metadata", "-1", path]
    done = subprocess.run(command, input=data, capture_output=True)
    if done.returncode != 0:
        raise RuntimeError(f"ffmpeg couldn't write {path}: {done.stderr.decode(errors='replace').strip()}")


def read(path: str) -> tuple[int, np.ndarray]:
    """Decodes an Ogg file: (rate, samples from -1 to 1, shape (n,) or (2, n))."""
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        raise RuntimeError("reading Ogg Vorbis needs ffmpeg, which isn't installed")
    probe = subprocess.run([ffmpeg, "-i", path], capture_output=True, text=True).stderr
    rate = int(probe.split(" Hz")[0].split()[-1])
    channels = 2 if "stereo" in probe else 1
    out = subprocess.run([ffmpeg, "-loglevel", "error", "-i", path, "-f", "s16le", "-"], capture_output=True, check=True).stdout
    samples = np.frombuffer(out, dtype="<i2").astype(float) / 32767.0
    return rate, samples if channels == 1 else samples.reshape(-1, 2).T
