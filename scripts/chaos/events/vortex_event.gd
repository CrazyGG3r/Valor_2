class_name VortexEvent
extends ChaosEvent
## Chaos hazard: a gravity well opens and continuously DRAGS every
## CharacterBody3D in range toward its damaging core. Unlike the other
## hazards it attacks positioning, not a spot -- the player must spend
## movement fighting the pull while everything else is happening, and
## enemies get dragged into the core too (free kills if you bait them).
##
## The pull is a horizontal position shift (grounded bodies zero their own
## velocity every frame, so velocity-based forces would be eaten). It is
## always weaker than the player's move speed, so escape is guaranteed but
## costs time; damage only ticks in the small core.

@export var pull_radius := 9.0
## Drag at the core edge, fading to zero at the rim. Keep below the player's
## move speed (5.0) or the vortex becomes inescapable.
@export var pull_speed := 4.0
@export var core_radius := 1.6
@export var core_damage := 4.0
@export var core_interval := 0.6

const FADE_TIME := 0.8

var _indicator: WarningIndicator
var _core_hitbox: Hitbox
var _swirl: Node3D
var _core_visual: MeshInstance3D
var _disc_material: StandardMaterial3D


func _init() -> void:
	event_id = &"vortex"
	warning_duration = 1.8
	active_duration = 6.5
	cooldown = 13.0
	# Full-intensity: twin wells tearing the arena apart.
	salvo_max = 2
	salvo_stagger = 1.2


func _start_warning() -> void:
	global_position = pick_ground_point(6.0)
	_indicator = WarningIndicator.circle(pull_radius, warning_duration)
	add_child(_indicator)
	# Swirl arms preview the spin at low alpha during the warning.
	_swirl = Node3D.new()
	add_child(_swirl)
	var arm_material := make_glow_material(Color(0.6, 0.3, 1.0), 0.5, 2.0)
	for i in 3:
		var arm := BoxMesh.new()
		arm.size = Vector3(3.2, 0.05, 0.35)
		arm.material = arm_material
		var mesh := MeshInstance3D.new()
		mesh.mesh = arm
		mesh.rotation.y = TAU * float(i) / 3.0
		mesh.position = Vector3(0.0, 0.15, 0.0) \
			+ Vector3(cos(mesh.rotation.y), 0.0, -sin(mesh.rotation.y)) * 2.2
		_swirl.add_child(mesh)


func _warning_process(delta: float) -> void:
	_swirl.rotation.y += 1.5 * delta  # lazy spin; speeds up when live


func _execute() -> void:
	_indicator.queue_free()
	var shape := SphereShape3D.new()
	shape.radius = core_radius
	_core_hitbox = make_hitbox(shape, core_damage, true, core_interval)
	_core_hitbox.position.y = 1.0
	var sphere := SphereMesh.new()
	sphere.radius = 0.9
	sphere.height = 1.8
	sphere.material = make_glow_material(Color(0.25, 0.05, 0.5), 0.95, 2.5)
	_core_visual = MeshInstance3D.new()
	_core_visual.mesh = sphere
	_core_visual.position.y = 1.0
	add_child(_core_visual)
	# Faint disc marking the full pull zone while the well is live.
	var disc := CylinderMesh.new()
	disc.top_radius = pull_radius
	disc.bottom_radius = pull_radius
	disc.height = 0.02
	_disc_material = make_glow_material(Color(0.5, 0.2, 0.9), 0.15, 1.0)
	disc.material = _disc_material
	var disc_mesh := MeshInstance3D.new()
	disc_mesh.mesh = disc
	disc_mesh.position.y = 0.06
	add_child(disc_mesh)


func _active_process(delta: float) -> void:
	_swirl.rotation.y += 5.0 * delta
	_core_visual.rotation.y -= 3.0 * delta
	if _phase_time_left < FADE_TIME:
		var fraction := clampf(_phase_time_left / FADE_TIME, 0.0, 1.0)
		_disc_material.albedo_color.a = 0.15 * fraction
		_core_visual.scale = Vector3.ONE * maxf(fraction, 0.05)
		if _core_hitbox != null:  # collapsing well stops hurting
			_core_hitbox.queue_free()
			_core_hitbox = null
		return
	_pull_bodies(delta)


func hazard_info() -> Dictionary:
	var info := super()
	info["radius"] = pull_radius
	info["core_radius"] = core_radius
	info["pull_speed"] = pull_speed
	return info


func _pull_bodies(delta: float) -> void:
	for group in [&"player", &"enemies"]:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as CharacterBody3D
			if body == null:
				continue
			var offset := global_position - body.global_position
			offset.y = 0.0
			var distance := offset.length()
			if distance > pull_radius or distance < 0.3:
				continue
			var strength := pull_speed * (1.0 - distance / pull_radius)
			body.global_position += offset / distance * strength * delta
