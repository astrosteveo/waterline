"""A kiln project: its config, its recipes, and what has already been built.

A project is a folder with a `kiln.toml`:

    output = "../godot/assets"    # where built assets go
    reports = "../build/kiln"     # where reports and preview sheets go (keep it out of git)

Every `*.py` file under the folder is a recipe, except files and folders whose names start
with `_`, which hold code that recipes share. A recipe at `models/props/crate.py` is the asset
`models/props/crate` and builds `<output>/models/props/crate.glb`; a texture recipe at
`textures/sand.py` builds `<output>/textures/sand_albedo.png` and its other maps.
`kiln.lock.json` beside `kiln.toml` records what each asset was built from and the files it
made, so unchanged assets are skipped.
"""
from __future__ import annotations

import hashlib
import json
import tomllib
from dataclasses import dataclass
from pathlib import Path

CONFIG = "kiln.toml"
LOCK = "kiln.lock.json"
# The kiln package itself: a change to it rebuilds every asset, except a change to these
# files, which only run outside Blender.
PACKAGE = Path(__file__).resolve().parent
HOST_ONLY = {"cli.py", "project.py"}


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
                       (root / config.get("reports", "reports")).resolve())

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

    def shared_files(self) -> list[Path]:
        """The code every recipe may use: the project's `_` files and the parts of kiln that
        shape what a build makes (not the command line or this file)."""
        shared = [p for p in sorted(self.root.rglob("*.py"))
                  if any(part.startswith("_") for part in p.relative_to(self.root).parts)]
        return shared + sorted(p for p in PACKAGE.rglob("*.py") if p.name not in HOST_ONLY)

    def fingerprint(self, asset: Asset, blender_version: str) -> str:
        """A hash of everything the asset is built from. The same hash means the same build."""
        digest = hashlib.sha256()
        digest.update(blender_version.encode())
        for path in [asset.recipe, *self.shared_files()]:
            digest.update(path.name.encode())
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
