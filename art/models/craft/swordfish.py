"""Swordfish: fast once it's going, slow to get there and to turn. Long, narrow and low, with
a fine pointed bow and a long, low hood."""
from kiln import model

from models.craft._jetski import MARKERS, JetSki, build as build_jetski, spec_size

SWORDFISH = JetSki(
    length=3.2, beam=1.04, deadrise=22.0, widest_at=0.42, transom_width=0.86, bow_fullness=1.6,
    bow_rise=0.3, rocker_from=0.62, deck_stern=0.41, deck_mid=0.44, deck_bow=0.54,
    hood_from=0.53, hood_height=0.27, hood_peak=0.1, hood_width=0.6,
    seat_from=0.08, seat_to=0.55, seat_width=0.42, bar_at=0.58,
)


@model(max_triangles=6000, size=spec_size(SWORDFISH), markers=MARKERS)
def build(k):
    build_jetski(k, SWORDFISH)
