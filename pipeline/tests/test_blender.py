"""Builds in real Blender. Skipped when Blender isn't installed."""
import json
import math
import shutil
import struct
from pathlib import Path

import pytest

from kiln import cli, png

BLENDER = shutil.which("blender")
EXAMPLES = Path(__file__).resolve().parents[1] / "examples" / "basics"

pytestmark = pytest.mark.skipif(BLENDER is None, reason="Blender isn't installed")

# Recipes that break their spec, each in a way a check must catch.
BROKEN = {
    "open": '''
from kiln import model, geometry
@model()
def build(k):
    k.loft("Tube", [geometry.ring([(0, 0), (1, 0), (1, 1), (0, 1)], 0),
                    geometry.ring([(0, 0), (1, 0), (1, 1), (0, 1)], -1)], caps=False)
''',
    "flipped": '''
from kiln import model, geometry
@model()
def build(k):
    box = geometry.box((1, 1, 1))
    faces = list(box.faces)
    faces[0] = tuple(reversed(faces[0]))
    k.mesh("Box", geometry.Mesh(box.vertices, tuple(faces)))
''',
    "inside_out": '''
from kiln import model, geometry
@model()
def build(k):
    k.mesh("Box", geometry.box((1, 1, 1)).flipped())
''',
    "over_budget": '''
from kiln import model
@model(max_triangles=10, size=(2, 1, 1), markers=["Seat"], materials=["Paint", "Unused"])
def build(k):
    k.box("Box", (1, 1, 1), material=k.material("Paint", "#ffffff"))
    k.material("Unused", "#000000")
''',
    "crossed": '''
from kiln import model, geometry
@model()
def build(k):
    # A box with one corner pulled through the far side, and two boxes merged into one mesh
    # that overlap: only the first cuts through itself.
    box = geometry.box((1, 1, 1))
    vertices = list(box.vertices)
    vertices[7] = (-0.9, 0.0, 0.0)
    k.mesh("Folded", geometry.Mesh(tuple(vertices), box.faces))
    k.mesh("Two", geometry.box((1, 1, 1)).merged(geometry.box((1, 1, 1), center=(0.5, 0.2, 0.1))), position=(3, 0, 0))
''',
    "flat_uvs": '''
from kiln import model, geometry
@model()
def build(k):
    box = geometry.box((1, 1, 1))
    k.mesh("Box", geometry.Mesh(box.vertices, box.faces, uvs=tuple(((0, 0),) * 4 for _ in box.faces)))
''',
    "same_name": '''
from kiln import model
@model()
def build(k):
    k.box("Seat", (1, 1, 1))
    k.marker("Seat", (0, 1, 0))
''',
    "no_weight": '''
from kiln import model, geometry
@model()
def build(k):
    bones = k.armature("Skeleton", {"Arm": ((0, 0, 0), (0, 1, 0))})
    k.skin(k.mesh("Box", geometry.box((1, 1, 1))), bones, lambda p: {"Arm": 1.0} if p[1] > 0 else {})
''',
    "half_weighted": '''
from kiln import model, geometry
@model(bones=["Arm", "Leg"])
def build(k):
    bones = k.armature("Skeleton", {"Arm": ((0, 0, 0), (0, 1, 0)), "Box": ((0, 0, 0), (1, 0, 0))})
    box = k.mesh("Box", geometry.box((1, 1, 1)))
    box.vertex_groups.new(name="Arm").add([0, 1, 2, 3], 1.0, "REPLACE")
    box.modifiers.new("Armature", "ARMATURE").object = bones
''',
    "two_paints": '''
from kiln import model
@model()
def build(k):
    k.box("Hull", (1, 1, 1), material=k.material("Paint", "#ff0000", roughness=0.4))
    k.box("Hood", (1, 1, 1), center=(2, 0, 0), material=k.material("Paint", "#ff0000", roughness=0.4))
    k.box("Deck", (1, 1, 1), center=(4, 0, 0), material=k.material("Paint", "#0000ff", roughness=0.4))
''',
    "clear": '''
from kiln import model
@model()
def build(k):
    k.box("Box", (1, 1, 1), material=k.material("Nothing", "#ffffff", alpha=0.0))
''',
    "jumpy": '''
from kiln import model
@model()
def build(k):
    door = k.box("Door", (1, 2, 0.1), center=(0, 1, 0))
    k.clip("Swing", 1.0, {door: [(0.0, {"rotation": (0, 0, 0)}), (1.0, {"rotation": (0, 90, 0)})]}, loop=True)
''',
    "raises": '''
from kiln import model
@model()
def build(k):
    raise RuntimeError("no wood left")
''',
}

