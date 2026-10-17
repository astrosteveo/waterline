"""The preview sheet: the model from the front, side, top and three-quarter view, in one PNG.

Rendered with Blender's Workbench engine, with markers drawn as small magenta diamonds so
their placement shows. The first two rows draw each material as the game will where the
project says how ([preview.materials] in kiln.toml): in a texture it builds, or in the
colour the game paints it; elsewhere in its own colour. When the model has UVs, a third row
shows it from the front and the back three-quarters in a checker, so stretched or squashed
UVs show: squares about a sixteenth of the model across, red rising along u and green along
v. The last row shows its triangles, as the game gets them, over the model in grey.

Each animation clip (`kiln.blender.kit.Kit.clip`) gets a filmstrip of its own beside the
sheet, `clip-<name>.png`: the three-quarter view at eight moments through it, four to a row.

`compare_sheets` puts a sheet beside the one before it, for a rebuild's changes. Run
`render_sheet` after export: it adds a camera and the marker diamonds to the scene, changes
the materials and rescales the UVs.
"""
from __future__ import annotations

import os
import tempfile

import bpy
import numpy as np
from mathutils import Vector

from kiln.blender.kit import CLIP_FPS, parse_color
from kiln.blender.space import to_blender

VIEW_SIZE = 512
BACKGROUND = (0.82, 0.84, 0.87)
MARKER_COLOR = (1.0, 0.1, 0.9, 1.0)
WIRE_COLOR = (0.06, 0.07, 0.1, 1.0)
WIRE_GROUND = (0.78, 0.78, 0.78, 1.0)

# Each view: where the camera looks from, in game space (a direction from the model), and
# whether it is orthographic. "front" looks at the model's front, which faces -Z.
VIEWS = (
    ("front", (0.0, 0.0, -1.0), True),
    ("side", (1.0, 0.0, 0.0), True),
    ("top", (0.0, 1.0, 0.0), True),
    ("three-quarter", (0.8, 0.55, -1.0), False),
)
CHECKER_VIEWS = (
    ("checker-front", (0.8, 0.55, -1.0), False),
    ("checker-back", (-0.8, 0.55, 1.0), False),
)
WIRE_VIEWS = (
    ("wire-front", (0.8, 0.55, -1.0), False),
    ("wire-back", (-0.8, 0.55, 1.0), False),
)
# The checker: this many squares a side to each UV unit, and that many units across the model.
CHECKER_SQUARES = 8
CHECKER_ACROSS = 2.0
# The wireframe's lines, as a share of the model's size.
WIRE_WIDTH = 0.0015
# A sheet's pixels that differ from the last by more than this (0 to 1) count as changed.
CHANGED = 2 / 255
# A clip's filmstrip: this many moments, four to a row, each this many pixels a side.
FILMSTRIP_FRAMES = 8
FILMSTRIP_SIZE = 256


def render_sheet(path: str, bounds, materials: list[dict] = (), clips: list[dict] = ()) -> dict[str, str]:
    """Renders the views and saves them as a sheet, two to a row, at `path`. `bounds` is the
    model's game-space bounding box (lowest corner, highest corner). `materials` says how to
    draw materials the game textures or paints: each {"name", "prefix", "color", "albedo",
    "tile"} (see `kiln.cli.preview_materials`). Returns each of `clips`' filmstrip, by name."""
    scene = bpy.context.scene
    low, high = Vector(to_blender(bounds[0])), Vector(to_blender(bounds[1]))
    centre = (low + high) / 2
    extent = max((high - low).length, 0.01)
    meshes = [o for o in scene.objects if o.type == "MESH"]
    _add_marker_diamonds(extent)
    _set_up_render(scene)
    camera = bpy.data.objects.new("KilnPreviewCamera", bpy.data.cameras.new("KilnPreviewCamera"))
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera.data.clip_end = extent * 20
    has_uvs = any(o.data.uv_layers for o in meshes)
    saved = _uvs(meshes)
    tiles_by_material = _dress_as_the_game(materials)
    if has_uvs:
        _scale_uvs_by_material(meshes, tiles_by_material)
    tiles = _render_views(scene, camera, VIEWS, centre, extent)
    strips = {clip["name"]: _filmstrip(scene, camera, clip, centre, extent,
                                       os.path.join(os.path.dirname(path), f"clip-{clip['name']}.png"))
              for clip in clips}
    _restore_uvs(meshes, saved)
    if has_uvs:
        _dress_in_checker(extent)
        tiles += _render_views(scene, camera, CHECKER_VIEWS, centre, extent)
    _add_wireframes(meshes, extent)
    scene.display.shading.color_type = "MATERIAL"
    tiles += _render_views(scene, camera, WIRE_VIEWS, centre, extent)
    _save_sheet(path, tiles)
    return strips


