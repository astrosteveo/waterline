"""A wooden pier: a deck of planks across three stringers on cross beams, two rows of piles
down to the seabed, cross bracing, kerbs along both edges and iron bollards.

Built as environment/pier.gd's defaults: 30 m long and 4 m wide, the deck's top 1.75 m above
the water (deck height 1.6 plus half the deck), from the landward end at the origin along
-Z. Piles stand 4.3 m apart and reach 6 m down. The game stretches it to other sizes,
measuring it as built from the DeckEnd marker (the far right corner of the deck's top) and
the PileFoot marker (the foot of a pile).
"""
import math
import random

from kiln import geometry, model

LENGTH = 30.0
WIDTH = 4.0
DECK_TOP = 1.75
PLANK = 0.24
GAP = 0.02
PILE_DEPTH = -6.0
PILE_ROWS = 8


@model(max_triangles=5000, size=(WIDTH + 0.2, DECK_TOP + 0.45 - PILE_DEPTH, LENGTH),
       markers=["DeckEnd", "PileFoot"], allow_self_intersections=True, materials=["Wood", "WoodDark"])
def build(k):
    wood = k.material("Wood", "#9a7350", roughness=0.85)
    dark = k.material("WoodDark", "#4e3a2a", roughness=0.9)
    iron = k.material("Iron", "#24262b", roughness=0.6, metallic=0.5)
    rng = random.Random(7)
    planks = geometry.Mesh((), ())
    count = int(LENGTH / (PLANK + GAP))
    pitch = LENGTH / count
    for i in range(count):
        z = -pitch * (i + 0.5)
        sag = rng.uniform(-0.006, 0.0)
        planks = planks.merged(geometry.box((WIDTH, 0.06, pitch - GAP), (0, DECK_TOP - 0.03 + sag, z)))
    for x in (-WIDTH / 2 + 0.08, WIDTH / 2 - 0.08):
        planks = planks.merged(geometry.box((0.16, 0.12, LENGTH), (x, DECK_TOP + 0.06, -LENGTH / 2)))
    k.mesh("Deck", planks, material=wood)
    frame = geometry.Mesh((), ())
    for x in (-1.5, 0.0, 1.5):
        frame = frame.merged(geometry.box((0.16, 0.24, LENGTH), (x, DECK_TOP - 0.18, -LENGTH / 2)))
    piles = geometry.Mesh((), ())
    pile = geometry.lathe([(0, PILE_DEPTH), (0.18, PILE_DEPTH), (0.18, DECK_TOP - 0.3), (0.15, DECK_TOP - 0.3),
                           (0, DECK_TOP - 0.25)], 8)
    for row in range(PILE_ROWS):
        z = -LENGTH * row / (PILE_ROWS - 1)
        z = min(max(z, -LENGTH + 0.2), -0.2)
        frame = frame.merged(geometry.box((WIDTH + 0.2, 0.22, 0.26), (0, DECK_TOP - 0.41, z)))
        for x in (-WIDTH / 2 + 0.15, WIDTH / 2 - 0.15):
            piles = piles.merged(pile.translated((x, 0, z)))
        # Cross bracing between the two piles, under the deck.
        span = WIDTH - 0.3
        rise = 1.6
        angle = math.degrees(math.atan2(rise, span))
        brace = geometry.box((math.hypot(span, rise), 0.12, 0.1))
        for turn in (angle, -angle):
            frame = frame.merged(brace.rotated("z", turn).translated((0, DECK_TOP - 1.4, z + 0.2)))
    k.mesh("Frame", frame, material=dark)
    k.mesh("Piles", piles, material=dark)
    bollards = geometry.Mesh((), ())
    post = geometry.lathe([(0, 0), (0.12, 0), (0.1, 0.25), (0.14, 0.3), (0.14, 0.34), (0, 0.36)], 8)
    for z in (-1.5, -LENGTH / 2, -LENGTH + 1.5):
        for x in (-WIDTH / 2 + 0.3, WIDTH / 2 - 0.3):
            bollards = bollards.merged(post.translated((x, DECK_TOP, z)))
    k.mesh("Bollards", bollards, material=iron)
    k.marker("DeckEnd", (WIDTH / 2, DECK_TOP, -LENGTH))
    k.marker("PileFoot", (-WIDTH / 2 + 0.15, PILE_DEPTH, -0.2))
