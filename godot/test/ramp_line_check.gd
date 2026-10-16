extends RefCounted
## Checks the racing line over each ramp of a course (issue #74): it runs up the ramp,
## [member RacingLine.ramp_margin] inside its sides, straight (from the leading edge to the lip it
## moves sideways less than [constant TOLERANCE]), and the gap a rider's moves are kept in is
## inside the ramp, [member RacingLine.ramp_margin] from its sides, from
## [member RacingLine.ramp_approach] before the leading edge to the lip. Run from gdh on a course:
## [code]gdh live eval "load('res://test/ramp_line_check.gd').new().failures(course)"[/code]

## How far the line may move sideways up a ramp, in metres: the most is 0.39 m, on Gull Cove's
## second ramp, which has a buoy 10 m before it.
const TOLERANCE := 0.5


## The problems found, as lines of text: empty if the line takes every ramp.
func failures(course: Course) -> PackedStringArray:
	var failed := PackedStringArray()
	var line := RacingLine.new(course)
	if line.ramp_offsets.is_empty():
		failed.append("%s has no ramps" % course.name)
	for r in line.ramp_offsets.size():
		var ramp := _ramp_at(course, line.ramp_offsets[r])
		var middle := line.ramp_offsets[r]
		var lateral := line.ramp_laterals[r]
		var half := line.ramp_half_widths[r] - line.ramp_margin
		for along: float in [-ramp.length * 0.5, 0.0, ramp.length * 0.5]:
			var off := line.lateral_at(middle + along) - lateral
			if absf(off) > half + 0.01:
				failed.append("%s ramp %d: the line is %.2f m from its middle %.1f m along it, past %.2f m" % [
						course.name, r, off, along, half])
		var drift := line.lateral_at(middle + ramp.length * 0.5) - line.lateral_at(middle - ramp.length * 0.5)
		if absf(drift) > TOLERANCE:
			failed.append("%s ramp %d: the line moves %.2f m sideways up the ramp" % [course.name, r, drift])
		var gap := line.gap_between(middle - ramp.length * 0.5 - line.ramp_approach, middle + ramp.length * 0.5)
		if gap.x < lateral - half - 0.01 or gap.y > lateral + half + 0.01:
			failed.append("%s ramp %d: riders may move from %.2f to %.2f m, past the ramp's %.2f to %.2f m" % [
					course.name, r, gap.x, gap.y, lateral - half, lateral + half])
	return failed


## The ramp whose middle is nearest course offset [param offset].
static func _ramp_at(course: Course, offset: float) -> Ramp:
	var best: Ramp = null
	var best_distance := INF
	for ramp: Ramp in course.find_children("*", "Ramp", true, false):
		var at := CourseProgress.new()
		course.relocate(at, ramp.global_position)
		var distance := absf(wrapf(at.offset - offset, -course.length * 0.5, course.length * 0.5))
		if distance < best_distance:
			best_distance = distance
			best = ramp
	return best
