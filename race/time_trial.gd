class_name TimeTrial
extends Node
## Time trial: the player alone against the clock and a ghost of the course's best run.
##
## It records the run ([GhostRecorder]), plays back the saved ghost ([GhostRider]), and at the
## finish saves the race time and best lap to [Records] if they beat the records, and the run
## as the new ghost if it set the race record.

## A lap ended: [param lap_time] and its difference from the record lap (NAN if none).
signal split(lap: int, lap_time: float, difference: float)
## The run ended: [param records] says which records it set (race, lap).
signal run_over(records: Dictionary)

var race: Race
var course_id: String = ""
var record_race: float = INF
var record_lap: float = INF
var record_rider: String = ""
## Which records the run set, once over.
var new_records: Dictionary = {}
var ghost: GhostRider
var recorder: GhostRecorder


func setup(p_race: Race, p_course_id: String) -> void:
	race = p_race
	course_id = p_course_id
	var records := Game.records
	record_race = records.best_race(course_id)
	record_lap = records.best_lap(course_id)
	record_rider = records.best_race_rider(course_id)
	recorder = GhostRecorder.new()
	recorder.name = "GhostRecorder"
	recorder.craft = race.player.craft
	add_child(recorder)
	var saved := records.load_ghost(course_id)
	if not saved.is_empty():
		ghost = GhostRider.new()
		ghost.name = "Ghost"
		ghost.race = race
		race.add_child(ghost)
		if not ghost.setup(saved, preload("res://jetski/model/jetski_model.tscn"), Game.rider_named(str(saved.get("rider", "")))):
			ghost.queue_free()
			ghost = null
	race.started.connect(recorder.start)
	race.lap_completed.connect(_on_lap)
	race.finished.connect(_on_finished)


func _on_lap(racer: RacerState, lap: int, lap_time: float) -> void:
	if racer != race.player:
		return
	split.emit(lap, lap_time, lap_time - record_lap if record_lap < INF else NAN)


func _on_finished() -> void:
	recorder.stop()
	var player := race.player
	if player.disqualified or not player.finished:
		run_over.emit({})
		return
	var rider := player.profile.display_name if player.profile != null else ""
	new_records = Game.records.submit_time_trial(course_id, rider, player.finish_time, player.lap_times)
	if new_records.get("race", false):
		Game.records.save_ghost(course_id, recorder.data(rider, course_id, player.finish_time))
	run_over.emit(new_records)
