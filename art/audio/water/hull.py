"""The water round a moving jet ski, as loops the game sets by speed and thrust:

- `wash`: off the plane, slow, the hull pushing water aside: lapping and gurgling;
- `rush`: on the plane, the hull skimming: the hiss of spray, a fizz of small bubbles and the
  rumble of the hull chattering over ripples;
- `jet`: the jet's water roaring out of the nozzle and churning behind, made at full revs (the
  game bends its pitch with the revs and drops it when the nozzle leaves the water).
"""
import numpy as np
from kiln import sound

from audio.water._water import bubbles, thump

SECONDS = 2.5


def swell(s, seconds: float, seed: int, rate: float, depth: float) -> np.ndarray:
    """A slow, random rise and fall around 1, about `rate` times a second, by up to `depth`."""
    wander = s.lowpass(s.noise(seconds, seed), rate, order=2)
    return np.maximum(1.0 + depth * wander / max(float(np.max(np.abs(wander))), 1e-9), 0.0)


@sound(loop=True, seconds=(2.0, 3.0))
def build(s):
    rng = s.rng(5)
    # Lapping: water sloshing along the sides, now and then slapping the hull.
    slosh = s.bandpass(s.noise(SECONDS, 1, "pink"), 520.0, 0.8) * swell(s, SECONDS, 2, 3.0, 0.9)
    laps = s.arrange(SECONDS, [(t, thump(s, 0.15, rng.uniform(160.0, 260.0), 0.025) * rng.uniform(0.2, 0.6))
                               for t in rng.uniform(0.0, SECONDS, 9)])
    gurgle = bubbles(s, SECONDS, 45.0 * swell(s, SECONDS, 3, 2.0, 0.8), 4, smallest=0.0015, largest=0.012) * 0.8
    wash = s.lowpass(slosh * 0.9 + laps + gurgle, 4500.0)

    # Planing: spray hissing off the chines, small bubbles fizzing in the wake, the hull
    # chattering over ripples.
    hiss = s.bandpass(s.noise(SECONDS, 6), 3800.0, 0.7) * 1.6 + s.highpass(s.noise(SECONDS, 7), 7000.0) * 0.6 \
        + s.bandpass(s.noise(SECONDS, 15, "pink"), 1200.0, 0.5) * 0.9
    fizz = bubbles(s, SECONDS, 900.0, 8, smallest=0.0004, largest=0.003) * 0.55
    chatter = s.lowpass(s.noise(SECONDS, 9, "brown"), 260.0) * swell(s, SECONDS, 10, 11.0, 0.7) * 0.45
    rush = (hiss * swell(s, SECONDS, 11, 4.0, 0.25) + fizz + chatter) * 0.8

    # The jet: water forced out at speed, a broad roar with the churn of the wake behind it.
    roar = s.lowpass(s.noise(SECONDS, 12, "pink"), 2400.0, order=2)
    roar = s.eq(s.eq(roar, 620.0, 5.0, 1.2), 1500.0, 3.0, 1.5) * swell(s, SECONDS, 13, 25.0, 0.35)
    churn = bubbles(s, SECONDS, 260.0, 14, smallest=0.001, largest=0.006) * 0.6
    jet = (roar + churn) * 0.9
    return {"wash": wash, "rush": rush, "jet": jet}
