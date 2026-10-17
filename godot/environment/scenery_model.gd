class_name SceneryModel
extends RefCounted
## Puts kiln-built models (art/models) into scenery built from code: buoys, ramps, the start
## gate, rocks, piers, lamps and harbour buildings each draw a model scene of their own,
## stretched to their size, with materials repainted by name where they take a colour of
## their own (a red or yellow buoy, a building's walls).
##
## A model's Rock, Wood and WoodDark materials are drawn in kiln's textures by its import
## script (environment/model_import.gd swaps them for environment/materials/), so they need
## nothing here.


## Instantiates [param scene] as [param parent]'s internal child named "Model", marked with
## [param part_meta] so the parent's next rebuild frees it, its meshes drawn on the visual
## [param layers]. Returns it.
static func add(parent: Node3D, scene: PackedScene, part_meta: StringName, layers: int = ShoreMap.SCENERY_LAYER) -> Node3D:
	var model := scene.instantiate() as Node3D
	model.name = "Model"
	model.set_meta(part_meta, true)
	parent.add_child(model, false, Node.INTERNAL_MODE_FRONT)
	for mesh in meshes(model):
		mesh.layers = layers
	return model


## Every [MeshInstance3D] in [param model], itself included.
static func meshes(model: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if model is MeshInstance3D:
		found.append(model)
	for child in model.find_children("*", "MeshInstance3D", true, false):
		found.append(child as MeshInstance3D)
	return found


## Draws every surface of [param model] whose material is named [param material_name] in one
## copy of that material, coloured [param color] and, unless [param glow] is black, glowing
## that colour at [param glow_energy]. Returns the copy, to change later (a buoy's flash), or
## null if the model has no such material.
static func paint(model: Node, material_name: String, color: Color, glow: Color = Color.BLACK,
		glow_energy: float = 1.0) -> StandardMaterial3D:
	var copy: StandardMaterial3D = null
	for mesh in meshes(model):
		for surface in mesh.mesh.get_surface_count():
			var original := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if original == null or original.resource_name != material_name:
				continue
			if copy == null:
				copy = original.duplicate() as StandardMaterial3D
				copy.albedo_color = color
				if glow != Color.BLACK:
					copy.emission_enabled = true
					copy.emission = glow
					copy.emission_energy_multiplier = glow_energy
			mesh.set_surface_override_material(surface, copy)
	return copy


## Every vertex of [param model]'s meshes, in [param model]'s own space as its transform
## (and its parts') would place them in its parent: for a collision shape or to fit it to
## a size.
static func points(model: Node3D) -> PackedVector3Array:
	var found := PackedVector3Array()
	for mesh in meshes(model):
		var place := model.transform * _relative(mesh, model)
		for surface in mesh.mesh.get_surface_count():
			for vertex: Vector3 in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				found.append(place * vertex)
	return found


## [param node]'s transform relative to [param ancestor].
static func _relative(node: Node3D, ancestor: Node3D) -> Transform3D:
	var relative := Transform3D.IDENTITY
	var at := node
	while at != ancestor and at != null:
		relative = at.transform * relative
		at = at.get_parent() as Node3D
	return relative
