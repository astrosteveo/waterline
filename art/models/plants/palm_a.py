"""A tall palm leaning out. See _palm.py."""
from kiln import model

from models.plants._palm import Palm, build as build_palm

PALM = Palm(height=7.0, lean=1.4, seed=3)


@model(max_triangles=2000, allow_self_intersections=True)
def build(k):
    build_palm(k, PALM)
