from pathlib import Path

import pytest

from kiln import png
from kiln.project import PACKAGE, Project
from kiln.recipe import ModelSpec, SoundSpec, TextureSpec, find_recipe, model, sound, texture


def make_project(root: Path) -> Project:
    root.mkdir(parents=True)
    (root / "kiln.toml").write_text('output = "../out"\nreports = "../reports"\n')
    (root / "models" / "props").mkdir(parents=True)
    (root / "models" / "props" / "crate.py").write_text("from models.craft._hull import hull\n")
    (root / "models" / "props" / "barrel.py").write_text("from _shared import util\n")
    (root / "models" / "craft").mkdir()
    (root / "models" / "craft" / "petrel.py").write_text("# petrel\n")
    (root / "models" / "craft" / "_hull.py").write_text("# shared\n")
    (root / "_shared").mkdir()
    (root / "_shared" / "util.py").write_text("# shared\n")
    return Project.load(root)


def test_finds_recipes_but_not_shared_code(tmp_path):
    project = make_project(tmp_path / "art")
    assert [a.id for a in project.assets()] == ["models/craft/petrel", "models/props/barrel", "models/props/crate"]
    crate = project.select(["models/props/crate"])[0]
    assert crate.stem == (tmp_path / "out" / "models" / "props" / "crate").resolve()
    assert crate.report_dir == (tmp_path / "reports" / "models" / "props" / "crate").resolve()


def test_selects_by_folder_and_rejects_unknown_ids(tmp_path):
    project = make_project(tmp_path / "art")
    assert [a.id for a in project.select(["models/props/"])] == ["models/props/barrel", "models/props/crate"]
    with pytest.raises(KeyError):
        project.select(["models/boats"])


def test_finds_the_project_from_below_or_from_an_art_folder(tmp_path):
    make_project(tmp_path / "art")
    assert Project.find(tmp_path / "art" / "models").root == (tmp_path / "art").resolve()
    assert Project.find(tmp_path).root == (tmp_path / "art").resolve()


def test_fingerprint_follows_the_recipe_and_the_shared_code_it_imports(tmp_path):
    project = make_project(tmp_path / "art")
    crate, barrel = project.select(["models/props/crate"])[0], project.select(["models/props/barrel"])[0]
    before = project.fingerprint(crate, "Blender 5.2")
    other = project.fingerprint(barrel, "Blender 5.2")
    assert project.fingerprint(crate, "Blender 5.2") == before
    assert project.fingerprint(crate, "Blender 5.3") != before
    (tmp_path / "art" / "models" / "craft" / "_hull.py").write_text("# changed\n")
    assert project.fingerprint(crate, "Blender 5.2") != before
    assert project.fingerprint(barrel, "Blender 5.2") == other
    (tmp_path / "art" / "_shared" / "util.py").write_text("# changed\n")
    assert project.fingerprint(barrel, "Blender 5.2") != other


def test_dependencies_follow_imports_through_shared_code_and_kiln(tmp_path):
    project = make_project(tmp_path / "art")
    root = tmp_path / "art"
    (root / "audio").mkdir()
    (root / "audio" / "_tones.py").write_text("from audio import _scales\nimport math\n")
    (root / "audio" / "_scales.py").write_text("NOTES = 12\n")
    (root / "audio" / "bell.py").write_text(
        "from kiln import sound\nfrom audio._tones import *\n\n@sound()\ndef build(s):\n    pass\n")
    bell = project.select(["audio/bell"])[0]
    assert project.kind(bell) == "sound"
    names = dependency_names(project, bell)
    assert {"audio/bell.py", "audio/_tones.py", "audio/_scales.py"} <= names
    assert {"kiln/__init__.py", "kiln/recipe.py", "kiln/audio/build.py", "kiln/audio/kit.py"} <= names
    # A sound doesn't depend on Blender's code, nor on the models' shared code.
    assert not any(name.startswith(("kiln/blender/", "models/")) for name in names)
    crate = project.select(["models/props/crate"])[0]
    assert project.kind(crate) == "model"
    names = dependency_names(project, crate)
    assert {"models/props/crate.py", "models/craft/_hull.py", "kiln/blender/worker.py", "kiln/blender/kit.py"} <= names
    assert not any(name.startswith(("kiln/audio/", "audio/")) for name in names)