# Texture recipes that break their promises.
BROKEN_TEXTURES = {
    "seam": '''
from kiln import texture
@texture(size=64, maps=("albedo",), samples=1)
def build(t):
    t.output(albedo=t.ramp(t.u, [(0, "#000000"), (1, "#ffffff")]))
''',
    "no_height": '''
from kiln import texture
@texture(size=64, samples=1)
def build(t):
    t.output(albedo="#808080", roughness=0.5)
''',
    "half_stripes": '''
from kiln import texture
@texture(size=64, maps=("height",), samples=1)
def build(t):
    t.output(height=t.stripes(2.5))
''',
}

# A mesh made with bpy, unwrapped by the kit.
UNWRAPPED = '''
import bmesh
import bpy
from kiln import model
@model()
def build(k):
    mesh = bpy.data.meshes.new("Ball")
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=2, radius=0.5)
    bm.to_mesh(mesh)
    bm.free()
    ball = bpy.data.objects.new("Ball", mesh)
    k.collection.objects.link(ball)
    ball.scale = (2, 1, 1)
    k.unwrap(ball)
'''

# An arm of two bones: the upper part blends onto the lower bone toward the elbow, and the
# lower part and the cap on it are wholly on the lower bone.
ARM = '''
from kiln import geometry, model
@model(bones=["UpperBone", "LowerBone"], markers=["Elbow"])
def build(k):
    bones = k.armature("Skeleton", {"UpperBone": ((0, 0, 0), (0.5, 0, 0)), "LowerBone": ((0.5, 0, 0), (1.0, 0, 0))})
    upper = k.mesh("Upper", geometry.box((0.5, 0.1, 0.1), (0.25, 0, 0)))
    lower = k.mesh("Lower", geometry.box((0.5, 0.08, 0.08)), position=(0.75, 0, 0))
    cap = k.mesh("Cap", geometry.box((0.05, 0.05, 0.05)), parent=lower, position=(1.0, 0, 0))
    k.skin(upper, bones, lambda p: {"UpperBone": 1.0, "LowerBone": max(0.0, (p[0] - 0.4) / 0.2)})
    k.skin(lower, bones, "LowerBone")
    k.skin(cap, bones, "LowerBone")
    k.marker("Elbow", (0.5, 0, 0))
'''

HANDLEBAR = '''
from kiln import model
@model(markers=["Handlebar"])
def build(k):
    k.box("Hull", (1, 0.5, 2), center=(0, 0.25, 0))
    bar = k.marker("Handlebar", (0, 1.38, -0.42), rotation=(-20, 0, 0))
    k.box("Bar", (0.74, 0.05, 0.05), center=(0, 1.38, -0.42), parent=bar)
'''


@pytest.fixture
def project(tmp_path):
    root = tmp_path / "art"
    shutil.copytree(EXAMPLES / "models", root / "models")
    shutil.copytree(EXAMPLES / "textures", root / "textures")
    (root / "kiln.toml").write_text('output = "out"\nreports = "reports"\n')
    return root


def kiln(root, *args):
    return cli.main(["--project", str(root), *args])


def test_builds_the_examples_once_and_identically(project, capsys):
    assert kiln(project, "build") == 0
    out = capsys.readouterr().out
    assert "ok           models/crate" in out and "ok           models/buoy" in out
    crate = project / "out" / "models" / "crate.glb"
    assert crate.is_file()
    assert (project / "reports" / "models" / "crate" / "preview.png").is_file()
    lock = json.loads((project / "kiln.lock.json").read_text())
    assert lock["models/crate"]["triangles"] > 0
    report = json.loads((project / "reports" / "models" / "crate" / "report.json").read_text())
    assert report["materials"] == ["Iron", "Wood"]
    # The meshes are closed, so the materials draw only their front faces.
    materials = read_gltf(crate)["materials"]
    assert [m["name"] for m in materials] == ["Wood", "Iron"]
    assert not any(m.get("doubleSided") for m in materials)
    first = crate.read_bytes()

    assert kiln(project, "build") == 0
    assert "up to date   models/crate" in capsys.readouterr().out

    assert kiln(project, "build", "--force", "--no-preview", "models/crate") == 0
    assert crate.read_bytes() == first


