class_name CourseGate
extends RefCounted
## A line across the course that racers cross in order: one through each buoy, and the
## start and finish line. [Course] builds them; [Race] tests each racer's movement against
## them every physics tick.

## Where the line crosses the buoy (or the centre line, for the finish line). y is 0.
var position: Vector3 = Vector3.ZERO
## Distance along the course's centre line, from the start line.
var offset: float = 0.0
## Direction of travel across the line (the course tangent, horizontal).
var forward: Vector3 = Vector3.FORWARD
## Horizontal direction along the line, to the right of [member forward].
var right: Vector3 = Vector3.RIGHT
## How far the line reaches to the left and to the right of [member position].
var reach_left: float = 30.0
var reach_right: float = 30.0
## Which side of the buoy a racer must pass on: -1 left of it (keep it on your right),
## +1 right of it (keep it on your left), 0 either (the finish line).
var required_side: int = 0
## The buoy this gate belongs to, or null for the finish line.
var buoy: Buoy = null
## Index among the course's buoy gates, or -1 for the finish line.
var index: int = -1


## Where a move from [param from] to [param to] crosses this line going forward: the
## fraction of the move (0 to 1), or -1 if it doesn't cross within the line's reach.
func crossing(from: Vector3, to: Vector3) -> float:
	var before := (from - position).dot(forward)
	var after := (to - position).dot(forward)
	if before >= 0.0 or after < 0.0:
		return -1.0
	var t := before / (before - after)
	var along := (from.lerp(to, t) - position).dot(right)
	if along < -reach_left or along > reach_right:
		return -1.0
	return t


## Signed distance along the line from the gate's centre to [param point]; positive is to
## the right of [member position].
func side_offset(point: Vector3) -> float:
	return (point - position).dot(right)


## True if a racer crossing at [param point] passed on the side the buoy asks for.
func is_correct_side(point: Vector3) -> bool:
	if required_side == 0:
		return true
	return signf(side_offset(point)) == float(required_side)
