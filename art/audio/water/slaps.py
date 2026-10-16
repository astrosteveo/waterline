"""The hull slapping down on chop at speed: a hard knock and a smack of water, with a little
spray. Four, so a run of them doesn't repeat."""
from kiln import sound

from audio.water._water import bubbles, spray, thump


@sound(seconds=(0.2, 0.6))
def build(s):
    sounds = {}
    for k in range(4):
        rng = s.rng(60 + k)
        knock = thump(s, 0.35, rng.uniform(105.0, 140.0), rng.uniform(0.03, 0.045))
        smack = s.bandpass(s.noise(0.35, 70 + k), rng.uniform(1100.0, 1700.0), 0.6) * s.decay(0.35, 0.018, 0.0008) * 2.0
        hiss = spray(s, 0.35, 80 + k) * s.decay(0.35, 0.07, 0.006) * 0.5
        fizz = bubbles(s, 0.35, 900.0 * s.decay(0.35, 0.06), 90 + k, largest=0.004) * 0.5
        sounds[str(k + 1)] = s.fade(s.highpass(knock + smack + hiss + fizz, 40.0), 0.0005, 0.12)
    return sounds
