class_name ShockwaveEvent
extends ChaosEvent
## Chaos hazard: an orb charges over a marked epicenter, detonates, and a
## low ring of force expands outward across the arena. Like the laser it is
## jumpable -- the radial version of the timing game: watch the ring approach
## and hop as it passes. Bodies caught at ground zero when it detonates are
## hit immediately.
##
## The ring hits each target at most once, resolved the frame the ring front
## reaches it: airborne (mid-jump) targets are spared, grounded ones are hit
## via their Hurtbox so i-frames still apply.

@export var start_radius := 1.5
@export var max_radius := 16.0
@export var ring_speed := 10.0
@export var damage := 12.0
## Bodies whose origin has risen above this (relative to the ground) when
## the ring reaches them are considered to have jumped it. Tuned against the
## player's ~1.03m jump apex on a 2m capsule (grounded origin ~1.0).
@export var clear_height := 1.55
@export var epicenter_radius := 2.0

var _indicator: WarningIndicator
var _orb: MeshInstance3D
var _ring: MeshInstance3D
var _ring_material: StandardMaterial3D
var _radius := 0.0
var _warning_elapsed := 0.0
## instance_id -> true once the ring front has passed a body (hit or spared).
var _resolved := {}


func _init() -> void:
	event_id = &"shockwave"
	warning_duration = 1.6
	active_duration = 1.45  # placeholder; derived from ring_speed below
	cooldown = 8.0
	# Full-intensity: several detonations, overlapping rings to time.
	salvo_max = 3
	salvo_stagger = 0.6


func _start_warning() -> void:
	global_position = pick_ground_point(3.0)
	active_duration = (max_radius - start_radius) / ring_speed
	_indicator = WarningIndicator.circle(epicenter_radius, warning_duration, true)
	add_child(_indicator)
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.material = make_glow_material(Color(1.0, 0.55, 0.1), 0.9, 3.0)
	_orb = MeshInstance3D.new()
	_orb.mesh = sphere
	_orb.position.y = 1.0
	add_child(_orb)


func _warning_process(delta: float) -> void:
	_warning_elapsed += delta
	# The orb swells and quivers faster as detonation nears.
	var charge := clampf(_warning_elapsed / warning_duration, 0.0, 1.0)
	var pulse := 1.0 + 0.4 * charge + 0.15 * sin(_warning_elapsed * (8.0 + 10.0 * charge))
	_orb.scale = Vector3.ONE * pulse


func _execute() -> void:
	_indicator.queue_free()
	_orb.queue_free()
	_radius = start_radius
	# Unit torus scaled outward each frame; XZ scaling widens the tube
	# horizontally, which reads as the wave losing punch as it travels.
	var torus := TorusMesh.new()
	torus.inner_radius = 0.86
	torus.outer_radius = 1.0
	_ring_material = make_glow_material(Color(1.0, 0.5, 0.1), 0.8, 3.0)
	torus.material = _ring_material
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.position.y = 0.3
	_ring.scale = Vector3(_radius, 1.0, _radius)
	add_child(_ring)
	_sweep_targets()  # ground zero: anything inside start_radius is hit now


func _active_process(delta: float) -> void:
	_radius += ring_speed * delta
	_ring.scale = Vector3(_radius, 1.0, _radius)
	_ring_material.albedo_color.a = 0.8 * clampf(_phase_time_left / active_duration, 0.2, 1.0)
	_sweep_targets()


func hazard_info() -> Dictionary:
	var info := super()
	info["radius"] = epicenter_radius if phase == Phase.WARNING else _radius
	info["ring_speed"] = ring_speed
	info["max_radius"] = max_radius
	return info


## Resolves every body the ring front has reached this frame, exactly once:
## hit through the Hurtbox if grounded, spared if airborne.
func _sweep_targets() -> void:
	for body in _candidate_bodies():
		var id := body.get_instance_id()
		if _resolved.has(id):
			continue
		var offset := body.global_position - global_position
		if Vector2(offset.x, offset.z).length() > _radius:
			continue
		_resolved[id] = true
		if offset.y >= clear_height:
			continue  # jumped over the wave
		var hurtbox := body.get_node_or_null(^"Hurtbox") as Hurtbox
		if hurtbox != null:
			hurtbox.receive_hit(damage, self)


func _candidate_bodies() -> Array[Node3D]:
	var bodies: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group(&"player"):
		if node is Node3D:
			bodies.append(node)
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if node is Node3D:
			bodies.append(node)
	return bodies
