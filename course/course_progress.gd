class_name CourseProgress
extends RefCounted
## Where one racer is along a [Course]: the nearest point of the centre line and the
## distance travelled along it. [method Course.track] updates it every physics tick.

## Index of the nearest centre-line sample, or -1 before the first update.
var index: int = -1
## Distance along the centre line from the start line, 0 to the course length.
var offset: float = 0.0
## Signed distance from the centre line; positive to the right of the direction of travel.
var lateral: float = 0.0
## Distance travelled along the course since the start line, counting laps: one course
## length per lap. Negative behind the start line before the race.
var distance: float = 0.0


func copy_from(other: CourseProgress) -> void:
	index = other.index
	offset = other.offset
	lateral = other.lateral
	distance = other.distance
