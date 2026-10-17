class_name Announcer
extends CanvasLayer
## The race announcer, as text across the top of the screen and a voice on the Voice bus: the
## start, lead changes, the player moving up, the final lap, crashes, stunts,
## disqualifications, the finish, the tide, the weather, and in the solo modes ring chains,
## lap records and the clock running down.
##
## Lines queue up and show one at a time for [member line_time] seconds, or while the voice
## says them if that is longer; a line waiting longer than [member stale_time] is dropped, so
## the calls stay current. A more important line cuts in ahead of the queue, cutting off the
## voice. Each line is recorded whole (`tools/voice/`), one clip for each rider, course or
## stunt it names: its id names the clip, `res://assets/audio/voice/<id>.ogg`. A line with no
## clip only shows.

@export var race: Race
## Seconds each line stays up.
@export_range(0.5, 10.0, 0.1, "suffix:s") var line_time: float = 2.4
## Lines that waited this long are dropped.
@export_range(0.5, 10.0, 0.1, "suffix:s") var stale_time: float = 3.0
## Seconds between two lead-change calls, so a close fight doesn't flood the screen.
@export_range(0.0, 20.0, 0.1, "suffix:s") var lead_call_gap: float = 5.0

const NAME_COLOR := "ffd820"
const PRIORITY_LOW := 0
const PRIORITY_NORMAL := 1
const PRIORITY_HIGH := 2
## Where the voice clips are.
const VOICE_DIR := "res://assets/audio/voice"
## What the announcer calls, by kind: the words shown and spoken, with {rider}, {course},
## {stunt}, {place}, {rings} and {time} filled in. A pair is [shown, spoken] where they differ.
const CALLS: Dictionary[String, Variant] = {
	"marks": "Riders, take your marks at {course}!",
	"time_trial": "Time trial at {course}. Set the pace!",
	"time_trial_ghost": "Time trial at {course}. Beat the ghost!",
	"stunt_run": "Stunt run at {course}. Hit the rings!",
	"off": "And they're off!",
	"go": "Go!",
	"lead": "{rider} takes the lead!",
	"moves_up": "{rider} moves up to {place}!",
	"final_lap": "Final lap! {rider} leads!",
	"wipeout": "Oh! {rider} wipes out!",
	"in_water": "{rider} is in the water!",
	"combo": "What a combo from {rider}!",
	"nails": "{rider} nails the {stunt}!",
	"throws": "{rider} throws a {stunt}!",
	"full_power": "{rider} is at full power!",
	"disqualified": "{rider} is disqualified!",
	"wins": "{rider} wins at {course}!",
	"finishes": "{rider} finishes {place}!",
	"solo_finish": ["{rider} finishes in {time}!", "{rider} finishes!"],
	"photo_finish": "Photo finish!",
	"ten_seconds": "Ten seconds left!",
	"rings": "{rings} rings in a row!",
	"lap_record": "New lap record!",
	"tide": "The tide is going out. Watch for rocks!",
	"weather_change": "The weather is changing!",
}
## The places each kind of call can name: moving up ends in 2nd or 3rd (1st takes the lead),
## and the winner has a call of its own.
const PLACES: Dictionary[String, Array] = {"moves_up": [2, 3], "finishes": [2, 3, 4]}
const PLACE_WORDS: Array[String] = ["", "first", "second", "third", "fourth", "fifth", "sixth"]
## Ring chains are voiced up to this many; a longer one only shows.
const RINGS_VOICED := 15

## Every line said so far, for tests: [time, text shown].
var history: Array = []
## The id of each line shown so far, for tests.
var voiced: PackedStringArray = []

var _label: RichTextLabel
var _voice: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _queue: Array[Dictionary] = []
var _showing := 0.0
var _clock := 0.0
var _leader: RacerState
var _last_lead_call := -INF
var _player_place := 0
var _last_place_call := -INF
var _final_lap_called := false
var _winner_called := false
var _modes_connected := false
var _chain_called := 0
var _ten_seconds_called := false
var _tween: Tween


