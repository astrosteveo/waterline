"""Koa, the heaviest rider: broad shoulders, a long back, thick arms and legs, a bulky vest
with a high collar and a full-face helmet."""
from kiln import model

from models.riders._rider import JOINTS, PARTS, Rider, build as build_rider

KOA = Rider(shoulder_half=0.235, hip_half=0.12, back=1.04, girth=1.16, skin="#8a5a3c", vest="bulky")


@model(max_triangles=4000, markers=JOINTS + PARTS)
def build(k):
    build_rider(k, KOA)
