"""The game's band: instruments built with kiln's kit, and a way to write a song down as lines
of notes over bars, which `Song.render` mixes into a stereo loop.

Notes are named as on a keyboard: `C4` is middle C and `A4` 440 Hz, `#` and `b` sharpen and
flatten. A line is written a step at a time with a `|` between bars: a note starts on its
step, `-` holds the note before for another step, and `.` is a rest. A drum line marks its
hits with `X` (accented), `x` and `g` (a ghost note, quiet). Chords are named as in a lead
sheet (`Am7`, `Fmaj7`, `G/B`, `C7sus4`), a bar's worth between each `|`, two in a bar
sharing it.

Instruments are functions of the kit (always out of loop mode, so a note is made once
through) and of the note's pitch, length and velocity; they ring on past the note and fade.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

import numpy as np

from kiln.audio import SoundKit

PITCHES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
SHAPES = {
    "": (0, 4, 7), "m": (0, 3, 7), "7": (0, 4, 7, 10), "maj7": (0, 4, 7, 11), "m7": (0, 3, 7, 10),
    "6": (0, 4, 7, 9), "m6": (0, 3, 7, 9), "9": (0, 4, 7, 10, 14), "m9": (0, 3, 7, 10, 14),
    "maj9": (0, 4, 7, 11, 14), "add9": (0, 4, 7, 14), "sus2": (0, 2, 7), "sus4": (0, 5, 7),
    "7sus4": (0, 5, 7, 10), "dim": (0, 3, 6),
}
VELOCITY = {"X": 1.0, "x": 0.75, "g": 0.35}


def midi(note) -> int:
    """A note's MIDI number (`C4` is 60)."""
    if isinstance(note, (int, np.integer)):
        return int(note)
    found = re.fullmatch(r"([A-G])([#b]?)(-?\d)", note)
    if found is None:
        raise ValueError(f"no note {note!r}")
    letter, accidental, octave = found.groups()
    return 12 * (int(octave) + 1) + PITCHES[letter] + {"#": 1, "b": -1, "": 0}[accidental]


def hz(note) -> float:
    """A note's frequency, tuned to A4 at 440 Hz."""
    return 440.0 * 2.0 ** ((midi(note) - 69) / 12.0)


def chord(name: str) -> tuple[int, tuple[int, ...], int]:
    """A chord's root (as a pitch class, 0 for C), the intervals over it, and its bass note."""
    found = re.fullmatch(r"([A-G][#b]?)([^/]*)(?:/([A-G][#b]?))?", name)
    if found is None or found[2] not in SHAPES:
        raise ValueError(f"no chord {name!r}")
    root = midi(found[1] + "0") % 12
    return root, SHAPES[found[2]], (midi(found[3] + "0") % 12 if found[3] else root)


def voicing(name: str, around: float = 62.0, previous: list[int] | None = None) -> list[int]:
    """The chord's notes as MIDI numbers, close together near `around`, moving each voice as
    little as it can from `previous` (voice leading)."""
    root, shape, _ = chord(name)
    classes = [(root + i) % 12 for i in shape]
    best, best_cost = None, float("inf")
    for first in range(len(classes)):
        order = classes[first:] + classes[:first]
        for low in range(int(around) - 12, int(around) + 1):
            if low % 12 != order[0]:
                continue
            notes = [low]
            for pc in order[1:]:
                notes.append(notes[-1] + (pc - notes[-1]) % 12 or 12)
            if previous and len(previous) == len(notes):
                cost = sum(abs(a - b) for a, b in zip(sorted(previous), notes))
            else:
                cost = abs(float(np.mean(notes)) - around) * len(notes)
            if cost < best_cost:
                best, best_cost = notes, cost
    return best


def bass_note(name: str, octave: int = 2) -> int:
    """The chord's bass note in `octave`."""
    return 12 * (octave + 1) + chord(name)[2]


# --- Drums ---

def kick(k: SoundKit, velocity: float = 1.0) -> np.ndarray:
    """A deep, round kick: a sine falling fast in pitch, and a click for its beater."""
    seconds = 0.5
    t = k.time(seconds)
    body = k.sine(46.0 + 120.0 * np.exp(-t / 0.032), seconds) * np.exp(-t / 0.14)
    click = k.lowpass(k.noise(seconds, 101), 5000.0) * np.exp(-t / 0.003) * 0.45
    return k.fade((body + click) * velocity, 0.0005, 0.1)


