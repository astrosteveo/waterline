"""A flat slab, for reefs and breakwaters. See _rock.py."""
from kiln import model

from models.rocks._rock import MATERIALS, Rock, build as build_rock

ROCK = Rock(half_height=0.5, cuts=6, squareness=3, seed=5)


@model(max_triangles=1400, size=(2.0, ROCK.half_height * 2, 2.0), materials=MATERIALS)
def build(k):
    build_rock(k, ROCK)
