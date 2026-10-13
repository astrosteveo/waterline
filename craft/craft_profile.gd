class_name CraftProfile
extends Resource
## A jet ski: its name, a line about how it rides, its scene, its base tuning and its four
## stats (top speed, acceleration, handling and grip). Any rider can ride any craft.
##
## The four stats scale a copy of the base [JetSkiTuning] ([method tuned]), so a craft changes
## the ride without code: 1.0 is the base craft, 1.05 is 5% more. The rider's weight changes
## the result afterwards ([method RiderProfile.tuned]).

## Short name used on the command line (`-- --craft petrel`) and in save files.
@export var id: String = ""
## Name shown in menus.
@export var display_name: String = "Craft"
## One line about how the craft rides, for menus.
@export var tagline: String = ""
## The craft's scene: its root is a [JetSki].
@export var scene: PackedScene
## The tuning before the four stats. Empty: the tuning on the craft's scene.
@export var tuning: JetSkiTuning
@export_group("Stats")
## Top speed factor. The drag falls with its square, so the thrust and the acceleration
## from a standstill don't change.
@export_range(0.8, 1.2, 0.01) var top_speed: float = 1.0
## Acceleration factor: the thrust grows by it and the drag with it, so the top speed
## doesn't change.
@export_range(0.8, 1.3, 0.01) var acceleration: float = 1.0
## Handling factor: the turn rates and how quickly the yaw follows the stick.
@export_range(0.8, 1.3, 0.01) var handling: float = 1.0
## Grip factor: the most sideways force the hull makes and how quickly it cancels a slide.
@export_range(0.8, 1.3, 0.01) var grip: float = 1.0

## The four stats shown in menus, in order.
const STATS: Array[StringName] = [&"top_speed", &"acceleration", &"handling", &"grip"]
const STAT_LABELS: Array[String] = ["TOP SPEED", "ACCELERATION", "HANDLING", "GRIP"]


## A copy of [param base] changed by this craft's four stats.
func tuned(base: JetSkiTuning) -> JetSkiTuning:
	var t := base.duplicate() as JetSkiTuning
	# Top speed v solves thrust = linear * v + quadratic * v². Multiplying the thrust and both
	# drag terms by the acceleration keeps v; dividing the drag by the top speed factor (and
	# its square) moves v by that factor.
	t.max_thrust = base.max_thrust * acceleration
	t.linear_drag = base.linear_drag * acceleration / top_speed
	t.quadratic_drag = base.quadratic_drag * acceleration / (top_speed * top_speed)
	t.reference_top_speed = base.reference_top_speed * top_speed
	t.turn_rate_low = base.turn_rate_low * handling
	t.turn_rate_high = base.turn_rate_high * handling
	t.yaw_response = base.yaw_response * handling
	t.max_yaw_acceleration = base.max_yaw_acceleration * handling
	t.grip_g = base.grip_g * grip
	t.grip_rate = base.grip_rate * grip
	return t


## The tuning [param rider] gets on this craft: [member tuning] (or [param fallback] when it
## is empty) changed by the four stats, then by the rider's weight.
func tuning_for(rider: RiderProfile, fallback: JetSkiTuning = null) -> JetSkiTuning:
	var base := tuning if tuning != null else fallback
	if base == null:
		base = JetSkiTuning.new()
	var t := tuned(base)
	return rider.tuned(t) if rider != null else t


## A stat on the menus' 1-to-5 scale: 3 for the base craft, a point for every 7% above or
## below it, in half steps.
func rating(stat: StringName) -> float:
	var value: float = get(stat)
	return clampf(snappedf(3.0 + (value - 1.0) / 0.07, 0.5), 1.0, 5.0)
