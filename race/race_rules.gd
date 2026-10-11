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


## The thrust multiplier for [param level], clamped to the table.
func thrust_for(level: int) -> float:
	if power_thrust.is_empty():
		return 1.0
	return power_thrust[clampi(level, 0, power_thrust.size() - 1)]
