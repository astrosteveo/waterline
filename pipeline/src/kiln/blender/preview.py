"""The preview sheet: the model from the front, side, top and three-quarter view, in one PNG.

Rendered with Blender's Workbench engine in each material's colour, with markers drawn as
small magenta diamonds so their placement shows. Run it after export: it adds a camera and
the marker diamonds to the scene.
"""
from __future__ import annotations

import os
import tempfile

import bpy
import numpy as np
from mathutils import Vector

from kiln.blender.space import to_blender

VIEW_SIZE = 512
BACKGROUND = (0.82, 0.84, 0.87)
MARKER_COLOR = (1.0, 0.1, 0.9, 1.0)

# Each view: where the camera looks from, in game space (a direction from the model), and
# whether it is orthographic. "front" looks at the model's front, which faces -Z.
VIEWS = (
    ("front", (0.0, 0.0, -1.0), True),
    ("side", (1.0, 0.0, 0.0), True),
    ("top", (0.0, 1.0, 0.0), True),
    ("three-quarter", (0.8, 0.55, -1.0), False),
)


def render_sheet(path: str, bounds) -> None:
    """Renders the views and saves them as a 2×2 sheet at `path`. `bounds` is the model's
    game-space bounding box (lowest corner, highest corner)."""
    scene = bpy.context.scene
    low, high = Vector(to_blender(bounds[0])), Vector(to_blender(bounds[1]))
    centre = (low + high) / 2
    extent = max((high - low).length, 0.01)
    _add_marker_diamonds(extent)
    _set_up_render(scene)
    camera = bpy.data.objects.new("KilnPreviewCamera", bpy.data.cameras.new("KilnPreviewCamera"))
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera.data.clip_end = extent * 20
    tiles = []
    with tempfile.TemporaryDirectory() as folder:
        for name, direction, ortho in VIEWS:
            offset = to_blender(direction).normalized()
            camera.location = centre + offset * extent * 3
            camera.rotation_euler = (-offset).to_track_quat("-Z", "Y" if abs(offset.z) < 0.99 else "Z").to_euler()
            if abs(offset.z) >= 0.99:
                # Top view: game -Z (forward) points up the image.
                camera.rotation_euler = (0, 0, 0)
            camera.data.type = "ORTHO" if ortho else "PERSP"
            camera.data.ortho_scale = extent * 1.15
            camera.data.lens = 50
            camera.data.sensor_width = 36
            if not ortho:
                camera.location = centre + offset * extent * 1.9
            frame = os.path.join(folder, name + ".png")
            scene.render.filepath = frame
            bpy.ops.render.render(write_still=True)
            tiles.append(_load_rgba(frame))
    _save_sheet(path, tiles)


def _set_up_render(scene) -> None:
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = scene.render.resolution_y = VIEW_SIZE
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"  # the materials' own colours
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "MATERIAL"
    shading.show_cavity = True
    shading.cavity_type = "WORLD"
    shading.show_object_outline = True
    scene.display.render_aa = "8"


def _add_marker_diamonds(extent: float) -> None:
    """A small magenta diamond at every empty, so markers show in the renders."""
    material = bpy.data.materials.new("KilnMarker")
    material.diffuse_color = MARKER_COLOR
    radius = max(extent * 0.015, 0.01)
    for empty in [o for o in bpy.context.scene.objects if o.type == "EMPTY"]:
        mesh = bpy.data.meshes.new("KilnMarkerDiamond")
        r = radius
        verts = [(r, 0, 0), (-r, 0, 0), (0, r, 0), (0, -r, 0), (0, 0, r), (0, 0, -r)]
        faces = [(0, 2, 4), (2, 1, 4), (1, 3, 4), (3, 0, 4), (2, 0, 5), (1, 2, 5), (3, 1, 5), (0, 3, 5)]
        mesh.from_pydata(verts, [], faces)
        mesh.materials.append(material)
        diamond = bpy.data.objects.new("KilnMarkerDiamond", mesh)
        diamond.location = empty.matrix_world.translation
        bpy.context.scene.collection.objects.link(diamond)


def _load_rgba(path: str) -> np.ndarray:
    image = bpy.data.images.load(path)
    width, height = image.size
    pixels = np.empty(width * height * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    bpy.data.images.remove(image)
    return pixels.reshape(height, width, 4)


def _save_sheet(path: str, tiles: list[np.ndarray]) -> None:
    """Puts the tiles on the background colour, 2×2, and saves a PNG. Blender's image rows
    run bottom to top, so the first tile goes in the top-left by filling from the top."""
    h, w = tiles[0].shape[:2]
    sheet = np.ones((h * 2, w * 2, 4), dtype=np.float32)
    sheet[:, :, :3] = BACKGROUND
    for index, tile in enumerate(tiles):
        row, col = divmod(index, 2)
        y0 = (1 - row) * h
        alpha = tile[:, :, 3:4]
        region = sheet[y0:y0 + h, col * w:(col + 1) * w, :3]
        sheet[y0:y0 + h, col * w:(col + 1) * w, :3] = tile[:, :, :3] * alpha + region * (1 - alpha)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image = bpy.data.images.new("KilnPreviewSheet", w * 2, h * 2, alpha=False)
    image.pixels.foreach_set(sheet.ravel())
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)
