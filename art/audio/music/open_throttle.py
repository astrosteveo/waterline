"""Open Throttle, race music: a driving track at 136 beats a minute in A minor, a galloping
bass pumping with the kick, plucked arpeggios, a synth lead and brass stabs in the chorus.
Forty bars: an intro, a verse, the chorus, the verse and the chorus again, and a way out
that leads back into the intro."""
from kiln import sound

from audio.music._band import Song, bass, brass, clap, crash, hat, kick, lead, open_hat, pad, pluck, snare

INTRO = "Am | F | C | G"
VERSE = f"{INTRO} | {INTRO}"
CHORUS = "F | G | Am | Am | F | G | C | E7"
VERSE_TUNE = "E5 - A5 - B5 C6 - B5 | A5 - - - F5 - A5 C6 | E6 - D6 C6 - G5 - C6 | D6 - - B5 - G5 A5 B5"
CHORUS_TUNE = ("C6 - - A5 C6 - D6 - | D6 - - B5 D6 - E6 - | E6 - - - C6 - A5 - | B5 C6 - B5 A5 - E5 - |"
               " F5 - A5 C6 - A5 C6 - | D6 - G6 - - E6 D6 B5 | C6 - - E6 - D6 C6 - | B5 - G#5 - E5 - B4 -")
GALLOP = "r.ro.ro.r.ro.ro."
FILL = "............xxxx"


@sound(loop=True, channels=2, format="ogg", seconds=(40.0, 120.0))
def build(s):
    song = Song(s, bpm=136, bars=40, seed=5)
    song.part("kick", gain_db=-4.0, reverb=0.02)
    song.part("clap", gain_db=-3.0, reverb=0.2)
    song.part("snare", gain_db=-11.0, reverb=0.2)
    song.part("hats", gain_db=-8.0, pan=0.25, reverb=0.05)
    song.part("open hats", gain_db=-11.5, pan=-0.2, reverb=0.1)
    song.part("crash", gain_db=-8.5, pan=-0.3, reverb=0.2)
    song.part("bass", gain_db=1.5, reverb=0.0, pump=0.5)
    song.part("arp", gain_db=-7.5, pan=0.2, reverb=0.15, delay=0.25, pump=0.35)
    song.part("pad", gain_db=-4.0, reverb=0.3, width=1.0, pump=0.6)
    song.part("brass", gain_db=-4.5, pan=-0.15, reverb=0.2, width=0.3)
    song.part("lead", gain_db=-5.0, reverb=0.2, delay=0.2)

    song.hits("kick", range(1, 41), "x...x...x...x...", kick)
    song.hits("hats", range(1, 41), "xgxgxgxgxgxgxgxg", hat)
    song.hits("clap", range(5, 41), "....x.......x...", clap)
    song.hits("open hats", range(5, 37), "..x...x...x...x.", open_hat)
    song.hits("snare", (12, 20, 28, 36), FILL, snare)
    song.hits("snare", (40,), "....x...x.x.xxxx", snare)
    song.hits("crash", (1, 13, 29), "x...............", crash)

    sections = [(1, INTRO), (5, VERSE), (13, CHORUS), (21, VERSE), (29, CHORUS), (37, INTRO)]
    for start, chords in sections:
        song.bassline("bass", start, chords, GALLOP, bass, octave=1)
    for start in (5, 21, 37):
        song.arpeggio("arp", start, VERSE if start < 37 else INTRO, pluck, order="0 1 2 3 4 3 2 1")
    for start in (13, 29):
        song.chords("brass", start, CHORUS, brass, rhythm="x-....x-..x-....", around=64.0)
        song.chords("pad", start, CHORUS, pad, velocity=0.5)
        song.line("lead", start, CHORUS_TUNE, lead)
    song.line("lead", 9, VERSE_TUNE, lead, velocity=0.7)
    song.line("lead", 25, VERSE_TUNE, lead, velocity=0.75)
    return song.render(reverb_seconds=1.6, echo_beats=0.75)