func _ready() -> void:
	layer = 6
	_label = RichTextLabel.new()
	_label.name = "Line"
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_override(&"normal_font", MenuStyle.font())
	_label.add_theme_font_size_override(&"normal_font_size", 40)
	_label.add_theme_color_override(&"default_color", Color.WHITE)
	_label.add_theme_color_override(&"font_outline_color", MenuStyle.OUTLINE)
	_label.add_theme_constant_override(&"outline_size", 8)
	add_child(_label)
	# 1200 px wide, centred, near the top.
	_label.anchor_left = 0.5
	_label.anchor_right = 0.5
	_label.offset_left = -600.0
	_label.offset_right = 600.0
	_label.offset_top = 34.0
	_label.offset_bottom = 100.0
	_label.modulate.a = 0.0
	_voice = AudioStreamPlayer.new()
	_voice.name = "Voice"
	_voice.bus = &"Voice"
	add_child(_voice)
	_rng.seed = 96
	if race == null:
		return
	race.countdown_changed.connect(_on_countdown)
	race.started.connect(func() -> void: call_out("off" if race.racers.size() > 1 else "go", {}, PRIORITY_HIGH))
	race.racer_crashed.connect(_on_crashed)
	race.racer_landed.connect(_on_landed)
	race.racer_disqualified.connect(func(racer: RacerState) -> void:
		call_out("disqualified", {"rider": racer}, PRIORITY_HIGH))
	race.racer_finished.connect(_on_finished)
	race.lap_completed.connect(_on_lap)
	race.power_changed.connect(func(racer: RacerState, level: int) -> void:
		if racer == race.watched and level >= race.rules.power_levels:
			call_out("full_power", {"rider": racer}, PRIORITY_LOW))
	race.tide_turned.connect(func(_level: float) -> void: call_out("tide", {}, PRIORITY_NORMAL))
	race.weather_changed.connect(func(weather: Weather) -> void:
		if weather != null and weather.announcement != "":
			say(weather.announcement, PRIORITY_NORMAL, "weather_" + weather.id)
		else:
			call_out("weather_change", {}, PRIORITY_NORMAL))


## Queues a call of [param kind] (a key of [constant CALLS]) about [param values]: a
## [RacerState] for {rider}, and the course's name, a stunt's id, a place or a count.
func call_out(kind: String, values: Dictionary = {}, priority: int = PRIORITY_NORMAL) -> void:
	var words: Variant = CALLS[kind]
	var shown_template: String = words[0] if words is Array else words
	var shown := {}
	var spoken := {}
	for key: String in values:
		var value: Variant = values[key]
		match key:
			"rider":
				shown[key] = _name(value)
				spoken[key] = (value as RacerState).display_name
			"stunt":
				shown[key] = JetSki.STUNTS[value]["label"]
				spoken[key] = (JetSki.STUNTS[value]["label"] as String).to_lower()
			"place":
				shown[key] = Race.ordinal(value).to_upper()
				spoken[key] = place_word(value)
			"time":
				shown[key] = value
			_:
				shown[key] = str(value).to_upper()
				spoken[key] = str(value)
	var id := line_id(kind, spoken)
	if kind == "rings" and int(values["rings"]) > RINGS_VOICED:
		id = ""
	say(_fill(shown_template.to_upper(), shown), priority, id)


## Queues [param text] (uppercase, with names already coloured by [method _name]) and the
## voice clip [param id] with it, if there is one.
func say(text: String, priority: int = PRIORITY_NORMAL, id: String = "") -> void:
	history.append([race.race_time if race != null else 0.0, text])
	var line := {"text": text, "priority": priority, "at": _clock, "id": id}
	if priority >= PRIORITY_HIGH:
		_queue.push_front(line)
		if _showing > 0.0:
			_showing = 0.0
	else:
		_queue.append(line)
	while _queue.size() > 3:
		_queue.pop_back()


func _process(delta: float) -> void:
	_clock += delta
	if race == null:
		return
	_connect_modes()
	if race.phase == Race.Phase.RACING:
		_watch_places()
		_watch_clock()
	if _showing > 0.0:
		_showing -= delta
		if _showing <= 0.0 and _queue.is_empty():
			_fade_out()
		return
	while not _queue.is_empty() and _clock - float(_queue[0]["at"]) > stale_time:
		_queue.pop_front()
	if _queue.is_empty():
		return
	var line: Dictionary = _queue.pop_front()
	_show(line["text"], line["id"])


func _show(text: String, id: String) -> void:
	_label.text = "[center]%s[/center]" % text
	_showing = line_time
	voiced.append(id)
	# A new line cuts off the last one's voice, so the announcer never talks over himself.
	_voice.stop()
	var clip := voice_clip(id)
	if clip != null:
		_voice.stream = clip
		_voice.play()
		_showing = maxf(line_time, clip.get_length() + 0.3)
	if _tween != null:
		_tween.kill()
	_label.modulate.a = 1.0
	_label.scale = Vector2(1.08, 1.08)
	_label.pivot_offset = Vector2(600, 24)
	_tween = create_tween()
	_tween.tween_property(_label, ^"scale", Vector2.ONE, 0.15)


