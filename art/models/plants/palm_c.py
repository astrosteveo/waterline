"""A tall palm with a long curving lean. See _palm.py."""
from kiln import model

from models.plants._palm import Palm, build as build_palm

PALM = Palm(height=8.4, lean=2.2, fronds=12, frond_length=3.6, droop=1.9, seed=14)


@model(max_triangles=2000, allow_self_intersections=True)
def build(k):
    build_palm(k, PALM)