def snare(k: SoundKit, velocity: float = 1.0) -> np.ndarray:
    """A snare: the drum's tone, the rattle of its wires and the crack of the stick."""
    seconds = 0.35
    t = k.time(seconds)
    tone = k.sine(185.0 * (1.0 + 0.4 * np.exp(-t / 0.012)), seconds) * np.exp(-t / 0.06) * 0.7
    wires = k.bandpass(k.noise(seconds, 102), 4200.0, 0.5) * np.exp(-t / 0.09) * 1.7
    crack = k.highpass(k.noise(seconds, 103), 2000.0) * np.exp(-t / 0.01) * 0.8
    return k.fade((tone + wires + crack) * velocity, 0.0003, 0.1)


def rim(k: SoundKit, velocity: float = 1.0) -> np.ndarray:
    """A rimshot's click, for quieter grooves."""
    seconds = 0.12
    strike = k.impulses(seconds, [0.0008])
    body = k.resonator(strike, 1650.0, 0.012) + k.resonator(strike, 520.0, 0.02, 0.6)
    return k.fade(body * 0.6 * velocity, 0.0, 0.04)


def clap(k: SoundKit, velocity: float = 1.0) -> np.ndarray:
    """A hand clap: a few hands a moment apart, and the room after."""
    seconds = 0.4
    t = k.time(seconds)
    hands = sum(np.exp(-np.maximum(t - d, 0.0) / 0.004) * (t >= d) for d in (0.0, 0.009, 0.019))
    room = np.exp(-np.maximum(t - 0.028, 0.0) / 0.09) * (t >= 0.028)
    return k.fade(k.bandpass(k.noise(seconds, 104), 1300.0, 0.9) * (hands * 0.8 + room) * 2.4 * velocity, 0.0003, 0.12)


def hat(k: SoundKit, velocity: float = 1.0, open: bool = False) -> np.ndarray:
    """A hi-hat, closed or open: six detuned square waves (as the old drum machines made a
    cymbal's clang) and hiss, high-passed."""
    seconds = 0.5 if open else 0.12
    t = k.time(seconds)
    metal = sum(k.square(f, seconds) for f in (205.3, 304.4, 369.6, 522.7, 540.0, 800.0)) / 6.0
    clang = k.highpass(k.bandpass(metal, 9000.0, 1.2), 7000.0) * 1.5
    hiss = k.highpass(k.noise(seconds, 105), 8000.0) * 0.5
    return k.fade((clang + hiss) * np.exp(-t / (0.16 if open else 0.022)) * velocity, 0.0002, 0.15 if open else 0.04)


def open_hat(k: SoundKit, velocity: float = 1.0) -> np.ndarray:
    """An open hi-hat."""
    return hat(k, velocity, open=True)


def crash(k: SoundKit, velocity: float = 1.0) -> np.ndarray:
    """A crash cymbal, for the top of a section."""
    seconds = 1.8
    t = k.time(seconds)
    metal = sum(k.square(f, seconds) for f in (241.0, 356.3, 431.9, 577.0, 618.2, 911.0)) / 6.0
    wash = k.highpass(k.bandpass(metal, 7000.0, 0.7), 4000.0) + k.highpass(k.noise(seconds, 107), 5000.0) * 0.7
    return k.fade(wash * np.exp(-t / 0.55) * np.minimum(t / 0.002, 1.0) * 0.9 * velocity, 0.0, 0.6)


def shaker(k: SoundKit, velocity: float = 1.0) -> np.ndarray:
    """A shaker: a short, soft burst of seeds."""
    seconds = 0.09
    t = k.time(seconds)
    envelope = np.minimum(t / 0.006, 1.0) * np.exp(-np.maximum(t - 0.006, 0.0) / 0.025)
    return k.fade(k.bandpass(k.noise(seconds, 108), 7000.0, 1.0) * envelope * 1.2 * velocity, 0.0, 0.02)


def conga(k: SoundKit, velocity: float = 1.0, high: bool = False) -> np.ndarray:
    """A conga's open tone, its skin dropping a little in pitch, and the slap of the hand."""
    seconds = 0.35
    t = k.time(seconds)
    freq = (330.0 if high else 220.0) * (1.0 + 0.12 * np.exp(-t / 0.02))
    skin = k.sine(freq, seconds) * np.exp(-t / 0.11)
    slap = k.bandpass(k.noise(seconds, 109), 2200.0, 1.0) * np.exp(-t / 0.006) * 0.8
    return k.fade((skin + slap) * 0.8 * velocity, 0.0005, 0.08)


