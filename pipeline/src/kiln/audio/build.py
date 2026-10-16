"""Building a sound recipe: run it, scale and check its sounds, write them as WAV files and
render the preview sheet. It runs in the command line's own Python, not in Blender.

A recipe returns one sound, written as `<stem>.wav`, or a dict of named sounds, written as
`<stem>_<name>.wav`. Every sound is checked:

- every sample is a number, and the sound isn't silent;
- its length is within the spec's `seconds`;
- it sits on zero: its mean is within 0.01 of it (no DC offset);
- a loop joins up: the step from its last sample to its first is no bigger than 1.5 times its
  biggest steps inside (the 99.9th percentile), plus a little;
- a sound that doesn't loop starts and ends in silence, so it doesn't click on and off: its
  first and last samples are within 0.02 of zero, and its last millisecond peaks at under
  0.12 of its peak (18 dB below), so it has faded out rather than stopped;
- with `peak` set to None, nothing goes past full scale.
"""
from __future__ import annotations

import importlib.metadata
import importlib.util
import json
import os
import sys
import time
import traceback

import numpy as np

from kiln.audio import preview, wav
from kiln.audio.kit import SoundKit
from kiln.recipe import SoundSpec, find_recipe

SEAM_RATIO = 1.5
SEAM_SLACK = 0.002
MAX_DC = 0.01
MAX_END_SAMPLE = 0.02
END_SECONDS = 0.001
MAX_END_SHARE = 0.12


def tools() -> str:
    """The libraries a sound is built with, part of its fingerprint: another version may
    build different samples."""
    return ", ".join(f"{name} {importlib.metadata.version(name)}" for name in ("numpy", "scipy"))


def build_sound(recipe, stem: str, export: bool, report_dir: str | None) -> dict:
    """Runs a sound recipe, scales and checks its sounds, and (with `export`) writes them next
    to `stem`. With `report_dir`, renders the preview sheet there. Returns the report fields."""
    spec: SoundSpec = recipe.spec
    made = recipe.build(SoundKit(spec.rate, spec.loop))
    sounds = dict(made) if isinstance(made, dict) else {"": made}
    report = {"kind": "sound", "rate": spec.rate, "loop": spec.loop, "problems": []}
    problems = report["problems"]
    if not sounds:
        problems.append("the recipe returned no sounds")
        return report
    for name, samples in list(sounds.items()):
        label = _label(name)
        if not isinstance(samples, np.ndarray) or samples.dtype.kind not in "fiu":
            problems.append(f"{label}: the recipe returned {type(samples).__name__}, not an array of samples")
            continue
        samples = samples.astype(float)
        sounds[name] = samples
        wanted = (samples.shape[-1],) if spec.channels == 1 else (2, samples.shape[-1])
        if samples.shape != wanted or samples.shape[-1] == 0:
            problems.append(f"{label}: samples shaped {samples.shape}, where {'mono' if spec.channels == 1 else 'stereo'} "
                            f"is {'(n,)' if spec.channels == 1 else '(2, n)'}")
        elif not np.all(np.isfinite(samples)):
            problems.append(f"{label}: {int(np.sum(~np.isfinite(samples)))} samples aren't numbers")
    if problems:
        return report

    loudest = max(float(np.max(np.abs(s))) for s in sounds.values())
    if loudest == 0.0:
        problems.append("every sound is silent")
        return report
    scale = 10.0 ** (spec.peak / 20.0) / loudest if spec.peak is not None else 1.0
    sounds = {name: samples * scale for name, samples in sounds.items()}
    report["scale_db"] = round(20.0 * np.log10(scale), 2)
    report["sounds"] = {name: measure(samples, spec.rate, spec.loop) for name, samples in sounds.items()}
    for name, m in report["sounds"].items():
        problems.extend(f"{_label(name)}: {problem}" for problem in judge(m, spec))
    report["outputs"] = [_output(stem, name) for name in sounds]
    if export and not problems:
        os.makedirs(os.path.dirname(stem) or ".", exist_ok=True)
        for name, samples in sounds.items():
            wav.write(_output(stem, name), samples, spec.rate, spec.loop)
    if report_dir is not None:
        os.makedirs(report_dir, exist_ok=True)
        sheet = os.path.join(report_dir, "preview.png")
        preview.render_sheet(sheet, sounds, report["sounds"], spec.rate, spec.loop)
        report["preview"] = sheet
    return report


