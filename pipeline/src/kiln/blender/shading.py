"""`TextureKit`, what a texture recipe's build function gets: Blender's procedural textures,
maths and colour ramps, wired into one material that kiln bakes into maps.

Every pattern tiles: the noise and Voronoi textures are sampled on a torus in four
dimensions, so the left edge meets the right and the top meets the bottom, and stripes and
bands come in whole numbers per tile. Scales are per metre of the game's surface (the
recipe's `tile` says how many metres one tile covers).

A value can also be baked partway through (`TextureKit.bake`), and masks that look at the
pixels round each one worked out from it (`kiln.masks`): blurred, ridges, hollows and
ambient occlusion, which the rest of the graph uses as values.

Values and colours are nodes; arithmetic on them adds nodes:

    grains = t.noise(scale=30, detail=4)
    ripples = t.stripes(12, along="v", warp=t.noise(scale=2) * 3)
    height = grains * 0.3 + ripples * 0.7
    colour = t.ramp(height, [(0.2, "#b89a64"), (0.8, "#e6d3a3")])
    t.output(albedo=colour, roughness=0.9 - grains * 0.2, height=height)
"""
from __future__ import annotations

import math
import zlib
from typing import Sequence

import bpy
import numpy as np

from kiln import masks
from kiln.blender.kit import parse_color

# The noise types Blender's Noise texture offers, by the names recipes use.
NOISE_TYPES = {
    "fbm": "FBM",
    "multifractal": "MULTIFRACTAL",
    "ridged": "RIDGED_MULTIFRACTAL",
    "hybrid": "HYBRID_MULTIFRACTAL",
    "hetero": "HETERO_TERRAIN",
}
# What a Voronoi texture can give, by the names recipes use: (Blender feature, output).
VORONOI_OUTPUTS = {
    "distance": ("F1", "Distance"),
    "second": ("F2", "Distance"),
    "smooth": ("SMOOTH_F1", "Distance"),
    "edge": ("DISTANCE_TO_EDGE", "Distance"),
    "random": ("F1", "Color"),
}


class Value:
    """A number per pixel: a node's output. Combine with numbers and other values using
    + - * / ** and the methods below."""

    def __init__(self, kit: "TextureKit", socket) -> None:
        self.kit = kit
        self.socket = socket

    def _op(self, operation: str, other=None, swap: bool = False) -> "Value":
        a, b = (other, self) if swap else (self, other)
        return self.kit._math(operation, a, b)

    def __add__(self, other): return self._op("ADD", other)
    def __radd__(self, other): return self._op("ADD", other, swap=True)
    def __sub__(self, other): return self._op("SUBTRACT", other)
    def __rsub__(self, other): return self._op("SUBTRACT", other, swap=True)
    def __mul__(self, other): return self._op("MULTIPLY", other)
    def __rmul__(self, other): return self._op("MULTIPLY", other, swap=True)
    def __truediv__(self, other): return self._op("DIVIDE", other)
    def __rtruediv__(self, other): return self._op("DIVIDE", other, swap=True)
    def __pow__(self, other): return self._op("POWER", other)
    def __neg__(self): return self._op("MULTIPLY", -1.0)
    def __abs__(self): return self._op("ABSOLUTE")

    def min(self, other) -> "Value":
        return self._op("MINIMUM", other)

    def max(self, other) -> "Value":
        return self._op("MAXIMUM", other)

    def clamp(self, low: float = 0.0, high: float = 1.0) -> "Value":
        return self.max(low).min(high)

    def floor(self) -> "Value":
        return self._op("FLOOR")

    def fract(self) -> "Value":
        return self._op("FRACT")

    def wrap(self, high: float) -> "Value":
        """The value wrapped into 0..`high`."""
        node = self.kit._math("WRAP", self, high)
        node.socket.node.inputs[2].default_value = 0.0
        return node

    def sin(self) -> "Value":
        return self._op("SINE")

    def cos(self) -> "Value":
        return self._op("COSINE")

    def remap(self, low: float, high: float, to_low: float = 0.0, to_high: float = 1.0,
              smooth: bool = False) -> "Value":
        """`low`..`high` mapped onto `to_low`..`to_high`, clamped; with `smooth`, eased at
        both ends (smoothstep)."""
        node = self.kit._node("ShaderNodeMapRange")
        node.interpolation_type = "SMOOTHSTEP" if smooth else "LINEAR"
        node.clamp = True
        self.kit._link(self, node.inputs["Value"])
        for name, number in (("From Min", low), ("From Max", high), ("To Min", to_low), ("To Max", to_high)):
            node.inputs[name].default_value = number
        return Value(self.kit, node.outputs["Result"])

    def smoothstep(self, low: float, high: float) -> "Value":
        """0 below `low`, 1 above `high`, eased between."""
        return self.remap(low, high, smooth=True)


