class_name CourseInfo
extends Resource
## A course as the menus list it: its name, the conditions to expect, its scene and its map.
## tools/courses/course_tool.py writes it (`levels/<id>.course.tres`) from the course's spec.

## Where the course comes in the menus and the championship: lower first.
@export var order: int = 0
## Short name used in save files and on the command line (`-- --course gull_cove`).
@export var id: String = ""
@export var display_name: String = ""
## One line on the conditions, for the course select screen.
@export var conditions: String = ""
## The course scene: its root is a [Course].
@export_file("*.tscn") var scene: String = ""
## The top-down map the course select screen shows (`levels/<id>_map.png`), or null.
@export var map: Texture2D
## The waves, sky, water look and tide to race [member scene] in instead of its own, or null
## for the scene's own. Several courses can share a scene this way, each with its own
## [member id], so each keeps its own records and ghost.
@export var overrides: CourseConditions
## The weathers a race here can have: a championship's forecast and a random quick race draw
## from them. Empty: every weather in [member Game.weathers].
@export var weathers: Array[Weather] = []
