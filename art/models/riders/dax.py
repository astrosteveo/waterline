"""Dax: wiry, in a shorty wetsuit (bare forearms and shins), a full-face helmet with a
motocross peak and a standard vest."""
from kiln import model

from models.riders._rider import JOINTS, PAINTED, PARTS, Rider, build as build_rider

DAX = Rider(shoulder_half=0.2, hip_half=0.105, girth=0.94, skin="#5e3d2a", helmet="peak", suit="shorty")


@model(max_triangles=4000, markers=JOINTS + PARTS, materials=PAINTED)
def build(k):
    build_rider(k, DAX)
