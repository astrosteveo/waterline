@tool
class_name GerstnerWave
extends Resource
## One directional wave train in a [WaveSet].
##
## A point of the surface that rests at horizontal position p moves to
##   p + direction * sharpness * amplitude * cos(f)   (horizontally)
##   amplitude * sin(f)                                (vertically)
## with f = k * dot(direction, p) - omega * t + phase, k = 2 * PI / wavelength and
## omega = sqrt(g * k) * speed_scale (the deep-water dispersion relation).
## The horizontal motion bunches points together at the crests, so crests come out
## sharp and troughs broad.

## Direction the wave travels, in degrees. 0 travels toward +X, 90 toward +Z.
@export_range(0.0, 360.0, 0.1, "degrees") var direction_degrees: float = 0.0:
	set(value):
		direction_degrees = value
		emit_changed()

## Crest-to-crest distance in meters.
@export_range(0.5, 400.0, 0.01, "or_greater", "suffix:m") var wavelength: float = 20.0:
	set(value):
		wavelength = maxf(value, 0.01)
		emit_changed()

## Height of a crest above the rest level, in meters (half the crest-to-trough height).
@export_range(0.0, 4.0, 0.001, "or_greater", "suffix:m") var amplitude: float = 0.3:
	set(value):
		amplitude = maxf(value, 0.0)
		emit_changed()

## How far points move horizontally, as a share of the amplitude. 0 gives a plain sine
## wave; 1 gives the circular orbits of a true Gerstner wave and the sharpest crests.
@export_range(0.0, 1.0, 0.01) var sharpness: float = 0.7:
	set(value):
		sharpness = clampf(value, 0.0, 1.0)
		emit_changed()

## Phase offset in degrees, so waves of similar length don't line up.
@export_range(0.0, 360.0, 0.1, "degrees") var phase_degrees: float = 0.0:
	set(value):
		phase_degrees = value
		emit_changed()

## Multiplies the natural deep-water speed of this wave.
@export_range(0.0, 4.0, 0.01) var speed_scale: float = 1.0:
	set(value):
		speed_scale = maxf(value, 0.0)
		emit_changed()


func _init(p_direction_degrees: float = 0.0, p_wavelength: float = 20.0, p_amplitude: float = 0.3,
		p_sharpness: float = 0.7, p_phase_degrees: float = 0.0) -> void:
	direction_degrees = p_direction_degrees
	wavelength = p_wavelength
	amplitude = p_amplitude
	sharpness = p_sharpness
	phase_degrees = p_phase_degrees