def test_bakes_textures_that_tile_identically(project, capsys):
    assert kiln(project, "build", "textures") == 0
    assert "ok           textures/planks  256 x 256 px: albedo, normal, roughness, height" in capsys.readouterr().out
    out = project / "out" / "textures"
    shapes = {name: png.read(str(out / f"planks_{name}.png"))[:4] for name in ("albedo", "normal", "roughness", "height")}
    assert shapes == {"albedo": (256, 256, 3, 8), "normal": (256, 256, 3, 8),
                      "roughness": (256, 256, 1, 8), "height": (256, 256, 1, 16)}
    lock = json.loads((project / "kiln.lock.json").read_text())
    assert lock["textures/planks"]["outputs"][0] == "out/textures/planks_albedo.png"
    assert lock["textures/planks"]["maps"] == ["albedo", "normal", "roughness", "height"]
    assert lock["textures/planks"]["tile"] == 1.2
    report = json.loads((project / "reports" / "textures" / "planks" / "report.json").read_text())
    for edge, inside in report["seams"].values():
        assert edge <= inside * 1.5 + 0.002
    # Flat where the planks are flat: the normal map's blue is near 1 and its red and green
    # near the middle on most pixels.
    width, height, _, _, data = png.read(str(out / "planks_normal.png"))
    blues = data[2::3]
    assert sum(1 for b in blues if b > 240) > 0.5 * width * height
    first = (out / "planks_normal.png").read_bytes()
    assert kiln(project, "build", "--force", "--no-preview", "textures/planks") == 0
    assert (out / "planks_normal.png").read_bytes() == first
    # A deleted map is rebuilt.
    (out / "planks_height.png").unlink()
    capsys.readouterr()
    assert kiln(project, "build", "--no-preview", "textures") == 0
    assert "ok           textures/planks" in capsys.readouterr().out


# Ridges four to a tile, baked to make dirt in the troughs and an occlusion map.
DIRTY = '''
from kiln import texture
@texture(size=64, tile=1.0, relief=0.05, maps=("albedo", "occlusion"), samples=1)
def build(t):
    height = t.stripes(4, along="u")
    baked = t.bake(height)
    dirt = t.hollows(baked, 0.04)
    t.output(albedo=t.mix("#c0b090", "#403020", dirt), occlusion=t.occlusion(baked, 0.08), height=height)
'''


def test_masks_from_a_baked_height_darken_its_hollows(project, capsys):
    (project / "textures" / "dirty.py").write_text(DIRTY)
    assert kiln(project, "build", "textures/dirty") == 0
    out = project / "out" / "textures"
    width, _, _, _, occlusion = png.read(str(out / "dirty_occlusion.png"))
    _, _, _, _, albedo = png.read(str(out / "dirty_albedo.png"))
    row = list(occlusion[:width])
    # Across a row: stripe crests (u = 1/16, 5/16, ...) and troughs (u = 3/16, 7/16, ...).
    crest, trough = width // 16, 3 * width // 16
    assert row[crest] > 240 and row[trough] < row[crest] - 20
    assert albedo[3 * trough] < albedo[3 * crest] - 60
    first = (out / "dirty_occlusion.png").read_bytes()
    assert kiln(project, "build", "--force", "--no-preview", "textures/dirty") == 0
    assert (out / "dirty_occlusion.png").read_bytes() == first


def test_orm_maps_pack_occlusion_roughness_and_metallic(project, capsys):
    (project / "textures" / "metal.py").write_text('''
from kiln import texture
@texture(size=64, tile=1.0, relief=0.05, maps=("albedo", "orm"), samples=1)
def build(t):
    height = t.stripes(4, along="u")
    t.output(albedo="#808080", height=height, roughness=0.2 + height * 0.6, metallic=0.4,
             occlusion=t.occlusion(t.bake(height), 0.08))
''')
    (project / "textures" / "matte.py").write_text('''
from kiln import texture
@texture(size=64, maps=("albedo", "roughness"), samples=1)
def build(t):
    t.output(albedo=t.ramp(t.noise(scale=4, seed=1), [(0, "#404040"), (1, "#c0c0c0")]), roughness=0.7)
''')
    assert kiln(project, "build", "textures/metal", "textures/matte") == 0
    out = capsys.readouterr().out
    width, _, channels, _, orm = png.read(str(project / "out" / "textures" / "metal_orm.png"))
    assert channels == 3
    crest, trough = width // 16, 3 * width // 16
    # Red the occlusion, green the roughness, blue the metallic.
    assert orm[3 * crest] > orm[3 * trough] + 20
    assert orm[3 * crest + 1] == pytest.approx(0.8 * 255, abs=3) and orm[3 * trough + 1] == pytest.approx(0.2 * 255, abs=3)
    assert set(orm[2::3]) == {round(0.4 * 255)}
    # A map of one value is pointed out, and an output given as a number is kept in the lock.
    assert "note: roughness holds one value (0.700)" in out
    lock = json.loads((project / "kiln.lock.json").read_text())
    assert lock["textures/matte"]["values"] == {"roughness": 0.7}
    assert lock["textures/metal"]["values"] == {"metallic": 0.4}


