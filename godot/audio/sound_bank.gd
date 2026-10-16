class_name SoundBank
extends RefCounted
## Every sound in the game that isn't a craft's engine ([EngineVoice] holds those), the one
## place the game finds them. kiln builds them from the recipes in `art/audio/` (with its
## synthesis kit, `pipeline/src/kiln/audio/`) into `res://assets/audio/`: the water round a
## craft, splashes and hull slaps, and the race's beeps, horn, bells, chime and fanfare.

## The water round the hull, as loops: lapping off the plane, the rush on it, and the jet.
const WASH: AudioStream = preload("res://assets/audio/water/hull_wash.wav")
const RUSH: AudioStream = preload("res://assets/audio/water/hull_rush.wav")
const JET: AudioStream = preload("res://assets/audio/water/hull_jet.wav")
## Splashes, three of each, and the hull slapping on chop.
const HOPS: Array[AudioStream] = [
	preload("res://assets/audio/water/splashes_hop_1.wav"),
	preload("res://assets/audio/water/splashes_hop_2.wav"),
	preload("res://assets/audio/water/splashes_hop_3.wav"),
]
const LANDINGS: Array[AudioStream] = [
	preload("res://assets/audio/water/splashes_land_1.wav"),
	preload("res://assets/audio/water/splashes_land_2.wav"),
	preload("res://assets/audio/water/splashes_land_3.wav"),
]
const CRASHES: Array[AudioStream] = [
	preload("res://assets/audio/water/splashes_crash_1.wav"),
	preload("res://assets/audio/water/splashes_crash_2.wav"),
	preload("res://assets/audio/water/splashes_crash_3.wav"),
]
const SLAPS: Array[AudioStream] = [
	preload("res://assets/audio/water/slaps_1.wav"),
	preload("res://assets/audio/water/slaps_2.wav"),
	preload("res://assets/audio/water/slaps_3.wav"),
	preload("res://assets/audio/water/slaps_4.wav"),
]
## The start clock's beep for each count, and the starter's air horn at the start.
const BEEP: AudioStream = preload("res://assets/audio/race/countdown_beep.wav")
const HORN: AudioStream = preload("res://assets/audio/race/countdown_go.wav")
## A buoy's bell, passed on its marked side, and the clank and buzz of a miss.
const BELL: AudioStream = preload("res://assets/audio/race/buoy_bell.wav")
const MISS: AudioStream = preload("res://assets/audio/race/buoy_miss.wav")
## A stunt ring taken, and the finish.
const RING: AudioStream = preload("res://assets/audio/race/ring.wav")
const FANFARE: AudioStream = preload("res://assets/audio/race/fanfare.wav")


## One of [param sounds], picked by [param rng], so a sound that plays often doesn't repeat.
static func pick(sounds: Array[AudioStream], rng: RandomNumberGenerator) -> AudioStream:
	return sounds[rng.randi_range(0, sounds.size() - 1)]
