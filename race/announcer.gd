class_name Announcer
extends CanvasLayer
## The race announcer, as text across the top of the screen: the start, lead changes, the
## player moving up, the final lap, crashes, stunts, disqualifications, the finish, the tide,
## the weather, and in the solo modes ring chains, lap records and the clock running down.
##
## Lines queue up and show one at a time for [member line_time] seconds; a line waiting
## longer than [member stale_time] is dropped, so the calls stay current. A more important
## line cuts in ahead of the queue.

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

## Every line said so far, for tests: [time, text].
var history: Array = []

var _label: RichTextLabel
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
	if race == null:
		return
	race.countdown_changed.connect(_on_countdown)
	race.started.connect(func() -> void: say("AND THEY'RE OFF!" if race.racers.size() > 1 else "GO!", PRIORITY_HIGH))
	race.racer_crashed.connect(_on_crashed)
	race.racer_landed.connect(_on_landed)
	race.racer_disqualified.connect(func(racer: RacerState) -> void:
		say("%s IS DISQUALIFIED!" % _name(racer), PRIORITY_HIGH))
	race.racer_finished.connect(_on_finished)
	race.lap_completed.connect(_on_lap)
	race.power_changed.connect(func(racer: RacerState, level: int) -> void:
		if racer == race.watched and level >= race.rules.power_levels:
			say("%s IS AT FULL POWER!" % _name(racer), PRIORITY_LOW))
	race.tide_turned.connect(func(_level: float) -> void:
		say("THE TIDE IS GOING OUT. WATCH FOR ROCKS!", PRIORITY_NORMAL))
	race.weather_changed.connect(func(weather: Weather) -> void:
		say(weather.announcement if weather != null and weather.announcement != "" else "THE WEATHER IS CHANGING!",
				PRIORITY_NORMAL))


## Queues [param text] (uppercase, with [b]names[/b] already coloured by [method _name]).
func say(text: String, priority: int = PRIORITY_NORMAL) -> void:
	history.append([race.race_time if race != null else 0.0, text])
	var line := {"text": text, "priority": priority, "at": _clock}
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
	_show(line["text"])


func _show(text: String) -> void:
	_label.text = "[center]%s[/center]" % text
	_showing = line_time
	if _tween != null:
		_tween.kill()
	_label.modulate.a = 1.0
	_label.scale = Vector2(1.08, 1.08)
	_label.pivot_offset = Vector2(600, 24)
	_tween = create_tween()
	_tween.tween_property(_label, ^"scale", Vector2.ONE, 0.15)


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
		var where := race.course.course_name.to_upper() if race.course != null else ""
		if Game.mode == Game.Mode.TIME_TRIAL:
			say("TIME TRIAL AT %s. BEAT THE GHOST!" % where if race.time_trial != null and race.time_trial.ghost != null
					else "TIME TRIAL AT %s. SET THE PACE!" % where, PRIORITY_HIGH)
		elif Game.mode == Game.Mode.STUNT:
			say("STUNT RUN AT %s. HIT THE RINGS!" % where, PRIORITY_HIGH)
		else:
			say("RIDERS, TAKE YOUR MARKS AT %s!" % where, PRIORITY_HIGH)


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
			say("%s TAKES THE LEAD!" % _name(leader), PRIORITY_NORMAL)
			_last_place_call = _clock
	var watched := race.watched
	if watched == null or not watched.is_racing():
		return
	if _player_place != 0 and watched.place < _player_place and watched.place > 1 \
			and race.race_time > 4.0 and _clock - _last_place_call > lead_call_gap:
		_last_place_call = _clock
		say("%s MOVES UP TO %s!" % [_name(watched), Race.ordinal(watched.place).to_upper()], PRIORITY_LOW)
	_player_place = watched.place


## In stunt mode, the last ten seconds.
func _watch_clock() -> void:
	if race.stunt_mode != null and not _ten_seconds_called and not race.stunt_mode.over \
			and race.stunt_mode.time_left() <= 10.0:
		_ten_seconds_called = true
		say("TEN SECONDS LEFT!", PRIORITY_HIGH)


func _connect_modes() -> void:
	if _modes_connected:
		return
	_modes_connected = true
	if race.stunt_mode != null:
		race.stunt_mode.ring_taken.connect(func(_ring: StuntRing, _points: int, _multiplier: float) -> void:
			var chain := race.stunt_mode.chain
			if chain >= 3 and chain > _chain_called:
				_chain_called = chain
				say("%d RINGS IN A ROW!" % chain, PRIORITY_NORMAL))
		race.stunt_mode.ring_missed.connect(func(_ring: StuntRing) -> void: _chain_called = 0)
	if race.time_trial != null:
		var best := [race.time_trial.record_lap]
		race.time_trial.split.connect(func(_lap: int, lap_time: float, _difference: float) -> void:
			# The lap itself against the best lap so far (the record, then this run's laps).
			if lap_time < best[0]:
				if best[0] < INF:
					say("NEW LAP RECORD!", PRIORITY_HIGH)
				best[0] = lap_time)


func _on_crashed(racer: RacerState, _reason: StringName) -> void:
	if not racer.is_racing():
		return
	if racer == race.watched:
		say("OH! %s WIPES OUT!" % _name(racer), PRIORITY_NORMAL)
	else:
		say("%s IS IN THE WATER!" % _name(racer), PRIORITY_LOW)


func _on_landed(racer: RacerState, quality: StringName, stunts: Array[StringName], _points: int) -> void:
	if quality == &"failed" or stunts.is_empty():
		return
	var trick: String = JetSki.STUNTS[stunts[0]]["label"]
	if stunts.size() > 1:
		say("WHAT A COMBO FROM %s!" % _name(racer), PRIORITY_NORMAL)
	elif racer == race.watched:
		if quality == &"clean":
			say("%s NAILS THE %s!" % [_name(racer), trick], PRIORITY_LOW)
	elif randf() < 0.6:
		say("%s THROWS A %s!" % [_name(racer), trick], PRIORITY_LOW)


func _on_lap(racer: RacerState, lap: int, _lap_time: float) -> void:
	if lap == race.laps - 1 and not _final_lap_called and racer.place == 1 and race.racers.size() > 1:
		_final_lap_called = true
		say("FINAL LAP! %s LEADS!" % _name(racer), PRIORITY_NORMAL)


func _on_finished(racer: RacerState) -> void:
	var course := race.course.course_name.to_upper() if race.course != null else ""
	if race.racers.size() < 2:
		if racer == race.watched:
			say("%s FINISHES IN %s!" % [_name(racer), Race.format_time(racer.finish_time)], PRIORITY_HIGH)
		return
	if not _winner_called:
		_winner_called = true
		say("%s WINS AT %s!" % [_name(racer), course], PRIORITY_HIGH)
		return
	# A close finish behind the winner, or the player coming home.
	for other in race.racers:
		if other != racer and other.finished and absf(other.finish_time - racer.finish_time) < 0.3:
			say("PHOTO FINISH!", PRIORITY_HIGH)
			return
	if racer == race.watched:
		say("%s FINISHES %s!" % [_name(racer), Race.ordinal(racer.place).to_upper()], PRIORITY_NORMAL)
