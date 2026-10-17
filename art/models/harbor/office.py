"""A four-storey harbour office with a flat roof behind a parapet. See _building.py for its parts."""
from kiln import model

from models.harbor._building import MATERIALS, Building, build as build_building

BUILDING = Building(11, 12, 9, floors=4, roof="flat", seed=5)


@model(max_triangles=4000, size=(BUILDING.outer_width, None, None), allow_self_intersections=True,
       materials=MATERIALS)
def build(k):
    build_building(k, BUILDING)
