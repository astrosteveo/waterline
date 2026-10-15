"""Skipjack: quick off the mark, but the tail slides out in turns. Short and wide, with a
flat bottom, small chines and a blunt bow."""
from kiln import model

from models.craft._jetski import MARKERS, JetSki, build as build_jetski, spec_size

SKIPJACK = JetSki(
    length=2.72, beam=1.2, deadrise=13.0, widest_at=0.55, transom_width=0.97, bow_fullness=3.6,
    bow_rise=0.38, rocker_from=0.55, chine_lip=0.03, flare=0.06, deck_mid=0.5, deck_bow=0.66,
    hood_from=0.56, hood_height=0.42, hood_peak=0.25, hood_width=0.72,
    seat_from=0.12, seat_to=0.59, bar_at=0.63,
)


@model(max_triangles=6000, size=spec_size(SKIPJACK), markers=MARKERS)
def build(k):
    build_jetski(k, SKIPJACK)