def _filmstrip(scene, camera, clip: dict, centre, extent, path: str) -> str:
    """Renders `clip` from the three-quarter view at FILMSTRIP_FRAMES moments through it
    (from its start to its end, or just short of it for a loop, whose end is its start) and
    saves them four to a row at `path`."""
    moved = [obj for obj in scene.objects if obj.animation_data
             and any(track.name == clip["action"].name for track in obj.animation_data.nla_tracks)]
    tracks = [track for obj in moved for track in obj.animation_data.nla_tracks if track.name == clip["action"].name]
    # A muted track stops moving what it moved but doesn't put it back: keep the model as
    # built to put back after.
    built = {obj.name: (obj.matrix_basis.copy(), [b.matrix_basis.copy() for b in obj.pose.bones] if obj.pose else [])
             for obj in moved}
    for track in tracks:
        track.mute = False
    scene.render.resolution_x = scene.render.resolution_y = FILMSTRIP_SIZE
    steps = FILMSTRIP_FRAMES if clip["loop"] else FILMSTRIP_FRAMES - 1
    frames = []
    for i in range(FILMSTRIP_FRAMES):
        scene.frame_set(round(clip["seconds"] * i / steps * CLIP_FPS))
        frames += _render_views(scene, camera, (VIEWS[3],), centre, extent)
    for track in tracks:
        track.mute = True
    scene.frame_set(0)
    for obj in moved:
        obj.matrix_basis, bones = built[obj.name]
        for pose_bone, matrix in zip(obj.pose.bones if obj.pose else [], bones):
            pose_bone.matrix_basis = matrix
    bpy.context.view_layer.update()
    scene.render.resolution_x = scene.render.resolution_y = VIEW_SIZE
    _save_sheet(path, frames, columns=4)
    return path


def compare_sheets(before: str, after: str, out: str) -> dict | None:
    """Saves `before` and `after` (two sheets) side by side at `out`, with a third image
    marking where they differ, half size. Returns {"path", "share"} (the share of pixels that
    changed), or None, removing an old `out`, when they are the same."""
    old, new = _load_rgba(before)[:, :, :3], _load_rgba(after)[:, :, :3]
    height, width = max(old.shape[0], new.shape[0]), max(old.shape[1], new.shape[1])
    old, new = _padded(old, height, width), _padded(new, height, width)
    changed = np.abs(old - new).max(axis=2) > CHANGED
    share = float(changed.mean())
    if share == 0.0:
        if os.path.isfile(out):
            os.remove(out)
        return None
    # The new sheet, dimmed, with the changed pixels in red.
    marked = new * 0.35 + 0.15
    marked[changed] = (0.95, 0.15, 0.1)
    gap = np.full((height, 16, 3), BACKGROUND)
    picture = np.concatenate([old, gap, new, gap, marked], axis=1)[::2, ::2]
    _save_image(out, picture)
    return {"path": out, "share": round(share, 5)}


def _render_views(scene, camera, views, centre, extent) -> list[np.ndarray]:
    tiles = []
    with tempfile.TemporaryDirectory() as folder:
        for name, direction, ortho in views:
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
    return tiles


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
    # A material's active image texture where it has one, its colour where it hasn't.
    shading.color_type = "TEXTURE"
    shading.show_cavity = True
    shading.cavity_type = "WORLD"
    shading.show_object_outline = True
    scene.display.render_aa = "8"


def _dress_as_the_game(rules) -> dict[str, float]:
    """Draws each material a rule names as the game will: in the rule's texture (its albedo
    map, the material's active image), or its colour times the material's own. Returns the
    textured materials' tiles, in metres, by name."""
    tiles: dict[str, float] = {}
    for material in bpy.data.materials:
        rule = next((r for r in rules if material.name == r["name"]
                     or (r["prefix"] and material.name.startswith(r["name"]))), None)
        if rule is None:
            continue
        if rule.get("color"):
            paint = parse_color(rule["color"])
            own = material.diffuse_color
            material.diffuse_color = (own[0] * paint[0], own[1] * paint[1], own[2] * paint[2], own[3])
        if rule.get("albedo") and material.node_tree is not None:
            node = material.node_tree.nodes.new("ShaderNodeTexImage")
            node.image = bpy.data.images.load(rule["albedo"], check_existing=True)
            material.node_tree.nodes.active = node
            tiles[material.name] = rule["tile"]
            if rule.get("color"):
                # Workbench draws the texture alone; tint the image itself.
                node.image = _tinted(node.image, parse_color(rule["color"]))
    return tiles


