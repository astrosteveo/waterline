"""Records the announcer's lines with VoiceStudio, into godot/assets/audio/voice/.

    uv run --project pipeline python tools/voice/voice_tool.py               # record what's new or changed
    uv run --project pipeline python tools/voice/voice_tool.py --force ID... # record these again (ids or prefixes)
    uv run --project pipeline python tools/voice/voice_tool.py --list        # the lines, and which are recorded
    uv run --project pipeline python tools/voice/voice_tool.py --check       # hear each clip back, list the misses

It asks the game for every line the announcer can call (res://test/tools/announcer_lines.tscn,
from `Announcer.every_line`), records each one whose clip is missing or whose words or voice
settings changed, and writes it as `<id>.ogg`: trimmed of the silence round it, faded at its
ends and brought to one loudness, so no line is louder than another. A clip whose line the game
doesn't call is deleted. `tools/voice/voice.lock.json` keeps what each clip was recorded
from; commit it with the clips. `--check` has VoiceStudio's speech recognition hear every clip
and lists those whose words don't match their line, to record again with `--force`.

VoiceStudio must be running (the app, or its server alone; see `--server`). The voice is its
profile named VOICE, made from the catalogue's ARCHETYPE the first time; it renders a sample
with a fixed seed, so the voice is the same each time it's made.
"""
from __future__ import annotations

import argparse
import difflib
import io
import re
import json
import os
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import uuid
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "pipeline" / "src"))
from kiln.audio import ogg  # noqa: E402

OUT = ROOT / "godot" / "assets" / "audio" / "voice"
LOCK = Path(__file__).resolve().parent / "voice.lock.json"
SERVER = "http://127.0.0.1:3900"
# The announcer's voice: a VoiceStudio profile, made from this archetype if it is missing.
VOICE = "Waterline Announcer"
ARCHETYPE = "feat_14_the_hype_host"
# How each line is rendered; a change records every line again.
SETTINGS = {"seed": 7, "effect_preset": "broadcast", "speed": 1.0, "guidance_scale": 2.0}
# Each clip's loudness (RMS over the speech) and its highest peak, in dB below full scale.
LOUDNESS_DB = -17.0
PEAK_DB = -1.0
# The level below which the ends count as silence, and what is kept round the speech.
SILENCE_DB = -42.0
LEAD_IN = 0.02
TAIL = 0.08


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="voice_tool", description=__doc__.split("\n\n")[0])
    parser.add_argument("ids", nargs="*", help="with --force: the lines to record again (an id or a prefix)")
    parser.add_argument("--force", action="store_true", help="record the lines named again")
    parser.add_argument("--list", action="store_true", help="list the lines and whether each is recorded")
    parser.add_argument("--check", action="store_true", help="hear each clip back and list those that don't match")
    parser.add_argument("--server", default=os.environ.get("VOICESTUDIO", SERVER),
                        help=f"VoiceStudio's server (default: $VOICESTUDIO or {SERVER})")
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"), help="the Godot binary (default: $GODOT or godot)")
    args = parser.parse_args(argv)

    lines = game_lines(args.godot)
    lock = json.loads(LOCK.read_text()) if LOCK.is_file() else {}
    wanted = {id: {"text": text, "voice": VOICE, **SETTINGS} for id, text in lines.items()}
    todo = [id for id in sorted(wanted)
            if lock.get(id) != wanted[id] or not (OUT / f"{id}.ogg").is_file()
            or (args.force and any(id.startswith(name) for name in args.ids))]
    if args.list:
        for id in sorted(wanted):
            print(f"{'to record' if id in todo else 'recorded':10} {id:40} {lines[id]}")
        return 0
    if args.check:
        return check(args.server, {id: text for id, text in lines.items() if (OUT / f"{id}.ogg").is_file()})

    OUT.mkdir(parents=True, exist_ok=True)
    for stale in sorted(set(lock) - set(wanted)):
        (OUT / f"{stale}.ogg").unlink(missing_ok=True)
        (OUT / f"{stale}.ogg.import").unlink(missing_ok=True)
        del lock[stale]
        print(f"deleted      {stale}")
    if todo:
        profile = voice_profile(args.server)
        for number, id in enumerate(todo, 1):
            rate, samples = record(args.server, profile, lines[id])
            clip = tidy(samples, rate)
            ogg.write(str(OUT / f"{id}.ogg"), clip, rate)
            lock[id] = wanted[id]
            LOCK.write_text(json.dumps(dict(sorted(lock.items())), indent=2) + "\n")
            print(f"recorded     {id}  {len(clip) / rate:.2f} s  ({number}/{len(todo)})  {lines[id]}")
    print(f"{len(wanted)} lines, {len(todo)} recorded")
    return 0


def check(server: str, lines: dict[str, str]) -> int:
    """Has VoiceStudio's speech recognition hear each clip; lists those that don't say their
    line (words under 80% alike, by difflib). Returns 1 if any don't."""
    misses = 0
    for id, text in sorted(lines.items()):
        heard = hear(server, OUT / f"{id}.ogg")
        likeness = difflib.SequenceMatcher(None, _words(text), _words(heard)).ratio()
        if likeness < 0.8:
            misses += 1
            print(f"MISS  {id:40} {likeness:.2f}  said {heard!r} for {text!r}")
    print(f"{len(lines)} clips heard, {misses} don't match")
    return 1 if misses else 0