def test_broken_textures_fail_with_reasons(project, capsys):
    (project / "textures" / "broken").mkdir(parents=True)
    for name, text in BROKEN_TEXTURES.items():
        (project / "textures" / "broken" / f"{name}.py").write_text(text)
    assert kiln(project, "build", "textures/broken") == 1
    out = capsys.readouterr().out
    sections = {name: out.split(f"textures/broken/{name}")[1].split("textures/broken/")[0] for name in BROKEN_TEXTURES}
    assert "albedo doesn't tile" in sections["seam"]
    assert "the recipe gave no height" in sections["no_height"]
    assert "2.5 stripes don't tile" in sections["half_stripes"]
    assert not (project / "out" / "textures" / "broken").exists()


def test_check_writes_no_outputs(project, capsys):
    assert kiln(project, "check") == 0
    assert not (project / "out").exists()
    assert "ok" in capsys.readouterr().out


def test_broken_recipes_fail_with_reasons(project, capsys):
    (project / "models" / "broken").mkdir()
    for name, text in BROKEN.items():
        (project / "models" / "broken" / f"{name}.py").write_text(text)
    assert kiln(project, "build", "models/broken") == 1
    out = capsys.readouterr().out
    sections = {name: out.split(f"models/broken/{name}")[1].split("models/broken/")[0] for name in BROKEN}
    assert "edges not shared by exactly two faces" in sections["open"]
    assert "faces turned against their neighbours" in sections["flipped"]
    assert "inside out" in sections["inside_out"]
    assert "over the budget of 10" in sections["over_budget"]
    assert "x size 1.000 m, expected 2.000 m" in sections["over_budget"]
    assert "no marker named Seat" in sections["over_budget"]
    assert "no face has the material Unused" in sections["over_budget"]
    assert "material Paint" not in sections["over_budget"]
    assert "Folded: " in sections["crossed"] and "cut through each other" in sections["crossed"]
    assert "Two:" not in sections["crossed"]
    assert "6 faces whose UVs cover no area" in sections["flat_uvs"]
    assert "no wood left" in sections["raises"]
    assert "clip Swing doesn't loop: Door rotation_quaternion" in sections["jumpy"]
    assert "the material 'Nothing' has alpha 0.0" in sections["clear"]
    # Asked for again with the same settings it is the same material; with others, it fails.
    assert "the material 'Paint' was made with other settings (color '#ff0000', now '#0000ff')" in sections["two_paints"]
    assert "an object named 'Seat' already exists" in sections["same_name"]
    assert "has no weight on any bone" in sections["no_weight"]
    assert "Box: 4 vertices whose weights on the bones don't add up to 1" in sections["half_weighted"]
    assert "no bone named Leg" in sections["half_weighted"]
    assert "the bone Box has an object's name" in sections["half_weighted"]
    for name in BROKEN:
        assert not (project / "out" / "models" / "broken" / f"{name}.glb").exists()
    lock = json.loads((project / "kiln.lock.json").read_text())
    assert not any(key.startswith("models/broken") for key in lock)


