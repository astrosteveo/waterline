"""A jet ski engine, recorded as loops at a few revs under load and off it, which the game
crossfades and bends in pitch between (`EngineVoice`).

Each firing is an exact click (`s.impulses`) shaped into a pressure pulse and rung through
the exhaust's resonances, with a burst of noise for the rasp of the port or valve. The
firings vary from cylinder to cylinder (no two burn quite alike, which gives the lope at the
engine's cycle rate) and from cycle to cycle, more at low revs and light load. Under them run
the intake's breathing, the water-cooled exhaust gurgling at the waterline at low revs, the
mechanical noise of the engine and the jet pump's blade whine, which follows the crankshaft
(the pump is driven straight off it).

Real numbers this follows: a two-stroke fires every cylinder once a turn and a four-stroke
every other turn, so a two-stroke twin at 7000 rpm fires 233 times a second and a four-stroke
triple at 8000 rpm 200 times; jet ski engines idle at about 1300-1800 rpm and peak at 7000-8000;
the pump's impeller has three or four blades.
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from kiln.audio import SoundKit

# What brings each part to about the firings' level at a share of 1 (measured on Tradewind).
RASP_LEVEL = 15.0
INTAKE_LEVEL = 7.0
PATTER_LEVEL = 3.5


@dataclass(frozen=True)
class Engine:
    """One engine's make-up and character. The shares are against the firings' own sound."""

    cylinders: int
    # 2 or 4: how many strokes a cylinder's cycle takes.
    strokes: int
    idle: float
    # Full throttle on the water, and where the rev limiter cuts in.
    rated: float
    limiter: float
    # The revs the loops are made at, from idle up.
    layers: tuple[float, ...]
    # The exhaust's resonances, each (Hz, q, gain dB), which colour the firings.
    exhaust: tuple[tuple[float, float, float], ...]
    # How fast a firing's pressure rises and falls: the cutoff its click is smoothed at (Hz).
    pulse_hz: float
    # The noise in each firing (the rasp of the port or valve), its centre (Hz) and its share.
    rasp_hz: float
    rasp: float
    # How differently the cylinders burn (the lope), and how much each firing varies.
    imbalance: float
    roughness: float
    # The share of firings that miss off the throttle (two-strokes stutter; four-strokes barely).
    misfire: float
    # The intake's breathing, the mechanical patter, the pump whine and the wet exhaust's
    # gurgle at low revs, as shares: 1 is about as loud as the firings at full throttle
    # (the gurgle: at idle), 0.25 about 12 dB quieter.
    intake: float
    mechanical: float
    whine: float
    gurgle: float
    blades: int
    # The hull round the engine muffles what is above this (Hz).
    hull_hz: float
    seed: int

    def firing_rate(self, rpm: float) -> float:
        """Firings a second at `rpm`."""
        return rpm / 60.0 * self.cylinders * 2.0 / self.strokes


def loops(s, engine: Engine, seconds: float = 1.2) -> dict:
    """The engine's loops: `on_<rpm>` with the throttle open and `off_<rpm>` with it shut,
    at each of its layers' revs, about `seconds` long."""
    sounds = {}
    for rpm in engine.layers:
        sounds[f"on_{int(rpm)}"] = render(s, engine, rpm, 1.0, seconds)
        sounds[f"off_{int(rpm)}"] = render(s, engine, rpm, 0.0, seconds)
    return sounds


def render(s, e: Engine, rpm: float, load: float, seconds: float, parts: bool = False):
    """One loop of the engine at `rpm` and `load` (0, throttle shut, to 1, open), holding a
    whole number of engine cycles, so its end runs on into its start. With `parts`, the parts of the
    sound unmixed, by name, for tuning."""
    rng = s.rng(e.seed * 100003 + int(rpm) * 7 + int(load * 10))
    revs = _revs(e, rpm)
    cycle = 60.0 / rpm * e.strokes / 2.0
    cycles = max(round(seconds / cycle), 2)
    length = s.samples(cycles * cycle) / s.rate
    count = cycles * e.cylinders
    gap = length / count
    times = np.arange(count) * gap + rng.normal(size=count) * gap * 0.012 * (1.5 - revs)
    return _sound(s, e, length, times, np.arange(count) % e.cylinders, rpm, load, 1.0, rng, parts)


