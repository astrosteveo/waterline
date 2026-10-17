"""`Kit`, what a recipe's build function gets: makes objects, materials and markers.

Every position, size and rotation is in game space (metres, +Y up, -Z forward). Objects are
placed in the world; giving a `parent` keeps them where they are and makes them move with it
in the game (as a handlebar's meshes move with the `Handlebar` marker). Every mesh the kit
makes has UVs, in metres (see `kiln.geometry`).
"""
from __future__ import annotations

import math
from typing import Sequence

import bpy
from mathutils import Matrix, Vector

from kiln import geometry
from kiln.blender.space import rotation_to_blender, to_blender, to_game

# UVs covering less than this (m²) count as none: a texture would smear across the face.
MIN_UV_AREA = 1e-10


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
        # Each material made, by name, with the settings it was made with.
        self._materials: dict[str, tuple[bpy.types.Material, dict]] = {}

    # --- Materials ---------------------------------------------------------------------

    def material(self, name: str, color, roughness: float = 0.5, metallic: float = 0.0,
                 double_sided: bool = False, emission=None, emission_strength: float = 1.0,
                 alpha: float = 1.0) -> bpy.types.Material:
        """A material with a flat colour, made once per name: asked for again with the same
        settings it is the same material, and with others it fails, since the game finds a
        material by its name. In the game it imports as a StandardMaterial3D with that
        colour, roughness and metallic. Only its front faces are drawn, as kiln's meshes are
        closed; `double_sided` draws both, for an open mesh.

        With `emission` (a colour) it glows in that colour, `emission_strength` times as
        bright (a lamp's glass: 2 to 5). With `alpha` below 1 it is see-through, blended over
        what is behind it (glass, a visor)."""
        if not 0.0 < alpha <= 1.0:
            raise ValueError(f"the material {name!r} has alpha {alpha}: give 1 for opaque, down to above 0")
        if emission_strength < 0.0:
            raise ValueError(f"the material {name!r} has a negative emission_strength")
        settings = {"color": color, "roughness": roughness, "metallic": metallic, "double_sided": double_sided,
                    "emission": emission, "emission_strength": emission_strength, "alpha": alpha}
        if name in self._materials:
            made, before = self._materials[name]
            if before != settings:
                changed = ", ".join(f"{key} {before[key]!r}, now {settings[key]!r}"
                                    for key in settings if before[key] != settings[key])
                raise ValueError(f"the material {name!r} was made with other settings ({changed}); "
                                 "give a different material its own name")
            return made
        material = bpy.data.materials.new(name)
        material.use_backface_culling = not double_sided
        bsdf = material.node_tree.nodes["Principled BSDF"]
        rgba = parse_color(color)
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
        if emission is not None:
            # The glTF exporter writes a strength over 1 as KHR_materials_emissive_strength,
            # which Godot imports as the emission's energy.
            bsdf.inputs["Emission Color"].default_value = parse_color(emission)
            bsdf.inputs["Emission Strength"].default_value = emission_strength
        if alpha < 1.0:
            # Exported with glTF's alphaMode BLEND.
            bsdf.inputs["Alpha"].default_value = alpha
            material.surface_render_method = "BLENDED"
        # What the preview sheet shows: a glowing material in its glow, at its alpha.
        rgba = (*parse_color(emission)[:3], 1.0) if emission is not None else rgba
        material.diffuse_color = (*rgba[:3], alpha)
        self._materials[name] = (material, settings)
        return material

    # --- Meshes ------------------------------------------------------------------------

    def mesh(self, name: str, mesh: geometry.Mesh, material=None, parent=None,
             smooth_angle: float | None = None, position: Sequence[float] = (0, 0, 0)) -> bpy.types.Object:
        """An object from a `kiln.geometry.Mesh`, its origin at `position` (the mesh's
        vertices are relative to it). `material` is one material, or a list with one per
        material slot of the mesh. With `smooth_angle` (degrees) its shading is smooth across
        edges whose faces meet at less than that angle, sharp elsewhere. A mesh without UVs
        is given them by `kiln.geometry.Mesh.projected`."""
        data = bpy.data.meshes.new(name)
        data.from_pydata([tuple(to_blender(v)) for v in mesh.vertices], [], [list(f) for f in mesh.faces])
        if mesh.materials is not None:
            data.polygons.foreach_set("material_index", mesh.materials)
        uvs = mesh.uvs if mesh.uvs is not None else mesh.projected().uvs
        # Blender keeps a UV for each corner of each face, in the order the faces list them.
        data.uv_layers.new(name="UVMap").data.foreach_set(
            "uv", [value for face in uvs for corner in face for value in corner])
        data.validate()
        if smooth_angle is not None:
            data.shade_smooth()
            data.set_sharp_from_angle(angle=math.radians(smooth_angle))
        for slot_material in (material if isinstance(material, (list, tuple)) else [material]):
            if slot_material is not None:
                data.materials.append(slot_material)
        obj = self._new_object(name, data)
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
        # A bevel blends the UVs either side of each seam it rounds, adding them in an order
        # that can change from run to run, so the last bit of a float differs. Work them out
        # again from the positions, which come out the same every time.
        self.project_uvs(obj)

    def project_uvs(self, obj: bpy.types.Object) -> None:
        """Gives every face of `obj` UVs projected from the axis it faces most (see
        `kiln.geometry.Mesh.projected`), from its position in the object."""
        mesh = obj.data
        uv = (mesh.uv_layers.active or mesh.uv_layers.new(name="UVMap")).data
        for polygon in mesh.polygons:
            normal = to_game(polygon.normal)
            for i in range(polygon.loop_start, polygon.loop_start + polygon.loop_total):
                uv[i].uv = geometry.projected_uv(to_game(mesh.vertices[mesh.loops[i].vertex_index].co), normal)

    def unwrap(self, obj: bpy.types.Object, angle: float = 66.0) -> None:
        """Gives `obj` (made with `bpy`) new UVs by Blender's Smart UV Project, which cuts its
        surface where faces meet at more than `angle` degrees and lays the pieces flat, then
        scales them so a UV unit is a metre on the model, as on the kit's own meshes."""
        view_layer = bpy.context.view_layer
        for other in view_layer.objects:
            other.select_set(other is obj)
        view_layer.objects.active = obj
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(angle), island_margin=0.0, area_weight=0.0,
                                 correct_aspect=True, scale_to_bounds=False)
        bpy.ops.object.mode_set(mode="OBJECT")
        # Smart UV Project fits the pieces into one square; scale them back to metres, by the
        # ratio of the surface's area (as placed, with the object's scale) to the UVs'.
        mesh = obj.data
        uv = mesh.uv_layers.active.data
        scale = obj.matrix_world.to_3x3()
        surface = sum(_area([scale @ mesh.vertices[mesh.loops[i].vertex_index].co
                             for i in range(p.loop_start, p.loop_start + p.loop_total)]) for p in mesh.polygons)
        flat = sum(uv_area([uv[i].uv for i in range(p.loop_start, p.loop_start + p.loop_total)])
                   for p in mesh.polygons)
        factor = math.sqrt(surface / flat) if flat > 0 else 1.0
        for loop in uv:
            loop.uv = loop.uv * factor

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
        empty = self._new_object(name, None)
        empty.empty_display_type = "ARROWS"
        empty.empty_display_size = 0.1
        empty.matrix_world = Matrix.Translation(to_blender(position)) @ rotation_to_blender(rotation).to_4x4()
        self.collection.objects.link(empty)
        if parent is not None:
            self.parent(empty, parent)
        return empty

    def _new_object(self, name: str, data) -> bpy.types.Object:
        """A new object called `name`. Blender would rename a second object of a name
        (`Seat.001`), and the game finds parts and markers by name, so a taken name fails."""
        if name in bpy.data.objects:
            raise ValueError(f"an object named {name!r} already exists; the game finds parts and markers by "
                             "name, so each needs its own")
        return bpy.data.objects.new(name, data)

    def parent(self, child: bpy.types.Object, parent: bpy.types.Object) -> None:
        """Makes `child` move with `parent`, keeping it where it is now."""
        # The child's own transform holds the offset from the parent (no parent inverse), so
        # the game sees the same transforms Blender shows.
        bpy.context.view_layer.update()  # brings the matrix_world of both up to date
        where = child.matrix_world.copy()
        child.parent = parent
        child.matrix_parent_inverse = Matrix.Identity(4)
        child.matrix_basis = parent.matrix_world.inverted() @ where

    # --- Skeletons ---------------------------------------------------------------------

    def armature(self, name: str, bones: dict) -> bpy.types.Object:
        """A skeleton: a bone for each name in `bones`, from its head to its tail (game-space
        points, as {name: (head, tail)}), none the parent of another. `skin` fixes meshes to
        its bones; the game imports it as a Skeleton3D and moves the meshes by posing it."""
        data = bpy.data.armatures.new(name)
        obj = self._new_object(name, data)
        self.collection.objects.link(obj)
        view_layer = bpy.context.view_layer
        for other in view_layer.objects:
            other.select_set(other is obj)
        view_layer.objects.active = obj
        bpy.ops.object.mode_set(mode="EDIT")
        for bone_name, (head, tail) in bones.items():
            bone = data.edit_bones.new(bone_name)
            bone.head = to_blender(head)
            bone.tail = to_blender(tail)
        bpy.ops.object.mode_set(mode="OBJECT")
        return obj

    def skin(self, obj: bpy.types.Object, armature: bpy.types.Object, weights) -> None:
        """Fixes `obj`'s vertices to `armature`'s bones, so they move as the bones are posed.
        `weights` is a bone's name, for every vertex wholly on that bone, or a function from a
        vertex's game-space position to {bone: weight}; each vertex's weights are scaled to
        add up to 1. `obj` becomes the armature's child, where it is now."""
        bpy.context.view_layer.update()
        world = obj.matrix_world
        groups: dict = {}
        for vertex in obj.data.vertices:
            amounts = {weights: 1.0} if isinstance(weights, str) else weights(to_game(world @ vertex.co))
            total = sum(amount for amount in amounts.values() if amount > 0)
            if total <= 0:
                at = ", ".join(f"{c:.3f}" for c in to_game(world @ vertex.co))
                raise ValueError(f"{obj.name}: the vertex at ({at}) has no weight on any bone")
            for bone, amount in amounts.items():
                if amount <= 0:
                    continue
                if bone not in armature.data.bones:
                    raise ValueError(f"{obj.name}: {armature.name} has no bone {bone!r}")
                if bone not in groups:
                    groups[bone] = obj.vertex_groups.new(name=bone)
                groups[bone].add([vertex.index], amount / total, "REPLACE")
        modifier = obj.modifiers.new("Armature", "ARMATURE")
        modifier.object = armature
        self.parent(obj, armature)


def uv_area(points) -> float:
    """The area a face covers in UV space, from its corners' UVs."""
    return abs(sum(points[i][0] * points[(i + 1) % len(points)][1] - points[(i + 1) % len(points)][0] * points[i][1]
                   for i in range(len(points)))) / 2


def _area(points) -> float:
    """A polygon's area in space, from its corners (mathutils vectors)."""
    total = Vector((0.0, 0.0, 0.0))
    for i in range(len(points)):
        total = total + points[i].cross(points[(i + 1) % len(points)])
    return total.length / 2
