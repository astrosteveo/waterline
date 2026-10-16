"""A buoy passed: `bell`, a buoy's bronze bell struck once when the craft passes on the
marked side, and `miss`, a dull clank and a low buzz when it doesn't.

A bell's partials aren't harmonic: over its prime come a minor third (the tierce), a fifth,
the octave (the nominal, which sets the note heard) and higher ones, the hum an octave below,
each dying at its own rate, the higher sooner. Pairs a little apart beat, which makes a bell
shimmer."""
from kiln import sound

# (ratio to the prime, level, seconds to 1/e) for a small bell.
PARTIALS = [(0.5, 0.35, 0.7), (1.0, 0.6, 0.55), (1.003, 0.3, 0.5), (1.183, 0.45, 0.4), (1.506, 0.22, 0.3),
            (2.0, 1.0, 0.35), (2.006, 0.4, 0.33), (2.5, 0.3, 0.2), (2.66, 0.28, 0.18), (3.01, 0.2, 0.14),
            (4.1, 0.12, 0.08)]


@sound(seconds=(0.2, 2.0))
def build(s):
    seconds = 1.4
    strike = s.impulses(seconds, [0.002])
    bell = sum(s.resonator(strike, 660.0 * ratio, decay, level) for ratio, level, decay in PARTIALS)
    clank = s.highpass(s.noise(seconds, 3), 3000.0) * s.decay(seconds, 0.006, 0.0005) * 0.8
    bell = s.fade(bell * 0.25 + clank, 0.0, 0.4)

    seconds = 0.42
    knock = sum(s.resonator(s.impulses(seconds, [0.002]), hz, decay, level)
                for hz, decay, level in ((180.0, 0.06, 1.0), (437.0, 0.03, 0.5), (911.0, 0.015, 0.3)))
    buzz = s.lowpass(s.mix(s.square(110.0, seconds), s.square(116.5, seconds) * 0.8), 900.0, order=2)
    buzz *= s.adsr(seconds - 0.08, 0.01, 0.1, 0.7, 0.08)
    miss = s.fade(knock * 0.08 + buzz * 0.35, 0.0, 0.06)
    return {"bell": bell, "miss": miss}
