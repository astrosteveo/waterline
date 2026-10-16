class_name EngineVoice
extends Resource
## A craft's engine as [EngineSound] plays it: loops made at a few revs with the throttle open
## ([member on_load]) and shut ([member off_load]), which it crossfades and bends in pitch to
## the revs between them, and the starter cranking it into life. kiln builds the sounds from
## `art/audio/engines/`; the revs here must be the ones the recipe made them at, which the
## file names carry (the `engine_sound` scenario checks).
##
## The revs follow how a jet ski's engine works: the pump is driven straight off the crankshaft
## and its load grows steeply with the revs, so the throttle sets the revs more than the speed
## does, and with the intake out of the water the load is gone and the engine flies up to its
## limiter.

## Revs at idle, with the throttle shut.
@export_range(500.0, 4000.0, 10.0, "suffix:rpm") var idle_rpm: float = 1750.0
## Revs at full throttle on the water, at a standstill (they rise a little with speed).
@export_range(2000.0, 12000.0, 10.0, "suffix:rpm") var rated_rpm: float = 7800.0
## Where the rev limiter cuts the ignition.
@export_range(2000.0, 12000.0, 10.0, "suffix:rpm") var limiter_rpm: float = 8100.0
## The revs each loop was made at, from idle up.
@export var layer_rpm: PackedFloat32Array = PackedFloat32Array()
## A loop at each of [member layer_rpm] with the throttle open, and with it shut.
@export var on_load: Array[AudioStream] = []
@export var off_load: Array[AudioStream] = []
## The starter cranking the engine over until it catches, and the revs flaring.
@export var start: AudioStream
## Seconds into [member start] that the engine catches and the loops take over.
@export_range(0.0, 2.0, 0.01, "suffix:s") var start_catch: float = 0.55

@export_group("Spool")
## Seconds to 1/e of the way to higher revs: with the pump loaded, and with it out of the water.
@export_range(0.01, 2.0, 0.01, "suffix:s") var spool_up: float = 0.3
@export_range(0.01, 2.0, 0.01, "suffix:s") var spool_up_free: float = 0.12
## Seconds to 1/e of the way to lower revs: the loaded pump brakes the engine, the free one doesn't.
@export_range(0.01, 4.0, 0.01, "suffix:s") var spool_down: float = 0.35
@export_range(0.01, 4.0, 0.01, "suffix:s") var spool_down_free: float = 0.7


## What is wrong with this voice, if anything: a list longer than another, a loop whose file
## wasn't made at the revs listed for it (kiln names them `<craft>_on_<rpm>.wav`), a loop that
## doesn't loop, revs out of order.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if on_load.size() != layer_rpm.size() or off_load.size() != layer_rpm.size():
		found.append("%d revs, %d open loops, %d shut" % [layer_rpm.size(), on_load.size(), off_load.size()])
		return found
	if not (idle_rpm < rated_rpm and rated_rpm < limiter_rpm):
		found.append("idle %d, rated %d and limiter %d rpm out of order" % [idle_rpm, rated_rpm, limiter_rpm])
	for i in layer_rpm.size():
		if i > 0 and layer_rpm[i] <= layer_rpm[i - 1]:
			found.append("layer %d's revs don't rise" % i)
		for stream: AudioStream in [on_load[i], off_load[i]]:
			var file := stream.resource_path.get_file().get_basename()
			if file.get_slice("_", file.get_slice_count("_") - 1) != str(int(layer_rpm[i])):
				found.append("%s isn't at %d rpm" % [file, layer_rpm[i]])
			var wav := stream as AudioStreamWAV
			if wav != null and wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
				found.append("%s doesn't loop" % file)
	return found
