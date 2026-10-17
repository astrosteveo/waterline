"""The checks every model build gets, against its recipe's `ModelSpec`."""
from __future__ import annotations

import bmesh
import bpy
from mathutils.bvhtree import BVHTree

from kiln.blender.kit import MIN_UV_AREA, uv_area
from kiln.blender.space import to_game
from kiln.recipe import ModelSpec

# Faces smaller than this (m²) count as degenerate.
MIN_FACE_AREA = 1e-8


def mesh_objects() -> list[bpy.types.Object]:
    return sorted((o for o in bpy.context.scene.objects if o.type == "MESH"), key=lambda o: o.name)


def measure() -> dict:
    """Triangles, size and markers of everything in the scene, plus per-mesh problems."""
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    triangles = 0
    lows, highs = [float("inf")] * 3, [float("-inf")] * 3
    meshes = {}
    materials: set[str] = set()
    for obj in mesh_objects():
        bm = bmesh.new()
        bm.from_object(obj, depsgraph)
        bm.transform(obj.matrix_world)
        for vert in bm.verts:
            p = to_game(vert.co)
            for axis in range(3):
                lows[axis] = min(lows[axis], p[axis])
                highs[axis] = max(highs[axis], p[axis])
        tris = sum(len(face.verts) - 2 for face in bm.faces)
        triangles += tris
        uv = bm.loops.layers.uv.active
        unweighted = _unweighted_vertices(obj)
        slots = [slot.material.name if slot.material else None for slot in obj.material_slots]
        materials.update(slots[face.material_index] for face in bm.faces if face.material_index < len(slots))
        areas = [face.calc_area() for face in bm.faces]
        uv_areas = [uv_area([loop[uv].uv for loop in face.loops]) for face in bm.faces] if uv else []
        meshes[obj.name] = {
            "triangles": tris,
            "open_edges": sum(1 for edge in bm.edges if len(edge.link_faces) != 2),
            # Edges between two faces that run them the same way: one face is flipped.
            "flipped_edges": sum(1 for edge in bm.edges
                                 if len(edge.link_faces) == 2 and not edge.is_contiguous),
            "volume": round(bm.calc_volume(signed=True), 6),
            "degenerate_faces": sum(1 for area in areas if area < MIN_FACE_AREA),
            "self_intersections": _self_intersections(bm),
            "uvs": uv is not None,
            # Skinned: fixed to an armature's bones. Its vertices whose weights on them don't
            # add up to 1 would be left behind, or pulled toward the origin, when it's posed.
            "skinned": unweighted is not None,
            "unweighted_vertices": unweighted or 0,
            # The surface's area and its UVs' (m²): equal when the UVs are in metres throughout.
            "area": round(sum(areas), 6),
            "uv_area": round(sum(uv_areas), 6),
            # Faces with area whose UVs have none: a texture would smear across them.
            "flat_uv_faces": sum(1 for area, flat in zip(areas, uv_areas)
                                 if area >= MIN_FACE_AREA and flat < MIN_UV_AREA),
        }
        bm.free()
    size = [round(highs[i] - lows[i], 5) if highs[i] >= lows[i] else 0.0 for i in range(3)]
    return {
        "triangles": triangles,
        "size": size,
        "bounds": [[round(v, 5) for v in lows], [round(v, 5) for v in highs]] if meshes else None,
        "objects": sorted(o.name for o in bpy.context.scene.objects),
        # The materials on at least one face, and the bones of every armature.
        "materials": sorted(name for name in materials if name),
        "bones": sorted(bone.name for o in bpy.context.scene.objects if o.type == "ARMATURE" for bone in o.data.bones),
        "meshes": meshes,
    }


def _unweighted_vertices(obj: bpy.types.Object) -> int | None:
    """How many of `obj`'s vertices don't have weights adding up to 1 on the bones of the
    armature it is skinned to, or None if it isn't skinned."""
    armatures = [m.object for m in obj.modifiers if m.type == "ARMATURE" and m.object is not None]
    if not armatures:
        return None
    bones = {bone.name for armature in armatures for bone in armature.data.bones}
    deform = {group.index for group in obj.vertex_groups if group.name in bones}
    return sum(1 for vertex in obj.data.vertices
               if abs(sum(g.weight for g in vertex.groups if g.group in deform) - 1.0) > 1e-3)