def test_markers_and_parents_export_in_game_space(project):
    (project / "models" / "handlebar.py").write_text(HANDLEBAR)
    assert kiln(project, "build", "--no-preview", "models/handlebar") == 0
    nodes = read_gltf(project / "out" / "models" / "handlebar.glb")["nodes"]
    by_name = {node["name"]: node for node in nodes}
    handlebar, bar = by_name["Handlebar"], by_name["Bar"]
    assert handlebar["translation"] == pytest.approx([0, 1.38, -0.42], abs=1e-5)
    # -20 degrees about X: the quaternion (x, y, z, w) = (sin(-10°), 0, 0, cos(-10°)).
    half = math.radians(-10)
    assert handlebar["rotation"] == pytest.approx([math.sin(half), 0, 0, math.cos(half)], abs=1e-5)
    assert nodes.index(bar) in handlebar["children"]
    # The bar was made at the handlebar's origin, unturned, and kept there when parented: no
    # offset, and turned back by the handlebar's 20 degrees (glTF leaves a zero translation out).
    assert bar.get("translation", [0, 0, 0]) == pytest.approx([0, 0, 0], abs=1e-5)
    assert bar["rotation"] == pytest.approx([-math.sin(half), 0, 0, math.cos(half)], abs=1e-5)


def test_every_mesh_has_uvs_in_metres(project):
    (project / "models" / "unwrapped.py").write_text(UNWRAPPED)
    assert kiln(project, "build") == 0
    for name in ("crate", "buoy", "unwrapped"):
        gltf = read_gltf(project / "out" / "models" / f"{name}.glb")
        assert all("TEXCOORD_0" in primitive["attributes"] for mesh in gltf["meshes"] for primitive in mesh["primitives"])
        report = json.loads((project / "reports" / "models" / name / "report.json").read_text())
        for mesh in report["meshes"].values():
            assert mesh["uvs"] and mesh["flat_uv_faces"] == 0
    # A box's faces, the bevel's included, and the unwrapped ball (stretched by its object's
    # scale) are mapped a UV unit to a metre. A lathe's poles are mapped a little larger.
    crate = json.loads((project / "reports" / "models" / "crate" / "report.json").read_text())["meshes"]["Body"]
    assert crate["uv_area"] == pytest.approx(crate["area"], rel=0.01)
    ball = json.loads((project / "reports" / "models" / "unwrapped" / "report.json").read_text())["meshes"]["Ball"]
    assert ball["uv_area"] == pytest.approx(ball["area"], rel=1e-3)
    first = (project / "out" / "models" / "unwrapped.glb").read_bytes()
    assert kiln(project, "build", "--force", "--no-preview", "models/unwrapped") == 0
    assert (project / "out" / "models" / "unwrapped.glb").read_bytes() == first


def test_materials_glow_and_let_light_through(project):
    (project / "models" / "lantern.py").write_text('''
from kiln import model
@model()
def build(k):
    k.box("Glass", (0.3, 0.3, 0.3), material=k.material("Glass", "#d0e8f0", alpha=0.4))
    k.box("Flame", (0.1, 0.1, 0.1), center=(1, 0, 0), material=k.material("Flame", "#ffffff", emission="#ffb040", emission_strength=4.0))
    k.box("Base", (0.3, 0.1, 0.3), center=(2, 0, 0), material=k.material("Iron", "#202020"))
''')
    assert kiln(project, "build", "models/lantern") == 0
    materials = {m["name"]: m for m in read_gltf(project / "out" / "models" / "lantern.glb")["materials"]}
    assert materials["Glass"]["alphaMode"] == "BLEND"
    assert materials["Glass"]["pbrMetallicRoughness"]["baseColorFactor"][3] == pytest.approx(0.4)
    assert materials["Flame"]["emissiveFactor"] == pytest.approx([1.0, 0.434, 0.051], abs=0.01)
    assert materials["Flame"]["extensions"]["KHR_materials_emissive_strength"]["emissiveStrength"] == 4.0
    assert "alphaMode" not in materials["Iron"] and "emissiveFactor" not in materials["Iron"]


def test_mesh_colours_export_as_vertex_colours(project):
    (project / "models" / "frond.py").write_text('''
from kiln import geometry, model
@model()
def build(k):
    # Red rising up the box, as a sway weight would; green a constant phase.
    k.mesh("Frond", geometry.box((0.2, 1.0, 0.2), (0, 0.5, 0)).with_colors(lambda p: (p[1], 0.25, 0.0)))
    k.box("Stem", (0.1, 0.1, 0.1), center=(1, 0, 0))
''')
    assert kiln(project, "build", "models/frond") == 0
    gltf = read_gltf(project / "out" / "models" / "frond.glb")
    attributes = {node["name"]: gltf["meshes"][node["mesh"]]["primitives"][0]["attributes"]
                  for node in gltf["nodes"] if "mesh" in node}
    assert "COLOR_0" in attributes["Frond"] and "COLOR_0" not in attributes["Stem"]
    colors = read_accessor(project / "out" / "models" / "frond.glb", attributes["Frond"]["COLOR_0"])
    # The values go out as given, not converted: red 0 to 1 up the box, green 0.25 throughout.
    reds, greens = [c[0] for c in colors], [c[1] for c in colors]
    assert (min(reds), max(reds)) == pytest.approx((0.0, 1.0), abs=1e-3)
    assert set(round(g, 3) for g in greens) == {0.25}
    report = json.loads((project / "reports" / "models" / "frond" / "report.json").read_text())
    assert report["meshes"]["Frond"]["colors"] and not report["meshes"]["Stem"]["colors"]


