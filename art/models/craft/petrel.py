"""Petrel: turns tight and holds its line. A deep vee with wide chine lips that bite, flared
sides and a high bow."""
from kiln import model

from models.craft._jetski import MARKERS, JetSki, build as build_jetski, spec_size

PETREL = JetSki(
    length=2.9, beam=1.12, deadrise=25.0, chine_lip=0.1, flare=0.16, bow_fullness=2.0,
    bow_rise=0.56, rocker_from=0.48, deck_mid=0.5, deck_bow=0.7, hood_height=0.4, hood_width=0.68,
)


@model(max_triangles=6000, size=spec_size(PETREL), markers=MARKERS)
def build(k):
    build_jetski(k, PETREL)
