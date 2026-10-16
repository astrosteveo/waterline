"""The recipe side of kiln: the `model` and `texture` decorators and what each promises.

A model recipe looks like this:

    from kiln import model

    @model(max_triangles=800, size=(0.8, 0.8, 0.8), markers=["Lid"])
    def build(k):
        k.box("Body", (0.8, 0.8, 0.8), bevel=0.03, material=k.material("Wood", "#8a5a2b"))
        k.marker("Lid", (0, 0.8, 0))

`k` is a `kiln.blender.Kit`. Coordinates are in game space: metres, +X right, +Y up and
-Z forward, as Godot uses them. Kiln turns them into Blender's axes and back on export.

A texture recipe builds a material from Blender's procedural textures, which kiln bakes into
image maps that tile:

    from kiln import texture

    @texture(size=1024, tile=2.0, relief=0.02)
    def build(t):
        grains = t.noise(scale=40, detail=4)
        t.output(albedo=t.ramp(grains, [(0, "#c9b07a"), (1, "#e8d6a8")]), roughness=0.9, height=grains)

`t` is a `kiln.blender.shading.TextureKit`.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable, Sequence


@dataclass(frozen=True)
class ModelSpec:
    """What a model recipe promises, checked after every build."""

    # The most triangles the model may have, counted after modifiers. None: no limit.
    max_triangles: int | None = None
    # The model's expected bounding box in game space (x, y, z) in metres. An axis given as
    # None isn't checked.
    size: Sequence[float | None] | None = None
    # How far the bounding box may differ from `size`, as a share of each axis.
    size_tolerance: float = 0.02
    # Marker names that must exist (empties the game finds by name).
    markers: Sequence[str] = field(default_factory=tuple)
    # True: every mesh must be closed (each edge shared by exactly two faces).
    closed: bool = True
    # False: no mesh may cut through itself. Separate objects may still overlap.
    allow_self_intersections: bool = False


# The maps a texture can have, and what each holds.
TEXTURE_MAPS = {
    "albedo": "the surface's colour (sRGB)",
    "normal": "tangent-space normals from the height (OpenGL convention: green points up the image)",
    "roughness": "roughness, 0 to 1",
    "height": "the height, 0 to 1 (16-bit)",
}


@dataclass(frozen=True)
class TextureSpec:
    """What a texture recipe makes, checked after every bake. Every map must tile."""

    # Pixels along each side of each map.
    size: int = 1024
    # Metres of the game's surface one tile covers. The recipe's scales are per metre.
    tile: float = 1.0
    # Metres between height 0 and height 1, which sets how strong the normal map is.
    relief: float = 0.0
    # The maps to write, from TEXTURE_MAPS.
    maps: Sequence[str] = ("albedo", "normal", "roughness")
    # Samples per pixel when baking, which smooths edges finer than a pixel.
    samples: int = 16

    def __post_init__(self) -> None:
        unknown = [m for m in self.maps if m not in TEXTURE_MAPS]
        if unknown:
            raise ValueError(f"unknown texture maps {unknown}; kiln makes {list(TEXTURE_MAPS)}")
        if self.size < 4 or self.size & (self.size - 1):
            raise ValueError(f"texture size {self.size} isn't a power of two")


@dataclass(frozen=True)
class Recipe:
    """A recipe's build function and the spec it was declared with."""

    kind: str
    spec: ModelSpec | TextureSpec
    build: Callable


def model(**spec_fields) -> Callable[[Callable], Callable]:
    """Marks a function as a model recipe. The keyword arguments are `ModelSpec` fields."""
    spec = ModelSpec(**spec_fields)

    def mark(build: Callable) -> Callable:
        build.kiln_recipe = Recipe("model", spec, build)
        return build

    return mark


def texture(**spec_fields) -> Callable[[Callable], Callable]:
    """Marks a function as a texture recipe. The keyword arguments are `TextureSpec` fields."""
    spec = TextureSpec(**spec_fields)

    def mark(build: Callable) -> Callable:
        build.kiln_recipe = Recipe("texture", spec, build)
        return build

    return mark


def find_recipe(module) -> Recipe:
    """The one recipe in a recipe module. Raises ValueError if there is none or more than one."""
    found = [value.kiln_recipe for value in vars(module).values() if hasattr(value, "kiln_recipe")]
    if len(found) != 1:
        raise ValueError(f"{module.__file__}: expected one @model or @texture function, found {len(found)}")
    return found[0]
