"""Sound recipes: the kit, the WAV files, the checks, and builds from the command line. None
of it needs Blender."""
import json

import numpy as np
import pytest

from kiln import cli
from kiln.audio import wav
from kiln.audio.build import build_sound
from kiln.audio.kit import SoundKit
from kiln.recipe import Recipe, SoundSpec

RATE = 44100


def level_between(x, low, high, rate=RATE):
    """The share of `x`'s energy between `low` and `high` Hz."""
    power = np.abs(np.fft.rfft(x)) ** 2
    freqs = np.fft.rfftfreq(len(x), 1.0 / rate)
    return power[(freqs >= low) & (freqs < high)].sum() / power.sum()


def strongest(x, rate=RATE):
    """The frequency with the most energy in `x`."""
    spectrum = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    return np.fft.rfftfreq(len(x), 1.0 / rate)[np.argmax(spectrum)]


def seam_ok(x):
    """True when the step from the last sample to the first is like the steps inside."""
    return abs(x[0] - x[-1]) <= np.percentile(np.abs(np.diff(x)), 99.9) * 1.5 + 0.002


def test_noise_is_seeded_coloured_and_loops():
    s = SoundKit()
    white, pink, brown = (s.noise(1.0, 5, color) for color in ("white", "pink", "brown"))
    assert np.array_equal(white, s.noise(1.0, 5))
    assert not np.array_equal(white, s.noise(1.0, 6))
    assert np.sqrt(np.mean(white ** 2)) == pytest.approx(0.3)
    # Each colour holds less of its energy in the highs than the last.
    highs = [level_between(x, 5000, 20000) for x in (white, pink, brown)]
    assert highs[0] > highs[1] > highs[2]
    assert abs(white.mean()) < 1e-9
    assert seam_ok(brown)


def test_oscillators_hold_whole_cycles_in_a_loop():
    looped = SoundKit(loop=True)
    for wave in (looped.sine(441.3, 0.37), looped.saw(97.1, 0.37), looped.square(61.7, 0.37), looped.triangle(80.9, 0.37)):
        assert seam_ok(wave)
    # Outside a loop the frequency is exact.
    assert strongest(SoundKit().sine(441.3, 2.0)) == pytest.approx(441.3, abs=0.5)
    # A sawtooth's harmonics fall away; the smoothing keeps the highest from folding back.
    saw = SoundKit().saw(1000, 1.0)
    assert level_between(saw, 900, 1100) > level_between(saw, 1900, 2100) > level_between(saw, 2900, 3100)


def test_clicks_land_between_samples_and_ring_a_resonator():
    s = SoundKit()
    at = 0.01 + 0.25 / RATE
    click = s.impulses(0.05, [at])
    centre = np.sum(np.arange(len(click)) * click ** 2) / np.sum(click ** 2)
    assert centre == pytest.approx(at * RATE, abs=0.05)
    ring = s.resonator(s.impulses(0.5, [0.0]), 1000.0, 0.05)
    assert strongest(ring) == pytest.approx(1000.0, abs=3.0)
    # After one decay time the ring is 1/e as loud.
    early = np.abs(ring[100:300]).max()
    late = np.abs(ring[100 + int(0.05 * RATE):300 + int(0.05 * RATE)]).max()
    assert late / early == pytest.approx(np.exp(-1.0), rel=0.05)


def test_filters_cut_where_they_say_and_follow_a_moving_cutoff():
    s = SoundKit()
    noise = s.noise(1.0, 2)
    low = s.lowpass(noise, 1000.0, order=2)
    assert level_between(low, 0, 1000) > 0.9
    high = s.highpass(noise, 4000.0, order=2)
    assert level_between(high, 0, 2000) < 0.01
    band = s.bandpass(noise, 2000.0, q=8.0)
    assert strongest(s.smooth(np.abs(np.fft.rfft(band)), 50.0)) >= 0  # runs on any array
    assert level_between(band, 1500, 2700) > 0.6
    # A sweep from 200 Hz to 8 kHz: the first half is darker than the second.
    swept = s.lowpass(noise, s.line(1.0, [(0.0, 200.0), (1.0, 8000.0)]))
    half = len(swept) // 2
    assert level_between(swept[:half], 3000, 20000) < level_between(swept[half:], 3000, 20000)


