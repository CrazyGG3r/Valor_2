class_name WarningIndicator
extends Node3D
## Flat ground telegraph for chaos hazards. Circle (with optional shrink-to-
## impact fill, read as a countdown) or strip (edge/line markers). Purely
## visual -- damage zones are separate Hitboxes owned by the event. Built
## entirely in code so events need no art assets.

const GROUND_OFFSET := 0.05

var _duration := 1.0
var _elapsed := 0.0
var _shrink := false
var _fill: MeshInstance3D
var _fill_material: StandardMaterial3D
var _base_alpha := 0.45


## Circular zone marker. With shrink = true the bright inner fill contracts
## over `duration`, hitting zero exactly at impact (meteor-style countdown).
## Red by default (danger); pass a color for other meanings (green = safe).
static func circle(radius: float, duration: float, shrink := false,
		color := Color(1.0, 0.25, 0.1)) -> WarningIndicator:
	var indicator := WarningIndicator.new()
	indicator._duration = maxf(duration, 0.01)
	indicator._shrink = shrink
	indicator._build_disc(radius, 0.22, color.darkened(0.35), false)
	indicator._build_disc(radius, 0.45, color, true)
	return indicator


## Flat rectangle on the ground; size.x runs along local X, size.y along
## local Z. Callers rotate the node to orient it (laser start edge).
static func strip(size: Vector2, duration: float) -> WarningIndicator:
	var indicator := WarningIndicator.new()
	indicator._duration = maxf(duration, 0.01)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size.x, 0.04, size.y)
	box.material = indicator._make_material(Color(1.0, 0.25, 0.1), 0.45)
	mesh.mesh = box
	mesh.position.y = GROUND_OFFSET
	indicator.add_child(mesh)
	indicator._fill = mesh
	indicator._fill_material = box.material
	return indicator


func _physics_process(delta: float) -> void:
	# Physics-driven so the countdown stays in lockstep with the owning
	# event's phase timer under AI training pause/step.
	_elapsed += delta
	if _fill_material != null:
		_fill_material.albedo_color.a = _base_alpha * (0.7 + 0.3 * sin(_elapsed * 12.0))
	if _shrink and _fill != null:
		var fraction := clampf(1.0 - _elapsed / _duration, 0.001, 1.0)
		_fill.scale = Vector3(fraction, 1.0, fraction)


func _build_disc(radius: float, alpha: float, color: Color, is_fill: bool) -> void:
	var mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.02
	disc.material = _make_material(color, alpha)
	mesh.mesh = disc
	# Fill sits a hair above the outline so the two never z-fight.
	mesh.position.y = GROUND_OFFSET + (0.02 if is_fill else 0.0)
	add_child(mesh)
	if is_fill:
		_fill = mesh
		_fill_material = disc.material
		_base_alpha = alpha


func _make_material(color: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.2
	return material