def run(s, e: Engine, rpm: np.ndarray, load, lit, seed: int) -> np.ndarray:
    """The engine once through, its revs following `rpm` (a value for each sample), its load
    `load` and its firings happening only where `lit` (0 or 1, a number or for each sample)."""
    rng = s.rng(seed)
    length = len(rpm) / s.rate
    turned = np.cumsum(rpm / 60.0 * 2.0 / e.strokes * e.cylinders) / s.rate
    count = int(turned[-1])
    # The time each firing comes round, found where the turning passes it.
    times = np.interp(np.arange(1, count + 1), turned, np.arange(len(rpm)) / s.rate)
    times += rng.normal(size=count) * 0.0006
    return _sound(s, e, length, times, np.arange(count) % e.cylinders, rpm, load, lit, rng, False)


def start(s, e: Engine, catch: float, seconds: float, seed: int) -> np.ndarray:
    """The starter cranking the engine over for `catch` seconds, the first firings catching and
    the revs flaring, fading out over its last part as the game's loops take over."""
    t = s.time(seconds)
    crank = 330.0
    # The starter spins the engine up, slowing a little at each compression, then lets go
    # as the firings catch and the revs flare above idle.
    spin = crank * np.minimum(t / 0.07, 1.0)
    turned = np.cumsum(spin / 60.0 * e.cylinders * 2.0 / e.strokes) / s.rate
    squeeze = 0.5 - 0.5 * np.cos(2.0 * np.pi * turned)
    flare = e.idle * (1.0 + 0.6 * np.exp(-np.maximum(t - catch - 0.12, 0.0) / 0.25))
    rising = np.clip((t - catch) / 0.12, 0.0, 1.0)
    rpm = np.where(t < catch, spin * (1.0 - 0.18 * squeeze), crank + (flare - crank) * rising ** 0.7)
    lit = (t >= catch).astype(float)
    engine = run(s, e, rpm, 0.6, lit, seed)

    # The starter motor: a whine from its gears meshing with the flywheel's teeth, and the
    # brushes' hiss, both following the cranking speed; gone once it lets go.
    held = np.clip((catch + 0.06 - t) / 0.06, 0.0, 1.0) * np.minimum(t / 0.02, 1.0)
    turning = np.where(t < catch + 0.06, rpm, crank) / crank
    gears = sum(s.sine(620.0 * h * turning) * g for h, g in ((1, 1.0), (2, 0.4), (3.02, 0.2)))
    brushes = s.bandpass(s.noise(seconds, seed + 1), 3500.0, 0.8) * 0.6
    motor = (gears * 0.12 + brushes * 0.25) * held * (0.7 + 0.3 * squeeze)
    # Each compression pushes air out through the exhaust: a muffled chuff.
    chuffs = s.lowpass(s.noise(seconds, seed + 2, "pink"), 500.0) * squeeze ** 3 * (t < catch) * 1.4
    out = engine + motor + chuffs
    return s.fade(s.highpass(out, 30.0), 0.003, seconds - catch - 0.2)


