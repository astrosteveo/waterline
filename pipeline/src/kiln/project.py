"""A kiln project: its config, its recipes, and what has already been built.

A project is a folder with a `kiln.toml`:

    output = "../godot/assets"    # where built assets go
    reports = "../build/kiln"     # where reports and preview sheets go (keep it out of git)

    [preview.materials]           # how preview sheets draw the materials a game textures or paints
    Rock = { texture = "textures/rock" }    # in a texture the project builds
    "Suit*" = { color = "#d91f24" }         # in a colour, times its own (a name ending * is a prefix)

Every `*.py` file under the folder is a recipe, except files and folders whose names start
with `_`, which hold code that recipes share. A recipe at `models/props/crate.py` is the asset
`models/props/crate` and builds `<output>/models/props/crate.glb`; a texture recipe at
`textures/sand.py` builds `<output>/textures/sand_albedo.png` and its other maps; a sound
recipe at `audio/bell.py` builds `<output>/audio/bell.wav` (or `bell_<name>.wav` for each of
the sounds it names). `kiln.lock.json` beside `kiln.toml` records what each asset was built
from and the files it made, so unchanged assets are skipped.

An asset is built from its recipe, the project's files and kiln's own that the recipe and the
code building its kind import, followed through their imports. Kiln reads the imports from
the code without running it, so a module imported some other way (`importlib`) isn't seen.
"""
from __future__ import annotations

import ast
import hashlib
import json
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

from kiln.recipe import KINDS

CONFIG = "kiln.toml"
LOCK = "kiln.lock.json"
PACKAGE = Path(__file__).resolve().parent
# The code that builds each kind of recipe, whose imports are part of what an asset is built from.
BUILDERS = {
    "model": PACKAGE / "blender" / "worker.py",
    "texture": PACKAGE / "blender" / "worker.py",
    "sound": PACKAGE / "audio" / "build.py",
}


@dataclass(frozen=True)
class Asset:
    """One recipe and where its results go."""

    id: str
    recipe: Path
    # Where its outputs go, less the ending: `<output>/models/props/crate` for crate.glb.
    stem: Path
    report_dir: Path