def test_loops_carry_what_rings_on_into_the_start():
    looped = SoundKit(loop=True)
    # An event near the end comes in again at the start.
    bang = looped.arrange(0.5, [(0.49, np.ones(int(0.02 * RATE)))])
    assert bang[0] == 1.0 and bang[int(0.005 * RATE)] == 1.0
    for x in (looped.lowpass(looped.noise(0.4, 1), 300.0, q=6.0),
              looped.resonator(looped.dust(0.4, 30, 3), 600.0, 0.2),
              looped.reverb(looped.noise(0.4, 4), 1.5),
              looped.delay(looped.noise(0.4, 8), 0.13, feedback=0.6)):
        assert len(x) == looped.samples(0.4)
        assert seam_ok(x)
    # Outside a loop, the reverb's tail makes the sound longer.
    plain = SoundKit()
    assert len(plain.reverb(plain.noise(0.4, 4), 1.0)) > plain.samples(1.3)


def test_envelopes_and_fades():
    s = SoundKit()
    env = s.adsr(0.3, 0.01, 0.1, 0.5, 0.2)
    assert len(env) == s.samples(0.5)
    assert env[0] == 0.0 and env[s.samples(0.01)] == pytest.approx(1.0, abs=0.01)
    assert env[s.samples(0.29)] == pytest.approx(0.5, abs=0.01) and env[-1] < 1e-3
    faded = s.fade(np.ones(1000), 0.002, 0.002)
    assert faded[0] < 0.01 and faded[-1] < 0.01 and faded[500] == 1.0
    tape = s.varispeed(s.sine(100.0, 1.0), 2.0)
    assert len(tape) == pytest.approx(s.samples(0.5), abs=2)
    assert strongest(tape) == pytest.approx(200.0, abs=2.0)


def test_wav_round_trip_with_loop_points(tmp_path):
    mono = np.sin(np.linspace(0, 20 * np.pi, 1000)) * 0.5
    wav.write(str(tmp_path / "a.wav"), mono, RATE, loop=True)
    rate, back, loop = wav.read(str(tmp_path / "a.wav"))
    assert rate == RATE and loop == (0, 1000)
    assert np.allclose(back, mono, atol=1 / 32767)
    # The loop's start runs on after its end, for a player reading ahead.
    data = (tmp_path / "a.wav").read_bytes()
    pcm = np.frombuffer(data[data.index(b"data") + 8:], dtype="<i2")
    assert len(pcm) == 1000 + wav.RUN_ON and np.array_equal(pcm[1000:], pcm[:wav.RUN_ON])
    stereo = np.stack([mono, -mono])
    wav.write(str(tmp_path / "b.wav"), stereo, 22050, loop=False)
    rate, back, loop = wav.read(str(tmp_path / "b.wav"))
    assert rate == 22050 and loop is None and back.shape == (2, 1000)
    assert np.allclose(back[1], -mono, atol=1 / 32767)


def build(spec: SoundSpec, make, tmp_path):
    return build_sound(Recipe("sound", spec, make), str(tmp_path / "out" / "thing"), True, str(tmp_path / "report"))


def test_the_build_scales_sounds_together_and_names_their_files(tmp_path):
    def make(s):
        tone = s.fade(s.sine(440.0, 0.5), 0.005, 0.05)
        return {"loud": tone, "quiet": tone * 0.25}
    report = build(SoundSpec(peak=-3.0), make, tmp_path)
    assert report["problems"] == []
    assert report["sounds"]["loud"]["peak_db"] == pytest.approx(-3.0, abs=0.01)
    assert report["sounds"]["quiet"]["peak_db"] == pytest.approx(-3.0 - 12.04, abs=0.05)
    assert [p.split("/")[-1] for p in report["outputs"]] == ["thing_loud.wav", "thing_quiet.wav"]
    assert (tmp_path / "out" / "thing_quiet.wav").is_file()
    assert (tmp_path / "report" / "preview.png").is_file()