def _sound(s, e: Engine, length: float, times: np.ndarray, cylinder: np.ndarray, rpm, load, lit, rng, parts: bool):
    """The engine's sound from its firing times: a value for each sample, or a number, for
    each of `rpm`, `load` and `lit`."""
    revs = _revs(e, rpm)
    at = lambda value: value if np.ndim(value) == 0 else value[np.clip((times * s.rate).astype(int), 0, len(value) - 1)]
    count = len(times)

    # Each firing's strength: its cylinder's own, varied from cycle to cycle, more so at low
    # revs and light load. Off the throttle the firings are weak and some miss.
    own = 1.0 + e.imbalance * s.rng(e.seed).normal(size=e.cylinders)
    load_then, revs_then = at(load), at(revs)
    spread = e.roughness * (1.6 - 0.9 * revs_then) * (1.6 - 0.6 * load_then)
    strength = own[cylinder] * np.clip(1.0 + spread * rng.normal(size=count), 0.15, 2.5)
    strength *= (0.25 + 0.75 * load_then) * (0.45 + 0.55 * revs_then) * at(lit)
    missed = rng.random(count) < e.misfire * (1.0 - revs_then * 0.5) * (1.0 - np.clip(load_then * 2.0, 0.0, 1.0))
    strength = np.where(missed, strength * 0.08, strength)
    clicks = s.impulses(length, times, strength)

    # The pressure pulse: a fast rise and a short fall, each firing's peaking at its strength,
    # coloured by the exhaust's resonances.
    shape = lambda k, x: k.smooth(k.smooth(x, e.pulse_hz), e.pulse_hz * 1.7)
    pulse = shape(s, clicks) / _peak_of_one(s, shape)
    firing = pulse + s.formants(pulse, e.exhaust)

    # Envelopes that follow the firings: a short one for the rasp, a long one for the breath.
    short = lambda k, x: k.smooth(x, 180.0)
    burst = np.maximum(short(s, np.abs(clicks)) / _peak_of_one(s, short), 0.0)
    long = lambda k, x: k.smooth(x, 40.0)
    breath = np.maximum(long(s, np.abs(clicks)) / _peak_of_one(s, long) / np.maximum(e.firing_rate(rpm) / 60.0, 1.0), 0.0)

    sound = {"firing": firing}
    sound["rasp"] = s.bandpass(s.noise(length, rng.integers(1 << 30)), e.rasp_hz, 0.9) * burst \
        * e.rasp * RASP_LEVEL * (0.5 + 0.5 * load)
    sound["intake"] = s.bandpass(s.noise(length, rng.integers(1 << 30), "pink"), 650.0 + 500.0 * revs, 0.7) \
        * (0.5 + breath) * e.intake * INTAKE_LEVEL * (0.2 + 0.8 * load) * (0.4 + 0.6 * revs) * lit
    # The wet exhaust at the waterline: a gurgle of bubbles with each firing at low revs,
    # gone once the craft is up and planing.
    wet = (1.0 - np.minimum(revs * 2.2, 1.0)) ** 2
    pops = s.impulses(length, times + rng.uniform(0.0, 0.8, count) * np.diff(times, append=times[-1] + 0.01 if count else 0.0),
                      strength * rng.uniform(0.3, 1.0, count))
    sound["gurgle"] = sum(s.resonator(pops * w, hz, 0.012) for hz, w in ((140.0, 1.0), (230.0, 0.7), (410.0, 0.35))) \
        * e.gurgle * wet
    sound["patter"] = s.highpass(s.noise(length, rng.integers(1 << 30)), 2500.0) * (0.4 + burst) \
        * e.mechanical * PATTER_LEVEL * (0.3 + 0.7 * revs)
    # The jet pump's whine, at the blade rate and its harmonics.
    blade = np.asarray(rpm) / 60.0 * e.blades
    sound["whine"] = sum(s.sine(blade * h, length) * g for h, g in ((1, 1.0), (2, 0.45), (3, 0.2))) \
        * e.whine * (0.15 + np.maximum(revs, 0.0)) ** 2 * (0.7 + 0.3 * load)
    if parts:
        return sound
    engine = s.lowpass(sum(sound.values()), e.hull_hz, order=2)
    # The firings push one way, so the saturation leaves an offset: the high-pass comes last.
    return s.highpass(s.saturate(engine * 0.8) / 0.8, 28.0, order=2)


def _revs(e: Engine, rpm):
    """Where `rpm` sits from idle (0) to the limiter (1); below idle while cranking."""
    return (np.asarray(rpm, dtype=float) - e.idle) / (e.limiter - e.idle)


def _peak_of_one(s, shape) -> float:
    """The peak `shape(kit, samples)` makes of a single click of height 1, to scale it by."""
    plain = SoundKit(s.rate)
    return float(np.max(np.abs(shape(plain, plain.impulses(0.05, [0.01])))))
