"""The kit a sound recipe builds with: `SoundKit`, passed to the recipe as `s`.

A sound is a numpy array of samples, about -1 to 1: shape (n,) for mono or (2, n) for stereo.
The kit makes signals (oscillators, noise, clicks, envelopes), shapes them (filters,
resonators, saturation, delay, reverb) and arranges them in time; anything else is numpy
maths on the arrays. A setting that changes over time (a filter's cutoff, an oscillator's
frequency) can be a number or an array with a value for each sample.

In a recipe declared with `loop=True` everything the kit makes wraps round: noise and
oscillators hold whole periods, filters, resonators, delays and reverbs carry what rings on
past the end into the start, and sounds placed past the end come in again at the start. The
end then runs on into the start without a seam, as long as the recipe's own maths does too.
"""
from __future__ import annotations

import math
from typing import Callable, Iterable, Sequence

import numpy as np
from scipy import signal as sps

Signal = np.ndarray

# Filters whose settings change over time take new coefficients every this many samples.
BLOCK = 32
# A click (`SoundKit.impulses`) is a windowed sinc this many samples either side of its time.
CLICK_HALF_WIDTH = 16
# How long a filter rings on after its input stops, for the loops' run-in, in seconds.
FILTER_SETTLE = 0.5


class SoundKit:
    """Makes and shapes sounds at `rate` samples a second; with `loop`, everything wraps round."""

    def __init__(self, rate: int = 44100, loop: bool = False):
        self.rate = rate
        self.loop = loop

    # --- Time ---

    def samples(self, seconds: float) -> int:
        """The number of samples in `seconds`."""
        return max(int(round(seconds * self.rate)), 0)

    def length(self, x: Signal) -> float:
        """How long `x` lasts, in seconds."""
        return x.shape[-1] / self.rate

    def time(self, seconds: float) -> Signal:
        """Each sample's time from the start, in seconds."""
        return np.arange(self.samples(seconds)) / self.rate

    def silence(self, seconds: float) -> Signal:
        """`seconds` of nothing."""
        return np.zeros(self.samples(seconds))

    def line(self, seconds: float, points: Sequence[tuple[float, float]]) -> Signal:
        """A value for each sample through (time, value) points, straight between them and
        held before the first and after the last."""
        times, values = zip(*sorted(points))
        return np.interp(self.time(seconds), times, values)

    def rng(self, seed: int) -> np.random.Generator:
        """A random number generator for a recipe's own choices. The same seed gives the same
        numbers on every build."""
        return np.random.default_rng(seed)

    # --- Envelopes ---

    def decay(self, seconds: float, time: float, attack: float = 0.002) -> Signal:
        """An envelope that rises over `attack` seconds, then dies away exponentially, to 1/e
        every `time` seconds, as a struck or plucked thing does."""
        t = self.time(seconds)
        envelope = np.exp(-np.maximum(t - attack, 0.0) / time)
        if attack > 0.0:
            envelope *= np.minimum(t / attack, 1.0)
        return envelope

    def adsr(self, seconds: float, attack: float, decay: float, sustain: float, release: float) -> Signal:
        """An envelope for a note held `seconds`: up to 1 over `attack`, down to `sustain`
        over `decay`, held, then down to silence over `release` after `seconds`. It lasts
        `seconds + release`."""
        t = self.time(seconds + release)
        held = np.where(t < attack, t / max(attack, 1e-9),
                        1.0 - (1.0 - sustain) * _settle(np.clip((t - attack) / max(decay, 1e-9), 0.0, 1.0)))
        level = held[min(self.samples(seconds), len(held) - 1)] if len(held) else 0.0
        after = np.clip((t - seconds) / max(release, 1e-9), 0.0, 1.0)
        return np.where(t < seconds, held, level * (1.0 - _settle(after)))

    # --- Oscillators ---

    def phase(self, freq, seconds: float | None = None) -> Signal:
        """An oscillator's phase at each sample, in cycles, running at `freq` Hz (a number, or
        an array that also sets the length). In a loop it is nudged to hold a whole number of
        cycles, so the end joins the start."""
        f = self._control(freq, seconds)
        cycles = np.concatenate(([0.0], np.cumsum(f[:-1]))) / self.rate
        if self.loop and len(f):
            total = float(np.sum(f)) / self.rate
            if total > 0.0:
                cycles *= max(round(total), 1) / total
        return cycles

    def sine(self, freq, seconds: float | None = None, phase=0.0) -> Signal:
        """A sine wave at `freq` Hz. `phase` (in cycles, a number or an array) shifts it, which
        is also how one oscillator frequency-modulates another: `s.sine(f, phase=2 * s.sine(f * 1.4, n))`."""
        return np.sin(2.0 * np.pi * (self.phase(freq, seconds) + phase))

    def saw(self, freq, seconds: float | None = None) -> Signal:
        """A sawtooth rising from -1 to 1 each cycle, its jumps smoothed (PolyBLEP) so it
        doesn't alias: every harmonic, falling 6 dB an octave."""
        p = self.phase(freq, seconds) % 1.0
        step = self._control(freq, seconds) / self.rate
        return 2.0 * p - 1.0 - _blep(p, step)

    def square(self, freq, seconds: float | None = None, width=0.5) -> Signal:
        """A pulse wave, high for `width` of each cycle (0.5: a square, odd harmonics only),
        its jumps smoothed so it doesn't alias."""
        p = self.phase(freq, seconds) % 1.0
        step = self._control(freq, seconds) / self.rate
        width = self._control(width, None, len(p))
        out = np.where(p < width, 1.0, -1.0)
        out += _blep(p, step) - _blep((p - width) % 1.0, step)
        return out - (2.0 * width - 1.0)

    def triangle(self, freq, seconds: float | None = None) -> Signal:
        """A triangle wave: odd harmonics, falling 12 dB an octave."""
        p = self.phase(freq, seconds) % 1.0
        return 1.0 - 4.0 * np.abs(p - 0.5)

    # --- Noise and clicks ---

    def noise(self, seconds: float, seed: int, color: str = "white") -> Signal:
        """Random noise with an RMS of 0.3. `color` is white (every frequency alike, a hiss),
        pink (3 dB less each octave up, like surf and rain) or brown (6 dB less, a rumble);
        nothing below 20 Hz grows further. Made over its own length, it always loops."""
        n = self.samples(seconds)
        if n < 2:
            return np.zeros(n)
        rng = np.random.default_rng(seed)
        bins = n // 2 + 1
        spectrum = rng.normal(size=bins) + 1j * rng.normal(size=bins)
        freqs = np.fft.rfftfreq(n, 1.0 / self.rate)
        slope = {"white": 0.0, "pink": 0.5, "brown": 1.0}[color]
        spectrum *= np.where(freqs > 0.0, np.maximum(freqs, 20.0) ** -slope, 0.0)
        out = np.fft.irfft(spectrum, n)
        return out * (0.3 / max(float(np.sqrt(np.mean(out * out))), 1e-12))

    def impulses(self, seconds: float, times, amps=1.0) -> Signal:
        """Clicks at `times` (in seconds, between samples too), each `amps` high. A click holds
        no frequency the rate can't carry (a windowed sinc), so a train of them is exact in
        pitch. Filters and resonators give them a shape. In a loop, times past the end come in
        again at the start."""
        n = self.samples(seconds)
        out = np.zeros(n)
        times = np.atleast_1d(np.asarray(times, dtype=float))
        if n == 0 or times.size == 0:
            return out
        amps = np.broadcast_to(np.asarray(amps, dtype=float), times.shape)
        centre = times * self.rate
        base = np.floor(centre).astype(np.int64)
        offsets = np.arange(-CLICK_HALF_WIDTH + 1, CLICK_HALF_WIDTH + 1)
        where = base[:, None] + offsets[None, :]
        x = offsets[None, :] - (centre - base)[:, None]
        # A sinc cut at 90% of the highest frequency, in a Hann window.
        kernel = 0.9 * np.sinc(0.9 * x) * (0.5 + 0.5 * np.cos(np.pi * np.clip(x / CLICK_HALF_WIDTH, -1.0, 1.0)))
        kernel *= amps[:, None]
        if self.loop:
            np.add.at(out, where.ravel() % n, kernel.ravel())
        else:
            inside = (where >= 0) & (where < n)
            np.add.at(out, where[inside], kernel[inside])
        return out

    def dust(self, seconds: float, density: float, seed: int, amps: tuple[float, float] = (-1.0, 1.0)) -> Signal:
        """Clicks at random times, `density` a second on average, each of a random height
        between `amps`: crackle, droplets, grit."""
        rng = np.random.default_rng(seed)
        count = rng.poisson(density * seconds)
        return self.impulses(seconds, rng.uniform(0.0, seconds, count), rng.uniform(*amps, count))

    # --- Filters ---

    def lowpass(self, x: Signal, cutoff, q=0.7071, order: int = 1) -> Signal:
        """Keeps what is below `cutoff` Hz, falling 12 dB an octave above it for each `order`.
        A `q` over 0.7 makes it ring at the cutoff."""
        for _ in range(order):
            x = self._biquad(x, "lowpass", cutoff, q)
        return x

    def highpass(self, x: Signal, cutoff, q=0.7071, order: int = 1) -> Signal:
        """Keeps what is above `cutoff` Hz, falling 12 dB an octave below it for each `order`."""
        for _ in range(order):
            x = self._biquad(x, "highpass", cutoff, q)
        return x

    def bandpass(self, x: Signal, centre, q=1.0) -> Signal:
        """Keeps a band round `centre` Hz, at its own level there; the higher `q`, the narrower."""
        return self._biquad(x, "bandpass", centre, q)

    def notch(self, x: Signal, centre, q=1.0) -> Signal:
        """Takes out a band round `centre` Hz."""
        return self._biquad(x, "notch", centre, q)

    def eq(self, x: Signal, freq, gain_db, q=1.0) -> Signal:
        """Raises (or with a negative `gain_db`, lowers) a band round `freq` Hz."""
        return self._biquad(x, "peak", freq, q, gain_db)

    def lowshelf(self, x: Signal, freq, gain_db) -> Signal:
        """Raises or lowers everything below `freq` Hz by `gain_db`."""
        return self._biquad(x, "lowshelf", freq, 0.7071, gain_db)

    def highshelf(self, x: Signal, freq, gain_db) -> Signal:
        """Raises or lowers everything above `freq` Hz by `gain_db`."""
        return self._biquad(x, "highshelf", freq, 0.7071, gain_db)

    def smooth(self, x: Signal, cutoff) -> Signal:
        """A gentle low-pass (6 dB an octave above `cutoff` Hz), also for smoothing an envelope
        or another control."""
        if np.ndim(cutoff) == 0:
            pole = math.exp(-2.0 * math.pi * min(float(cutoff), self.rate * 0.49) / self.rate)
            return self._run(x, [], lambda v: sps.lfilter([1.0 - pole], [1.0, -pole], v, axis=-1))
        return self._biquad(x, "onepole", cutoff, 0.7071)

    def resonator(self, x: Signal, freq, decay, gain=1.0) -> Signal:
        """Rings at `freq` Hz, the ring dying to 1/e every `decay` seconds, as a struck bar, a
        bubble or a pipe does: a click of height 1 in gives `gain * e^(-t/decay) sin(2πft)`
        out. Several side by side make a bell or a hollow body."""
        settle = 8.0 * float(np.max(decay))
        if np.ndim(freq) == 0 and np.ndim(decay) == 0:
            b, a = _resonator_coefficients(float(freq), float(decay), self.rate)
            return gain * self._run(x, [], lambda v: sps.lfilter(b, a, v, axis=-1), settle)

        def process(v, f, d):
            return _blocks(v, f, d, lambda fb, db: _resonator_coefficients(fb, db, self.rate))
        return gain * self._run(x, [freq, decay], process, settle)

    def formants(self, x: Signal, bands: Iterable[tuple[float, float, float]]) -> Signal:
        """`x` through band-passes side by side, each (centre Hz, q, gain in dB), as a pipe, a
        hull or a mouth colours a sound."""
        out = np.zeros_like(x)
        for centre, q, gain_db in bands:
            out += self.bandpass(x, centre, q) * 10.0 ** (gain_db / 20.0)
        return out

    # --- Shaping ---

    @staticmethod
    def gain(x: Signal, db) -> Signal:
        """`x` made `db` louder (or quieter, if negative)."""
        return x * 10.0 ** (np.asarray(db) / 20.0)

    @staticmethod
    def db(value) -> "float | np.ndarray":
        """A level in dB as a factor: -6 gives about 0.5."""
        return 10.0 ** (np.asarray(value) / 20.0)

    @staticmethod
    def saturate(x: Signal, drive=1.0) -> Signal:
        """Rounds off the peaks, as an overdriven amplifier or a pipe at its limit does:
        tanh(drive * x). The more `drive`, the louder and rougher."""
        return np.tanh(x * drive)

    def fade(self, x: Signal, fade_in: float = 0.0, fade_out: float = 0.0) -> Signal:
        """`x` faded in over its first `fade_in` seconds and out over its last `fade_out`, on
        a smooth curve."""
        n = x.shape[-1]
        envelope = np.ones(n)
        for seconds, at_start in ((fade_in, True), (fade_out, False)):
            k = min(self.samples(seconds), n)
            if k > 0:
                ramp = 0.5 - 0.5 * np.cos(np.pi * (np.arange(k) + 0.5) / k)
                if at_start:
                    envelope[:k] *= ramp
                else:
                    envelope[n - k:] *= ramp[::-1]
        return x * envelope

    def delay(self, x: Signal, seconds: float, feedback: float = 0.0) -> Signal:
        """`x` late by `seconds`, its echoes coming round at `feedback` times the level each
        time (an echo, or with a short delay a comb that rings at 1/seconds Hz). The result is
        as long as `x`: in a loop the late part comes in again at the start, otherwise it is
        cut off."""
        late = max(self.samples(seconds), 1)

        def process(v):
            out = np.zeros_like(v)
            for start in range(late, v.shape[-1], late):
                end = min(start + late, v.shape[-1])
                out[..., start:end] = v[..., start - late:end - late] + feedback * out[..., start - late:end - late]
            return out
        settle = seconds * (1.0 + (math.log(1e-3) / math.log(abs(feedback)) if 0.0 < abs(feedback) < 1.0 else 1.0))
        return self._run(x, [], process, settle)

    def reverb(self, x: Signal, seconds: float = 1.2, damping: float = 0.5, mix: float = 0.25,
               predelay: float = 0.012, seed: int = 1, stereo: bool = False) -> Signal:
        """`x` with a tail that dies away to -60 dB over `seconds`, its highs dying sooner the
        more `damping` (0 to 1): the room, the hall or the open air round a sound. `mix` is
        the tail's share, `predelay` the gap before it. `stereo` gives a mono `x` a different
        tail on each side. Outside a loop the result is longer than `x` by the tail."""
        plain = SoundKit(self.rate)
        length = seconds + predelay
        t = plain.time(length)
        tails = []
        for channel in range(2 if stereo or x.ndim == 2 else 1):
            tail = plain.noise(length, seed + 7919 * channel) * np.exp(-6.9 * np.maximum(t - predelay, 0.0) / seconds)
            tail[t < predelay] = 0.0
            # The highs die away sooner: a low-pass whose cutoff falls through the tail.
            cutoff = 16000.0 * np.exp(-t * damping * 6.0 / seconds) + 600.0
            tail = plain.lowpass(tail, np.minimum(cutoff, self.rate * 0.45))
            tails.append(tail / max(float(np.sqrt(np.sum(tail * tail))), 1e-12))
        dry = x if x.ndim == 2 or len(tails) == 1 else np.stack([x, x])
        wet = np.stack([self._convolve(dry[c] if dry.ndim == 2 else dry, tails[c]) for c in range(len(tails))])
        wet = wet[0] if len(tails) == 1 else wet
        if not self.loop:
            dry = self.pad(dry, self.length(wet))
        return dry * (1.0 - mix) + wet * mix

    def convolve(self, x: Signal, response: Signal) -> Signal:
        """`x` through an impulse response: what `response` would make of a click, it makes of
        each sample. Outside a loop the result is longer by the response."""
        if x.ndim == 2:
            return np.stack([self._convolve(channel, response) for channel in x])
        return self._convolve(x, response)

    def varispeed(self, x: Signal, speed, seconds: float | None = None) -> Signal:
        """`x` played `speed` times as fast (a number, or an array of speeds over time), pitch
        and length changing together as a tape's do. It plays until `x` runs out, or for
        `seconds`; in a loop it wraps round `x`."""
        n = x.shape[-1]
        if np.ndim(speed) == 0:
            count = self.samples(seconds) if seconds is not None else int(n / max(float(speed), 1e-9))
            speeds = np.full(count, float(speed))
        else:
            speeds = np.asarray(speed, dtype=float)
        where = np.concatenate(([0.0], np.cumsum(speeds[:-1])))
        if self.loop:
            where %= n
        else:
            where = where[where <= n - 1]
        return _cubic(x, where, self.loop)

    # --- Arranging ---

    def pad(self, x: Signal, seconds: float) -> Signal:
        """`x` with silence after it, to last `seconds`."""
        extra = self.samples(seconds) - x.shape[-1]
        if extra <= 0:
            return x
        return np.concatenate([x, np.zeros(x.shape[:-1] + (extra,))], axis=-1)

    def mix(self, *sounds: Signal) -> Signal:
        """The sounds added together from the start, the shorter ones padded with silence. If
        any is stereo, so is the mix."""
        stereo = any(s.ndim == 2 for s in sounds)
        n = max(s.shape[-1] for s in sounds)
        out = np.zeros((2, n) if stereo else n)
        for s in sounds:
            out[..., :s.shape[-1]] += s
        return out

    def arrange(self, seconds: float, events: Iterable[tuple[float, Signal]]) -> Signal:
        """A sound `seconds` long with each (time, sound) of `events` starting at its time. In
        a loop, what runs past the end comes in again at the start; otherwise it is cut off."""
        events = list(events)
        n = self.samples(seconds)
        stereo = any(s.ndim == 2 for _, s in events)
        out = np.zeros((2, n) if stereo else n)
        for at, sound in events:
            start = self.samples(at)
            if self.loop:
                where = (start + np.arange(sound.shape[-1])) % n
                np.add.at(out, (slice(None), where) if stereo else where, sound)
            elif start < n:
                end = min(start + sound.shape[-1], n)
                out[..., start:end] += sound[..., :end - start]
        return out

    def pan(self, x: Signal, position) -> Signal:
        """A mono `x` placed between the left (-1) and the right (1), keeping its loudness:
        a stereo sound."""
        angle = (np.clip(position, -1.0, 1.0) + 1.0) * np.pi / 4.0
        return np.stack([x * np.cos(angle), x * np.sin(angle)])

    # --- Inside the kit ---

    def _control(self, value, seconds: float | None, n: int | None = None) -> np.ndarray:
        """A setting as a value for each sample: an array as it is, a number repeated."""
        if np.ndim(value) > 0:
            return np.asarray(value, dtype=float)
        if n is None:
            if seconds is None:
                raise ValueError("give seconds, or a value for each sample")
            n = self.samples(seconds)
        return np.full(n, float(value))

    def _run(self, x: Signal, controls: list, process: Callable, settle: float = FILTER_SETTLE) -> Signal:
        """`process(x, *controls)`. In a loop, it runs first through enough copies of `x` (and of
        the controls that change over time) to cover `settle` seconds, and only the last copy
        is kept: what rings on past the end has come round into the start."""
        n = x.shape[-1]
        if not self.loop or n == 0:
            return process(x, *controls)
        copies = 1 + max(1, math.ceil(settle * self.rate / n))
        tiled = np.concatenate([x] * copies, axis=-1)
        tiled_controls = [np.tile(c, copies) if np.ndim(c) > 0 else c for c in controls]
        return process(tiled, *tiled_controls)[..., -n:]

    def _biquad(self, x: Signal, kind: str, freq, q, gain_db=0.0) -> Signal:
        nyquist = self.rate * 0.49
        if np.ndim(freq) == 0 and np.ndim(q) == 0 and np.ndim(gain_db) == 0:
            b, a = _biquad_coefficients(kind, min(max(float(freq), 1.0), nyquist), float(q), float(gain_db), self.rate)
            return self._run(x, [], lambda v: sps.lfilter(b, a, v, axis=-1))
        n = x.shape[-1]
        controls = [self._control(freq, None, n), self._control(q, None, n), self._control(gain_db, None, n)]

        def process(v, f, qs, gains):
            return _blocks(v, np.clip(f, 1.0, nyquist), qs, lambda fb, qb, gb: _biquad_coefficients(kind, fb, qb, gb, self.rate), gains)
        return self._run(x, controls, process)

    def _convolve(self, x: Signal, response: Signal) -> Signal:
        if not self.loop:
            return sps.fftconvolve(x, response)
        n = len(x)
        folded = np.zeros(n)
        np.add.at(folded, np.arange(len(response)) % n, response)
        return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(folded), n)


