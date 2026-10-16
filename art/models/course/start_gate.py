"""The start and finish arch: two pylons in red and white bands standing in the water, with
white caps, and a blue banner across the course with a chequered strip under it.

Built for course/start_gate.gd's defaults, 46 m between the pylons and the banner's top
13 m up. The game moves the parts to fit a gate of another size: PylonLeft and PylonRight
(their origins at their feet, 4 m under the water) go to either side and stretch to the
height, and the Banner (its origin at its centre, the chequered strip moving with it) goes
to the top and stretches across.
"""
from kiln import geometry, model

SPAN = 46.0
HEIGHT = 13.0
PYLON_BOTTOM = -4.0
PYLON_WIDTH = 1.6
BANDS = 7
BANNER_HEIGHT = 2.4
BANNER_DEPTH = 0.35
SQUARE = 1.2


def banded_column(width: float, low: float, high: float, bands: int) -> geometry.Mesh:
    """A square column from `low` to `high` in `bands` equal bands, alternating slots 0 and 1
    from the bottom, its caps in slot 1."""
    h = width / 2
    sections = []
    for i in range(bands + 1):
        y = low + (high - low) * i / bands
        sections.append([(-h, y, -h), (h, y, -h), (h, y, h), (-h, y, h)])
    column = geometry.loft(sections, cap_slot=1)
    slots = list(column.slots())
    for band in range(bands):
        for side in range(4):
            slots[band * 4 + side] = band % 2
    return geometry.Mesh(column.vertices, column.faces, tuple(slots))


def chequer(width: float, height: float, depth: float, cols: int, rows: int) -> geometry.Mesh:
    """A slab chequered in slots 0 and 1 on every face, centred on the origin."""
    xs = [-width / 2 + width * i / cols for i in range(cols + 1)]
    ys = [-height / 2 + height * j / rows for j in range(rows + 1)]
    vertices = []
    for z in (depth / 2, -depth / 2):
        vertices.extend((x, y, z) for y in ys for x in xs)
    back = len(vertices) // 2

    def front(i, j):
        return j * (cols + 1) + i

    faces, slots = [], []
    for j in range(rows):
        for i in range(cols):
            faces.append((front(i, j), front(i + 1, j), front(i + 1, j + 1), front(i, j + 1)))
            faces.append((back + front(i, j + 1), back + front(i + 1, j + 1), back + front(i + 1, j), back + front(i, j)))
            slots += [(i + j) % 2] * 2
    for i in range(cols):
        top, bottom = rows, 0
        faces.append((front(i, top), front(i + 1, top), back + front(i + 1, top), back + front(i, top)))
        faces.append((back + front(i, bottom), back + front(i + 1, bottom), front(i + 1, bottom), front(i, bottom)))
        slots += [(i + rows - 1) % 2, i % 2]
    for j in range(rows):
        right, left = cols, 0
        faces.append((front(right, j), back + front(right, j), back + front(right, j + 1), front(right, j + 1)))
        faces.append((front(left, j + 1), back + front(left, j + 1), back + front(left, j), front(left, j)))
        slots += [(j + cols - 1) % 2, j % 2]
    return geometry.Mesh(tuple(vertices), tuple(faces), tuple(slots))


@model(max_triangles=3000, size=(SPAN + 2.2, HEIGHT + 0.4 - PYLON_BOTTOM, 2.2),
       markers=["PylonLeft", "PylonRight", "Banner"])
def build(k):
    pylon = k.material("Pylon", "#ee2219", roughness=0.55)
    white = k.material("White", "#f6f6f2", roughness=0.55)
    banner = k.material("Banner", "#1a4dcc", roughness=0.6)
    black = k.material("Black", "#15151a", roughness=0.6)
    column = banded_column(PYLON_WIDTH, 0.0, HEIGHT - PYLON_BOTTOM, BANDS)
    for name, side in (("PylonLeft", -1), ("PylonRight", 1)):
        foot = (side * SPAN / 2, PYLON_BOTTOM, 0.0)
        body = k.mesh(name, column, material=[pylon, white], position=foot)
        cap = geometry.box((2.2, 0.4, 2.2), (0.0, HEIGHT - PYLON_BOTTOM + 0.2, 0.0))
        k.mesh(name + "Cap", cap, material=white, position=foot, parent=body)
    centre = (0.0, HEIGHT - BANNER_HEIGHT / 2, 0.0)
    board = k.mesh("Banner", geometry.box((SPAN, BANNER_HEIGHT, BANNER_DEPTH)), material=banner, position=centre)
    cols = int(SPAN / SQUARE)
    strip = chequer(SPAN, 1.2, BANNER_DEPTH + 0.03, cols, 2)
    k.mesh("Chequer", strip, material=[white, black], position=(0.0, centre[1] - BANNER_HEIGHT / 2 - 0.6, 0.0),
           parent=board)
