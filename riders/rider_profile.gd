class_name RiderProfile
extends Resource
## A rider: name, colours, how the rider's craft rides (top speed, acceleration, handling and
## grip), and how well the rider races when the computer rides.
##
## The four craft factors scale a copy of the craft's [JetSkiTuning] ([method tuned]), so a
## rider changes the ride without code: 1.0 is the base craft, 1.05 is 5% more.

## Name shown on the HUD and the results.
@export var display_name: String = "Rider"
## One line about the rider, for the rider select screen.
@export var tagline: String = ""
@export_group("Colours")
@export var hull_color: Color = Color(0.98, 0.78, 0.10)
@export var trim_color: Color = Color(0.10, 0.35, 0.85)
@export var bottom_color: Color = Color(0.94, 0.95, 0.97)
@export var suit_color: Color = Color(0.85, 0.12, 0.14)
@export var vest_color: Color = Color(1.0, 0.86, 0.1)
@export var helmet_color: Color = Color(0.95, 0.96, 1.0)
@export_group("Craft")
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
## Craft plus rider, in kilograms. A heavier craft pushes others aside and is pushed less.
@export_range(200.0, 400.0, 1.0, "suffix:kg") var mass: float = 300.0
@export_group("Computer rider")
## 0 to 1: how well the computer rides as this rider (see [AIDriver]).
@export_range(0.0, 1.0, 0.01) var ai_skill: float = 0.8
## Seed for the computer rider's mistakes.
@export var ai_seed: int = 1

## The four stats shown on the rider select screen, in order.
const STATS: Array[StringName] = [&"top_speed", &"acceleration", &"handling", &"grip"]
const STAT_LABELS: Array[String] = ["TOP SPEED", "ACCELERATION", "HANDLING", "GRIP"]


## Paints a [JetSkiModel] (or any model with the same colour properties) in this rider's colours.
func apply_colors(model: Node) -> void:
	if model == null:
		return
	for property in [&"hull_color", &"trim_color", &"bottom_color", &"suit_color", &"vest_color", &"helmet_color"]:
		if property in model:
			model.set(property, get(property))


## A copy of [param base] changed by this rider's craft factors.
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
	# Forces that scale with the body keep the same feel at another weight.
	var weight := mass / base.mass
	t.mass = mass
	t.inertia = base.inertia * weight
	t.max_thrust *= weight
	t.linear_drag *= weight
	t.quadratic_drag *= weight
	t.buoyancy_stiffness = base.buoyancy_stiffness * weight
	t.water_damping = base.water_damping * weight
	t.slam_damping = base.slam_damping * weight
	t.planing_lift = base.planing_lift * weight
	t.lean_torque = base.lean_torque * weight
	t.bank_stiffness = base.bank_stiffness * weight
	t.pitch_limit_stiffness = base.pitch_limit_stiffness * weight
	t.pitch_damping = base.pitch_damping * weight
	t.roll_damping = base.roll_damping * weight
	t.trim_torque = base.trim_torque * weight
	t.air_drag = base.air_drag * weight
	return t


## A stat on the rider select screen's 1-to-5 scale: 3 for the base craft, a point for every
## 7% above or below it, in half steps.
func rating(stat: StringName) -> float:
	var value: float = get(stat)
	return clampf(snappedf(3.0 + (value - 1.0) / 0.07, 0.5), 1.0, 5.0)
