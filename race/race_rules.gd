class_name RaceRules
extends Resource
## The rules of a race: the power meter, disqualification and the start. [Race] reads them;
## NOTES.md records the chosen values and why.

## Levels on the power meter. Each buoy passed on the correct side adds one, up to this.
@export_range(1, 10, 1) var power_levels: int = 5
## Thrust multiplier at each power level, from level 0 (empty meter) up. Top speed grows
## with about the square root of the thrust, so 1.38 is about 18% faster than 1.0.
@export var power_thrust: PackedFloat32Array = PackedFloat32Array([1.0, 1.07, 1.14, 1.22, 1.30, 1.38])
## A missed buoy empties the meter.
@export var miss_resets_power: bool = true
## Missing this many buoys in one race disqualifies a racer. 0 turns disqualification off.
@export_range(0, 50, 1) var misses_to_disqualify: int = 5
## Power levels added for each stunt landed (clean or untidy) in a race. 0 turns it off.
@export_range(0, 5, 1) var stunt_power: int = 1
## Computer riders get up to this much more thrust when far behind the player, and this
## much less when far ahead, so races stay close. 0 turns it off.
@export_range(0.0, 0.5, 0.01) var catch_up: float = 0.05
## Distance gap, in meters, at which the catch-up is at its full amount.
@export_range(10.0, 1000.0, 1.0, "suffix:m") var catch_up_distance: float = 120.0


## The thrust multiplier for [param level], clamped to the table.
func thrust_for(level: int) -> float:
	if power_thrust.is_empty():
		return 1.0
	return power_thrust[clampi(level, 0, power_thrust.size() - 1)]