def _self_intersections(bm: bmesh.types.BMesh) -> int:
    """Pairs of faces of one connected part (faces joined through shared vertices) that cut
    through each other. Separate parts may overlap: recipes merge parts into one mesh to
    draw them at once, a box sunk into another. The tree also reports faces that only meet
    at a shared vertex or edge (a flat fan round a pole), so those pairs don't count."""
    tree = BVHTree.FromBMesh(bm)
    bm.faces.ensure_lookup_table()
    part = _connected_parts(bm)
    count = 0
    for a, b in tree.overlap(tree):
        if part[a] != part[b]:
            continue
        shared = {v.index for v in bm.faces[a].verts} & {v.index for v in bm.faces[b].verts}
        if not shared:
            count += 1
    return count


def _connected_parts(bm: bmesh.types.BMesh) -> list[int]:
    """For each face, a number shared by the faces of its connected part."""
    bm.verts.ensure_lookup_table()
    root = list(range(len(bm.verts)))

    def find(i: int) -> int:
        while root[i] != i:
            root[i] = root[root[i]]
            i = root[i]
        return i

    for face in bm.faces:
        first = find(face.verts[0].index)
        for vert in face.verts[1:]:
            root[find(vert.index)] = first
    return [find(face.verts[0].index) for face in bm.faces]


def problems(spec: ModelSpec, measured: dict) -> list[str]:
    """Each way the build breaks its spec, as a sentence. Empty when it passes."""
    found = []
    if not measured["meshes"]:
        found.append("the recipe made no meshes")
    if spec.max_triangles is not None and measured["triangles"] > spec.max_triangles:
        found.append(f"{measured['triangles']} triangles, over the budget of {spec.max_triangles}")
    if spec.size is not None:
        for axis, want, got in zip("xyz", spec.size, measured["size"]):
            if want is not None and abs(got - want) > spec.size_tolerance * want:
                found.append(f"{axis} size {got:.3f} m, expected {want:.3f} m "
                             f"(within {spec.size_tolerance:.0%})")
    for name in spec.markers:
        if name not in measured["objects"]:
            found.append(f"no marker named {name}")
    for name in spec.materials:
        if name not in measured["materials"]:
            found.append(f"no face has the material {name}")
    for name in spec.bones:
        if name not in measured["bones"]:
            found.append(f"no bone named {name}")
    for name in sorted(set(measured["bones"]) & set(measured["objects"])):
        found.append(f"the bone {name} has an object's name: glTF makes a node of each, and an importer "
                     "renames one of two nodes with one name")
    for name, mesh in measured["meshes"].items():
        if spec.closed and mesh["open_edges"]:
            found.append(f"{name}: {mesh['open_edges']} edges not shared by exactly two faces "
                         "(holes or non-manifold edges)")
        if mesh["flipped_edges"]:
            found.append(f"{name}: faces turned against their neighbours at {mesh['flipped_edges']} edges")
        elif spec.closed and not mesh["open_edges"] and mesh["volume"] < 0:
            found.append(f"{name}: inside out (its faces point inward)")
        if mesh["degenerate_faces"]:
            found.append(f"{name}: {mesh['degenerate_faces']} faces with no area")
        if mesh["unweighted_vertices"]:
            found.append(f"{name}: {mesh['unweighted_vertices']} vertices whose weights on the bones don't add up to 1")
        if mesh["flat_uv_faces"]:
            found.append(f"{name}: {mesh['flat_uv_faces']} faces whose UVs cover no area (a texture would smear "
                         "across them)")
        if not spec.allow_self_intersections and mesh["self_intersections"]:
            found.append(f"{name}: {mesh['self_intersections']} pairs of faces cut through each other")
    return found
