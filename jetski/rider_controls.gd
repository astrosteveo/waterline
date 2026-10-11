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
## True on the tick the rider asks for a stunt. [JetSki] clears it once read.
var stunt: bool = false
## The stick or keys held when the stunt was asked for: x is steer (-1 left to 1 right), y is
## lean (-1 back to 1 forward). It picks the stunt (see [method JetSki.stunt_for]).
var stunt_direction: Vector2 = Vector2.ZERO


func clear() -> void:
	throttle = 0.0
	steer = 0.0
	lean = 0.0
	stunt = false
	stunt_direction = Vector2.ZERO


## Asks for the stunt that [param direction] picks (x steer, y lean).
func request_stunt(direction: Vector2) -> void:
	stunt = true
	stunt_direction = direction