@dataclass(frozen=True)
class Project:
    root: Path
    output: Path
    reports: Path
    # [preview.materials] from kiln.toml: by material name, {"texture": an id, "color": a colour}.
    preview_materials: dict = field(default_factory=dict)

    @staticmethod
    def find(start: Path) -> "Project":
        """The project whose `kiln.toml` is in `start` or the nearest folder above it, or in an
        `art` folder there."""
        start = start.resolve()
        for folder in [start, *start.parents]:
            for candidate in (folder, folder / "art"):
                if (candidate / CONFIG).is_file():
                    return Project.load(candidate)
        raise FileNotFoundError(f"no {CONFIG} in {start} or above it")

    @staticmethod
    def load(root: Path) -> "Project":
        root = root.resolve()
        config = tomllib.loads((root / CONFIG).read_text())
        return Project(root, (root / config.get("output", "out")).resolve(),
                       (root / config.get("reports", "reports")).resolve(),
                       config.get("preview", {}).get("materials", {}))

    def assets(self) -> list[Asset]:
        """Every recipe in the project, sorted by id."""
        found = []
        for path in sorted(self.root.rglob("*.py")):
            relative = path.relative_to(self.root)
            if any(part.startswith(("_", ".")) for part in relative.parts):
                continue
            asset_id = relative.with_suffix("").as_posix()
            found.append(Asset(asset_id, path, self.output / relative.with_suffix(""),
                               self.reports / relative.with_suffix("")))
        return found

    def select(self, ids: list[str]) -> list[Asset]:
        """The assets named in `ids` (an id, or a folder of ids such as `models/craft`), or
        every asset when `ids` is empty."""
        everything = self.assets()
        if not ids:
            return everything
        chosen = []
        for wanted in ids:
            wanted = wanted.strip("/").removesuffix(".py")
            matches = [a for a in everything if a.id == wanted or a.id.startswith(wanted + "/")]
            if not matches:
                raise KeyError(f"no recipe {wanted!r} in {self.root}")
            chosen.extend(a for a in matches if a not in chosen)
        return chosen

    def kind(self, asset: Asset) -> str:
        """Which kind of recipe the asset is (`model`, `texture` or `sound`), read from its
        decorator without running it. A recipe kiln can't read counts as a model, so Blender
        reports what is wrong with it."""
        try:
            tree = ast.parse(asset.recipe.read_text(), str(asset.recipe))
        except (SyntaxError, ValueError):
            return "model"
        for node in ast.walk(tree):
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                for decorator in node.decorator_list:
                    target = decorator.func if isinstance(decorator, ast.Call) else decorator
                    name = target.attr if isinstance(target, ast.Attribute) else getattr(target, "id", None)
                    if name in KINDS:
                        return name
        return "model"

    def dependencies(self, asset: Asset) -> list[Path]:
        """The files the asset is built from: its recipe, and the project's and kiln's files
        that it and the code building its kind import, followed through their imports."""
        roots = [self.root, PACKAGE.parent]
        found: set[Path] = set()
        todo = [asset.recipe.resolve(), BUILDERS[self.kind(asset)]]
        while todo:
            path = todo.pop()
            if path in found:
                continue
            found.add(path)
            todo.extend(_imported_files(path, roots))
        return sorted(found)

    def fingerprint(self, asset: Asset, tools: str) -> str:
        """A hash of everything the asset is built from, and of `tools` (the Blender version,
        or the libraries a sound is made with). The same hash means the same build."""
        digest = hashlib.sha256()
        digest.update(tools.encode())
        for path in self.dependencies(asset):
            root = self.root if path.is_relative_to(self.root) else PACKAGE.parent
            digest.update(path.relative_to(root).as_posix().encode())
            digest.update(path.read_bytes())
        return digest.hexdigest()

    def built_files(self, entry: dict) -> list[Path]:
        """The files a lock entry says its build made."""
        outputs = entry.get("outputs", [entry["output"]] if "output" in entry else [])
        return [self.root / output for output in outputs]

    def up_to_date(self, asset: Asset, lock: dict, fingerprint: str) -> bool:
        """True when the asset was last built from the same inputs and its files are there."""
        entry = lock.get(asset.id)
        if entry is None or entry.get("fingerprint") != fingerprint:
            return False
        files = self.built_files(entry)
        return bool(files) and all(path.is_file() for path in files)

    def read_lock(self) -> dict:
        path = self.root / LOCK
        return json.loads(path.read_text()) if path.is_file() else {}

    def write_lock(self, lock: dict) -> None:
        text = json.dumps(dict(sorted(lock.items())), indent=2, sort_keys=True) + "\n"
        (self.root / LOCK).write_text(text)


def _imported_files(path: Path, roots: list[Path]) -> list[Path]:
    """The files under `roots` that the code in `path` imports, with the `__init__.py` of each
    package on the way, read from the code without running it."""
    try:
        tree = ast.parse(path.read_text(), str(path))
    except (SyntaxError, ValueError, OSError):
        return []
    names: list[tuple[Path | None, list[str]]] = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            names.extend((None, alias.name.split(".")) for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            base = None
            if node.level:
                base = path.parent
                for _ in range(node.level - 1):
                    base = base.parent
            parts = node.module.split(".") if node.module else []
            names.append((base, parts))
            # `from package import name` may name a module in the package.
            names.extend((base, parts + [alias.name]) for alias in node.names if alias.name != "*")
    files = []
    for base, parts in names:
        for root in ([base] if base is not None else roots):
            for depth in range(1, len(parts) + 1):
                folder = root.joinpath(*parts[:depth])
                for candidate in (folder / "__init__.py", folder.with_suffix(".py")):
                    if candidate.is_file():
                        files.append(candidate.resolve())
            if base is not None and not parts:
                init = base / "__init__.py"
                if init.is_file():
                    files.append(init.resolve())
    return files