func _notification(what: int) -> void:
	if (what == NOTIFICATION_PAUSED or what == NOTIFICATION_UNPAUSED) and _voice != null:
		_voice.stream_paused = what == NOTIFICATION_PAUSED


func _fade_out() -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_label, ^"modulate:a", 0.0, 0.3)


## A racer's name, coloured.
func _name(racer: RacerState) -> String:
	return "[color=#%s]%s[/color]" % [NAME_COLOR, racer.display_name.to_upper()]


func _on_countdown(left: int) -> void:
	if left == 3:
		var where := {"course": race.course.course_name if race.course != null else ""}
		if Game.mode == Game.Mode.TIME_TRIAL:
			var ghost := race.time_trial != null and race.time_trial.ghost != null
			call_out("time_trial_ghost" if ghost else "time_trial", where, PRIORITY_HIGH)
		elif Game.mode == Game.Mode.STUNT:
			call_out("stunt_run", where, PRIORITY_HIGH)
		else:
			call_out("marks", where, PRIORITY_HIGH)


## Lead changes and the player moving up the order.
func _watch_places() -> void:
	if race.racers.size() < 2:
		return
	var leader: RacerState = null
	for racer in race.racers:
		if racer.place == 1:
			leader = racer
	if leader != _leader:
		var previous := _leader
		_leader = leader
		if previous != null and leader != null and race.race_time > 4.0 \
				and _clock - _last_lead_call > lead_call_gap and not leader.finished:
			_last_lead_call = _clock
			call_out("lead", {"rider": leader}, PRIORITY_NORMAL)
			_last_place_call = _clock
	var watched := race.watched
	if watched == null or not watched.is_racing():
		return
	if _player_place != 0 and watched.place < _player_place and watched.place > 1 \
			and race.race_time > 4.0 and _clock - _last_place_call > lead_call_gap:
		_last_place_call = _clock
		call_out("moves_up", {"rider": watched, "place": watched.place}, PRIORITY_LOW)
	_player_place = watched.place


## In stunt mode, the last ten seconds.
func _watch_clock() -> void:
	if race.stunt_mode != null and not _ten_seconds_called and not race.stunt_mode.over \
			and race.stunt_mode.time_left() <= 10.0:
		_ten_seconds_called = true
		call_out("ten_seconds", {}, PRIORITY_HIGH)


func _connect_modes() -> void:
	if _modes_connected:
		return
	_modes_connected = true
	if race.stunt_mode != null:
		race.stunt_mode.ring_taken.connect(func(_ring: StuntRing, _points: int, _multiplier: float) -> void:
			var chain := race.stunt_mode.chain
			if chain >= 3 and chain > _chain_called:
				_chain_called = chain
				call_out("rings", {"rings": chain}, PRIORITY_NORMAL))
		race.stunt_mode.ring_missed.connect(func(_ring: StuntRing) -> void: _chain_called = 0)
	if race.time_trial != null:
		var best := [race.time_trial.record_lap]
		race.time_trial.split.connect(func(_lap: int, lap_time: float, _difference: float) -> void:
			# The lap itself against the best lap so far (the record, then this run's laps).
			if lap_time < best[0]:
				if best[0] < INF:
					call_out("lap_record", {}, PRIORITY_HIGH)
				best[0] = lap_time)


func _on_crashed(racer: RacerState, _reason: StringName) -> void:
	if not racer.is_racing():
		return
	call_out("wipeout" if racer == race.watched else "in_water", {"rider": racer},
			PRIORITY_NORMAL if racer == race.watched else PRIORITY_LOW)


func _on_landed(racer: RacerState, quality: StringName, stunts: Array[StringName], _points: int) -> void:
	if quality == &"failed" or stunts.is_empty():
		return
	if stunts.size() > 1:
		call_out("combo", {"rider": racer}, PRIORITY_NORMAL)
	elif racer == race.watched:
		if quality == &"clean":
			call_out("nails", {"rider": racer, "stunt": stunts[0]}, PRIORITY_LOW)
	elif _rng.randf() < 0.6:
		call_out("throws", {"rider": racer, "stunt": stunts[0]}, PRIORITY_LOW)


func _on_lap(racer: RacerState, lap: int, _lap_time: float) -> void:
	if lap == race.laps - 1 and not _final_lap_called and racer.place == 1 and race.racers.size() > 1:
		_final_lap_called = true
		call_out("final_lap", {"rider": racer}, PRIORITY_NORMAL)


