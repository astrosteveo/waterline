"""A tall, narrow three-storey house with a steep gable roof. See _building.py for its parts."""
from kiln import model

from models.harbor._building import MATERIALS, Building, build as build_building

BUILDING = Building(9, 10, 8, floors=3, seed=2)


@model(max_triangles=4000, size=(BUILDING.outer_width, None, None), allow_self_intersections=True,
       materials=MATERIALS)
def build(k):
    build_building(k, BUILDING)
