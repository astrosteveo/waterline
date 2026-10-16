"""Swordfish's engine: a big four-stroke four, deep and heavy, slow to wind up."""
from kiln import sound

from audio.engines._engine import Engine, loops

ENGINE = Engine(
    cylinders=4, strokes=4, idle=1600.0, rated=7300.0, limiter=7600.0,
    layers=(1600.0, 2500.0, 3700.0, 5300.0, 7600.0),
    exhaust=((140.0, 1.0, 8.0), (420.0, 1.8, 5.0), (1100.0, 2.5, 0.0)),
    pulse_hz=260.0, rasp_hz=1300.0, rasp=0.15, imbalance=0.08, roughness=0.1, misfire=0.03,
    intake=0.3, mechanical=0.045, whine=0.09, gurgle=0.8, blades=4, hull_hz=2600.0, seed=47,
)


@sound(loop=True, seconds=(0.8, 1.6))
def build(s):
    return loops(s, ENGINE)
