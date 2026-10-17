extends Node
## The music (autoload `Music`), on the Music bus: [constant MENU] in the menus, and in a
## race one of [constant RACES], picked by the course, from the starting horn. Changing track
## fades one out as the next comes in. While the game is paused the music dips and plays on.
## kiln builds the tracks from `art/audio/music/`.

const MENU: AudioStream = preload("res://assets/audio/music/slack_tide.ogg")
const RACES: Array[AudioStream] = [
	preload("res://assets/audio/music/open_throttle.ogg"),
	preload("res://assets/audio/music/reef_runner.ogg"),
]
## Seconds a track takes to fade in or out.
const FADE := 1.5
## How far the music dips while the game is paused, in dB.
const PAUSED_DIP := -8.0

## The track playing, or that was last asked for (null: none).
var track: AudioStream
var _players: Array[AudioStreamPlayer] = []
## Each player's level before the dip, in dB.
var _levels := PackedFloat32Array([-80.0, -80.0])
var _playing := 0
var _dip := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = &"Music"
		player.volume_db = -80.0
		add_child(player)
		_players.append(player)
	get_tree().scene_changed.connect(_on_scene_changed)
	_on_scene_changed.call_deferred()


func _process(delta: float) -> void:
	_dip = move_toward(_dip, PAUSED_DIP if get_tree().paused else 0.0, delta * absf(PAUSED_DIP) * 3.0)
	for i in _players.size():
		# On a dB scale: up to full quickly, down to silence over FADE.
		var target := 0.0 if i == _playing and track != null else -80.0
		_levels[i] = move_toward(_levels[i], target, delta * 80.0 / FADE)
		var player := _players[i]
		player.volume_db = _levels[i] + _dip
		if _levels[i] <= -80.0 and player.playing:
			player.stop()


## Plays [param stream] from its start, fading out what was playing. The same track again
## carries on; null fades the music out.
func play(stream: AudioStream) -> void:
	if stream == track:
		return
	track = stream
	if stream == null:
		return
	# The other player, so the track fading out isn't cut off.
	_playing = (_playing + 1) % _players.size()
	var player := _players[_playing]
	player.stream = stream
	_levels[_playing] = -30.0
	player.volume_db = -30.0 + _dip
	player.play()


## The track a race on [param course_scene] plays: the courses take the race tracks in turn,
## in the order the game lists them.
func race_track(course_scene: String) -> AudioStream:
	for i in Game.courses.size():
		if Game.courses[i].scene == course_scene:
			return RACES[i % RACES.size()]
	return RACES[0]


func _exit_tree() -> void:
	# Let go of the playbacks, so nothing is reported leaked when the game quits.
	for player in _players:
		player.stop()


func _on_scene_changed() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		# No scene (a script run on its own, such as the project check): no music.
		return
	var race := scene as Race
	if race == null:
		play(MENU)
		return
	# The engines idle through the countdown; the race's track comes in with the horn.
	play(null)
	race.started.connect(func() -> void:
		play(race_track(race.course_scene.resource_path if race.course_scene != null else "")))
