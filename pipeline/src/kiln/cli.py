"""The `kiln` command: build, check, preview and list a project's assets.

    kiln build [ID ...]      build what changed (all with --force), write outputs and previews
    kiln check [ID ...]      run the recipes and their checks; write nothing
    kiln preview [ID ...]    render preview sheets without changing outputs
    kiln status              which assets are up to date

An ID is an asset id (`models/props/crate`) or a folder of them (`models/props`). Kiln finds
the project's `kiln.toml` in the current folder, an `art` folder in it, or a folder above;
`--project DIR` names it. Reports and preview sheets go to the project's `reports` folder.
Models and textures are built in Blender, sounds here; Blender is only needed for the first.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from kiln.project import Asset, Project

WORKER = Path(__file__).resolve().parent / "blender" / "worker.py"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="kiln", description=__doc__.split("\n\n")[0])
    parser.add_argument("--project", type=Path, help="the folder with kiln.toml")
    parser.add_argument("--blender", default=os.environ.get("KILN_BLENDER", "blender"),
                        help="the Blender binary (default: $KILN_BLENDER or blender)")
    commands = parser.add_subparsers(dest="command", required=True)
    build = commands.add_parser("build", help="build assets whose recipe or kiln changed")
    build.add_argument("ids", nargs="*")
    build.add_argument("--force", action="store_true", help="build even if up to date")
    build.add_argument("--no-preview", action="store_true", help="skip the preview sheets")
    check = commands.add_parser("check", help="run recipes and checks, write nothing")
    check.add_argument("ids", nargs="*")
    preview = commands.add_parser("preview", help="render preview sheets only")
    preview.add_argument("ids", nargs="*")
    commands.add_parser("status", help="list assets and whether they are up to date")
    args = parser.parse_args(argv)

    try:
        project = Project.load(args.project) if args.project else Project.find(Path.cwd())
    except FileNotFoundError as error:
        print(f"kiln: {error}", file=sys.stderr)
        return 2
    blender = shutil.which(args.blender) or args.blender
    if args.command == "status":
        return status(project, blender)
    try:
        assets = project.select(args.ids)
    except KeyError as error:
        print(f"kiln: {error.args[0]}", file=sys.stderr)
        return 2
    if args.command == "build":
        return build_assets(project, blender, assets, args.force, not args.no_preview)
    if args.command == "check":
        return run(project, blender, assets, export=False, preview=False)[0]
    return run(project, blender, assets, export=False, preview=True)[0]


def status(project: Project, blender: str) -> int:
    tools = Tools(blender)
    lock = project.read_lock()
    for asset in project.assets():
        entry = lock.get(asset.id)
        if entry is None or not all(path.is_file() for path in project.built_files(entry)):
            state = "not built"
        elif not project.up_to_date(asset, lock, project.fingerprint(asset, tools.version(project.kind(asset)))):
            state = "out of date"
        else:
            state = "up to date"
        print(f"{state:12} {asset.id}")
    return 0


def build_assets(project: Project, blender: str, assets: list[Asset], force: bool, preview: bool) -> int:
    tools = Tools(blender)
    lock = project.read_lock()
    kinds = {a.id: project.kind(a) for a in assets}
    fingerprints = {a.id: project.fingerprint(a, tools.version(kinds[a.id])) for a in assets}
    todo = [a for a in assets if force or not project.up_to_date(a, lock, fingerprints[a.id])]
    for asset in assets:
        if asset not in todo:
            print(f"up to date   {asset.id}")
    if not todo:
        return 0
    code, results = run(project, blender, todo, export=True, preview=preview)
    for asset in todo:
        report = results.get(asset.id)
        if report and report["ok"]:
            entry = {
                "fingerprint": fingerprints[asset.id],
                "outputs": [os.path.relpath(path, project.root) for path in report["outputs"]],
            }
            if report["kind"] == "sound":
                entry["seconds"] = {name: m["length"] for name, m in report["sounds"].items()}
                entry["tools"] = tools.version("sound")
            else:
                entry["size"] = report["size"]
                entry["blender"] = tools.version(report["kind"])
                if report["kind"] == "model":
                    entry["triangles"] = report["triangles"]
                else:
                    entry["maps"] = report["maps"]
            lock[asset.id] = entry
    project.write_lock(lock)
    return code


class Tools:
    """The versions of what builds each kind of asset, found when first needed: Blender's
    only when a model or texture is built."""

    def __init__(self, blender: str):
        self.blender = blender
        self._versions: dict[str, str] = {}

    def version(self, kind: str) -> str:
        key = "sound" if kind == "sound" else "blender"
        if key not in self._versions:
            if key == "sound":
                from kiln.audio.build import tools
                self._versions[key] = tools()
            else:
                self._versions[key] = blender_version(self.blender)
        return self._versions[key]


def run(project: Project, blender: str, assets: list[Asset], export: bool, preview: bool) -> tuple[int, dict]:
    """Builds `assets`, the models and textures in Blender and the sounds here, and prints a
    line per asset. Returns 0 when every asset passed, 1 otherwise, and the reports."""
    sounds = [a for a in assets if project.kind(a) == "sound"]
    in_blender = [a for a in assets if a not in sounds]
    results: dict = {}
    if in_blender:
        results.update(run_blender(project, blender, in_blender, export, preview))
    if sounds:
        from kiln.audio.build import build_asset
        for asset in sounds:
            results[asset.id] = build_asset(asset, str(project.root), export, preview)
    failed = 0
    for asset in assets:
        report = results.get(asset.id)
        if report is None:
            failed += 1
            print(f"FAILED       {asset.id}")
            print("    Blender didn't build it")
            continue
        if report["ok"]:
            where = ""
            if export:
                where = f" -> {os.path.relpath(report['outputs'][0])}"
                if len(report["outputs"]) > 1:
                    where += f" and {len(report['outputs']) - 1} more"
            print(f"ok           {asset.id}  {describe(report)}{where}")
        else:
            failed += 1
            print(f"FAILED       {asset.id}")
            for problem in report["problems"]:
                print("    " + problem.replace("\n", "\n    ").rstrip())
        if report.get("preview"):
            print(f"             preview: {os.path.relpath(report['preview'])}")
    return (1 if failed else 0), results


def describe(report: dict) -> str:
    """What an asset's build made, in a few words."""
    if report["kind"] == "texture":
        size = " x ".join(str(v) for v in report["size"])
        return f"{size} px: {', '.join(report['maps'])}"
    if report["kind"] == "sound":
        lengths = [m["length"] for m in report["sounds"].values()]
        span = f"{min(lengths):.2f}" + (f"-{max(lengths):.2f}" if max(lengths) > min(lengths) else "")
        count = f"{len(lengths)} sounds" if len(lengths) > 1 else "1 sound"
        peak = max(m["peak_db"] for m in report["sounds"].values())
        return f"{count}, {span} s, peak {peak:.1f} dBFS{', loops' if report['loop'] else ''}"
    size = " x ".join(f"{v:.2f}" for v in report["size"])
    return f"{report['triangles']} triangles, {size} m"


