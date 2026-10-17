"""Baking a texture recipe into image maps that tile, and the texture's preview sheet.

The recipe's material goes on a square with UVs from 0 to 1 and Cycles bakes each value the
recipe gave (albedo, roughness, height) through an emission shader, on the CPU with a fixed
seed so every build gives the same pixels. The normal map is worked out from the height,
wrapping round the edges, so it tiles as the height does. Each map is checked for seams and
written as a PNG: `<stem>_<map>.png`.
"""
from __future__ import annotations

import os

import bpy
import numpy as np

from kiln import png
from kiln.blender.shading import TextureKit
from kiln.recipe import TextureSpec

# A map tiles when its wrap-round edges differ by no more than this many times as much as
# neighbouring pixels do on average (plus a little, for flat maps).
SEAM_RATIO = 1.5
SEAM_SLACK = 0.002
# The preview sheet: each map tiled 2x2 in a square this many pixels wide.
PREVIEW_TILE = 512


def build_texture(recipe, stem: str, export: bool, report_dir: str | None) -> dict:
    """Runs a texture recipe, bakes and checks its maps, and (with `export`) writes them next
    to `stem`. With `report_dir`, renders the preview sheet there. Returns the report fields."""
    spec: TextureSpec = recipe.spec
    kit = TextureKit(spec.tile)
    recipe.build(kit)
    problems = []
    needed = {"albedo": "albedo", "roughness": "roughness", "height": "height", "normal": "height"}
    missing = sorted({needed[m] for m in spec.maps if needed[m] not in kit.outputs})
    if missing:
        return {"kind": "texture", "problems": [f"the recipe gave no {', '.join(missing)} (t.output)"]}
    baked = {name: _bake(kit, value, spec) for name, value in kit.outputs.items()
             if name in {needed[m] for m in spec.maps}}
    maps = {}
    for name in spec.maps:
        if name == "albedo":
            maps[name] = _to_srgb(baked["albedo"][:, :, :3])
        elif name == "normal":
            maps[name] = normals_from_height(baked["height"][:, :, 0], spec.relief, spec.tile / spec.size) * 0.5 + 0.5
        else:
            maps[name] = baked[name][:, :, :1]
    seams = {}
    for name, pixels in maps.items():
        edge, inside = seam(pixels)
        seams[name] = [round(edge, 5), round(inside, 5)]
        if edge > inside * SEAM_RATIO + SEAM_SLACK:
            problems.append(f"{name} doesn't tile: its edges differ by {edge:.4f} where neighbouring "
                            f"pixels differ by {inside:.4f}")
        low, high = float(pixels.min()), float(pixels.max())
        if low < -0.001 or high > 1.001:
            problems.append(f"{name} runs from {low:.3f} to {high:.3f}, outside 0 to 1")
    report = {"kind": "texture", "size": [spec.size, spec.size], "tile": spec.tile, "maps": list(spec.maps),
              "seams": seams, "problems": problems}
    if problems:
        return report
    outputs = [f"{stem}_{name}.png" for name in spec.maps]
    if export:
        os.makedirs(os.path.dirname(stem), exist_ok=True)
        for name, path in zip(spec.maps, outputs):
            _write_png(path, maps[name], 16 if name == "height" else 8)
    report["outputs"] = outputs
    if report_dir is not None:
        sheet = os.path.join(report_dir, "preview.png")
        _preview(sheet, [maps[name] for name in spec.maps])
        report["preview"] = sheet
    return report


def normals_from_height(height: np.ndarray, relief: float, texel: float) -> np.ndarray:
    """Tangent-space normals (x right, y up the image, z out) from a height map whose rows
    run bottom to top, as Blender stores them. Slopes wrap round the edges."""
    scale = relief / (2 * texel)
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * scale
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * scale
    normal = np.stack([-dx, -dy, np.ones_like(height)], axis=-1)
    return normal / np.linalg.norm(normal, axis=-1, keepdims=True)


def seam(pixels: np.ndarray) -> tuple[float, float]:
    """How much a map's wrap-round edges differ (left from right, top from bottom) and how
    much neighbouring pixels differ on average inside it."""
    edge = (np.abs(pixels[:, 0] - pixels[:, -1]).mean() + np.abs(pixels[0] - pixels[-1]).mean()) / 2
    inside = (np.abs(np.diff(pixels, axis=1)).mean() + np.abs(np.diff(pixels, axis=0)).mean()) / 2
    return float(edge), float(inside)


