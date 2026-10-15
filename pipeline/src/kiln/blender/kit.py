"""`Kit`, what a recipe's build function gets: makes objects, materials and markers.

Every position, size and rotation is in game space (metres, +Y up, -Z forward). Objects are
placed in the world; giving a `parent` keeps them where they are and makes them move with it
in the game (as a handlebar's meshes move with the `Handlebar` marker).
"""
from __future__ import annotations

import math
from typing import Sequence

import bpy
from mathutils import Matrix

from kiln import geometry
from kiln.blender.space import rotation_to_blender, to_blender


def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def parse_color(color) -> tuple[float, float, float, float]:
    """A colour as linear RGBA from "#rrggbb", "#rrggbbaa" or an sRGB (r, g, b[, a]) tuple of
    0-1 floats."""
    if isinstance(color, str):
        text = color.lstrip("#")
        if len(text) not in (6, 8):
            raise ValueError(f"colour {color!r} isn't #rrggbb or #rrggbbaa")
        values = [int(text[i:i + 2], 16) / 255 for i in range(0, len(text), 2)]
    else:
        values = list(color)
    rgb = [srgb_to_linear(c) for c in values[:3]]
    return (*rgb, values[3] if len(values) > 3 else 1.0)


class Kit:
    """Builds a model into the current Blender scene."""

    def __init__(self) -> None:
        self.collection = bpy.context.scene.collection
        self._materials: dict[str, bpy.types.Material] = {}

    # --- Materials ---------------------------------------------------------------------

    def material(self, name: str, color, roughness: float = 0.5, metallic: float = 0.0) -> bpy.types.Material:
        """A material with a flat colour, made once per name. In the game it imports as a
        StandardMaterial3D with that colour, roughness and metallic."""
        if name in self._materials:
            return self._materials[name]
        material = bpy.data.materials.new(name)
        material.use_nodes = True
        bsdf = material.node_tree.nodes["Principled BSDF"]
        rgba = parse_color(color)
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
        material.diffuse_color = rgba  # what the preview sheet shows
        self._materials[name] = material
        return material

    # --- Meshes ------------------------------------------------------------------------

    def mesh(self, name: str, mesh: geometry.Mesh, material=None, parent=None,
             smooth_angle: float | None = None, position: Sequence[float] = (0, 0, 0)) -> bpy.types.Object:
        """An object from a `kiln.geometry.Mesh`, its origin at `position` (the mesh's
        vertices are relative to it). `material` is one material, or a list with one per
        material slot of the mesh. With `smooth_angle` (degrees) its shading is smooth across
        edges whose faces meet at less than that angle, sharp elsewhere."""
        data = bpy.data.meshes.new(name)
        data.from_pydata([tuple(to_blender(v)) for v in mesh.vertices], [], [list(f) for f in mesh.faces])
        if mesh.materials is not None:
            data.polygons.foreach_set("material_index", mesh.materials)
        data.validate()
        if smooth_angle is not None:
            data.shade_smooth()
            data.set_sharp_from_angle(angle=math.radians(smooth_angle))
        for slot_material in (material if isinstance(material, (list, tuple)) else [material]):
            if slot_material is not None:
                data.materials.append(slot_material)
        obj = bpy.data.objects.new(name, data)
        obj.location = to_blender(position)
        self.collection.objects.link(obj)
        if parent is not None:
            self.parent(obj, parent)
        return obj

    def box(self, name: str, size: Sequence[float], center: Sequence[float] = (0, 0, 0),
            bevel: float = 0.0, bevel_segments: int = 2, material=None, parent=None) -> bpy.types.Object:
        """A box with its origin at `center`, its edges rounded off by `bevel` metres."""
        obj = self.mesh(name, geometry.box(tuple(size)), material, parent, position=center)
        if bevel > 0:
            self.bevel(obj, bevel, bevel_segments)
        return obj

    def loft(self, name: str, sections, caps: bool = True, material=None, parent=None,
             smooth_angle: float | None = 35.0, bands=None, cap_slot: int = 0) -> bpy.types.Object:
        """A surface through rings of points (see `kiln.geometry.loft`); with `bands`,
        `material` is a list with one material per slot."""
        return self.mesh(name, geometry.loft(sections, caps, bands, cap_slot), material, parent, smooth_angle)

    def lathe(self, name: str, profile, segments: int = 16, material=None, parent=None,
              smooth_angle: float | None = 35.0) -> bpy.types.Object:
        """A solid of revolution about the Y axis (see `kiln.geometry.lathe`)."""
        return self.mesh(name, geometry.lathe(profile, segments), material, parent, smooth_angle)

    def bevel(self, obj: bpy.types.Object, width: float, segments: int = 2, angle: float = 30.0) -> None:
        """Rounds off `obj`'s edges sharper than `angle` degrees, `width` metres wide, and
        keeps the result as the object's mesh."""
        modifier = obj.modifiers.new("Bevel", "BEVEL")
        modifier.width = width
        modifier.segments = segments
        modifier.limit_method = "ANGLE"
        modifier.angle_limit = math.radians(angle)
        modifier.harden_normals = False
        self.apply_modifiers(obj)

    def apply_modifiers(self, obj: bpy.types.Object) -> None:
        """Makes `obj`'s modifiers part of its mesh."""
        depsgraph = bpy.context.evaluated_depsgraph_get()
        evaluated = obj.evaluated_get(depsgraph)
        mesh = bpy.data.meshes.new_from_object(evaluated)
        old = obj.data
        obj.modifiers.clear()
        obj.data = mesh
        bpy.data.meshes.remove(old)
        mesh.name = obj.name

    # --- Markers and hierarchy ---------------------------------------------------------

    def marker(self, name: str, position: Sequence[float], rotation: Sequence[float] = (0, 0, 0),
               parent=None) -> bpy.types.Object:
        """A named point the game finds by name (an empty, imported as a Node3D). `rotation`
        is in degrees, applied as Godot does (Z, then X, then Y)."""
        empty = bpy.data.objects.new(name, None)
        empty.empty_display_type = "ARROWS"
        empty.empty_display_size = 0.1
        empty.matrix_world = Matrix.Translation(to_blender(position)) @ rotation_to_blender(rotation).to_4x4()
        self.collection.objects.link(empty)
        if parent is not None:
            self.parent(empty, parent)
        return empty

    def parent(self, child: bpy.types.Object, parent: bpy.types.Object) -> None:
        """Makes `child` move with `parent`, keeping it where it is now."""
        # The child's own transform holds the offset from the parent (no parent inverse), so
        # the game sees the same transforms Blender shows.
        bpy.context.view_layer.update()  # brings parent.matrix_world up to date
        child.parent = parent
        child.matrix_parent_inverse = Matrix.Identity(4)
        child.matrix_basis = parent.matrix_world.inverted() @ child.matrix_basis
