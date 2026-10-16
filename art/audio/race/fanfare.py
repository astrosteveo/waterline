"""The finish: a short brass fanfare, three quick notes up to a held chord. A brass note
starts dark and bright in a moment as the lips catch (the filter opening), and the held chord
takes a little vibrato."""
import numpy as np
from kiln import sound


def brass(s, freq: float, seconds: float, vibrato: bool = False) -> np.ndarray:
    """One brass note at `freq` Hz held `seconds`, with its release after."""
    t = s.time(seconds + 0.18)
    wobble = 1.0 + (0.004 * np.sin(2.0 * np.pi * 5.5 * t) * np.clip((t - 0.25) / 0.2, 0.0, 1.0) if vibrato else 0.0)
    tone = s.saw(freq * wobble, seconds + 0.18) + s.saw(freq * 1.004 * wobble, seconds + 0.18) * 0.7
    opening = 700.0 + 3600.0 * np.exp(-t / 0.08) * np.minimum(t / 0.012, 1.0) + 1500.0 * np.minimum(t / 0.05, 1.0)
    return s.lowpass(tone, opening) * s.adsr(seconds, 0.02, 0.15, 0.75, 0.18)


@sound(seconds=(1.0, 4.0))
def build(s):
    beat = 0.13
    notes = [(0.0, 523.25, beat * 0.8), (beat, 659.25, beat * 0.8), (2 * beat, 783.99, beat * 0.8)]
    chord = [(3 * beat, hz, 0.95) for hz in (1046.5, 783.99, 659.25)]
    melody = s.arrange(2.2, [(at, brass(s, hz, held, vibrato=held > 0.5) * (0.6 if hz < 1000.0 and at > 0.3 else 1.0))
                             for at, hz, held in notes + chord])
    return s.fade(s.reverb(melody, seconds=1.3, damping=0.5, mix=0.2)[:s.samples(2.6)], 0.0, 0.5)
