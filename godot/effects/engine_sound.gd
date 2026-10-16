class_name EngineSound
extends Node3D
## A jet ski's sounds: its engine, the water round its hull, and its splashes. The sounds are
## built by kiln (see [SoundBank] and [EngineVoice]); this sets what plays and how loud.
##
## The engine's revs ([member rpm]) are worked out as a jet ski's are: the throttle sets them
## more than the speed does, since the pump on the crankshaft takes more power the faster it
## turns; with the intake out of the water the pump has nothing to push and the engine flies
## up to its limiter, which cuts the ignition until the revs drop. The engine's loops are
## crossfaded and bent in pitch to the revs, and between their throttle-open and throttle-shut
## recordings by the load. When the rider falls off, the lanyard on their wrist pulls the kill
## switch and the engine stops; climbing back on they start it again.

## The craft. Defaults to the parent.
@export var craft: JetSki
## The engine. Each craft's scene gives its own.
@export var voice: EngineVoice
## Distance at which the sounds start to fall off, in meters.
@export_range(1.0, 100.0, 0.1) var unit_size: float = 10.0

@export_group("Levels")
## The engine's loops and starter, the jet's roar, and the water round the hull, in dB.
@export_range(-40.0, 12.0, 0.1) var engine_volume: float = -6.0
@export_range(-40.0, 12.0, 0.1) var jet_volume: float = -12.0
@export_range(-40.0, 12.0, 0.1) var wash_volume: float = -14.0
@export_range(-40.0, 12.0, 0.1) var rush_volume: float = -10.0
## A big landing's or a crash's splash, in dB; smaller splashes and slaps are quieter.
@export_range(-40.0, 12.0, 0.1) var splash_volume: float = -2.0
@export_range(-40.0, 12.0, 0.1) var slap_volume: float = -9.0

@export_group("Revs")
## How much higher the revs run at top speed than at a standstill, as the water rammed into
## the intake eases the pump.
@export_range(0.0, 0.3, 0.005) var ram_rise: float = 0.03
## With the intake out of the water, the share of throttle that takes the engine to its limiter.
@export_range(0.05, 1.0, 0.01) var free_throttle: float = 0.4
## How long the limiter cuts the ignition each time the revs reach it, in seconds.
@export_range(0.005, 0.2, 0.001) var limiter_cut: float = 0.045
## How quickly a stopped engine's revs die, in seconds to 1/e.
@export_range(0.01, 2.0, 0.01) var stall_time: float = 0.18

@export_group("Hull")
## A hull point meeting the water faster than this slaps, in m/s; the slap is loudest this
## much faster again.
@export_range(0.0, 10.0, 0.1) var slap_speed: float = 1.5
@export_range(0.1, 10.0, 0.1) var slap_range: float = 3.5
## The least time between two slaps, in seconds.
@export_range(0.0, 1.0, 0.01) var slap_gap: float = 0.14

## What the engine is doing.
enum EngineState { RUNNING, STOPPED, STARTING }

## The engine's revs now: 0 when stopped.
var rpm: float = 0.0
## How far the throttle opens the engine's sound, 0 (shut, or the limiter cutting) to 1.
var load: float = 0.0
var engine_state: EngineState = EngineState.RUNNING

var _on: Array[AudioStreamPlayer3D] = []
var _off: Array[AudioStreamPlayer3D] = []
var _jet: AudioStreamPlayer3D
var _wash: AudioStreamPlayer3D
var _rush: AudioStreamPlayer3D
var _start: AudioStreamPlayer3D
var _splash: AudioStreamPlayer3D
var _slap: AudioStreamPlayer3D
var _starting := 0.0
var _cut := 0.0
var _levels := {&"jet": 0.0, &"wash": 0.0, &"rush": 0.0}
var _last_slam := 0.0
var _since_slap := 1.0
var _last_air_time := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if craft == null:
		craft = get_parent() as JetSki
	if voice == null:
		return
	for i in voice.layer_rpm.size():
		_on.append(_player("On%d" % i, voice.on_load[i], &"Engine"))
		_off.append(_player("Off%d" % i, voice.off_load[i], &"Engine"))
	_jet = _player("Jet", SoundBank.JET, &"Engine")
	_wash = _player("Wash", SoundBank.WASH, &"Effects")
	_rush = _player("Rush", SoundBank.RUSH, &"Effects")
	_start = _player("Start", voice.start, &"Engine")
	_splash = _player("Splash", null, &"Effects")
	_slap = _player("Slap", null, &"Effects")
	for player: AudioStreamPlayer3D in _on + _off + [_jet, _wash, _rush]:
		player.volume_db = -80.0
		player.play()
	rpm = voice.idle_rpm
	if craft != null:
		_rng.seed = hash(craft.name)
		craft.landed.connect(func(quality: StringName, _stunts: Array[StringName], _points: int) -> void:
			_play_splash(SoundBank.LANDINGS, splash_volume - (0.0 if quality != &"clean" else 3.0)))
		craft.crashed.connect(func(_reason: StringName) -> void: _play_splash(SoundBank.CRASHES, splash_volume))