def dependency_names(project, asset):
    """The asset's dependencies as paths from the project folder, or from `kiln/` for kiln's own."""
    return {p.relative_to(project.root).as_posix() if p.is_relative_to(project.root)
            else "kiln/" + p.relative_to(PACKAGE).as_posix() for p in project.dependencies(asset)}


def test_kind_is_read_from_the_decorator(tmp_path):
    project = make_project(tmp_path / "art")
    root = tmp_path / "art"
    (root / "textures").mkdir()
    (root / "textures" / "sand.py").write_text("import kiln\n\n@kiln.texture(size=64)\ndef build(t):\n    pass\n")
    (root / "textures" / "broken.py").write_text("def build(t:\n")
    assert project.kind(project.select(["textures/sand"])[0]) == "texture"
    # One kiln can't read goes to Blender, which reports the error.
    assert project.kind(project.select(["textures/broken"])[0]) == "model"


def test_lock_round_trip(tmp_path):
    project = make_project(tmp_path / "art")
    assert project.read_lock() == {}
    project.write_lock({"b": {"fingerprint": "2"}, "a": {"fingerprint": "1"}})
    assert list(project.read_lock()) == ["a", "b"]


def test_model_decorator_records_the_spec():
    @model(max_triangles=10, markers=["Seat"])
    def build(k):
        pass

    class Module:
        __file__ = "recipe.py"

    Module.build = build
    recipe = find_recipe(Module)
    assert recipe.kind == "model" and recipe.build is build
    assert recipe.spec == ModelSpec(max_triangles=10, markers=["Seat"])


def test_a_module_needs_exactly_one_recipe():
    class Module:
        __file__ = "recipe.py"

    with pytest.raises(ValueError):
        find_recipe(Module)


def test_texture_decorator_records_the_spec():
    @texture(size=256, tile=2.0, maps=("albedo", "height"))
    def build(t):
        pass

    class Module:
        __file__ = "recipe.py"

    Module.build = build
    recipe = find_recipe(Module)
    assert recipe.kind == "texture"
    assert recipe.spec == TextureSpec(size=256, tile=2.0, maps=("albedo", "height"))


def test_texture_spec_rejects_unknown_maps_and_odd_sizes():
    with pytest.raises(ValueError, match="unknown texture maps"):
        TextureSpec(maps=("albedo", "gloss"))
    with pytest.raises(ValueError, match="power of two"):
        TextureSpec(size=1000)


def test_up_to_date_needs_the_same_fingerprint_and_every_file(tmp_path):
    project = make_project(tmp_path / "art")
    crate = project.select(["models/props/crate"])[0]
    out = tmp_path / "out" / "textures"
    out.mkdir(parents=True)
    (out / "sand_albedo.png").write_bytes(b"png")
    lock = {crate.id: {"fingerprint": "f", "outputs": ["../out/textures/sand_albedo.png",
                                                       "../out/textures/sand_normal.png"]}}
    assert not project.up_to_date(crate, lock, "f")
    (out / "sand_normal.png").write_bytes(b"png")
    assert project.up_to_date(crate, lock, "f")
    assert not project.up_to_date(crate, lock, "g")
    # An entry from before kiln built textures names its one output.
    assert project.built_files({"output": "../out/models/props/crate.glb"}) == \
        [tmp_path / "art" / "../out/models/props/crate.glb"]


def test_png_round_trip(tmp_path):
    rgb = bytes(range(0, 4 * 3 * 3))
    png.write(str(tmp_path / "rgb.png"), rgb, 4, 3, 3)
    assert png.read(str(tmp_path / "rgb.png")) == (4, 3, 3, 8, rgb)
    grey16 = bytes(range(0, 2 * 5 * 2))
    png.write(str(tmp_path / "grey.png"), grey16, 5, 2, 1, 16)
    assert png.read(str(tmp_path / "grey.png")) == (5, 2, 1, 16, grey16)
    with pytest.raises(ValueError):
        png.write(str(tmp_path / "short.png"), rgb[:-1], 4, 3, 3)


def test_sound_decorator_records_the_spec():
    @sound(loop=True, seconds=(0.5, 2.0))
    def build(s):
        pass

    class Module:
        __file__ = "recipe.py"

    Module.build = build
    recipe = find_recipe(Module)
    assert recipe.kind == "sound"
    assert recipe.spec == SoundSpec(loop=True, seconds=(0.5, 2.0))
    with pytest.raises(ValueError, match="1 or 2 channels"):
        SoundSpec(channels=6)