def measure(samples: np.ndarray, rate: int, loop: bool) -> dict:
    """The numbers the checks and the preview sheet use, for one sound as it will be written."""
    mono = samples if samples.ndim == 1 else samples.mean(axis=0)
    peak = float(np.max(np.abs(samples)))
    rms = float(np.sqrt(np.mean(samples * samples)))
    m = {
        "length": round(samples.shape[-1] / rate, 4),
        "peak": round(peak, 4),
        "peak_db": round(_db(peak), 2),
        "rms_db": round(_db(rms), 2),
        "dc": round(float(np.max(np.abs(np.mean(samples, axis=-1)))), 5),
    }
    spectrum = np.abs(np.fft.rfft(mono))
    freqs = np.fft.rfftfreq(len(mono), 1.0 / rate)
    m["centroid_hz"] = round(float(np.sum(freqs * spectrum) / max(np.sum(spectrum), 1e-12)), 1)
    if loop:
        steps = np.abs(np.diff(samples, axis=-1))
        m["seam_step"] = round(float(np.max(np.abs(samples[..., 0] - samples[..., -1]))), 5)
        m["inside_step"] = round(float(np.percentile(steps, 99.9)), 5)
    else:
        tail = samples[..., -max(int(END_SECONDS * rate), 1):]
        m["first_sample"] = round(float(np.max(np.abs(samples[..., 0]))), 5)
        m["last_sample"] = round(float(np.max(np.abs(samples[..., -1]))), 5)
        m["end_share"] = round(float(np.max(np.abs(tail))) / max(peak, 1e-12), 4)
    return m


def judge(m: dict, spec: SoundSpec) -> list[str]:
    """What is wrong with a sound measured by `measure`."""
    problems = []
    if spec.seconds is not None:
        shortest, longest = spec.seconds
        if not shortest <= m["length"] <= longest:
            problems.append(f"lasts {m['length']} s, outside {shortest}-{longest} s")
    if m["dc"] > MAX_DC:
        problems.append(f"sits {m['dc']} off zero (a DC offset; a high-pass takes it out)")
    if spec.peak is None and m["peak"] > 1.0:
        problems.append(f"goes past full scale (peak {m['peak']})")
    if spec.loop:
        if m["seam_step"] > m["inside_step"] * SEAM_RATIO + SEAM_SLACK:
            problems.append(f"jumps by {m['seam_step']} where it loops, against steps of {m['inside_step']} inside it")
    else:
        if m["first_sample"] > MAX_END_SAMPLE:
            problems.append(f"starts with a click: its first sample is {m['first_sample']}")
        if m["last_sample"] > MAX_END_SAMPLE or m["end_share"] > MAX_END_SHARE:
            problems.append(f"is still sounding when it ends (its last millisecond peaks at {m['end_share']} "
                            f"of its peak, its last sample is {m['last_sample']}): fade it out")
    return problems


def build_asset(asset, project_root: str, export: bool, with_preview: bool) -> dict:
    """Builds one sound asset (a `kiln.project.Asset`) and returns its report, which is also
    written to the asset's report folder."""
    started = time.monotonic()
    report = {"id": asset.id, "recipe": str(asset.recipe)}
    # Recipes import shared code by its path from the project folder.
    added = project_root not in sys.path
    if added:
        sys.path.insert(0, project_root)
    try:
        name = "kiln_recipe_" + asset.id.replace("/", "_").replace("-", "_")
        module_spec = importlib.util.spec_from_file_location(name, asset.recipe)
        module = importlib.util.module_from_spec(module_spec)
        module_spec.loader.exec_module(module)
        report.update(build_sound(find_recipe(module), str(asset.stem), export,
                                  str(asset.report_dir) if with_preview else None))
    except Exception as error:
        report.setdefault("kind", "sound")
        report["problems"] = [_describe_error(error, str(asset.recipe), project_root)]
    finally:
        if added:
            sys.path.remove(project_root)
    report["seconds"] = round(time.monotonic() - started, 2)
    report["ok"] = not report["problems"]
    os.makedirs(asset.report_dir, exist_ok=True)
    with open(os.path.join(asset.report_dir, "report.json"), "w") as f:
        json.dump(report, f, indent=2)
    return report


def _describe_error(error: Exception, recipe: str, project_root: str) -> str:
    """The error and the lines of the project's code it came through (all of them when the
    error came from kiln itself)."""
    frames = traceback.extract_tb(error.__traceback__)
    ours = [f for f in frames if f.filename == recipe or f.filename.startswith(project_root + os.sep)] or frames
    lines = [f"{os.path.basename(f.filename)} line {f.lineno}: {(f.line or '').strip()}" for f in ours]
    return "the recipe raised " + "".join(traceback.format_exception_only(error)).strip() + \
        "".join("\n  " + line for line in lines)


def _output(stem: str, name: str) -> str:
    return f"{stem}_{name}.wav" if name else f"{stem}.wav"


def _label(name: str) -> str:
    return f"sound {name!r}" if name else "the sound"


def _db(value: float) -> float:
    return 20.0 * float(np.log10(max(value, 1e-12)))