func _process(delta: float) -> void:
	if craft == null or voice == null:
		return
	_follow_rider(delta)
	_spin(delta)
	_mix_engine()
	_mix_water(delta)
	_listen_for_slaps(delta)


## The revs the engine heads for, and how fast, from the throttle, the intake and the speed.
func _spin(delta: float) -> void:
	var target := 0.0
	var wet := craft.intake_wet
	var opening := 0.0
	if engine_state == EngineState.RUNNING:
		var throttle := craft.thrust if craft.is_rider_aboard() else 0.0
		var top := craft.tuning.reference_top_speed if craft.tuning != null else 17.5
		var pace := clampf(craft.speed / top, 0.0, 1.3)
		var loaded := lerpf(voice.idle_rpm, voice.rated_rpm, sqrt(throttle)) * (1.0 + ram_rise * pace)
		var free := lerpf(voice.idle_rpm, voice.limiter_rpm + 400.0, clampf(throttle / free_throttle, 0.0, 1.0))
		target = lerpf(free, loaded, wet)
		opening = throttle
		if _cut > 0.0:
			# The limiter has cut the ignition: no power until the revs drop.
			_cut -= delta
			target = voice.idle_rpm
			opening = 0.0
		elif rpm >= voice.limiter_rpm and target > voice.limiter_rpm:
			# The ignition cuts at once, so the sound does too.
			_cut = limiter_cut
			load = 0.0
			opening = 0.0
	var time := stall_time
	if engine_state == EngineState.RUNNING:
		if target > rpm:
			time = lerpf(voice.spool_up_free, voice.spool_up, wet)
		else:
			time = lerpf(voice.spool_down_free, voice.spool_down, wet)
	rpm = lerpf(rpm, target, 1.0 - exp(-delta / time))
	if engine_state != EngineState.RUNNING and rpm < 30.0:
		rpm = 0.0
	load = move_toward(load, opening, delta * 10.0)


## The lanyard: the engine stops when the rider comes off, and starts as they climb back on.
func _follow_rider(delta: float) -> void:
	match craft.rider_state:
		JetSki.RiderState.ABOARD:
			if engine_state != EngineState.RUNNING:
				_catch()
		JetSki.RiderState.MOUNTING:
			if engine_state == EngineState.STOPPED:
				engine_state = EngineState.STARTING
				_starting = 0.0
				_start.volume_db = engine_volume
				_start.play()
		_:
			engine_state = EngineState.STOPPED
	if engine_state == EngineState.STARTING:
		_starting += delta
		if _starting >= voice.start_catch:
			_catch()


func _catch() -> void:
	engine_state = EngineState.RUNNING
	# The revs flare above idle as it catches.
	rpm = maxf(rpm, voice.idle_rpm * 1.5)


## Each loop's volume and pitch: the two layers either side of the revs, the throttle-open
## and throttle-shut recordings by the load.
func _mix_engine() -> void:
	var layers := voice.layer_rpm
	var count := layers.size()
	var gains := PackedFloat32Array()
	gains.resize(count)
	if rpm < layers[0]:
		# Below idle: the engine dying, or catching.
		gains[0] = pow(clampf(rpm / layers[0], 0.0, 1.0), 2.0)
	elif rpm >= layers[count - 1]:
		gains[count - 1] = 1.0
	else:
		var i := 0
		while rpm >= layers[i + 1]:
			i += 1
		var w := log(rpm / layers[i]) / log(layers[i + 1] / layers[i])
		gains[i] = cos(w * PI * 0.5)
		gains[i + 1] = sin(w * PI * 0.5)
	var on := sqrt(load)
	var off := sqrt(1.0 - load)
	for i in count:
		var pitch := maxf(rpm / layers[i], 0.25)
		_drive(_on[i], gains[i] * on, engine_volume, pitch)
		_drive(_off[i], gains[i] * off, engine_volume, pitch)