def _tinted(image, color) -> bpy.types.Image:
    """A copy of `image` times `color` (linear)."""
    width, height = image.size
    pixels = np.empty(width * height * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    pixels = pixels.reshape(height, width, 4)
    tint = bpy.data.images.new(image.name + "Tinted", width, height, alpha=False)
    # The image's pixels are as stored (sRGB); a linear tint works on them as a gamma 2.2 one.
    pixels[:, :, :3] *= np.array(color[:3]) ** (1 / 2.2)
    tint.pixels.foreach_set(pixels.ravel())
    return tint


def _uvs(meshes) -> dict:
    """Each mesh's UVs, to put back after they are scaled."""
    saved = {}
    for obj in meshes:
        if obj.data.uv_layers:
            uv = obj.data.uv_layers.active.data
            values = np.empty(len(uv) * 2, dtype=np.float32)
            uv.foreach_get("uv", values)
            saved[obj.name] = values
    return saved


def _restore_uvs(meshes, saved: dict) -> None:
    for obj in meshes:
        if obj.name in saved:
            obj.data.uv_layers.active.data.foreach_set("uv", saved[obj.name])


def _scale_uvs_by_material(meshes, tiles: dict[str, float]) -> None:
    """Scales each textured face's UVs (in metres) by its texture's tile, so a texture spans
    as many metres as in the game: Workbench reads an image straight from the UVs."""
    if not tiles:
        return
    for obj in meshes:
        data = obj.data
        if not data.uv_layers:
            continue
        uv = data.uv_layers.active.data
        for polygon in data.polygons:
            slot = obj.material_slots[polygon.material_index] if polygon.material_index < len(obj.material_slots) else None
            tile = tiles.get(slot.material.name) if slot is not None and slot.material is not None else None
            if tile:
                for i in range(polygon.loop_start, polygon.loop_start + polygon.loop_total):
                    uv[i].uv = uv[i].uv / tile


def _add_wireframes(meshes, extent: float) -> None:
    """Grey for every material, and over each mesh a copy of its triangles as thin dark
    lines, for the wireframe views."""
    for material in bpy.data.materials:
        if material.name != "KilnMarker":
            material.diffuse_color = WIRE_GROUND
    wire = bpy.data.materials.new("KilnWire")
    wire.diffuse_color = WIRE_COLOR
    for obj in meshes:
        copy = obj.copy()
        copy.data = obj.data.copy()
        copy.data.materials.clear()
        copy.data.materials.append(wire)
        copy.modifiers.new("Triangles", "TRIANGULATE")
        lines = copy.modifiers.new("Lines", "WIREFRAME")
        lines.thickness = extent * WIRE_WIDTH
        lines.use_replace = True
        lines.use_even_offset = True
        bpy.context.scene.collection.objects.link(copy)


def _dress_in_checker(extent: float) -> None:
    """Draws every material in the checker and scales every mesh's UVs (in metres) so the
    model is CHECKER_ACROSS units across."""
    squares = np.indices((CHECKER_SQUARES, CHECKER_SQUARES))
    shade = np.where((squares[0] + squares[1]) % 2 == 0, 0.35, 0.85)
    # Rows run up the image (v) and columns along it (u).
    pixels = np.stack([shade * (0.55 + 0.45 * squares[1] / (CHECKER_SQUARES - 1)),
                       shade * (0.55 + 0.45 * squares[0] / (CHECKER_SQUARES - 1)),
                       shade * 0.7, np.ones_like(shade)], axis=-1)
    image = bpy.data.images.new("KilnChecker", CHECKER_SQUARES, CHECKER_SQUARES, alpha=False)
    image.pixels.foreach_set(pixels.astype(np.float32).ravel())
    for material in bpy.data.materials:
        if material.node_tree is None:
            continue
        node = material.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = image
        node.interpolation = "Closest"
        material.node_tree.nodes.active = node
    factor = CHECKER_ACROSS / extent
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH" and obj.data.uv_layers:
            for loop in obj.data.uv_layers.active.data:
                loop.uv = loop.uv * factor


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


def _padded(pixels: np.ndarray, height: int, width: int) -> np.ndarray:
    """`pixels` (rows bottom to top) on the background, `width` by `height`, kept at the top."""
    out = np.empty((height, width, 3), dtype=np.float32)
    out[:, :] = BACKGROUND
    out[height - pixels.shape[0]:, :pixels.shape[1]] = pixels
    return out


def _save_sheet(path: str, tiles: list[np.ndarray], columns: int = 2) -> None:
    """Puts the tiles on the background colour, `columns` to a row, and saves a PNG.
    Blender's image rows run bottom to top, so the first tile goes in the top-left by filling
    from the top."""
    h, w = tiles[0].shape[:2]
    rows = (len(tiles) + columns - 1) // columns
    sheet = np.ones((h * rows, w * columns, 3), dtype=np.float32)
    sheet[:, :] = BACKGROUND
    for index, tile in enumerate(tiles):
        row, col = divmod(index, columns)
        y0 = (rows - 1 - row) * h
        alpha = tile[:, :, 3:4]
        region = sheet[y0:y0 + h, col * w:(col + 1) * w]
        sheet[y0:y0 + h, col * w:(col + 1) * w] = tile[:, :, :3] * alpha + region * (1 - alpha)
    _save_image(path, sheet)


def _save_image(path: str, pixels: np.ndarray) -> None:
    """Saves RGB `pixels` (rows bottom to top) as a PNG."""
    height, width = pixels.shape[:2]
    rgba = np.ones((height, width, 4), dtype=np.float32)
    rgba[:, :, :3] = pixels
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image = bpy.data.images.new("KilnPreviewSheet", width, height, alpha=False)
    image.pixels.foreach_set(rgba.ravel())
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)