def _settle(u: np.ndarray) -> np.ndarray:
    """0 to 1 over u from 0 to 1, fast at first and slowing, as a charging capacitor does."""
    return (1.0 - np.exp(-5.0 * u)) / (1.0 - math.exp(-5.0))


def _blep(p: np.ndarray, step: np.ndarray) -> np.ndarray:
    """The PolyBLEP correction for a jump at phase 0, `step` cycles a sample."""
    out = np.zeros_like(p)
    step = np.maximum(np.broadcast_to(step, p.shape), 1e-9)
    near = p < step
    u = p[near] / step[near]
    out[near] = u + u - u * u - 1.0
    near = p > 1.0 - step
    u = (p[near] - 1.0) / step[near]
    out[near] = u * u + u + u + 1.0
    return out


def _biquad_coefficients(kind: str, freq: float, q: float, gain_db: float, rate: int) -> tuple[np.ndarray, np.ndarray]:
    """The coefficients of a filter from the Audio EQ Cookbook (Robert Bristow-Johnson)."""
    w = 2.0 * math.pi * freq / rate
    cos_w, sin_w = math.cos(w), math.sin(w)
    alpha = sin_w / (2.0 * max(q, 1e-4))
    level = 10.0 ** (gain_db / 40.0)
    if kind == "onepole":
        pole = math.exp(-w)
        return np.array([1.0 - pole, 0.0, 0.0]), np.array([1.0, -pole, 0.0])
    if kind == "lowpass":
        b = [(1 - cos_w) / 2, 1 - cos_w, (1 - cos_w) / 2]
        a = [1 + alpha, -2 * cos_w, 1 - alpha]
    elif kind == "highpass":
        b = [(1 + cos_w) / 2, -(1 + cos_w), (1 + cos_w) / 2]
        a = [1 + alpha, -2 * cos_w, 1 - alpha]
    elif kind == "bandpass":
        b = [alpha, 0.0, -alpha]
        a = [1 + alpha, -2 * cos_w, 1 - alpha]
    elif kind == "notch":
        b = [1.0, -2 * cos_w, 1.0]
        a = [1 + alpha, -2 * cos_w, 1 - alpha]
    elif kind == "peak":
        b = [1 + alpha * level, -2 * cos_w, 1 - alpha * level]
        a = [1 + alpha / level, -2 * cos_w, 1 - alpha / level]
    elif kind in ("lowshelf", "highshelf"):
        root = 2.0 * math.sqrt(level) * alpha
        sign = 1.0 if kind == "lowshelf" else -1.0
        b = [level * ((level + 1) - sign * (level - 1) * cos_w + root),
             sign * 2 * level * ((level - 1) - sign * (level + 1) * cos_w),
             level * ((level + 1) - sign * (level - 1) * cos_w - root)]
        a = [(level + 1) + sign * (level - 1) * cos_w + root,
             -sign * 2 * ((level - 1) + sign * (level + 1) * cos_w),
             (level + 1) + sign * (level - 1) * cos_w - root]
    else:
        raise ValueError(f"no filter {kind!r}")
    b, a = np.array(b), np.array(a)
    return b / a[0], a / a[0]


