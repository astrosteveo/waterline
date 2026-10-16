"""Ines, the lightest rider: slight and short-backed, in an open-face helmet and goggles with a
ponytail out the back, and a slim vest."""
from kiln import model

from models.riders._rider import JOINTS, PARTS, Rider, build as build_rider

INES = Rider(shoulder_half=0.188, hip_half=0.1, back=0.96, girth=0.87, skin="#e8c0a0", helmet="open",
             vest="slim", ponytail="#3a2418")


@model(max_triangles=4000, markers=JOINTS + PARTS)
def build(k):
    build_rider(k, INES)
