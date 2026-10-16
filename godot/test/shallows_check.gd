extends RefCounted
## Measures a course's terrain near the water's edge (issue #76): at points every
## [constant SPACING] metres where the terrain's height ([method Terrain.height_at]) lies well
## inside the split band ([constant LOWEST] to [constant HIGHEST]), a ray down finds the
## terrain's collision, and the ground it hits lies on the terrain's height. The same is worked
## out for the coarse grid the shallows had before, for comparison. Run from gdh on a course:
## [code]gdh live eval "load('res://test/shallows_check.gd').new().run(course.get_node('Terrain'))"[/code]

## Metres between the points checked.
const SPACING := 3.7
## The heights checked: inside the split band, clear of its edges, where the split cells meet
## the coarse ones.
const LOWEST := -7.0
const HIGHEST := 1.0


## Returns {"points": how many were checked, "holes": rays that found no ground, "worst": the
## largest gap in metres between the ground hit and the terrain's height, "coarse_worst": the
## same for the coarse grid alone}. Points where a ray hits something else first (a rock or a
## ramp) are left out.
func run(terrain: Terrain) -> Dictionary:
	var space := terrain.get_world_3d().direct_space_state
	var ground := terrain.get_node(^"Collision")
	var cell := terrain.size / terrain.cells
	var points := 0
	var holes := 0
	var worst := 0.0
	var coarse_worst := 0.0
	var steps := int(terrain.size / SPACING)
	for j in steps:
		for i in steps:
			var x := terrain.global_position.x - terrain.size * 0.5 + (i + 0.5) * SPACING
			var z := terrain.global_position.z - terrain.size * 0.5 + (j + 0.5) * SPACING
			var height := terrain.height_at(x, z)
			if height < terrain.global_position.y + LOWEST or height > terrain.global_position.y + HIGHEST:
				continue
			var query := PhysicsRayQueryParameters3D.create(Vector3(x, height + 50.0, z), Vector3(x, height - 50.0, z))
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				holes += 1
				continue
			if hit["collider"] != ground:
				continue
			points += 1
			worst = maxf(worst, absf((hit["position"] as Vector3).y - height))
			coarse_worst = maxf(coarse_worst, absf(_coarse_height(terrain, x, z, cell) - height))
	return {"points": points, "holes": holes, "worst": worst, "coarse_worst": coarse_worst}


## The height at (x, z) of the grid of [param cell]-metre cells alone: two flat triangles a
## cell, the diagonal alternating, as the terrain was before its shallows were split.
static func _coarse_height(terrain: Terrain, x: float, z: float, cell: float) -> float:
	var left := terrain.global_position.x - terrain.size * 0.5
	var back := terrain.global_position.z - terrain.size * 0.5
	var i := floori((x - left) / cell)
	var j := floori((z - back) / cell)
	var u := (x - left) / cell - i
	var v := (z - back) / cell - j
	var x0 := left + i * cell
	var z0 := back + j * cell
	var h00 := terrain.height_at(x0, z0)
	var h10 := terrain.height_at(x0 + cell, z0)
	var h01 := terrain.height_at(x0, z0 + cell)
	var h11 := terrain.height_at(x0 + cell, z0 + cell)
	if (i + j) % 2 == 0:
		# Split from (0, 0) to (1, 1).
		return h00 + (h10 - h00) * u + (h11 - h10) * v if u >= v else h00 + (h11 - h01) * u + (h01 - h00) * v
	# Split from (1, 0) to (0, 1).
	return h00 + (h10 - h00) * u + (h01 - h00) * v if u + v <= 1.0 \
			else h11 + (h01 - h11) * (1.0 - u) + (h10 - h11) * (1.0 - v)