func _on_finished(racer: RacerState) -> void:
	if race.racers.size() < 2:
		if racer == race.watched:
			call_out("solo_finish", {"rider": racer, "time": Race.format_time(racer.finish_time)}, PRIORITY_HIGH)
		return
	if not _winner_called:
		_winner_called = true
		call_out("wins", {"rider": racer, "course": race.course.course_name if race.course != null else ""}, PRIORITY_HIGH)
		return
	# A close finish behind the winner, or the player coming home.
	for other in race.racers:
		if other != racer and other.finished and absf(other.finish_time - racer.finish_time) < 0.3:
			call_out("photo_finish", {}, PRIORITY_HIGH)
			return
	if racer == race.watched:
		call_out("finishes", {"rider": racer, "place": racer.place}, PRIORITY_NORMAL)


## The voice clip for line [param id], or null if it has none.
static func voice_clip(id: String) -> AudioStream:
	var path := "%s/%s.ogg" % [VOICE_DIR, id]
	return load(path) as AudioStream if id != "" and ResourceLoader.exists(path) else null


## Every line the announcer can call in this game, with its riders, courses and weathers.
static func game_lines() -> Dictionary[String, String]:
	var riders := PackedStringArray()
	for rider in Game.riders:
		riders.append(rider.display_name)
	var courses := PackedStringArray()
	for info in Game.courses:
		if not courses.has(info.display_name):
			courses.append(info.display_name)
	return every_line(riders, courses, Game.weathers)


## The ids of this game's lines that have no voice clip.
static func unvoiced() -> PackedStringArray:
	var missing := PackedStringArray()
	for id: String in game_lines():
		if voice_clip(id) == null:
			missing.append(id)
	return missing


## A line's id, which names its clip: the kind, then what it names, in the order its words
## name them (`wins_koa_gull_cove`). The time a solo finish shows isn't part of it.
static func line_id(kind: String, spoken: Dictionary) -> String:
	var words: Variant = CALLS[kind]
	var template: String = words[1] if words is Array else words
	var id := kind
	for key in _placeholders(template):
		id += "_" + str(spoken[key]).to_lower().validate_filename().replace(" ", "_").replace("'", "")
	return id


## A place as a word, for the voice (2 is "second").
static func place_word(place: int) -> String:
	return PLACE_WORDS[place] if place < PLACE_WORDS.size() else Race.ordinal(place)


## Every line the announcer can call in a game with these riders, courses (their names) and
## weathers, as id to the words the voice says: what `tools/voice/` records.
static func every_line(riders: PackedStringArray, courses: PackedStringArray, weathers: Array[Weather]) -> Dictionary[String, String]:
	var stunts := PackedStringArray()
	for stunt: StringName in JetSki.STUNTS:
		var label := (JetSki.STUNTS[stunt]["label"] as String).to_lower()
		if not stunts.has(label):
			stunts.append(label)
	var lines: Dictionary[String, String] = {}
	for kind: String in CALLS:
		var words: Variant = CALLS[kind]
		var template: String = words[1] if words is Array else words
		var choices: Array[Dictionary] = [{}]
		for key in _placeholders(template):
			var domain: Array = []
			match key:
				"rider":
					domain = Array(riders)
				"course":
					domain = Array(courses)
				"stunt":
					domain = Array(stunts)
				"place":
					domain = PLACES[kind].map(func(place: int) -> String: return place_word(place))
				"rings":
					domain = range(3, RINGS_VOICED + 1)
			var wider: Array[Dictionary] = []
			for choice in choices:
				for value: Variant in domain:
					var more := choice.duplicate()
					more[key] = value
					wider.append(more)
			choices = wider
		for choice in choices:
			lines[line_id(kind, choice)] = _fill(template, choice)
	for weather in weathers:
		if weather.announcement != "":
			lines["weather_" + weather.id] = _sentence_case(weather.announcement)
	return lines


## The {keys} in [param template], in order.
static func _placeholders(template: String) -> PackedStringArray:
	var keys := PackedStringArray()
	var at := template.find("{")
	while at >= 0:
		var end := template.find("}", at)
		keys.append(template.substr(at + 1, end - at - 1))
		at = template.find("{", end)
	return keys


## [param template] with each {key} replaced by its value; an uppercase template takes
## uppercase keys.
static func _fill(template: String, values: Dictionary) -> String:
	var text := template
	for key: String in values:
		text = text.replace("{%s}" % key, str(values[key])).replace("{%s}" % key.to_upper(), str(values[key]))
	return text


## UPPERCASE TEXT as it would be said: "Here comes the storm! Hold on tight!"
static func _sentence_case(text: String) -> String:
	var out := ""
	var start := true
	for character in text.to_lower():
		out += character.to_upper() if start and character != " " else character
		if character in ".!?":
			start = true
		elif character != " ":
			start = false
	return out
