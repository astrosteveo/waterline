"""Tradewind's engine: a four-stroke triple, even and smooth, with a growl at the top."""
from kiln import sound

from audio.engines._engine import Engine, loops

ENGINE = Engine(
    cylinders=3, strokes=4, idle=1750.0, rated=7800.0, limiter=8100.0,
    layers=(1750.0, 2700.0, 4000.0, 5700.0, 8100.0),
    exhaust=((180.0, 1.2, 6.0), (520.0, 2.0, 4.0), (1350.0, 2.5, -2.0)),
    pulse_hz=320.0, rasp_hz=1600.0, rasp=0.2, imbalance=0.12, roughness=0.14, misfire=0.05,
    intake=0.25, mechanical=0.05, whine=0.1, gurgle=0.7, blades=3, hull_hz=3200.0, seed=31,
)


@sound(loop=True, seconds=(0.8, 1.6))
def build(s):
    return loops(s, ENGINE)
