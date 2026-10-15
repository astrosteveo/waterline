"""Runs inside Blender: builds each asset of a job, checks it, exports it and previews it.

The command line starts Blender with this script and a job file:

    blender --background --factory-startup --python-exit-code 1 --python worker.py -- job.json

The job lists the assets; the worker writes each asset's `report.json` and preview sheet to
its report folder and the results of the whole job to the job's `result` path.
"""
from __future__ import annotations

import importlib.util
import json
import os
import sys
import time
import traceback

import bpy

# Blender ignores PYTHONPATH, so find the kiln package from this file (src/kiln/blender/).
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from kiln.blender import checks, preview  # noqa: E402
from kiln.blender.kit import Kit  # noqa: E402
from kiln.recipe import find_recipe  # noqa: E402

# The project being built: errors show the lines of its code they came through.
PROJECT_ROOT = ""


def main() -> None:
    job_path = sys.argv[sys.argv.index("--") + 1]
    with open(job_path) as f:
        job = json.load(f)
    # Recipes import shared code by its path from the project folder
    # (`from models.craft._hull import hull`).
    sys.path.insert(0, job["project_root"])
    global PROJECT_ROOT
    PROJECT_ROOT = job["project_root"]
    results = {}
    for asset in job["assets"]:
        results[asset["id"]] = build_asset(asset, job.get("export", True), job.get("preview", True))
    with open(job["result"], "w") as f:
        json.dump(results, f, indent=2)


def build_asset(asset: dict, export: bool, with_preview: bool) -> dict:
    """Builds one asset and returns its report. Without `export` nothing is written to the
    asset's output; the preview sheet is still made when asked for."""
    started = time.monotonic()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    report = {"id": asset["id"], "recipe": asset["recipe"], "output": asset["output"]}
    try:
        module = _load_module(asset["recipe"], asset["id"])
        recipe = find_recipe(module)
        recipe.build(Kit())
        measured = checks.measure()
        report.update(measured)
        report["problems"] = checks.problems(recipe.spec, measured)
        if not report["problems"]:
            if export:
                os.makedirs(os.path.dirname(asset["output"]), exist_ok=True)
                _export(asset["output"])
            if with_preview:
                sheet = os.path.join(asset["report_dir"], "preview.png")
                preview.render_sheet(sheet, measured["bounds"])
                report["preview"] = sheet
    except Exception as error:
        report["problems"] = [_describe_error(error, asset["recipe"])]
    report["seconds"] = round(time.monotonic() - started, 2)
    report["ok"] = not report["problems"]
    os.makedirs(asset["report_dir"], exist_ok=True)
    with open(os.path.join(asset["report_dir"], "report.json"), "w") as f:
        json.dump(report, f, indent=2)
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
        export_animations=False,
        export_tangents=False,
        use_selection=False,
    )


if __name__ == "__main__":
    main()
