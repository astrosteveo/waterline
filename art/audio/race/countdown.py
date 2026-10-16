"""The start: `beep` for each count of the countdown, from the start clock, and `go`, the
starter's air horn: two horns a major third apart, as a dual-tone horn has, echoing back off
the shore."""
import numpy as np
from kiln import sound


def horn(s, freq: float, seconds: float, seed: int) -> np.ndarray:
    """One air horn's note: a reed's buzz through the horn's bell, its pitch settling as the
    air comes up to pressure."""
    t = s.time(seconds)
    pitch = freq * (1.0 - 0.06 * np.exp(-t / 0.04))
    reed = s.square(pitch, width=0.32)
    voiced = s.formants(reed, [(freq * 2.0, 2.0, 0.0), (1400.0, 1.6, 2.0), (2400.0, 2.0, -3.0)]) + reed * 0.15
    breath = s.bandpass(s.noise(seconds, seed), 2000.0, 0.7) * 0.15
    return (voiced + breath) * s.adsr(seconds - 0.15, 0.03, 0.1, 0.85, 0.15)


@sound(seconds=(0.1, 3.0))
def build(s):
    beep = s.mix(s.sine(880.0, 0.2), s.sine(1760.0, 0.2) * 0.12, s.sine(2640.0, 0.2) * 0.05)
    beep *= s.adsr(0.17, 0.004, 0.05, 0.8, 0.03)
    go = horn(s, 330.0, 1.05, 1) + horn(s, 415.3, 1.05, 2) * 0.9
    go = s.reverb(go, seconds=1.0, damping=0.7, mix=0.18, predelay=0.09)
    return {"beep": beep, "go": s.fade(go, 0.0, 0.3)}
