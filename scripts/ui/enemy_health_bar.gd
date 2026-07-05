class_name EnemyHealthBar
extends Node3D
## Floating world-space health bar: two unshaded quads (dark background +
## fill). The fill scales with health and shifts green -> red. Hidden at
## full health. Built in code so every enemy scene just adds one node.

@export var width := 1.6
@export var bar_height := 0.16
## Auto-resolved to the parent's HealthComponent child when left empty.
@export var health: HealthComponent

var _fill: MeshInstance3D
var _fill_material: StandardMaterial3D


func _ready() -> void:
	if health == null:
		for child in get_parent().get_children():
			if child is HealthComponent:
				health = child
				break
	if health == null:
		push_error("EnemyHealthBar on '%s' found no HealthComponent." % get_parent().name)
		return
	_build_quads()
	health.damaged.connect(func(_amount: float, _source: Node) -> void: _refresh())
	health.healed.connect(func(_amount: float) -> void: _refresh())
	_refresh()


func _process(_delta: float) -> void:
	# Hidden at full/zero health -- no need to reorient an invisible bar.
	if not visible:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	# Screen-aligned billboard: copy the camera's basis (bar stays parallel to
	# the view plane and upright on screen), then flip 180 deg about its up so
	# local -Z faces the camera, keeping the fill quad's -Z offset in front.
	# Unlike look_at(camera, Vector3.UP), this never hits the colinear warning
	# when an enemy passes directly under the camera.
	var cam_basis := camera.global_transform.basis
	global_transform.basis = cam_basis.rotated(cam_basis.y, PI)


func _build_quads() -> void:
	var background := MeshInstance3D.new()
	var background_mesh := QuadMesh.new()
	background_mesh.size = Vector2(width + 0.06, bar_height + 0.06)
	background_mesh.material = _make_material(Color(0.12, 0.12, 0.12))
	background.mesh = background_mesh
	background.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(background)

	_fill = MeshInstance3D.new()
	var fill_mesh := QuadMesh.new()
	fill_mesh.size = Vector2(width, bar_height)
	_fill_material = _make_material(Color.GREEN)
	fill_mesh.material = _fill_material
	_fill.mesh = fill_mesh
	# look_at() aims local -Z at the camera, so the camera-facing side is -Z.
	# The fill must sit in front of the background, i.e. slightly toward -Z.
	_fill.position.z = -0.02
	_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fill)


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	return material


func _refresh() -> void:
	var fraction := clampf(health.health / health.max_health, 0.0, 1.0)
	visible = fraction < 1.0 and fraction > 0.0
	_fill.scale.x = maxf(fraction, 0.001)
	_fill.position.x = -width * (1.0 - fraction) / 2.0
	_fill_material.albedo_color = Color(1.0 - fraction, fraction, 0.0)
