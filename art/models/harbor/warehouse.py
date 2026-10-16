"""A long, low warehouse with a roller door and a row of high windows. See _building.py for its parts."""
from kiln import model

from models.harbor._building import Building, build as build_building

BUILDING = Building(14, 6, 10, floors=1, door="roller", lit=0.35, seed=3)


@model(max_triangles=4000, size=(BUILDING.outer_width, None, None), allow_self_intersections=True)
def build(k):
    build_building(k, BUILDING)
