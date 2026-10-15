from pathlib import Path

import pytest

from kiln.project import Project
from kiln.recipe import ModelSpec, find_recipe, model


def make_project(root: Path) -> Project:
    root.mkdir(parents=True)
    (root / "kiln.toml").write_text('output = "../out"\nreports = "../reports"\n')
    (root / "models" / "props").mkdir(parents=True)
    (root / "models" / "props" / "crate.py").write_text("# crate\n")
    (root / "models" / "props" / "barrel.py").write_text("# barrel\n")
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
    assert crate.output == (tmp_path / "out" / "models" / "props" / "crate.glb").resolve()
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


def test_fingerprint_follows_the_recipe_and_shared_code(tmp_path):
    project = make_project(tmp_path / "art")
    crate, barrel = project.select(["models/props/crate"])[0], project.select(["models/props/barrel"])[0]
    before = project.fingerprint(crate, "Blender 5.2")
    other = project.fingerprint(barrel, "Blender 5.2")
    assert project.fingerprint(crate, "Blender 5.2") == before
    assert project.fingerprint(crate, "Blender 5.3") != before
    (tmp_path / "art" / "models" / "craft" / "_hull.py").write_text("# changed\n")
    assert project.fingerprint(crate, "Blender 5.2") != before
    assert project.fingerprint(barrel, "Blender 5.2") != other


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
