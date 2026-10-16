"""A sound recipe's preview sheet: a row for each sound, with its name and numbers, its
waveform, its spectrogram (time across, frequency up on a log scale from 30 Hz) and, for a
loop, its seam: the last and first few milliseconds side by side, joined where it loops."""
from __future__ import annotations

import numpy as np

from kiln import png

WAVE_WIDTH = 640
SPECTRUM_WIDTH = 640
SEAM_WIDTH = 160
PANEL_HEIGHT = 120
LABEL_HEIGHT = 18
GAP = 8
# The seam panel shows this many seconds either side of the join.
SEAM_SECONDS = 0.004
LOWEST_HZ = 30.0
# The spectrogram's range below its loudest point, in dB.
SPECTRUM_RANGE_DB = 72.0

BACKGROUND = np.array([18, 18, 22], dtype=np.uint8)
PANEL = np.array([30, 30, 36], dtype=np.uint8)
WAVE = np.array([120, 200, 255], dtype=np.uint8)
AXIS = np.array([70, 70, 80], dtype=np.uint8)
SEAM_MARK = np.array([255, 80, 200], dtype=np.uint8)
TEXT = np.array([225, 225, 230], dtype=np.uint8)
# A dark-to-bright colour ramp for the spectrogram, as (position, colour) stops.
RAMP = [(0.0, (0, 0, 4)), (0.3, (59, 15, 112)), (0.55, (140, 41, 129)), (0.8, (254, 159, 109)), (1.0, (252, 253, 191))]

# A 3x5 pixel font: each glyph is five rows of three bits, the left pixel the highest bit.
FONT = {
    "0": (7, 5, 5, 5, 7), "1": (2, 6, 2, 2, 7), "2": (7, 1, 7, 4, 7), "3": (7, 1, 7, 1, 7),
    "4": (5, 5, 7, 1, 1), "5": (7, 4, 7, 1, 7), "6": (7, 4, 7, 5, 7), "7": (7, 1, 1, 1, 1),
    "8": (7, 5, 7, 5, 7), "9": (7, 5, 7, 1, 7), "A": (2, 5, 7, 5, 5), "B": (6, 5, 6, 5, 6),
    "C": (3, 4, 4, 4, 3), "D": (6, 5, 5, 5, 6), "E": (7, 4, 6, 4, 7), "F": (7, 4, 6, 4, 4),
    "G": (3, 4, 5, 5, 3), "H": (5, 5, 7, 5, 5), "I": (7, 2, 2, 2, 7), "J": (1, 1, 1, 5, 2),
    "K": (5, 5, 6, 5, 5), "L": (4, 4, 4, 4, 7), "M": (5, 7, 7, 5, 5), "N": (6, 5, 5, 5, 5),
    "O": (2, 5, 5, 5, 2), "P": (6, 5, 6, 4, 4), "Q": (2, 5, 5, 6, 3), "R": (6, 5, 6, 5, 5),
    "S": (3, 4, 2, 1, 6), "T": (7, 2, 2, 2, 2), "U": (5, 5, 5, 5, 7), "V": (5, 5, 5, 5, 2),
    "W": (5, 5, 7, 7, 5), "X": (5, 5, 2, 5, 5), "Y": (5, 5, 2, 2, 2), "Z": (7, 1, 2, 4, 7),
    " ": (0, 0, 0, 0, 0), "_": (0, 0, 0, 0, 7), "-": (0, 0, 7, 0, 0), ".": (0, 0, 0, 0, 2),
    "/": (1, 1, 2, 4, 4), ":": (0, 2, 0, 2, 0), ",": (0, 0, 0, 2, 4), "(": (1, 2, 2, 2, 1),
    ")": (4, 2, 2, 2, 4), "+": (0, 2, 7, 2, 0), "%": (5, 1, 2, 4, 5), "=": (0, 7, 0, 7, 0),
}
UNKNOWN = (7, 1, 2, 0, 2)
SCALE = 2


