@tool
extends EditorScenePostImport
## Runs on every model Godot imports (the scene importer's import script, set as its default
## in project.godot and in each kiln model's .glb.import): swaps each material named in
## [constant MATERIALS] for the game's own, so a model's Rock, Wood and WoodDark faces are
## drawn in kiln's textures with no remap of their own in its import settings. A model gets
## the swap by naming its material; kiln checks recipes keep the names (their spec's
## [code]materials[/code]).
##
## Godot reads this only while importing. It doesn't notice a changed import setting by
## itself: delete a model's files in [code].godot/imported/[/code] to import it again.

## The game's materials, by the name a model gives the material they replace.
const MATERIALS := {
	"Rock": "res://environment/materials/rock.tres",
	"Wood": "res://environment/materials/wood.tres",
	"WoodDark": "res://environment/materials/wood_dark.tres",
}


func _post_import(scene: Node) -> Object:
	for node in scene.find_children("*", "", true, false):
		if node is ImporterMeshInstance3D and node.mesh != null:
			var importer_mesh := (node as ImporterMeshInstance3D).mesh
			for surface in importer_mesh.get_surface_count():
				var replacement := _replacement(importer_mesh.get_surface_material(surface))
				if replacement != null:
					importer_mesh.set_surface_material(surface, replacement)
		elif node is MeshInstance3D and node.mesh != null:
			var mesh := (node as MeshInstance3D).mesh
			for surface in mesh.get_surface_count():
				var replacement := _replacement(mesh.surface_get_material(surface))
				if replacement != null:
					mesh.surface_set_material(surface, replacement)
	return scene


## The game's material for [param material], or null if it keeps its own.
static func _replacement(material: Material) -> Material:
	if material == null or not MATERIALS.has(material.resource_name):
		return null
	return load(MATERIALS[material.resource_name]) as Material
