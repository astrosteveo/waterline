"""A tall, pointed pillar. See _rock.py."""
from kiln import model

from models.rocks._rock import MATERIALS, Rock, build as build_rock

ROCK = Rock(half_height=2.4, lumps=0.18, cuts=10, squareness=3, tilt=0.35, taper=0.3, seed=43)


@model(max_triangles=1400, size=(2.0, ROCK.half_height * 2, 2.0), materials=MATERIALS)
def build(k):
    build_rock(k, ROCK)