def run_blender(project: Project, blender: str, assets: list[Asset], export: bool, preview: bool) -> dict:
    """Runs the worker in Blender on `assets` and returns their reports (none if Blender
    failed)."""
    with tempfile.TemporaryDirectory(prefix="kiln-") as folder:
        job = {
            "project_root": str(project.root),
            "export": export,
            "preview": preview,
            "result": os.path.join(folder, "result.json"),
            "assets": [{"id": a.id, "recipe": str(a.recipe), "stem": str(a.stem),
                        "report_dir": str(a.report_dir)} for a in assets],
        }
        job_path = os.path.join(folder, "job.json")
        with open(job_path, "w") as f:
            json.dump(job, f)
        command = [blender, "--background", "--factory-startup", "--python-exit-code", "1",
                   "--python", str(WORKER), "--", job_path]
        done = subprocess.run(command, capture_output=True, text=True)
        if done.returncode != 0 or not os.path.isfile(job["result"]):
            print(done.stdout[-4000:] + done.stderr[-4000:], file=sys.stderr)
            print(f"kiln: Blender failed (exit code {done.returncode})", file=sys.stderr)
            return {}
        with open(job["result"]) as f:
            return json.load(f)


def blender_version(blender: str) -> str:
    """Blender's version line, part of every fingerprint (another Blender may build differently)."""
    try:
        out = subprocess.run([blender, "--version"], capture_output=True, text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"kiln: can't run Blender ({blender}): {error}")
    return out.splitlines()[0].strip()


if __name__ == "__main__":
    sys.exit(main())