# A flag on a pole: a waving loop and a raising, and a bone's clip on the arm's skeleton.
FLAG = '''
from kiln import geometry, model
@model(markers=["Pole", "Flag"])
def build(k):
    pole = k.box("Pole", (0.08, 3.0, 0.08), center=(0, 1.5, 0))
    flag = k.mesh("Flag", geometry.box((1.2, 0.7, 0.04), (0.6, 0, 0)), parent=pole, position=(0.04, 2.6, 0))
    k.clip("Wave", 2.0, {flag: [(0.0, {"rotation": (0, -20, 0)}), (1.0, {"rotation": (0, 20, 0)}),
                                (2.0, {"rotation": (0, -20, 0)})]}, loop=True)
    # Positions as built, in the model: the flag runs up the pole from near its foot.
    k.clip("Raise", 1.0, {"Flag": [(0.0, {"position": (0.04, 0.4, 0)}), (1.0, {"position": (0.04, 2.6, 0)})]},
           smooth=False)
'''


def test_clips_export_as_animations_with_filmstrips(project):
    (project / "models" / "flag.py").write_text(FLAG)
    (project / "models" / "arm.py").write_text(ARM.replace('''    k.marker("Elbow", (0.5, 0, 0))''', '''    k.marker("Elbow", (0.5, 0, 0))
    k.clip("Bend", 0.5, {"Skeleton/LowerBone": [(0.0, {}), (0.5, {"rotation": (0, 0, 60)})]})'''))
    assert kiln(project, "build", "models/flag", "models/arm") == 0
    gltf = read_gltf(project / "out" / "models" / "flag.glb")
    names = [node["name"] for node in gltf["nodes"]]
    animations = {a["name"]: a for a in gltf["animations"]}
    # A looping clip's name ends -loop, which Godot takes off, looping it.
    assert sorted(animations) == ["Raise", "Wave-loop"]
    assert {names[c["target"]["node"]] for c in animations["Raise"]["channels"]} == {"Flag"}
    # The flag is built at the top of the pole; the clip moves it in its parent's space.
    flag = gltf["nodes"][names.index("Flag")]
    assert flag["translation"] == pytest.approx([0.04, 1.1, 0], abs=1e-5)
    raise_path = next(c for c in animations["Raise"]["channels"] if c["target"]["path"] == "translation")
    sampler = animations["Raise"]["samplers"][raise_path["sampler"]]
    heights = [p[1] for p in read_accessor(project / "out" / "models" / "flag.glb", sampler["output"])]
    assert (heights[0], heights[-1]) == pytest.approx((-1.1, 1.1), abs=1e-4)
    times = read_accessor(project / "out" / "models" / "flag.glb", sampler["input"])
    assert times[-1][0] == pytest.approx(1.0)
    report = json.loads((project / "reports" / "models" / "flag" / "report.json").read_text())
    assert report["clips"]["Wave"]["loop"] and Path(report["clips"]["Wave"]["filmstrip"]).is_file()
    assert png_size(Path(report["clips"]["Raise"]["filmstrip"])) == (1024, 512)
    # A skeleton's clip carries every bone (as the exporter samples them); the lower one turns
    # through its 60 degrees and the upper one holds still.
    arm = read_gltf(project / "out" / "models" / "arm.glb")
    [bend] = arm["animations"]
    turns = {}
    for channel in bend["channels"]:
        if channel["target"]["path"] == "rotation":
            output = bend["samplers"][channel["sampler"]]["output"]
            quaternions = read_accessor(project / "out" / "models" / "arm.glb", output)
            dot = abs(sum(a * b for a, b in zip(quaternions[0], quaternions[-1])))
            turns[arm["nodes"][channel["target"]["node"]]["name"]] = math.degrees(2 * math.acos(min(dot, 1.0)))
    assert turns["LowerBone"] == pytest.approx(60, abs=0.5) and turns["UpperBone"] == pytest.approx(0, abs=0.01)
    first = (project / "out" / "models" / "flag.glb").read_bytes()
    assert kiln(project, "build", "--force", "--no-preview", "models/flag") == 0
    assert (project / "out" / "models" / "flag.glb").read_bytes() == first


