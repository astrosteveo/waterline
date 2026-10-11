extends Node
## The game's state between scenes (autoload `Game`): the riders, the player's chosen rider,
## and the scene changes between menus and races.

## Every rider, in the order the rider select screen shows them.
var riders: Array[RiderProfile] = [
	preload("res://riders/marina.tres"),
	preload("res://riders/koa.tres"),
	preload("res://riders/ines.tres"),
	preload("res://riders/dax.tres"),
]
## The rider the player chose, or null to use the race scene's own.
var player_rider: RiderProfile


## The rider called [param display_name] (any case), or null.
func rider_named(display_name: String) -> RiderProfile:
	for rider in riders:
		if rider.display_name.to_lower() == display_name.to_lower():
			return rider
	return null


## Every rider but [param player], to race against them.
func opponents_for(player: RiderProfile) -> Array[RiderProfile]:
	var others: Array[RiderProfile] = []
	for rider in riders:
		if rider != player:
			others.append(rider)
	return others


## The value after [param flag] on the command line (`-- --rider koa`), or "".
static func arg_value(flag: String) -> String:
	var args := OS.get_cmdline_user_args()
	var at := args.find(flag)
	return args[at + 1] if at >= 0 and at + 1 < args.size() else ""