def render_sheet(path: str, sounds: dict[str, np.ndarray], measures: dict[str, dict], rate: int, loop: bool) -> None:
    """Writes the preview sheet for `sounds` (name to samples, scaled as they are written) to
    `path` as a PNG."""
    width = GAP + WAVE_WIDTH + GAP + SPECTRUM_WIDTH + GAP + ((SEAM_WIDTH + GAP) if loop else 0)
    row = LABEL_HEIGHT + PANEL_HEIGHT + GAP
    image = np.empty((GAP + row * len(sounds), width, 3), dtype=np.uint8)
    image[:] = BACKGROUND
    for index, (name, samples) in enumerate(sounds.items()):
        mono = samples if samples.ndim == 1 else samples.mean(axis=0)
        top = GAP + index * row
        m = measures[name]
        label = f"{name or 'sound'}   {m['length']:.3f} S   PEAK {m['peak_db']:.1f} DB   RMS {m['rms_db']:.1f} DB"
        _text(image, GAP, top + 2, label.upper())
        y = top + LABEL_HEIGHT
        x = GAP
        image[y:y + PANEL_HEIGHT, x:x + WAVE_WIDTH] = _waveform(mono, WAVE_WIDTH)
        x += WAVE_WIDTH + GAP
        image[y:y + PANEL_HEIGHT, x:x + SPECTRUM_WIDTH] = _spectrogram(mono, rate, SPECTRUM_WIDTH)
        if loop:
            x += SPECTRUM_WIDTH + GAP
            k = max(int(SEAM_SECONDS * rate), 2)
            joined = np.concatenate([mono[-k:], mono[:k]])
            image[y:y + PANEL_HEIGHT, x:x + SEAM_WIDTH] = _waveform(joined, SEAM_WIDTH, line=True)
            image[y:y + PANEL_HEIGHT, x + SEAM_WIDTH // 2] = SEAM_MARK
    png.write(path, image.tobytes(), width, image.shape[0], 3)


def _waveform(samples: np.ndarray, width: int, line: bool = False) -> np.ndarray:
    """The waveform in a panel: the range of the samples in each column (with `line`, joined
    up to the column before, for a few samples a column), full scale at the panel's edges."""
    panel = np.empty((PANEL_HEIGHT, width, 3), dtype=np.uint8)
    panel[:] = PANEL
    middle = PANEL_HEIGHT // 2
    panel[middle] = AXIS
    if len(samples) == 0:
        return panel
    edges = np.linspace(0, len(samples), width + 1).astype(int)
    for column in range(width):
        start, end = edges[column], max(edges[column + 1], edges[column] + 1)
        # Joined up: each column reaches back to the last sample of the one before.
        chunk = samples[max(start - 1, 0) if line else start:min(end, len(samples))]
        low, high = float(chunk.min()), float(chunk.max())
        top = int(np.clip(middle - high * (middle - 1), 0, PANEL_HEIGHT - 1))
        bottom = int(np.clip(middle - low * (middle - 1), 0, PANEL_HEIGHT - 1))
        panel[top:bottom + 1, column] = WAVE
    return panel


def _spectrogram(samples: np.ndarray, rate: int, width: int) -> np.ndarray:
    """The spectrogram in a panel: level by colour, time across, log frequency up."""
    size = 2048 if len(samples) >= 4096 else max(256, 1 << int(np.log2(max(len(samples), 256) // 2)))
    padded = np.concatenate([np.zeros(size // 2), samples, np.zeros(size // 2)])
    starts = np.linspace(0, max(len(padded) - size, 0), width).astype(int)
    window = np.hanning(size)
    frames = np.stack([padded[s:s + size] * window if s + size <= len(padded)
                       else np.pad(padded[s:], (0, s + size - len(padded))) * window for s in starts])
    levels = 20.0 * np.log10(np.abs(np.fft.rfft(frames, axis=1)) + 1e-9)
    levels -= levels.max()
    freqs = np.fft.rfftfreq(size, 1.0 / rate)
    wanted = np.geomspace(LOWEST_HZ, rate / 2.0, PANEL_HEIGHT)[::-1]
    bins = np.clip(np.searchsorted(freqs, wanted), 1, len(freqs) - 1)
    shade = np.clip(1.0 + levels[:, bins].T / SPECTRUM_RANGE_DB, 0.0, 1.0)
    return _ramp(shade)


def _ramp(shade: np.ndarray) -> np.ndarray:
    positions = [p for p, _ in RAMP]
    out = np.empty(shade.shape + (3,), dtype=np.uint8)
    for channel in range(3):
        out[..., channel] = np.interp(shade, positions, [c[channel] for _, c in RAMP]).astype(np.uint8)
    return out


def _text(image: np.ndarray, x: int, y: int, text: str) -> None:
    """Draws `text` in the 3x5 font, scaled by SCALE, with its top left at (x, y)."""
    for char in text:
        glyph = FONT.get(char, UNKNOWN)
        for row, bits in enumerate(glyph):
            for col in range(3):
                if bits & (4 >> col):
                    top, left = y + row * SCALE, x + col * SCALE
                    image[top:top + SCALE, left:left + SCALE] = TEXT
        x += 4 * SCALE
        if x >= image.shape[1] - 4 * SCALE:
            return
