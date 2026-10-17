"""Marina, the base rider: an even build, a full-face helmet and a standard vest."""
from kiln import model

from models.riders._rider import JOINTS, PAINTED, PARTS, Rider, build as build_rider

MARINA = Rider(skin="#d9a982")


@model(max_triangles=4000, markers=JOINTS + PARTS, materials=PAINTED)
def build(k):
    build_rider(k, MARINA)
