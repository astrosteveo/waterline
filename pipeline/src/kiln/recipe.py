"""The recipe side of kiln: the `model` decorator and the checks a recipe asks for.

A recipe file looks like this:

    from kiln import model

    @model(max_triangles=800, size=(0.8, 0.8, 0.8), markers=["Lid"])
    def build(k):
        k.box("Body", (0.8, 0.8, 0.8), bevel=0.03, material=k.material("Wood", "#8a5a2b"))
        k.marker("Lid", (0, 0.8, 0))

`k` is a `kiln.blender.Kit`. Coordinates are in game space: metres, +X right, +Y up and
-Z forward, as Godot uses them. Kiln turns them into Blender's axes and back on export.
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


@dataclass(frozen=True)
class Recipe:
    """A recipe's build function and the spec it was declared with."""

    kind: str
    spec: ModelSpec
    build: Callable


def model(**spec_fields) -> Callable[[Callable], Callable]:
    """Marks a function as a model recipe. The keyword arguments are `ModelSpec` fields."""
    spec = ModelSpec(**spec_fields)

    def mark(build: Callable) -> Callable:
        build.kiln_recipe = Recipe("model", spec, build)
        return build

    return mark


def find_recipe(module) -> Recipe:
    """The one recipe in a recipe module. Raises ValueError if there is none or more than one."""
    found = [value.kiln_recipe for value in vars(module).values() if hasattr(value, "kiln_recipe")]
    if len(found) != 1:
        raise ValueError(f"{module.__file__}: expected one @model function, found {len(found)}")
    return found[0]