def test_skinned_meshes_export_with_their_skeleton(project):
    (project / "models" / "arm.py").write_text(ARM)
    assert kiln(project, "build", "models/arm") == 0
    gltf = read_gltf(project / "out" / "models" / "arm.glb")
    names = [node["name"] for node in gltf["nodes"]]
    [skin] = gltf["skins"]
    assert sorted(names[i] for i in skin["joints"]) == ["LowerBone", "UpperBone"]
    skinned = [node for node in gltf["nodes"] if "skin" in node]
    assert sorted(node["name"] for node in skinned) == ["Cap", "Lower", "Upper"]
    for node in skinned:
        attributes = gltf["meshes"][node["mesh"]]["primitives"][0]["attributes"]
        assert "JOINTS_0" in attributes and "WEIGHTS_0" in attributes
    report = json.loads((project / "reports" / "models" / "arm" / "report.json").read_text())
    assert report["bones"] == ["LowerBone", "UpperBone"]
    assert all(mesh["skinned"] and mesh["unweighted_vertices"] == 0 for mesh in report["meshes"].values())
    # Skinned at rest, the parts stay where they were built.
    assert report["size"] == pytest.approx([1.025, 0.1, 0.1], abs=1e-4)
    first = (project / "out" / "models" / "arm.glb").read_bytes()
    assert kiln(project, "build", "--force", "--no-preview", "models/arm") == 0
    assert (project / "out" / "models" / "arm.glb").read_bytes() == first


def test_preview_sheets_draw_the_games_look_and_what_changed(project, capsys):
    (project / "kiln.toml").write_text('''output = "out"
reports = "reports"
[preview.materials]
Wood = { texture = "textures/planks" }
Iron = { color = "#ff3030" }
''')
    assert kiln(project, "build", "textures") == 0
    assert kiln(project, "build", "models/crate") == 0
    report_dir = project / "reports" / "models" / "crate"
    assert "changes" not in json.loads((report_dir / "report.json").read_text())
    # Four rows of two 512-pixel views: the model as the game draws it twice, the UV
    # checker, and the triangles.
    assert png_size(report_dir / "preview.png") == (1024, 2048)
    recipe = project / "models" / "crate.py"
    recipe.write_text(recipe.read_text().replace("bevel=0.02", "bevel=0.04"))
    capsys.readouterr()
    assert kiln(project, "build", "models/crate") == 0
    assert "changes: " in capsys.readouterr().out
    changes = json.loads((report_dir / "report.json").read_text())["changes"]
    assert 0 < changes["share"] < 0.2 and (report_dir / "changes.png").is_file()
    # Built again the same, there are no changes, and the old picture of them goes.
    assert kiln(project, "build", "--force", "models/crate") == 0
    assert not (report_dir / "changes.png").exists()


def png_size(path: Path) -> tuple[int, int]:
    """A PNG's width and height, from its header."""
    return struct.unpack(">II", path.read_bytes()[16:24])


def read_accessor(path: Path, index: int) -> list[tuple[float, ...]]:
    """An accessor's values from a binary glTF, normalised integers as 0 to 1."""
    data = path.read_bytes()
    gltf = read_gltf(path)
    start = 20 + struct.unpack_from("<I", data, 12)[0] + 8
    accessor = gltf["accessors"][index]
    view = gltf["bufferViews"][accessor["bufferView"]]
    size = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[accessor["type"]]
    kind, scale = {5126: ("f", 1.0), 5123: ("H", 65535.0), 5121: ("B", 255.0)}[accessor["componentType"]]
    values = struct.unpack_from(f"<{accessor['count'] * size}{kind}", data,
                                start + view.get("byteOffset", 0) + accessor.get("byteOffset", 0))
    return [tuple(v / scale for v in values[i:i + size]) for i in range(0, len(values), size)]


def read_gltf(path: Path) -> dict:
    """The JSON chunk of a binary glTF."""
    data = path.read_bytes()
    length = struct.unpack_from("<I", data, 12)[0]
    return json.loads(data[20:20 + length])