def hear(server: str, path: Path) -> str:
    """What VoiceStudio's speech recognition hears in a clip."""
    rate, samples = ogg.read(str(path))
    pcm = io.BytesIO()
    with wave.open(pcm, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(np.clip(np.round(samples * 32767.0), -32768, 32767).astype("<i2").tobytes())
    boundary = uuid.uuid4().hex
    body = (f'--{boundary}\r\nContent-Disposition: form-data; name="language"\r\n\r\nen\r\n'
            f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="clip.wav"\r\n'
            f"Content-Type: audio/wav\r\n\r\n").encode() + pcm.getvalue() + f"\r\n--{boundary}--\r\n".encode()
    reply = _post(server, "/v1/audio/transcriptions", body, f"multipart/form-data; boundary={boundary}")
    return reply.get("text", "") if isinstance(reply, dict) else str(reply)


def _words(text: str) -> str:
    """Text as plain lowercase words, for comparing what was said with what was meant."""
    numbers = {"3": "three", "4": "four", "5": "five", "6": "six", "7": "seven", "8": "eight", "9": "nine",
               "10": "ten", "11": "eleven", "12": "twelve", "13": "thirteen", "14": "fourteen", "15": "fifteen"}
    words = re.sub(r"[^a-z0-9 ]", " ", text.lower()).split()
    return " ".join(numbers.get(word, word) for word in words)


def game_lines(godot: str) -> dict[str, str]:
    """Every line the announcer can call, from the game: id to the words the voice says."""
    with tempfile.TemporaryDirectory(prefix="voice-") as folder:
        out = Path(folder) / "lines.json"
        done = subprocess.run([godot, "--headless", "--path", str(ROOT / "godot"), "res://test/tools/announcer_lines.tscn",
                               "--", str(out)], capture_output=True, text=True, timeout=300)
        if done.returncode != 0 or not out.is_file():
            raise SystemExit(f"voice_tool: the game didn't list its lines:\n{done.stdout[-2000:]}{done.stderr[-2000:]}")
        return json.loads(out.read_text())


def voice_profile(server: str) -> str:
    """The id of VoiceStudio's profile named VOICE, made from ARCHETYPE if there is none."""
    try:
        profiles = _get(server, "/profiles")
    except urllib.error.URLError as error:
        raise SystemExit(f"voice_tool: VoiceStudio isn't answering at {server} ({error.reason}): start it first")
    for profile in profiles:
        if profile.get("name") == VOICE:
            return profile["id"]
    _post(server, f"/archetypes/{ARCHETYPE}/use?name={urllib.parse.quote(VOICE)}", b"", "application/json")
    for profile in _get(server, "/profiles"):
        if profile.get("name") == VOICE:
            return profile["id"]
    raise SystemExit(f"voice_tool: VoiceStudio didn't make the profile {VOICE!r}")


def record(server: str, profile: str, text: str) -> tuple[int, np.ndarray]:
    """The line said in the profile's voice: (rate, samples from -1 to 1)."""
    fields = {"text": text, "profile_id": profile, "language": "English", **{k: str(v) for k, v in SETTINGS.items()}}
    boundary = uuid.uuid4().hex
    body = b"".join(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode()
                    for name, value in fields.items()) + f"--{boundary}--\r\n".encode()
    audio = _post(server, "/generate", body, f"multipart/form-data; boundary={boundary}", raw=True)
    with wave.open(io.BytesIO(audio)) as w:
        rate, channels = w.getframerate(), w.getnchannels()
        samples = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(float) / 32767.0
    if channels > 1:
        samples = samples.reshape(-1, channels).mean(axis=1)
    return rate, samples


def tidy(samples: np.ndarray, rate: int) -> np.ndarray:
    """The speech without the silence round it, faded in and out, at one loudness."""
    window = max(int(0.01 * rate), 1)
    level = np.sqrt(np.convolve(samples * samples, np.ones(window) / window, mode="same"))
    loud = np.flatnonzero(level > 10.0 ** (SILENCE_DB / 20.0))
    if loud.size == 0:
        raise SystemExit("voice_tool: VoiceStudio gave back silence")
    start = max(loud[0] - int(LEAD_IN * rate), 0)
    end = min(loud[-1] + int(TAIL * rate), len(samples))
    clip = samples[start:end].copy()
    fade_in, fade_out = int(0.004 * rate), int(0.04 * rate)
    clip[:fade_in] *= np.linspace(0.0, 1.0, fade_in)
    clip[-fade_out:] *= np.linspace(1.0, 0.0, fade_out)
    speech = clip[level[start:end] > 10.0 ** (SILENCE_DB / 20.0)]
    gain = 10.0 ** (LOUDNESS_DB / 20.0) / max(float(np.sqrt(np.mean(speech * speech))), 1e-9)
    gain = min(gain, 10.0 ** (PEAK_DB / 20.0) / max(float(np.max(np.abs(clip))), 1e-9))
    return clip * gain


def _get(server: str, path: str):
    with urllib.request.urlopen(server + path, timeout=30) as reply:
        return json.loads(reply.read())


def _post(server: str, path: str, body: bytes, content_type: str, raw: bool = False):
    request = urllib.request.Request(server + path, data=body, method="POST", headers={"Content-Type": content_type})
    try:
        with urllib.request.urlopen(request, timeout=600) as reply:
            data = reply.read()
    except urllib.error.HTTPError as error:
        raise SystemExit(f"voice_tool: VoiceStudio refused {path}: {error.code} {error.read().decode(errors='replace')[:300]}")
    return data if raw else json.loads(data or b"null")


if __name__ == "__main__":
    sys.exit(main())