class Color:
    """A colour per pixel: a node's output. Multiply by a value or a number to darken or
    brighten it, or by another colour to tint it; add colours with +."""

    def __init__(self, kit: "TextureKit", socket) -> None:
        self.kit = kit
        self.socket = socket

    def __mul__(self, other) -> "Color":
        if isinstance(other, Color):
            return self.kit._mix_colors(self, other, 1.0, "MULTIPLY")
        node = self.kit._node("ShaderNodeVectorMath")
        node.operation = "SCALE"
        self.kit._link(self, node.inputs[0])
        self.kit._link(other, node.inputs["Scale"])
        return Color(self.kit, node.outputs["Vector"])

    __rmul__ = __mul__

    def __add__(self, other: "Color") -> "Color":
        return self.kit._mix_colors(self, other, 1.0, "ADD")


class Baked:
    """A value baked into a tile's pixels partway through a recipe (`TextureKit.bake`): what
    the masks are worked out from."""

    def __init__(self, pixels: np.ndarray) -> None:
        # Rows bottom to top, a value per pixel.
        self.pixels = pixels


class TextureKit:
    """Builds a texture's material in the current Blender scene. `output` says which values
    become which maps; kiln then bakes them. `size` is the maps' pixels a side, `relief` the
    metres between height 0 and 1, and `bake` bakes a value into pixels (see `bake`)."""

    def __init__(self, tile: float, size: int = 1024, relief: float = 0.0, bake=None) -> None:
        self.tile = tile
        self.size = size
        self.relief = relief
        self._bake = bake
        self.material = bpy.data.materials.new("KilnTexture")
        self.tree = self.material.node_tree
        for node in list(self.tree.nodes):
            self.tree.nodes.remove(node)
        self.outputs: dict[str, Value | Color] = {}
        coords = self._node("ShaderNodeTexCoord")
        uv = self._node("ShaderNodeSeparateXYZ")
        self.tree.links.new(coords.outputs["UV"], uv.inputs[0])
        self._uv = coords.outputs["UV"]
        # Across the tile, 0 to 1: u left to right, v bottom to top.
        self.u = Value(self, uv.outputs["X"])
        self.v = Value(self, uv.outputs["Y"])
        self._tori: dict[tuple, tuple] = {}

    # --- Patterns ----------------------------------------------------------------------

    def noise(self, scale: float, detail: float = 2.0, roughness: float = 0.5, lacunarity: float = 2.0,
              distortion: float = 0.0, stretch: Sequence[float] = (1.0, 1.0), seed: int = 0,
              kind: str = "fbm") -> Value:
        """Blender's Noise texture, about 0 to 1 (mostly 0.3 to 0.7), with about `scale`
        features a metre; `stretch` (u, v) makes them that many times longer along u or v.
        `kind` is fbm, multifractal, ridged, hybrid or hetero. A different `seed` gives a
        different pattern."""
        node = self._node("ShaderNodeTexNoise")
        node.noise_dimensions = "4D"
        node.noise_type = NOISE_TYPES[kind]
        vector, w = self._torus(stretch, seed)
        self.tree.links.new(vector, node.inputs["Vector"])
        self.tree.links.new(w, node.inputs["W"])
        for name, number in (("Scale", scale), ("Detail", detail), ("Roughness", roughness),
                             ("Lacunarity", lacunarity), ("Distortion", distortion)):
            node.inputs[name].default_value = number
        return Value(self, node.outputs["Fac"])

    def voronoi(self, scale: float, output: str = "distance", randomness: float = 1.0,
                smoothness: float = 0.5, stretch: Sequence[float] = (1.0, 1.0), seed: int = 0) -> Value:
        """Blender's Voronoi texture: cells about 1/`scale` metres across. `output` is the
        distance to the nearest cell centre ("distance"), to the second nearest ("second"),
        a smoothed distance ("smooth", with `smoothness`), the distance to the nearest edge
        between cells ("edge", for cracks), or a random number per cell ("random")."""
        feature, socket = VORONOI_OUTPUTS[output]
        node = self._node("ShaderNodeTexVoronoi")
        node.voronoi_dimensions = "4D"
        node.feature = feature
        vector, w = self._torus(stretch, seed)
        self.tree.links.new(vector, node.inputs["Vector"])
        self.tree.links.new(w, node.inputs["W"])
        node.inputs["Scale"].default_value = scale
        node.inputs["Randomness"].default_value = randomness
        if feature == "SMOOTH_F1":
            node.inputs["Smoothness"].default_value = smoothness
        result = node.outputs[socket]
        if output == "random":
            split = self._node("ShaderNodeSeparateColor")
            self.tree.links.new(result, split.inputs[0])
            result = split.outputs[0]
        return Value(self, result)

    def stripes(self, count: int, along: str = "v", warp=None, phase: float = 0.0) -> Value:
        """Soft stripes from 0 to 1 and back, `count` of them across the tile (a whole number,
        so they tile), running across `along` (u or v). `warp` (a value or number) bends them
        by that many stripe widths."""
        if count != int(count):
            raise ValueError(f"{count} stripes don't tile: give a whole number")
        position = self.u if along == "u" else self.v
        angle = position * (2 * math.pi * count) + phase
        if warp is not None:
            angle = angle + self._as_value(warp) * (2 * math.pi)
        return 0.5 + 0.5 * angle.sin()

    def bands(self, count: int, along: str = "v", warp=None) -> Value:
        """Which of `count` equal bands across the tile a pixel is in, as 0, 1/count, ...
        (count - 1)/count: planks or courses of stone. Feed it to `random` for a number per band."""
        position = self.u if along == "u" else self.v
        if warp is not None:
            position = position + warp
        return (position * count).floor().wrap(count) / count

    def random(self, value, seed: int = 0) -> Value:
        """A random number from 0 to 1 for each different `value` (white noise), the same
        for the same value: a tone per plank from `bands`, or per cell."""
        node = self._node("ShaderNodeTexWhiteNoise")
        node.noise_dimensions = "1D"
        self._link(self._as_value(value) + _seed_offset(seed), node.inputs["W"])
        return Value(self, node.outputs["Value"])

    # --- Masks -------------------------------------------------------------------------

    def bake(self, value) -> Baked:
        """Bakes `value` (usually the height) into the tile's pixels now, so the masks below
        can be worked out from it. Each bake takes as long as a map's."""
        if self._bake is None:
            raise RuntimeError("this texture kit can't bake")
        return Baked(self._bake(self._as_value(value)))

    def blurred(self, baked: Baked, radius: float) -> Value:
        """`baked` blurred over about `radius` metres."""
        return self._mask(masks.blurred(baked.pixels, self._pixels(radius)))

    def ridges(self, baked: Baked, radius: float) -> Value:
        """How far each point of `baked` (a height) stands above the height within about
        `radius` metres, 0 to 1: edges and crests, where a surface wears and lightens."""
        return self._mask(masks.ridges(baked.pixels, self._pixels(radius)))

    def hollows(self, baked: Baked, radius: float) -> Value:
        """How far each point of `baked` (a height) lies below the height within about
        `radius` metres, 0 to 1: cracks, pits and gaps, where dirt gathers."""
        return self._mask(masks.hollows(baked.pixels, self._pixels(radius)))

    def occlusion(self, baked: Baked, radius: float, relief: float | None = None) -> Value:
        """Ambient occlusion from `baked` (a height, `relief` metres between 0 and 1, the
        texture's own by default), looking about `radius` metres round each point: 1 open
        to the sky, toward 0 deep in a hollow. Darken the albedo with it, or output it as the
        occlusion map."""
        depth = (self.relief if relief is None else relief) / (self.tile / self.size)
        return self._mask(masks.occlusion(baked.pixels, self._pixels(radius), depth))

    def _pixels(self, metres: float) -> float:
        return metres / self.tile * self.size

    def _mask(self, pixels: np.ndarray) -> Value:
        """A value read from `pixels` (the tile's, rows bottom to top), each pixel as it is."""
        image = bpy.data.images.new("KilnMask", pixels.shape[1], pixels.shape[0], float_buffer=True, is_data=True)
        rgba = np.repeat(pixels[:, :, None], 4, axis=2)
        rgba[:, :, 3] = 1.0
        image.pixels.foreach_set(rgba.astype(np.float32).ravel())
        node = self._node("ShaderNodeTexImage")
        node.image = image
        node.interpolation = "Closest"
        node.extension = "REPEAT"
        self.tree.links.new(self._uv, node.inputs["Vector"])
        split = self._node("ShaderNodeSeparateColor")
        self.tree.links.new(node.outputs["Color"], split.inputs[0])
        return Value(self, split.outputs[0])

    # --- Colours -----------------------------------------------------------------------

    def color(self, color) -> Color:
        """A flat colour ("#rrggbb" or sRGB floats)."""
        node = self._node("ShaderNodeRGB")
        node.outputs[0].default_value = parse_color(color)
        return Color(self, node.outputs[0])

    def ramp(self, value, stops: Sequence[tuple[float, object]], ease: bool = False) -> Color:
        """A colour ramp: `value` from 0 to 1 picks a colour between the stops
        [(position, colour), ...]; with `ease`, eased between them."""
        node = self._node("ShaderNodeValToRGB")
        ramp = node.color_ramp
        ramp.interpolation = "EASE" if ease else "LINEAR"
        while len(ramp.elements) < len(stops):
            ramp.elements.new(0.5)
        for element, (position, color) in zip(ramp.elements, sorted(stops, key=lambda s: s[0])):
            element.position = position
            element.color = parse_color(color)
        self._link(value, node.inputs["Fac"])
        return Color(self, node.outputs["Color"])

    def mix(self, a, b, factor):
        """`a` where `factor` is 0, `b` where it is 1, between in between: two colours, or
        two values (or numbers)."""
        if isinstance(a, (Color, str)) or isinstance(b, (Color, str)):
            return self._mix_colors(self._as_color(a), self._as_color(b), factor, "MIX")
        node = self._node("ShaderNodeMix")
        node.data_type = "FLOAT"
        self._link(factor, _socket(node.inputs, "Factor", "VALUE"))
        self._link(a, _socket(node.inputs, "A", "VALUE"))
        self._link(b, _socket(node.inputs, "B", "VALUE"))
        return Value(self, _socket(node.outputs, "Result", "VALUE"))

    # --- Output ------------------------------------------------------------------------

    def output(self, albedo=None, roughness=None, height=None, occlusion=None) -> None:
        """Which colour is the albedo and which values the roughness, height and occlusion (0
        to 1). Numbers and "#rrggbb" colours are flat. The normal map is worked out from the
        height."""
        for name, given in (("albedo", albedo), ("roughness", roughness), ("height", height),
                            ("occlusion", occlusion)):
            if given is None:
                continue
            self.outputs[name] = self._as_color(given) if name == "albedo" else self._as_value(given)

    # --- Wiring ------------------------------------------------------------------------

    def _node(self, kind: str):
        return self.tree.nodes.new(kind)

    def _link(self, source, target) -> None:
        if isinstance(source, (Value, Color)):
            self.tree.links.new(source.socket, target)
        elif isinstance(source, str):
            target.default_value = parse_color(source)
        else:
            target.default_value = source

    def _as_value(self, given) -> Value:
        if isinstance(given, Value):
            return given
        node = self._node("ShaderNodeValue")
        node.outputs[0].default_value = float(given)
        return Value(self, node.outputs[0])

    def _as_color(self, given) -> Color:
        if isinstance(given, Color):
            return given
        if isinstance(given, Value):
            return Color(self, given.socket)
        return self.color(given)

    def _math(self, operation: str, a, b=None) -> Value:
        node = self._node("ShaderNodeMath")
        node.operation = operation
        self._link(a, node.inputs[0])
        if b is not None:
            self._link(b, node.inputs[1])
        return Value(self, node.outputs[0])

    def _mix_colors(self, a: Color, b: Color, factor, blend: str) -> Color:
        node = self._node("ShaderNodeMix")
        node.data_type = "RGBA"
        node.blend_type = blend
        self._link(factor, _socket(node.inputs, "Factor", "VALUE"))
        self._link(a, _socket(node.inputs, "A", "RGBA"))
        self._link(b, _socket(node.inputs, "B", "RGBA"))
        return Color(self, _socket(node.outputs, "Result", "RGBA"))

    def _torus(self, stretch: Sequence[float], seed: int):
        """Where each pixel lies on a flat torus in 4D whose two circles are the tile's width
        and height in metres (times `stretch`), so a pattern sampled there tiles. Returns the
        (x, y, z) vector and w sockets."""
        key = (tuple(stretch), seed)
        if key not in self._tori:
            radius_u = self.tile / (2 * math.pi) / stretch[0]
            radius_v = self.tile / (2 * math.pi) / stretch[1]
            offset = _seed_offset(seed)
            turn_u = self.u * (2 * math.pi)
            turn_v = self.v * (2 * math.pi)
            parts = [turn_u.cos() * radius_u + offset, turn_u.sin() * radius_u + offset * 0.7,
                     turn_v.cos() * radius_v + offset * 1.3, turn_v.sin() * radius_v + offset * 0.4]
            vector = self._node("ShaderNodeCombineXYZ")
            for index in range(3):
                self.tree.links.new(parts[index].socket, vector.inputs[index])
            self._tori[key] = (vector.outputs[0], parts[3].socket)
        return self._tori[key]


def _seed_offset(seed: int) -> float:
    """A fixed offset for each seed, far enough apart that patterns don't repeat."""
    return (zlib.crc32(str(seed).encode()) % 10007) * 3.17 if seed else 0.0


def _socket(sockets, name: str, kind: str):
    """The socket called `name` of type `kind` (the Mix node has one per data type)."""
    return next(s for s in sockets if s.name == name and s.type == kind)
