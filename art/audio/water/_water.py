"""Water sounds from their physics: most of what water sounds like is air bubbles ringing.

A bubble of radius r rings at its Minnaert frequency, about 3.26 / r Hz (a 1 mm bubble at
3.3 kHz, a 10 mm one at 330 Hz), dies away at about 0.043 f + 0.0014 f^1.5 a second, and
rises in pitch as it does, as it nears the surface (van den Doel, "Physically based models for
liquid sounds", 2005). Splashes, a wake's hiss and water lapping at a hull are crowds of them,
over the broadband noise of water tearing and spraying. There are many more small bubbles
than large ones (a power law), and the large ones are louder.
"""
from __future__ import annotations

import numpy as np


def bubble(s, radius: float, level: float, rise: float = 0.1) -> np.ndarray:
    """One bubble of `radius` metres, its peak at `level`, ringing until it is 60 dB down,
    rising in pitch by `rise` of its frequency for each 1/e it dies by."""
    f0 = 3.26 / radius
    damping = 0.043 * f0 + 0.0014 * f0 ** 1.5
    t = s.time(6.9 / damping)
    freq = f0 * (1.0 + rise * damping * t)
    phase = np.cumsum(freq) / s.rate
    # A short rise, so the bubble doesn't click on.
    onset = np.minimum(t * f0 / 2.0, 1.0)
    return level * np.sin(2.0 * np.pi * phase) * np.exp(-damping * t) * onset


def bubbles(s, seconds: float, density, seed: int, smallest: float = 0.0008, largest: float = 0.008,
            slope: float = 2.6, size: float = 1.0, rise: float = 0.1) -> np.ndarray:
    """A crowd of bubbles over `seconds`: `density` a second on average (a number, or a value
    for each sample to make them come and go), their radii between `smallest` and `largest`
    metres, fewer the larger by the power `slope`. `size` scales every radius (larger water,
    lower bubbles)."""
    rng = s.rng(seed)
    n = s.samples(seconds)
    if np.ndim(density) == 0:
        count = rng.poisson(float(density) * seconds)
        times = rng.uniform(0.0, seconds, count)
    else:
        # Thin a steady stream at the highest density down to the density at each moment.
        peak = float(np.max(density))
        candidates = rng.uniform(0.0, seconds, rng.poisson(peak * seconds))
        keep = rng.random(len(candidates)) * peak < density[np.minimum((candidates * s.rate).astype(int), n - 1)]
        times = candidates[keep]
    # Radii from a power law between the two sizes, by inverting its distribution.
    a, b = smallest ** (1.0 - slope), largest ** (1.0 - slope)
    radii = (a + rng.random(len(times)) * (b - a)) ** (1.0 / (1.0 - slope)) * size
    levels = (radii / largest) ** 0.9 * rng.uniform(0.3, 1.0, len(times))
    return s.arrange(seconds, [(t, bubble(s, r, v, rise)) for t, r, v in zip(times, radii, levels)])


def spray(s, seconds: float, seed: int, bright: float = 4000.0) -> np.ndarray:
    """Water thrown into the air and falling back: a hiss, brightest round `bright` Hz."""
    noise = s.noise(seconds, seed)
    return s.mix(s.bandpass(noise, bright, 0.6), s.highpass(noise, bright * 1.6) * 0.5) * 1.6


def thump(s, seconds: float, freq: float, decay: float) -> np.ndarray:
    """A heavy thing meeting the water: a low knock at `freq` Hz dying away over `decay` s,
    falling in pitch a little as it pushes the water aside."""
    t = s.time(seconds)
    glide = freq * (1.0 + 0.6 * np.exp(-t / (decay * 0.3)))
    return s.sine(glide, seconds) * s.decay(seconds, decay, 0.002)