def _resonator_coefficients(freq: float, decay: float, rate: int) -> tuple[np.ndarray, np.ndarray]:
    """A two-pole resonator whose response to a click is e^(-t/decay) sin(2πft)."""
    w = 2.0 * math.pi * min(max(freq, 1.0), rate * 0.49) / rate
    radius = math.exp(-1.0 / (max(decay, 1e-5) * rate))
    return np.array([math.sin(w), 0.0, 0.0]), np.array([1.0, -2.0 * radius * math.cos(w), radius * radius])


def _blocks(x: Signal, first: np.ndarray, second: np.ndarray, coefficients: Callable, third: np.ndarray | None = None) -> Signal:
    """Filters `x` a block at a time with coefficients from the controls' values at each
    block's middle, carrying the filter's state from block to block."""
    if x.ndim == 2:
        return np.stack([_blocks(channel, first, second, coefficients, third) for channel in x])
    out = np.empty_like(x)
    state = np.zeros(2)
    for start in range(0, len(x), BLOCK):
        end = min(start + BLOCK, len(x))
        middle = (start + end) // 2
        args = [float(first[middle]), float(second[middle])] + ([float(third[middle])] if third is not None else [])
        b, a = coefficients(*args)
        out[start:end], state = sps.lfilter(b, a, x[start:end], zi=state)
    return out


def _cubic(x: Signal, where: np.ndarray, wrap: bool) -> Signal:
    """`x` read at fractional positions `where` (Catmull-Rom)."""
    if x.ndim == 2:
        return np.stack([_cubic(channel, where, wrap) for channel in x])
    n = len(x)
    base = np.floor(where).astype(np.int64)
    u = where - base

    def at(offset):
        index = base + offset
        return x[index % n] if wrap else x[np.clip(index, 0, n - 1)]
    p0, p1, p2, p3 = at(-1), at(0), at(1), at(2)
    return p1 + 0.5 * u * (p2 - p0 + u * (2 * p0 - 5 * p1 + 4 * p2 - p3 + u * (3 * (p1 - p2) + p3 - p0)))
