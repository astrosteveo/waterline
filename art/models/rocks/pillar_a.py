"""A sea stack: a tall pillar with a flat top. See _rock.py."""
from kiln import model

from models.rocks._rock import Rock, build as build_rock

ROCK = Rock(half_height=2.6, lumps=0.3, cuts=12, cut_depth=0.2, squareness=2.6, tilt=0.4, taper=0.45, seed=31)


@model(max_triangles=1400, size=(2.0, ROCK.half_height * 2, 2.0))
def build(k):
    build_rock(k, ROCK)
