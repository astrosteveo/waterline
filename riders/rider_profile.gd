class_name RiderProfile
extends Resource
## A rider: name, colours, and how well the rider races when the computer rides.
## Milestone 6 adds each rider's top speed, acceleration, handling and grip.

## Name shown on the HUD and the results.
@export var display_name: String = "Rider"
@export_group("Colours")
@export var hull_color: Color = Color(0.98, 0.78, 0.10)
@export var trim_color: Color = Color(0.10, 0.35, 0.85)
@export var suit_color: Color = Color(0.85, 0.12, 0.14)
@export var vest_color: Color = Color(1.0, 0.86, 0.1)
@export var helmet_color: Color = Color(0.95, 0.96, 1.0)
@export_group("Computer rider")
## 0 to 1: how well the computer rides as this rider (see [AIDriver]).
@export_range(0.0, 1.0, 0.01) var ai_skill: float = 0.8
## Seed for the computer rider's mistakes.
@export var ai_seed: int = 1


## Paints a [JetSkiModel] (or any model with the same colour properties) in this rider's colours.
func apply_colors(model: Node) -> void:
	if model == null:
		return
	for property in [&"hull_color", &"trim_color", &"suit_color", &"vest_color", &"helmet_color"]:
		if property in model:
			model.set(property, get(property))
