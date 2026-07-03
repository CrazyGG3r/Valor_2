class_name HitFlash
extends Node
## Briefly tints the sibling mesh when the sibling HealthComponent takes
## damage. Duplicates the material at runtime so other instances of the same
## scene keep their original look.

@export var mesh: MeshInstance3D
@export var flash_color := Color(1.0, 0.25, 0.25)
@export var duration := 0.2

var _material: StandardMaterial3D
var _original_color: Color
var _tween: Tween


func _ready() -> void:
	var parent := get_parent()
	if mesh == null:
		mesh = parent.get_node_or_null(^"MeshInstance3D") as MeshInstance3D
	var health: HealthComponent = null
	for child in parent.get_children():
		if child is HealthComponent:
			health = child
			break
	if mesh == null or health == null:
		push_error("HitFlash on '%s' needs a sibling MeshInstance3D and HealthComponent." % parent.name)
		return
	var source := mesh.get_active_material(0)
	if source is StandardMaterial3D:
		_material = source.duplicate()
		mesh.set_surface_override_material(0, _material)
		_original_color = _material.albedo_color
	health.damaged.connect(_on_damaged)


func _on_damaged(_amount: float, _source: Node) -> void:
	if _material == null:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_material.albedo_color = flash_color
	_tween = create_tween()
	_tween.tween_property(_material, "albedo_color", _original_color, duration)
