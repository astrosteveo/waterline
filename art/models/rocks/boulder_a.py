"""A rounded boulder. See _rock.py."""
from kiln import model

from models.rocks._rock import Rock, build as build_rock

ROCK = Rock(half_height=1.0, seed=11)


@model(max_triangles=1400, size=(2.0, ROCK.half_height * 2, 2.0))
def build(k):
    build_rock(k, ROCK)