@pytest.mark.parametrize("spec, make, problem", [
    (SoundSpec(), lambda s: s.fade(s.sine(100, 0.5), 0.01, 0.01) + 0.2, "off zero"),
    (SoundSpec(), lambda s: s.fade(s.sine(100, 0.5, phase=0.25), 0.0, 0.01), "starts with a click"),
    (SoundSpec(), lambda s: s.fade(s.sine(100, 0.5), 0.01, 0.0), "fade it out"),
    (SoundSpec(loop=True), lambda s: s.line(0.5, [(0.0, -0.5), (0.5, 0.5)]), "where it loops"),
    (SoundSpec(seconds=(1.0, 2.0)), lambda s: s.fade(s.sine(100, 0.5), 0.01, 0.01), "outside 1.0-2.0 s"),
    (SoundSpec(peak=None), lambda s: s.fade(s.sine(100, 0.5) * 2.0, 0.01, 0.01), "past full scale"),
    (SoundSpec(), lambda s: np.full(100, np.nan), "aren't numbers"),
    (SoundSpec(channels=2), lambda s: s.sine(100, 0.5), "stereo"),
    (SoundSpec(), lambda s: [0.0, 0.1], "not an array"),
    (SoundSpec(), lambda s: s.silence(0.5), "silent"),
])
def test_the_checks_catch_broken_sounds(spec, make, problem, tmp_path):
    report = build(spec, make, tmp_path)
    assert any(problem in p for p in report["problems"]), report["problems"]
    assert not (tmp_path / "out" / "thing.wav").exists()


RECIPES = {
    "audio/bell.py": '''
from kiln import sound
from audio._partials import PARTIALS

@sound(seconds=(0.5, 3.0))
def build(s):
    click = s.impulses(2.0, [0.001])
    return s.fade(sum(s.resonator(click, 880.0 * r, 0.4 / r, g) for r, g in PARTIALS), 0.0, 0.05)
''',
    "audio/_partials.py": "PARTIALS = [(1.0, 1.0), (2.76, 0.4), (5.4, 0.2)]\n",
    "audio/surf.py": '''
from kiln import sound

@sound(loop=True, peak=-6.0)
def build(s):
    return {"near": s.lowpass(s.noise(1.0, 1, "pink"), 3000.0), "far": s.lowpass(s.noise(1.0, 2, "pink"), 800.0) * 0.5}
''',
}


def test_kiln_builds_sounds_without_blender(tmp_path, capsys):
    root = tmp_path / "art"
    for name, text in RECIPES.items():
        (root / name).parent.mkdir(parents=True, exist_ok=True)
        (root / name).write_text(text)
    (root / "kiln.toml").write_text('output = "out"\nreports = "reports"\n')
    run = lambda *args: cli.main(["--project", str(root), "--blender", str(tmp_path / "no-blender"), *args])

    assert run("build") == 0
    out = capsys.readouterr().out
    assert "ok           audio/bell  1 sound, 2.00 s, peak -1.0 dBFS" in out
    assert "ok           audio/surf  2 sounds, 1.00 s, peak -6.0 dBFS, loops" in out
    lock = json.loads((root / "kiln.lock.json").read_text())
    assert lock["audio/surf"]["outputs"] == ["out/audio/surf_near.wav", "out/audio/surf_far.wav"]
    assert lock["audio/surf"]["seconds"] == {"near": 1.0, "far": 1.0}
    assert "numpy" in lock["audio/bell"]["tools"]
    rate, near, loop = wav.read(str(root / "out" / "audio" / "surf_near.wav"))
    assert rate == 44100 and loop == (0, 44100) and len(near) == 44100
    bell = (root / "out" / "audio" / "bell.wav").read_bytes()

    assert run("build") == 0
    assert "up to date   audio/bell" in capsys.readouterr().out
    # Shared code the recipe imports rebuilds it; the same inputs give the same file.
    (root / "audio" / "_partials.py").write_text("PARTIALS = [(1.0, 1.0), (2.76, 0.4), (5.4, 0.2)]  # same\n")
    assert run("build") == 0
    out = capsys.readouterr().out
    assert "ok           audio/bell" in out and "up to date   audio/surf" in out
    assert (root / "out" / "audio" / "bell.wav").read_bytes() == bell
    assert run("status") == 0
    assert "up to date   audio/bell" in capsys.readouterr().out

    # Cut off while it still rings, it fails and nothing is written.
    (root / "audio" / "bell.py").write_text(RECIPES["audio/bell.py"].replace("2.0", "0.3").replace("0.05)", "0.0)"))
    assert run("build", "audio/bell") == 1
    assert "fade it out" in capsys.readouterr().out
    assert (root / "out" / "audio" / "bell.wav").read_bytes() == bell