def high_conga(k: SoundKit, velocity: float = 1.0) -> np.ndarray:
    """A higher conga."""
    return conga(k, velocity, high=True)


# --- Pitched ---

def bass(k: SoundKit, freq: float, seconds: float, velocity: float = 0.8) -> np.ndarray:
    """A synth bass: a sawtooth and a square through a low-pass that snaps shut after the
    attack, so each note plucks."""
    tail = 0.08
    total = seconds + tail
    t = k.time(total)
    wave = k.saw(freq, total) * 0.6 + k.square(freq, total) * 0.3
    cutoff = 160.0 + (700.0 + 2400.0 * velocity) * np.exp(-t / 0.08)
    tone = k.lowpass(wave, cutoff, q=1.3)
    return k.saturate(tone * k.adsr(seconds, 0.003, 0.15, 0.7, tail) * 1.8) / 1.8 * velocity


def slap(k: SoundKit, freq: float, seconds: float, velocity: float = 0.8) -> np.ndarray:
    """A slapped bass string: bright for a moment as the thumb strikes it, then round."""
    tail = 0.06
    total = seconds + tail
    t = k.time(total)
    string = k.saw(freq, total) * 0.55 + k.sine(freq, total) * 0.6
    cutoff = 280.0 + (2500.0 + 4000.0 * velocity) * np.exp(-t / 0.035)
    tone = k.lowpass(string, cutoff, q=1.6)
    thumb = k.highpass(k.noise(total, 110), 1500.0) * np.exp(-t / 0.004) * 0.25
    return k.saturate((tone * k.adsr(seconds, 0.002, 0.2, 0.55, tail) + thumb) * 1.5) / 1.5 * velocity


def epiano(k: SoundKit, freq: float, seconds: float, velocity: float = 0.7) -> np.ndarray:
    """An electric piano (frequency modulation, as the 80s keyboards made it): bell-like at
    the strike, mellow as it sustains, a little tine ping on top."""
    tail = 0.4
    total = seconds + tail
    t = k.time(total)
    depth = (0.06 + 0.22 * velocity) * np.exp(-t / 0.45) + 0.02
    body = k.sine(freq, total, phase=depth * k.sine(freq, total))
    tine = k.sine(freq * 14.0, total) * np.exp(-t / 0.012) * 0.06 * velocity
    return (body + tine) * k.adsr(seconds, 0.002, 1.4, 0.35, tail) * velocity * 0.5


def chord_epiano(k: SoundKit, freqs: list[float], seconds: float, velocity: float = 0.7) -> np.ndarray:
    """A chord on the electric piano."""
    return k.mix(*(epiano(k, f, seconds, velocity) for f in freqs)) / np.sqrt(len(freqs))


def pad(k: SoundKit, freqs: list[float], seconds: float, velocity: float = 0.6) -> np.ndarray:
    """A warm pad: three slightly detuned sawtooths a note, beating against each other,
    through a low-pass that drifts. Swells in and out slowly."""
    tail = 1.0
    total = seconds + tail
    t = k.time(total)
    voices = sum(k.saw(f * d, total) for f in freqs for d in (0.9965, 1.0, 1.0035)) / (3.0 * np.sqrt(len(freqs)))
    cutoff = 1100.0 + 450.0 * np.sin(2.0 * np.pi * 0.17 * t)
    return k.lowpass(voices, cutoff, q=0.8) * k.adsr(seconds, 0.45, 0.6, 0.85, tail) * velocity * 0.6


def steelpan(k: SoundKit, freq: float, seconds: float, velocity: float = 0.8) -> np.ndarray:
    """A steel pan's note: a tuned dent in a drum's head ringing in near-harmonic modes (the
    octave and the twelfth are tuned in), struck with a rubber mallet."""
    total = max(seconds, 0.15) + 0.9
    t = k.time(total)
    strike = k.impulses(total, [0.0012])
    modes = ((1.0, 1.0, 0.5), (2.0, 0.55, 0.32), (3.0, 0.25, 0.18), (4.02, 0.1, 0.1), (5.1, 0.05, 0.06))
    ring = sum(k.resonator(strike, freq * ratio, decay, level) for ratio, level, decay in modes)
    mallet = k.lowpass(k.noise(total, 111), 2400.0) * np.exp(-t / 0.005) * 0.25
    # Let go, the note is damped.
    damped = np.where(t < seconds + 0.25, 1.0, np.exp(-(t - seconds - 0.25) / 0.12))
    return k.fade((ring * 0.3 + mallet) * damped * velocity, 0.0, 0.1)


