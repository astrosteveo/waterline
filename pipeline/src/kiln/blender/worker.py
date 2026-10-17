"""Runs inside Blender: builds each asset of a job, checks it, exports it and previews it.
A model is exported as `<stem>.glb`; a texture is baked into `<stem>_<map>.png` files.

The command line starts Blender with this script and a job file:

    blender --background --factory-startup --python-exit-code 1 --python worker.py -- job.json

The job lists the assets; the worker writes each asset's `report.json` and preview sheet to
its report folder and the results of the whole job to the job's `result` path.
"""
from __future__ import annotations

import importlib.util
import json
import os
import shutil
import sys
import time
import traceback

import bpy

# Blender ignores PYTHONPATH, so find the kiln package from this file (src/kiln/blender/).
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from kiln.blender import bake, checks, preview  # noqa: E402
from kiln.blender.kit import Kit  # noqa: E402
from kiln.recipe import find_recipe  # noqa: E402

# The project being built: errors show the lines of its code they came through.
PROJECT_ROOT = ""
# How the preview sheets draw the materials a game paints or textures (cli.preview_materials).
PREVIEW_MATERIALS: list[dict] = []


def main() -> None:
    job_path = sys.argv[sys.argv.index("--") + 1]
    with open(job_path) as f:
        job = json.load(f)
    # Recipes import shared code by its path from the project folder
    # (`from models.craft._hull import hull`).
    sys.path.insert(0, job["project_root"])
    global PROJECT_ROOT, PREVIEW_MATERIALS
    PROJECT_ROOT = job["project_root"]
    PREVIEW_MATERIALS = job.get("preview_materials", [])
    results = {}
    for asset in job["assets"]:
        results[asset["id"]] = build_asset(asset, job.get("export", True), job.get("preview", True))
    with open(job["result"], "w") as f:
        json.dump(results, f, indent=2)


def build_asset(asset: dict, export: bool, with_preview: bool) -> dict:
    """Builds one asset and returns its report. Without `export` nothing is written to the
    asset's outputs; the preview sheet is still made when asked for."""
    started = time.monotonic()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    report = {"id": asset["id"], "recipe": asset["recipe"]}
    # The last build's sheet, to show what this one changed.
    sheet = os.path.join(asset["report_dir"], "preview.png")
    before = sheet + ".before"
    if with_preview and os.path.isfile(sheet):
        shutil.copyfile(sheet, before)
    try:
        module = _load_module(asset["recipe"], asset["id"])
        recipe = find_recipe(module)
        if recipe.kind == "texture":
            report.update(bake.build_texture(recipe, asset["stem"], export,
                                             asset["report_dir"] if with_preview else None))
        else:
            report.update(_build_model(recipe, asset, export, with_preview))
    except Exception as error:
        report["problems"] = [_describe_error(error, asset["recipe"])]
    if os.path.isfile(before):
        if report.get("preview"):
            changes = preview.compare_sheets(before, sheet, os.path.join(asset["report_dir"], "changes.png"))
            if changes:
                report["changes"] = changes
        os.remove(before)
    report["seconds"] = round(time.monotonic() - started, 2)
    report["ok"] = not report["problems"]
    os.makedirs(asset["report_dir"], exist_ok=True)
    with open(os.path.join(asset["report_dir"], "report.json"), "w") as f:
        json.dump(report, f, indent=2)
    return report


def _build_model(recipe, asset: dict, export: bool, with_preview: bool) -> dict:
    kit = Kit()
    recipe.build(kit)
    report = {"kind": "model", **checks.measure()}
    report["problems"] = checks.problems(recipe.spec, report) + kit.clip_problems()
    report["clips"] = {clip["name"]: {"seconds": clip["seconds"], "loop": clip["loop"]} for clip in kit.clips}
    if report["problems"]:
        return report
    output = asset["stem"] + ".glb"
    report["outputs"] = [output]
    if export:
        os.makedirs(os.path.dirname(output), exist_ok=True)
        _export(output)
    if with_preview:
        sheet = os.path.join(asset["report_dir"], "preview.png")
        strips = preview.render_sheet(sheet, report["bounds"], PREVIEW_MATERIALS, kit.clips)
        report["preview"] = sheet
        for name, path in strips.items():
            report["clips"][name]["filmstrip"] = path
    return report


def _describe_error(error: Exception, recipe: str) -> str:
    """The error and the lines of the project's code it came through, without kiln's and
    Blender's own frames (all of them when the error came from kiln itself)."""
    frames = traceback.extract_tb(error.__traceback__)
    ours = [f for f in frames
            if f.filename == recipe or (PROJECT_ROOT and f.filename.startswith(PROJECT_ROOT + os.sep))] or frames
    lines = [f"{os.path.basename(f.filename)} line {f.lineno}: {(f.line or '').strip()}" for f in ours]
    return "the recipe raised " + "".join(traceback.format_exception_only(error)).strip() + \
        "".join("\n  " + line for line in lines)


def _load_module(path: str, asset_id: str):
    name = "kiln_recipe_" + asset_id.replace("/", "_").replace("-", "_")
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _export(path: str) -> None:
    """Writes the scene as a binary glTF, in glTF's +Y up, with modifiers applied."""
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_cameras=False,
        export_lights=False,
        export_extras=False,
        # Each clip (Kit.clip), kept in muted NLA tracks, as an animation sampled every frame.
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_tangents=False,
        # A mesh's colour attribute, where it has one, as COLOR_0 (data for the game's shaders).
        export_vertex_color="ACTIVE",
        use_selection=False,
    )


if __name__ == "__main__":
    main()