def _bake(kit: TextureKit, value, spec: TextureSpec) -> np.ndarray:
    """Bakes one value of the material into a float image: rows bottom to top, RGBA."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = spec.samples
    scene.cycles.seed = 0
    scene.cycles.use_denoising = False
    plane = _plane(kit.material)
    tree = kit.tree
    for node in [n for n in tree.nodes if n.get("kiln_bake")]:
        tree.nodes.remove(node)
    emission = tree.nodes.new("ShaderNodeEmission")
    output = tree.nodes.new("ShaderNodeOutputMaterial")
    target = tree.nodes.new("ShaderNodeTexImage")
    for node in (emission, output, target):
        node["kiln_bake"] = True
    tree.links.new(value.socket, emission.inputs["Color"])
    tree.links.new(emission.outputs[0], output.inputs["Surface"])
    image = bpy.data.images.new("KilnBake", spec.size, spec.size, float_buffer=True, is_data=True)
    target.image = image
    tree.nodes.active = target
    bpy.context.view_layer.objects.active = plane
    plane.select_set(True)
    bpy.ops.object.bake(type="EMIT", margin=0, use_clear=True)
    pixels = np.empty(spec.size * spec.size * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    bpy.data.images.remove(image)
    return pixels.reshape(spec.size, spec.size, 4).astype(np.float64)


def _plane(material) -> bpy.types.Object:
    """The square the material is baked on, made once: UVs 0 to 1 across it."""
    plane = bpy.data.objects.get("KilnBakePlane")
    if plane is not None:
        return plane
    mesh = bpy.data.meshes.new("KilnBakePlane")
    corners = [(0, 0), (1, 0), (1, 1), (0, 1)]
    mesh.from_pydata([(x, y, 0) for x, y in corners], [], [(0, 1, 2, 3)])
    uv = mesh.uv_layers.new(name="UVMap")
    for loop in mesh.loops:
        uv.data[loop.index].uv = corners[loop.vertex_index]
    mesh.materials.append(material)
    plane = bpy.data.objects.new("KilnBakePlane", mesh)
    bpy.context.scene.collection.objects.link(plane)
    return plane


def _to_srgb(linear: np.ndarray) -> np.ndarray:
    linear = np.clip(linear, 0.0, 1.0)
    return np.where(linear <= 0.0031308, linear * 12.92, 1.055 * np.power(linear, 1 / 2.4) - 0.055)


def _write_png(path: str, pixels: np.ndarray, bit_depth: int) -> None:
    """Writes 0-1 pixels (rows bottom to top) as a PNG, top row first."""
    top_first = np.clip(pixels[::-1], 0.0, 1.0)
    if bit_depth == 16:
        data = np.round(top_first * 65535).astype(">u2").tobytes()
    else:
        data = np.round(top_first * 255).astype(np.uint8).tobytes()
    height, width, channels = top_first.shape
    png.write(path, data, width, height, channels, bit_depth)


def _preview(path: str, maps: list[np.ndarray]) -> None:
    """Each map tiled 2x2 (so a seam would show as a cross), two to a row, in one PNG."""
    tiles = []
    for pixels in maps:
        size = pixels.shape[0]
        step = max(size * 2 // PREVIEW_TILE, 1)
        tiled = np.tile(pixels[::-1], (2, 2, 1))[::step, ::step]
        if tiled.shape[2] == 1:
            tiled = np.repeat(tiled, 3, axis=2)
        tiles.append(tiled)
    rows = []
    for start in range(0, len(tiles), 2):
        row = tiles[start:start + 2]
        while len(row) < 2:
            row.append(np.full_like(tiles[0], 0.85))
        rows.append(np.concatenate([row[0], np.full((row[0].shape[0], 8, 3), 0.85), row[1]], axis=1))
    sheet = np.concatenate([np.concatenate([r, np.full((8, r.shape[1], 3), 0.85)], axis=0) for r in rows], axis=0)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # The sheet is top row first; _write_png takes rows bottom first.
    _write_png(path, sheet[::-1], 8)
