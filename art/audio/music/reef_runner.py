"""Reef Runner, race music: a funk groove at 118 beats a minute in B minor, a slapped bass
and stabbing electric piano under a steel pan, with a synth lead taking the chorus and
congas over a four-on-the-floor beat. Thirty-two bars: verse and chorus, twice."""
from kiln import sound

from audio.music._band import (Song, chord_epiano, clap, conga, crash, hat, high_conga, kick, lead, open_hat,
                               pad, slap, steelpan)

VERSE = "Bm7 | Bm7 | Gmaj7 | F#7 | Bm7 | Bm7 | Em7 | F#7sus4 F#7"
CHORUS = "Gmaj7 | A6 | F#m7 | Bm7 | Gmaj7 | A6 | F#7sus4 | F#7"
VERSE_TUNE = ("B4 - D5 F#5 - A5 - F#5 | E5 - D5 - B4 - . . | D5 - G5 B5 - A5 - F#5 | E5 - - C#5 - A#4 - . |"
              " B4 - D5 F#5 - A5 - B5 | D6 - C#6 - B5 - A5 - | G5 - - E5 - B5 - G5 | B5 - - C#6 - A#5 - F#5")
CHORUS_TUNE = ("B5 - - D6 - F#6 - D6 | E6 - C#6 - A5 - F#5 - | A5 - - C#6 - E6 - C#6 | D6 - B5 - F#5 - . . |"
               " B5 - - D6 - G6 - F#6 | E6 - - C#6 - E6 F#6 E6 | C#6 - B5 - - . E5 F#5 | A#5 - - - C#6 - A#5 -")


@sound(loop=True, channels=2, format="ogg", seconds=(40.0, 120.0))
def build(s):
    song = Song(s, bpm=118, bars=32, swing=0.06, seed=7)
    song.part("kick", gain_db=-4.5, reverb=0.02)
    song.part("clap", gain_db=-4.0, reverb=0.2)
    song.part("hats", gain_db=-9.0, pan=0.3, reverb=0.05)
    song.part("open hats", gain_db=-13.0, pan=-0.25, reverb=0.1)
    song.part("crash", gain_db=-10.0, pan=0.3, reverb=0.2)
    song.part("congas", gain_db=-11.5, pan=-0.35, reverb=0.15)
    song.part("bass", gain_db=-1.5, reverb=0.0, pump=0.3)
    song.part("keys", gain_db=-7.0, pan=0.2, reverb=0.15, width=0.5)
    song.part("pad", gain_db=-7.0, reverb=0.3, width=1.0, pump=0.4)
    song.part("pan", gain_db=-3.5, pan=-0.1, reverb=0.25, delay=0.15)
    song.part("lead", gain_db=-5.0, reverb=0.2, delay=0.2)

    song.hits("kick", range(1, 33), "x...x...x...x...", kick)
    song.hits("clap", range(1, 33), "....x.......x...", clap)
    song.hits("hats", range(1, 33), "xgxgxgxgxgxgxgxg", hat)
    song.hits("open hats", range(1, 33), "..x...x...x...x.", open_hat)
    song.hits("congas", range(1, 33), "......x..g....x.", conga)
    song.hits("congas", range(1, 33), "...g......x.g...", high_conga)
    song.hits("crash", (1, 9, 17, 25), "x...............", crash)

    for start in (1, 17):
        song.line("bass", start, " | ".join(["B1 . . B2 . B1 . B2 . . B1 . B2 . A1 A2"] * 6
                                               + ["E1 . . E2 . E1 . E2 . . E1 . E2 . F#1 F#2",
                                                  "F#1 . . F#2 . F#1 . F#2 . . F#1 . F#2 . A#1 A#2"]), slap, steps=16)
        song.chords("keys", start, VERSE, chord_epiano, rhythm="..x-.x....x-.x..", velocity=0.6)
        song.line("pan", start, VERSE_TUNE, steelpan, velocity=0.85)
    for start in (9, 25):
        song.bassline("bass", start, CHORUS, "r..o.r.o..r.o.ro", slap, octave=1)
        song.chords("keys", start, CHORUS, chord_epiano, rhythm="x-.x..x-..x-.x..", velocity=0.55)
        song.chords("pad", start, CHORUS, pad, velocity=0.5)
        song.line("lead", start, CHORUS_TUNE, lead, velocity=0.75)
    return song.render(reverb_seconds=1.5, echo_beats=0.75)