## The water round the hull: lapping off the plane, the rush on it, and the jet while its
## nozzle is in the water.
func _mix_water(delta: float) -> void:
	var top := craft.tuning.reference_top_speed if craft.tuning != null else 17.5
	var speed := craft.speed
	var pace := clampf(speed / top, 0.0, 1.2)
	var hull := clampf(craft.contact * 2.0, 0.0, 1.0) * (0.0 if craft.airborne else 1.0)
	var lapping := 0.3 + 0.7 * smoothstep(0.3, 2.0, speed)
	var targets := {
		&"wash": hull * lapping * (1.0 - smoothstep(5.0, 10.0, speed)),
		&"rush": hull * smoothstep(3.0, 16.0, speed),
		&"jet": (craft.thrust if engine_state == EngineState.RUNNING else 0.0) * craft.intake_wet,
	}
	for key: StringName in targets:
		_levels[key] = lerpf(_levels[key], targets[key], 1.0 - exp(-delta * 12.0))
	_drive(_wash, _levels[&"wash"], wash_volume, 0.85 + 0.3 * clampf(speed / 8.0, 0.0, 1.0))
	_drive(_rush, _levels[&"rush"], rush_volume, 0.8 + 0.35 * pace)
	_drive(_jet, _levels[&"jet"] * clampf(rpm / voice.rated_rpm, 0.0, 1.0), jet_volume,
			clampf(rpm / voice.rated_rpm, 0.3, 1.1))


## A slap each time the hull comes down hard on a wave, and a small splash after a hop.
## Jumps long enough to be judged splash through [signal JetSki.landed] instead.
func _listen_for_slaps(delta: float) -> void:
	_since_slap += delta
	var slam := craft.slam_speed
	var air := _last_air_time
	_last_air_time = craft.air_time
	var rising := slam > slap_speed and _last_slam <= slap_speed
	_last_slam = slam
	if not rising or _since_slap < slap_gap or air >= 0.3:
		return
	_since_slap = 0.0
	var hit := clampf((slam - slap_speed) / slap_range, 0.0, 1.0)
	if air > 0.12:
		_play_splash(SoundBank.HOPS, splash_volume - 6.0 + 4.0 * hit)
	else:
		_slap.stream = SoundBank.pick(SoundBank.SLAPS, _rng)
		_slap.volume_db = slap_volume + linear_to_db(0.35 + 0.65 * hit)
		_slap.pitch_scale = _rng.randf_range(0.92, 1.08)
		_slap.play()


func _play_splash(sounds: Array[AudioStream], volume_db: float) -> void:
	_splash.stream = SoundBank.pick(sounds, _rng)
	_splash.volume_db = volume_db
	_splash.pitch_scale = _rng.randf_range(0.93, 1.07)
	_splash.play()


## Sets a loop's level (0 to 1, on top of [param volume_db]) and pitch, pausing it while it
## can't be heard.
func _drive(player: AudioStreamPlayer3D, level: float, volume_db: float, pitch: float) -> void:
	player.stream_paused = level < 0.001 or get_tree().paused
	player.volume_db = volume_db + linear_to_db(maxf(level, 0.0001))
	player.pitch_scale = pitch


func _notification(what: int) -> void:
	# Silence everything while the game is paused, and pick up where it was after.
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_UNPAUSED:
		for player in get_children():
			if player is AudioStreamPlayer3D:
				(player as AudioStreamPlayer3D).stream_paused = what == NOTIFICATION_PAUSED


func _player(node_name: String, stream: AudioStream, bus: StringName) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = node_name
	player.stream = stream
	player.bus = bus
	player.unit_size = unit_size
	player.max_distance = 150.0
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(player)
	return player
