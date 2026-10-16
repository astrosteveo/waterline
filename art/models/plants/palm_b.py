"""A shorter, straighter palm. See _palm.py."""
from kiln import model

from models.plants._palm import Palm, build as build_palm

PALM = Palm(height=5.6, lean=0.8, fronds=10, frond_length=3.0, seed=8)


@model(max_triangles=2000, allow_self_intersections=True)
def build(k):
    build_palm(k, PALM)
