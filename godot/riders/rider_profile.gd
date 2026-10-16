class_name RiderProfile
extends Resource
## A rider: name, colours, weight, the craft the rider rides by default, and how well the
## rider races when the computer rides.
##
## How the craft rides (top speed, acceleration, handling, grip) belongs to the craft
## ([CraftProfile]). The rider's weight changes the craft's tuning afterwards ([method tuned]).

## Name shown on the HUD and the results.
@export var display_name: String = "Rider"
## One line about the rider, for the rider select screen.
@export var tagline: String = ""
## The craft this rider rides when the computer rides, and the player's first choice.
@export var default_craft: CraftProfile
## The rider's body and gear, built by kiln (see [member JetSkiModel.rider_scene]). Empty: the
## model's own.
@export var model: PackedScene
@export_group("Colours")
@export var hull_color: Color = Color(0.98, 0.78, 0.10)
@export var trim_color: Color = Color(0.10, 0.35, 0.85)
@export var bottom_color: Color = Color(0.94, 0.95, 0.97)
@export var suit_color: Color = Color(0.85, 0.12, 0.14)
@export var vest_color: Color = Color(1.0, 0.86, 0.1)
@export var helmet_color: Color = Color(0.95, 0.96, 1.0)
@export_group("Weight")
## Craft plus rider, in kilograms. A heavier craft pushes others aside and is pushed less.
@export_range(200.0, 400.0, 1.0, "suffix:kg") var mass: float = 300.0
@export_group("Computer rider")
## 0 to 1: how well the computer rides as this rider (see [AIDriver]).
@export_range(0.0, 1.0, 0.01) var ai_skill: float = 0.8
## Seed for the computer rider's mistakes.
@export var ai_seed: int = 1


## The weight on the menus' 1-to-5 scale: 3 at 300 kg (the base tuning's mass), a point for
## every 15 kg above or below it, in half steps.
func weight_rating() -> float:
	return clampf(snappedf(3.0 + (mass - 300.0) / 15.0, 0.5), 1.0, 5.0)


## Dresses a [JetSkiModel] (or any model with the same properties) as this rider: puts the
## rider's body and gear on it ([member model]) and paints the craft and the gear in the rider's
## colours.
func dress(craft_model: Node) -> void:
	if craft_model == null:
		return
	if model != null and &"rider_scene" in craft_model:
		craft_model.set(&"rider_scene", model)
	for property in [&"hull_color", &"trim_color", &"bottom_color", &"suit_color", &"vest_color", &"helmet_color"]:
		if property in craft_model:
			craft_model.set(property, get(property))


## A copy of [param base] changed by this rider's weight. Every force that scales with the
## body (thrust, drag, buoyancy, damping, torques) scales with the mass too, so the weight
## changes collisions (who pushes whom), not the ride.
func tuned(base: JetSkiTuning) -> JetSkiTuning:
	var t := base.duplicate() as JetSkiTuning
	var weight := mass / base.mass
	t.mass = mass
	t.inertia = base.inertia * weight
	t.max_thrust = base.max_thrust * weight
	t.linear_drag = base.linear_drag * weight
	t.quadratic_drag = base.quadratic_drag * weight
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
