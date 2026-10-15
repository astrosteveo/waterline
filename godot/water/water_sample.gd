class_name WaterSample
extends RefCounted
## What the water surface is doing at one horizontal position: returned by
## [method WaveSet.sample] and [method Ocean.sample].

## World height of the surface, in meters.
var height: float = 0.0
## Unit surface normal.
var normal: Vector3 = Vector3.UP
## Velocity of the water at the surface (the orbital motion of the waves), in m/s.
var velocity: Vector3 = Vector3.ZERO
## Determinant of the horizontal displacement's Jacobian: 1 on flat water, smaller where
## the surface is squeezed together at a crest, 0 where a crest would fold over.
var fold: float = 1.0
