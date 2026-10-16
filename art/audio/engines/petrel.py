"""Petrel's engine: a two-stroke triple, a smoother, higher buzz than a twin."""
from kiln import sound

from audio.engines._engine import Engine, loops

ENGINE = Engine(
    cylinders=3, strokes=2, idle=1350.0, rated=7100.0, limiter=7400.0,
    layers=(1350.0, 2150.0, 3250.0, 4900.0, 7400.0),
    exhaust=((260.0, 1.4, 5.0), (1050.0, 2.0, 6.0), (2600.0, 3.0, 2.0)),
    pulse_hz=400.0, rasp_hz=2900.0, rasp=0.4, imbalance=0.08, roughness=0.16, misfire=0.3,
    intake=0.2, mechanical=0.055, whine=0.09, gurgle=0.65, blades=3, hull_hz=4000.0, seed=71,
)


@sound(loop=True, seconds=(0.8, 1.6))
def build(s):
    return loops(s, ENGINE)
