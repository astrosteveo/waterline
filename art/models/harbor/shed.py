"""A two-storey net shed with a gable roof. See _building.py for its parts."""
from kiln import model

from models.harbor._building import MATERIALS, Building, build as build_building

BUILDING = Building(10, 7, 8, floors=2, lit=0.4, seed=6)


@model(max_triangles=4000, size=(BUILDING.outer_width, None, None),
       materials=MATERIALS)
def build(k):
    build_building(k, BUILDING)
