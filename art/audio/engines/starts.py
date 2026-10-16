"""Each craft's engine starting: the starter cranking it over, the first firings catching and
the revs flaring. The rider presses the starter on climbing back aboard (the lanyard cut the
engine in the crash); the game brings the idle loop in as the revs flare, at `CATCH`."""
from kiln import sound

from audio.engines import petrel, skipjack, swordfish, tradewind
from audio.engines._engine import start

# Seconds of cranking before the engine catches (EngineVoice.start_catch in the game).
CATCH = 0.55
CRAFT = {"petrel": petrel, "skipjack": skipjack, "swordfish": swordfish, "tradewind": tradewind}


@sound(seconds=(0.8, 1.2))
def build(s):
    return {name: start(s, craft.ENGINE, CATCH, 1.0, seed) for seed, (name, craft) in enumerate(CRAFT.items(), 1)}