def lead(k: SoundKit, freq: float, seconds: float, velocity: float = 0.8) -> np.ndarray:
    """A synth lead: two detuned sawtooths and a square an octave down, bright at the attack,
    taking a vibrato as it holds."""
    tail = 0.18
    total = seconds + tail
    t = k.time(total)
    wobble = 1.0 + 0.006 * np.sin(2.0 * np.pi * 5.5 * t) * np.clip((t - 0.2) / 0.25, 0.0, 1.0)
    f = freq * wobble
    wave = k.saw(f * 0.997) + k.saw(f * 1.003) + 0.4 * k.square(f * 0.5)
    cutoff = 1300.0 + 3000.0 * velocity * np.exp(-t / 0.25) + 500.0 * np.minimum(t / 0.05, 1.0)
    return k.lowpass(wave, cutoff, q=0.9) * k.adsr(seconds, 0.008, 0.25, 0.7, tail) * velocity * 0.35


def brass(k: SoundKit, freqs: list[float], seconds: float, velocity: float = 0.8) -> np.ndarray:
    """A brass section's stab: sawtooths for each player, a little apart, the filter opening as
    the lips catch."""
    tail = 0.12
    total = seconds + tail
    t = k.time(total)
    wave = sum(k.saw(f, total) + 0.6 * k.saw(f * 1.005, total) for f in freqs) / (1.6 * np.sqrt(len(freqs)))
    cutoff = 700.0 + 3600.0 * velocity * np.exp(-t / 0.1) * np.minimum(t / 0.012, 1.0) + 900.0 * np.minimum(t / 0.04, 1.0)
    return k.lowpass(wave, cutoff) * k.adsr(seconds, 0.012, 0.12, 0.6, tail) * velocity * 0.5


def pluck(k: SoundKit, freq: float, seconds: float, velocity: float = 0.7) -> np.ndarray:
    """A short plucked synth note for arpeggios: a narrow pulse through a filter that closes
    at once."""
    total = seconds + 0.25
    t = k.time(total)
    wave = k.square(freq, total, width=0.3) * 0.6 + k.saw(freq * 2.0, total) * 0.15
    cutoff = 350.0 + 4200.0 * velocity * np.exp(-t / 0.06)
    envelope = np.minimum(t / 0.002, 1.0) * np.exp(-t / 0.2)
    return k.fade(k.lowpass(wave, cutoff, q=1.1) * envelope * velocity * 0.5, 0.0, 0.08)


def marimba(k: SoundKit, freq: float, seconds: float, velocity: float = 0.7) -> np.ndarray:
    """A marimba's bar: its note, and the overtones its arched cut tunes in, dying fast."""
    total = 0.9
    strike = k.impulses(total, [0.001])
    modes = ((1.0, 1.0, 0.35), (3.93, 0.35, 0.08), (9.2, 0.1, 0.03))
    ring = sum(k.resonator(strike, freq * ratio, decay, level) for ratio, level, decay in modes)
    return k.fade(ring * 0.4 * velocity, 0.0, 0.2)


# --- Writing a song down ---

@dataclass
class Part:
    """One instrument's track in the mix."""

    gain_db: float = 0.0
    # -1 left to 1 right.
    pan: float = 0.0
    # The shares sent to the reverb and the echo.
    reverb: float = 0.15
    delay: float = 0.0
    # Spreads the part across the speakers (0 to 1: the right side up to 15 ms late).
    width: float = 0.0
    # How far each kick ducks it (0 to 1), so it pumps with the beat.
    pump: float = 0.0
    events: list = field(default_factory=list)


