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
@model(max_triangles=10, size=(2, 1, 1), markers=["Seat"])
def build(k):
    k.box("Box", (1, 1, 1))
''',
    "crossed": '''
from kiln import model, geometry
@model()
def build(k):
    k.mesh("Two", geometry.box((1, 1, 1)).merged(geometry.box((1, 1, 1), center=(0.5, 0.2, 0.1))))
''',
    "flat_uvs": '''
from kiln import model, geometry
@model()
def build(k):
    box = geometry.box((1, 1, 1))
    k.mesh("Box", geometry.Mesh(box.vertices, box.faces, uvs=tuple(((0, 0),) * 4 for _ in box.faces)))
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
    assert "cut through each other" in sections["crossed"]
    assert "6 faces whose UVs cover no area" in sections["flat_uvs"]
    assert "no wood left" in sections["raises"]
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


def read_gltf(path: Path) -> dict:
    """The JSON chunk of a binary glTF."""
    data = path.read_bytes()
    length = struct.unpack_from("<I", data, 12)[0]
    return json.loads(data[20:20 + length])
