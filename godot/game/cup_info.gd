class_name CupInfo
extends Resource
## A championship cup: its name, its courses in the order they are raced, the laps per race
## and how much better the computer riders ride. Each cup is a `*.cup.tres` in `res://cups/`.

## Where the cup comes on the cup select screen: lower first.
@export var order: int = 0
## Short name used on the command line (`-- --cup coast_cup`).
@export var id: String = ""
@export var display_name: String = ""
## The courses, in the order the championship runs them.
@export var courses: Array[CourseInfo] = []
## Laps per race; 0 races each course's own number of laps.
@export_range(0, 9, 1) var laps: int = 3
## Added to each computer rider's skill (kept within 0 to 1) in this cup's races.
@export_range(-1.0, 1.0, 0.01) var skill_offset: float = 0.0
