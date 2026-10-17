"""A two-storey boathouse with a gable roof. See _building.py for its parts."""
from kiln import model

from models.harbor._building import MATERIALS, Building, build as build_building

BUILDING = Building(12, 7, 9, floors=2, seed=1)


@model(max_triangles=4000, size=(BUILDING.outer_width, None, None),
       materials=MATERIALS)
def build(k):
    build_building(k, BUILDING)
