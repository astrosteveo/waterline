"""Tradewind, the base craft: even all round, a classic rounded hull."""
from kiln import model

from models.craft._jetski import MARKERS, JetSki, build as build_jetski, spec_size

TRADEWIND = JetSki()


@model(max_triangles=6000, size=spec_size(TRADEWIND), markers=MARKERS)
def build(k):
    build_jetski(k, TRADEWIND)
