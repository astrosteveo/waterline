class_name RaceSounds
extends Node
## The race's own sounds, heard by the player wherever the camera is: the start clock's beeps
## and the starter's horn, a buoy's bell (or a buzz for a miss), a chime for a stunt ring, and
## a fanfare at the finish. The craft make their own engine and water sounds ([EngineSound]).

@export var race: Race

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _modes_connected := false


func _ready() -> void:
	# One player per sound playing at once: setting a player's stream stops what it plays.
	for i in 4:
		var player := AudioStreamPlayer.new()
		player.bus = &"Effects"
		add_child(player)
		_players.append(player)
	if race == null:
		return
	race.countdown_changed.connect(func(left: int) -> void:
		if left > 0:
			_play(SoundBank.BEEP, -6.0))
	race.started.connect(func() -> void: _play(SoundBank.HORN, -3.0))
	race.gate_judged.connect(func(racer: RacerState, _gate: CourseGate, correct: bool) -> void:
		if racer == race.watched and racer.is_racing():
			_play(SoundBank.BELL if correct else SoundBank.MISS, -7.0 if correct else -8.0))
	race.racer_finished.connect(func(racer: RacerState) -> void:
		if racer == race.watched:
			_play(SoundBank.FANFARE, -4.0))


func _process(_delta: float) -> void:
	# The stunt run is set up after this node is ready.
	if not _modes_connected and race != null and race.stunt_mode != null:
		_modes_connected = true
		race.stunt_mode.ring_taken.connect(func(_ring: StuntRing, _points: int, _multiplier: float) -> void:
			_play(SoundBank.RING, -6.0))


func _play(stream: AudioStream, volume_db: float) -> void:
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = stream
	player.volume_db = volume_db
	player.play()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_UNPAUSED:
		for player in _players:
			player.stream_paused = what == NOTIFICATION_PAUSED
