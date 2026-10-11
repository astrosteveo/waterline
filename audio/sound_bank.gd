class_name SoundBank
extends RefCounted
## Every sound in the game, generated in code the first time it is asked for (no audio files):
## an engine loop and a water hiss whose pitch the craft varies, a splash, and short tones for
## the countdown, buoys and rings. 16-bit mono at [constant RATE] Hz.

const RATE := 22050

static var _cache: Dictionary[StringName, AudioStreamWAV] = {}


## A buzzy two-stroke engine note: an 80 Hz sawtooth-like stack of harmonics, pulsing at
## the firing rate, over a little rough noise. Loops seamlessly (0.5 s holds whole cycles).
## The craft sets its pitch from the speed.
static func engine() -> AudioStreamWAV:
	return _build(&"engine", func() -> Array:
		var n := RATE / 2
		var out := PackedFloat32Array()
		out.resize(n)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var rough := 0.0
		for i in n:
			var t := float(i) / RATE
			var s := 0.0
			for k in range(1, 9):
				s += sin(TAU * 80.0 * k * t + k * 0.7) / k
			var pulse := 0.72 + 0.28 * sin(TAU * 40.0 * t)
			rough = lerpf(rough, rng.randf_range(-1.0, 1.0), 0.25)
			out[i] = s * 0.5 * pulse + rough * 0.12
		return [out, true])


## Water rushing under the hull: band-limited noise. Loops; the craft sets its volume from the speed.
static func hiss() -> AudioStreamWAV:
	return _build(&"hiss", func() -> Array:
		var n := RATE
		var out := PackedFloat32Array()
		out.resize(n)
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var low := 0.0
		var lower := 0.0
		for i in n:
			var white := rng.randf_range(-1.0, 1.0)
			low = lerpf(low, white, 0.12)
			lower = lerpf(lower, low, 0.03)
			out[i] = (low - lower) * 2.2
		# Fade the seam: blend the end into the start.
		var fade := 1500
		for i in fade:
			var w := float(i) / fade
			out[n - fade + i] = lerpf(out[n - fade + i], out[i], w)
		return [out, true])


## A splash: a burst of noise that darkens and dies away over 0.7 s.
static func splash() -> AudioStreamWAV:
	return _build(&"splash", func() -> Array:
		var n := int(RATE * 0.7)
		var out := PackedFloat32Array()
		out.resize(n)
		var rng := RandomNumberGenerator.new()
		rng.seed = 23
		var low := 0.0
		for i in n:
			var t := float(i) / n
			low = lerpf(low, rng.randf_range(-1.0, 1.0), lerpf(0.6, 0.08, t))
			out[i] = low * exp(-t * 5.0) * minf(t * 60.0, 1.0) * 1.4
		return [out, false])


## A bright bell for a buoy passed on its marked side.
static func ding() -> AudioStreamWAV:
	return _tone(&"ding", [1318.5, 2637.0], [1.0, 0.35], 0.4, 7.0)


## A low buzz for a missed buoy.
static func buzz() -> AudioStreamWAV:
	return _build(&"buzz", func() -> Array:
		var n := int(RATE * 0.32)
		var out := PackedFloat32Array()
		out.resize(n)
		for i in n:
			var t := float(i) / RATE
			var square := 1.0 if fmod(t * 130.0, 1.0) < 0.5 else -1.0
			out[i] = square * 0.35 * minf(float(n - i) / 800.0, 1.0) * minf(i / 200.0, 1.0)
		return [out, false])


## Countdown beeps: low for 3, 2, 1, high for GO.
static func beep(high: bool) -> AudioStreamWAV:
	return _tone(&"beep_high" if high else &"beep_low", [1760.0 if high else 880.0], [1.0], 0.5 if high else 0.22, 3.0)


## Two quick notes for a stunt ring.
static func chime() -> AudioStreamWAV:
	return _build(&"chime", func() -> Array:
		var n := int(RATE * 0.45)
		var out := PackedFloat32Array()
		out.resize(n)
		for i in n:
			var t := float(i) / RATE
			var f := 1046.5 if t < 0.09 else 1568.0
			var start := 0.0 if t < 0.09 else 0.09
			out[i] = sin(TAU * f * t) * exp(-(t - start) * 9.0) * 0.8
		return [out, false])


## A short rising fanfare for the finish.
static func fanfare() -> AudioStreamWAV:
	return _build(&"fanfare", func() -> Array:
		var notes := [523.25, 659.25, 783.99, 1046.5]
		var n := int(RATE * 1.2)
		var out := PackedFloat32Array()
		out.resize(n)
		for i in n:
			var t := float(i) / RATE
			var k := mini(int(t / 0.14), notes.size() - 1)
			var local := t - k * 0.14
			var f: float = notes[k]
			var decay := exp(-local * (6.0 if k < notes.size() - 1 else 2.0))
			out[i] = (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * decay * 0.55
		return [out, false])


static func _tone(key: StringName, freqs: Array, gains: Array, length: float, decay: float) -> AudioStreamWAV:
	return _build(key, func() -> Array:
		var n := int(RATE * length)
		var out := PackedFloat32Array()
		out.resize(n)
		for i in n:
			var t := float(i) / RATE
			var s := 0.0
			for k in freqs.size():
				s += sin(TAU * float(freqs[k]) * t) * float(gains[k])
			out[i] = s * exp(-t * decay) * minf(i / 60.0, 1.0) * 0.7
		return [out, false])


## Builds (once) and returns the sound [param key]; [param make] returns the samples and
## whether the sound loops, as [samples, loops].
static func _build(key: StringName, make: Callable) -> AudioStreamWAV:
	if _cache.has(key):
		return _cache[key]
	var made: Array = make.call()
	var samples: PackedFloat32Array = made[0]
	var loops: bool = made[1]
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	if loops:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	_cache[key] = stream
	return stream


## Drops every cached sound, at exit.
static func release() -> void:
	_cache.clear()
