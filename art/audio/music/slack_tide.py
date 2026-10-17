"""Slack Tide, the menus' music: an easy tropical groove at 104 beats a minute in F major, a
steel pan carrying the tune over an electric piano chopping the offbeats, a round bass and
soft hand drums. Twenty-four bars: the tune, a bridge, and the tune again, turning round to
the start."""
from kiln import sound

from audio.music._band import (Song, bass, chord_epiano, conga, high_conga, kick, pad, rim, shaker,
                               steelpan)

VERSE = "Fmaj7 | Em7 A7 | Dm7 | Gm7 C7 | Fmaj7 | Em7 A7 | Dm7 | Gm7 C7"
BRIDGE = "Bbmaj7 | Am7 | Gm7 | C7sus4 C7 | Bbmaj7 | Am7 | Gm7 | C7sus4 C7"
TUNE = (". C5 F5 A5 - G5 A5 C6 | - . B5 A5 G5 - E5 C#5 | D5 - - . F5 A5 C6 - | Bb5 - A5 G5 - . E5 - |"
        " F5 . C5 F5 A5 - G5 A5 | B5 - G5 . E5 G5 C#6 - | D6 - C6 A5 - F5 A5 . | G5 - - . Bb5 - G5 E5")
# The last time through, the tune comes down to lead back to the start.
TUNE_HOME = TUNE.rsplit("|", 1)[0] + "| G5 - - . E5 - C5 ."
BRIDGE_TUNE = ("D6 - - C6 Bb5 - A5 F5 | - . E5 - G5 A5 C6 - | Bb5 - A5 - G5 - F5 D5 | F5 - - - E5 - G5 - |"
               " D6 - - C6 Bb5 - A5 C6 | - . A5 G5 E5 - C5 E5 | G5 - Bb5 - D6 - C6 Bb5 | A5 - G5 - E5 - . .")
VERSE_BASS = ("F2 - - F2 . C3 . E2 | E2 - . B2 A2 - . C#3 | D3 - - D3 . A2 . C3 | G2 - . D3 C3 - . E2 |"
              " F2 - - F2 . C3 . E2 | E2 - . B2 A2 - . C#3 | D3 - - D3 . A2 . C3 | G2 - . D3 C3 - . E2")
BRIDGE_BASS = ("Bb1 - - Bb1 . F2 . A1 | A1 - - A1 . E2 . Ab1 | G1 - - G1 . D2 . B1 | C2 - . G2 C2 - . E2 |"
               " Bb1 - - Bb1 . F2 . A1 | A1 - - A1 . E2 . Ab1 | G1 - - G1 . D2 . B1 | C2 - . G2 C2 - . E2")


@sound(loop=True, channels=2, format="ogg", seconds=(40.0, 120.0))
def build(s):
    song = Song(s, bpm=104, bars=24, swing=0.12, seed=3)
    song.part("kick", gain_db=-4.0, reverb=0.03)
    song.part("rim", gain_db=-11.0, pan=0.15, reverb=0.15)
    song.part("shaker", gain_db=-16.0, pan=-0.35, reverb=0.1)
    song.part("congas", gain_db=-10.0, pan=0.3, reverb=0.15)
    song.part("bass", gain_db=-1.0, reverb=0.0)
    song.part("keys", gain_db=-9.0, pan=-0.15, reverb=0.2, width=0.4)
    song.part("pad", gain_db=-6.5, reverb=0.3, width=1.0)
    song.part("tune", gain_db=-6.0, pan=0.1, reverb=0.25, delay=0.15)

    every = range(1, 25)
    song.hits("kick", every, "x.......x..x....", kick)
    song.hits("rim", every, "....x.......x...", rim)
    song.hits("shaker", every, "xgxgxgxgxgxgxgxg", shaker)
    song.hits("congas", range(9, 25), "........x.....x.", conga)
    song.hits("congas", range(9, 25), "..g.......x.....", high_conga)

    for start, chords, low in ((1, VERSE, VERSE_BASS), (9, BRIDGE, BRIDGE_BASS), (17, VERSE, VERSE_BASS)):
        song.line("bass", start, low, bass, velocity=0.75)
        # The offbeats chopped on the electric piano, as an island band's guitar does.
        song.chords("keys", start, chords, chord_epiano, rhythm="..x-..x-..x-..x-", velocity=0.6)
    song.chords("pad", 9, BRIDGE, pad, velocity=0.5)
    song.line("tune", 1, TUNE, steelpan, velocity=0.85)
    song.line("tune", 9, BRIDGE_TUNE, steelpan, velocity=0.8)
    song.line("tune", 17, TUNE_HOME, steelpan, velocity=0.85)
    return song.render(reverb_seconds=1.8, echo_beats=0.75)
