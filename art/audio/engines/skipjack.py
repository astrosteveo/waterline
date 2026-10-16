"""Skipjack's engine: a light two-stroke twin, raspy and quick to rev, stuttering off the throttle."""
from kiln import sound

from audio.engines._engine import Engine, loops

ENGINE = Engine(
    cylinders=2, strokes=2, idle=1400.0, rated=7000.0, limiter=7300.0,
    layers=(1400.0, 2200.0, 3300.0, 4900.0, 7300.0),
    exhaust=((230.0, 1.5, 4.0), (900.0, 2.2, 7.0), (2300.0, 3.0, 3.0)),
    pulse_hz=420.0, rasp_hz=2600.0, rasp=0.5, imbalance=0.1, roughness=0.2, misfire=0.35,
    intake=0.2, mechanical=0.06, whine=0.08, gurgle=0.7, blades=3, hull_hz=4200.0, seed=59,
)


@sound(loop=True, seconds=(0.8, 1.6))
def build(s):
    return loops(s, ENGINE)
