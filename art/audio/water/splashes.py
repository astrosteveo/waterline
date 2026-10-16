"""Splashes, three of each so they don't repeat: `hop` (the hull dropping back after a small
hop), `land` (coming down from a jump) and `crash` (the rider thrown into the water and the
craft slamming down). Each is the hull's thump and smack, the spray thrown up and falling
back, and the bubbles it drives under, bigger and longer for a bigger splash."""
import numpy as np
from kiln import sound

from audio.water._water import bubbles, spray, thump


def splash(s, size: float, seconds: float, seed: int) -> np.ndarray:
    """A splash of `size` (0.3 a hop, 1 a big landing) lasting `seconds`."""
    rng = s.rng(seed)
    t = s.time(seconds)
    knock = thump(s, seconds, 150.0 - 75.0 * min(size, 1.0) + rng.uniform(-8.0, 8.0), 0.03 + 0.05 * size) * (0.2 + 0.5 * size)
    smack = s.bandpass(s.noise(seconds, seed), 1400.0 + rng.uniform(-200.0, 200.0), 0.5) * s.decay(seconds, 0.025, 0.001) * 3.5
    # The spray goes up bright and darkens as it falls back in.
    thrown = spray(s, seconds, seed + 1) * s.decay(seconds, 0.12 + 0.25 * size, 0.012) * 3.5
    thrown = s.lowpass(thrown, 3000.0 + 7000.0 * np.exp(-t / (0.2 + 0.2 * size)))
    driven = bubbles(s, seconds, 2200.0 * size * np.exp(-t / (0.12 + 0.18 * size)) + 1.0, seed + 2,
                     smallest=0.0008, largest=0.005 + 0.005 * size)
    # Drops raining back down for a while after.
    drops = bubbles(s, seconds, 70.0 * size * np.exp(-np.maximum(t - 0.15, 0.0) / 0.3) * (t > 0.08) + 0.1, seed + 3,
                    smallest=0.0006, largest=0.003, rise=0.2) * 0.6
    out = knock + smack * (0.6 + 0.4 * size) + thrown * (0.5 + 0.5 * size) + driven * 0.7 + drops
    return s.fade(s.highpass(out, 35.0), 0.0005, seconds * 0.35)


@sound(seconds=(0.4, 2.0))
def build(s):
    sounds = {}
    for k in range(3):
        sounds[f"hop_{k + 1}"] = splash(s, 0.3, 0.6, 10 + k) * 0.55
        sounds[f"land_{k + 1}"] = splash(s, 1.0, 1.2, 20 + k)
        # The rider goes in a moment after the craft slams down.
        rider = s.pad(s.silence(0.09 + 0.03 * k), 1.6)
        rider = s.mix(rider, splash(s, 0.7, 1.45 - 0.03 * k, 40 + k) * 0.8)[:s.samples(1.6)]
        sounds[f"crash_{k + 1}"] = s.fade(s.mix(splash(s, 1.2, 1.6, 30 + k), rider), 0.0, 0.5)
    return sounds
