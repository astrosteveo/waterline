"""A stunt ring taken: two quick, bright notes, a fifth apart, from a struck metal bar (a
frequency-modulated bell tone, the modulation dying faster than the note)."""
from kiln import sound


def bar(s, freq: float, seconds: float):
    """A struck bar at `freq` Hz: its overtones bright at the strike, fading to the plain note."""
    index = 1.4 * s.decay(seconds, 0.06, 0.001)
    return s.sine(freq, seconds, phase=index * s.sine(freq * 3.5, seconds)) * s.decay(seconds, 0.22, 0.002)


@sound(seconds=(0.3, 1.5))
def build(s):
    seconds = 0.9
    chime = s.arrange(seconds, [(0.0, bar(s, 1046.5, 0.8) * 0.8), (0.085, bar(s, 1568.0, 0.8))])
    return s.fade(s.reverb(chime, seconds=0.6, damping=0.4, mix=0.15)[:s.samples(seconds)], 0.0, 0.25)
