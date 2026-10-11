class_name CourseInfo
extends Resource
## A course as the menus list it: its name, the conditions to expect and its scene.

## Short name used in save files and on the command line (`-- --course gull_cove`).
@export var id: String = ""
@export var display_name: String = ""
## One line on the conditions, for the course select screen.
@export var conditions: String = ""
## The course scene: its root is a [Course].
@export_file("*.tscn") var scene: String = ""