class Song:
    """A song `bars` long at `bpm`, a bar of four beats, written down part by part and mixed
    by `render`. `swing` delays every other sixteenth by that share of a sixteenth."""

    def __init__(self, s: SoundKit, bpm: float, bars: int, swing: float = 0.0, seed: int = 1):
        self.s = s
        self.k = SoundKit(s.rate)
        self.bpm = bpm
        self.bars = bars
        self.beat = 60.0 / bpm
        self.seconds = bars * 4 * self.beat
        self.swing = swing
        self.rng = s.rng(seed)
        self.parts: dict[str, Part] = {}
        self.kicks: list[float] = []
        self._made: dict = {}

    def part(self, name: str, **settings) -> Part:
        """The part called `name`, made with `settings` (see `Part`) the first time."""
        if name not in self.parts:
            self.parts[name] = Part(**settings)
        return self.parts[name]

    def time(self, bar: int, sixteenth: float) -> float:
        """When a bar's sixteenth (from 0) falls, bars counted from 1, with the swing."""
        offbeat = self.swing if int(sixteenth) % 2 == 1 and sixteenth == int(sixteenth) else 0.0
        return ((bar - 1) * 16 + sixteenth + offbeat) * self.beat / 4.0

    def hits(self, part: str, bars, pattern: str, drum, humanize: float = 0.003) -> None:
        """A drum's hits in each of `bars`, a sixteenth a character (`X`, `x`, `g`; `.` for none)."""
        steps = pattern.replace(" ", "").replace("|", "")
        sound = self._once((drum.__name__,), lambda: drum(self.k, 1.0))
        for bar in bars:
            for step, mark in enumerate(steps):
                if mark in VELOCITY:
                    at = self.time(bar + step // 16, step % 16) + self.rng.normal() * humanize
                    level = VELOCITY[mark] * (1.0 + 0.05 * self.rng.normal())
                    self.part(part).events.append((max(at, 0.0), sound * level))
                    if part == "kick":
                        self.kicks.append(at)

    def line(self, part: str, bar: int, text: str, instrument, steps: int = 8, velocity: float = 0.8,
             transpose: int = 0, legato: float = 0.92) -> None:
        """A line of single notes from `bar` on, `steps` to a bar."""
        for start, length, note in _parse(text, steps):
            seconds = length * 16 / steps * self.beat / 4.0 * legato
            level = velocity * (1.0 + 0.04 * self.rng.normal())
            sound = self._once((instrument.__name__, midi(note) + transpose, round(seconds, 3), round(level, 2)),
                               lambda: instrument(self.k, hz(midi(note) + transpose), seconds, round(level, 2)))
            self.part(part).events.append((self.time(bar, start * 16 / steps), sound))

    def chords(self, part: str, bar: int, progression: str, instrument, rhythm: str | None = None,
               around: float = 62.0, velocity: float = 0.7) -> None:
        """The chords of `progression` from `bar` on, voiced close and led smoothly from one to
        the next. Each is held for its share of the bar, or played on `rhythm` (a sixteenth a
        character, `x` to strike and `-` to hold, repeated each bar)."""
        previous = None
        for offset, bar_text in enumerate(progression.split("|")):
            names = bar_text.split()
            for index, name in enumerate(names):
                notes = voicing(name, around, previous)
                previous = notes
                share = 16 // len(names)
                first = index * share
                strikes = _strikes(rhythm, first, first + share) if rhythm else [(first, share)]
                for step, length in strikes:
                    seconds = length * self.beat / 4.0 * 0.95
                    level = velocity * (1.0 + 0.04 * self.rng.normal())
                    sound = self._once((instrument.__name__, tuple(notes), round(seconds, 3), round(level, 2)),
                                       lambda: instrument(self.k, [hz(n) for n in notes], seconds, round(level, 2)))
                    self.part(part).events.append((self.time(bar + offset, step), sound))

    def arpeggio(self, part: str, bar: int, progression: str, instrument, order: str = "0 1 2 1",
                 steps: int = 16, around: float = 69.0, velocity: float = 0.65) -> None:
        """The chords of `progression` broken into single notes, `steps` to a bar, taking the
        chord's notes in `order` (0 the lowest; past the top, the next octave up)."""
        picks = [int(i) for i in order.split()]
        previous = None
        for offset, bar_text in enumerate(progression.split("|")):
            names = bar_text.split()
            for step in range(steps):
                name = names[step * len(names) // steps]
                notes = voicing(name, around, previous)
                previous = notes
                pick = picks[step % len(picks)]
                note = notes[pick % len(notes)] + 12 * (pick // len(notes))
                seconds = 16 / steps * self.beat / 4.0 * 0.9
                sound = self._once((instrument.__name__, note, round(seconds, 3)),
                                   lambda: instrument(self.k, hz(note), seconds, velocity))
                level = 1.0 + 0.06 * self.rng.normal()
                self.part(part).events.append((self.time(bar + offset, step * 16 / steps), sound * level))

    def bassline(self, part: str, bar: int, progression: str, pattern: str, instrument, octave: int = 2,
                 velocity: float = 0.85) -> None:
        """A bass line from the chords: each bar played on `pattern`, a sixteenth a character:
        `r` the chord's bass note, `o` it an octave up, `5` its fifth, `-` hold, `.` rest."""
        steps = pattern.replace(" ", "")
        for offset, bar_text in enumerate(progression.split("|")):
            names = bar_text.split()
            for step, mark in enumerate(steps):
                if mark not in "ro5":
                    continue
                name = names[step * len(names) // 16]
                note = bass_note(name, octave) + {"r": 0, "o": 12, "5": 7}[mark]
                length = 1
                while step + length < len(steps) and steps[step + length] == "-":
                    length += 1
                seconds = length * self.beat / 4.0 * 0.9
                sound = self._once((instrument.__name__, note, round(seconds, 3)),
                                   lambda: instrument(self.k, hz(note), seconds, velocity))
                self.part(part).events.append((self.time(bar + offset, step), sound * (1.0 + 0.04 * self.rng.normal())))

    def render(self, reverb_seconds: float = 2.0, echo_beats: float = 0.75) -> np.ndarray:
        """The song mixed to stereo: each part panned, spread and ducked, sent to a reverb and
        an echo (to the left `echo_beats` late, to the right two thirds of that), then the whole
        evened out by a compressor and rounded off. In a loop it wraps round."""
        s = self.s
        n = s.samples(self.seconds)
        dry = np.zeros((2, n))
        to_reverb = np.zeros(n)
        to_echo = np.zeros(n)
        duck = self._ducking(n)
        for part in self.parts.values():
            mono = s.arrange(self.seconds, part.events) * s.db(part.gain_db)
            if part.pump:
                mono *= 1.0 - part.pump * duck
            stereo = s.pan(mono, part.pan)
            if part.width:
                stereo[1] = s.delay(stereo[1], 0.015 * part.width) * 0.85 + stereo[1] * 0.15
            dry += stereo
            to_reverb += mono * part.reverb
            to_echo += mono * part.delay
        hall = s.reverb(to_reverb, seconds=reverb_seconds, damping=0.6, mix=1.0, predelay=0.02, stereo=True)
        echo_in = s.lowpass(s.highpass(to_echo, 300.0), 4500.0)
        echo = np.stack([s.delay(echo_in, echo_beats * self.beat, 0.35), s.delay(echo_in, echo_beats * self.beat * 2 / 3, 0.35)])
        mix = s.highpass(dry + hall * 0.8 + echo * 0.5, 25.0)
        mix = s.compress(mix, threshold_db=-16.0, ratio=2.2, time=0.12)
        return s.saturate(mix * 1.2) / 1.2

    def _ducking(self, n: int) -> np.ndarray:
        """How far the kick ducks the parts that pump: 1 at each kick, back to 0 over a tenth
        of a second."""
        if not self.kicks:
            return np.zeros(n)
        t = np.arange(n) / self.s.rate
        kicks = np.sort(np.asarray(self.kicks) % self.seconds)
        # The last kick before each moment, the one before the first coming round from the end.
        index = np.searchsorted(kicks, t, side="right") - 1
        last = np.where(index >= 0, kicks[np.maximum(index, 0)], kicks[-1] - self.seconds)
        since = t - last
        return np.exp(-since / 0.1) * np.minimum(since / 0.004, 1.0)

    def _once(self, key, make):
        """A sound made once and kept, for the notes and hits that repeat."""
        if key not in self._made:
            self._made[key] = make()
        return self._made[key]


def _parse(text: str, steps: int) -> list[tuple[int, int, str]]:
    """(step, length in steps, note) for each note of a line, counting steps from its start;
    each bar between `|` must hold `steps` steps."""
    notes = []
    position = 0
    for bar_number, bar in enumerate(text.split("|")):
        tokens = bar.split()
        if not tokens:
            continue
        if len(tokens) != steps:
            raise ValueError(f"bar {bar_number + 1} of {text!r} has {len(tokens)} steps, not {steps}")
        for token in tokens:
            if token == "-":
                if notes and notes[-1][0] + notes[-1][1] == position:
                    start, length, note = notes[-1]
                    notes[-1] = (start, length + 1, note)
            elif token != ".":
                notes.append((position, 1, token))
            position += 1
    return notes


def _strikes(rhythm: str, first: int, end: int) -> list[tuple[int, int]]:
    """The strikes of a chord rhythm between two sixteenths: (step, length)."""
    marks = rhythm.replace(" ", "")
    strikes = []
    for step in range(first, end):
        if marks[step % 16] == "x":
            length = 1
            while step + length < end and marks[(step + length) % 16] == "-":
                length += 1
            strikes.append((step, length))
    return strikes
