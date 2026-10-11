class_name RiderControls
extends RefCounted
## What the rider asks of the craft this tick. [PlayerInput] fills it from the Input Map;
## a computer rider fills it the same way, so both drive the same physics.

## 0 to 1.
var throttle: float = 0.0
## -1 (full left) to 1 (full right).
var steer: float = 0.0
## -1 (full lean back, nose up) to 1 (full lean forward, nose down).
var lean: float = 0.0


func clear() -> void:
	throttle = 0.0
	steer = 0.0
	lean = 0.0
