class_name HunterOrbEvent
extends ChaosEvent
## Chaos hazard: a crimson orb materializes, locks on, and CHASES the player
## for its lifetime. The only hazard that pursues rather than occupies --
## it taxes movement continuously instead of claiming ground. Counterplay is
## built in: the orb is slower than the player (outrunnable), dash i-frames
## dodge its touch, and its contact damage hits enemies too, so kiting it
## through a pack does your work for you.
##
## The event node itself IS the orb: it moves during ACTIVE, so the base
## hazard_info() position stays accurate for the AI observation layer.

## Below the player's move speed (5.0) so it can pressure but never corner
## a healthy runner on open ground.
@export var chase_speed := 3.6
## Steering inertia: higher turns tighter. Low values give swooping arcs the
## player can juke.
@export var turn_rate := 2.5
@export var contact_damage := 16.0
@export var contact_radius := 0.8
@export var hover_height := 1.2
## The orb never materializes closer to the player than this.
@export var min_spawn_distance := 8.0

const FADE_TIME := 0.6

var _indicator: WarningIndicator
var _orb_visual: MeshInstance3D
var _orb_material: StandardMaterial3D
var _shards: Node3D
var _velocity := Vector3.ZERO
var _warning_elapsed := 0.0


func _init() -> void:
	event_id = &"hunter_orb"
	warning_duration = 1.5
	active_duration = 7.0
	cooldown = 10.0
	# Full-intensity: a pack of hunters converging from different sides.
	salvo_max = 3
	salvo_stagger = 0.8


func _start_warning() -> void:
	global_position = _pick_spawn_point()
	_indicator = WarningIndicator.circle(1.6, warning_duration, true)
	add_child(_indicator)
	var sphere := SphereMesh.new()
	sphere.radius = 0.55
	sphere.height = 1.1
	_orb_material = make_glow_material(Color(0.9, 0.08, 0.12), 0.35, 2.5)
	sphere.material = _orb_material
	_orb_visual = MeshInstance3D.new()
	_orb_visual.mesh = sphere
	_orb_visual.position.y = hover_height
	add_child(_orb_visual)
	# Orbiting shards sell the "alive and about to move" read.
	_shards = Node3D.new()
	_shards.position.y = hover_height
	add_child(_shards)
	var shard_material := make_glow_material(Color(1.0, 0.35, 0.15), 0.9, 3.0)
	for i in 3:
		var shard := BoxMesh.new()
		shard.size = Vector3(0.18, 0.18, 0.18)
		shard.material = shard_material
		var mesh := MeshInstance3D.new()
		mesh.mesh = shard
		var angle := TAU * float(i) / 3.0
		mesh.position = Vector3(cos(angle), 0.0, sin(angle)) * 1.0
		_shards.add_child(mesh)


func _warning_process(delta: float) -> void:
	_warning_elapsed += delta
	_shards.rotation.y += 3.0 * delta
	# Materializing: the orb solidifies as the hunt approaches.
	var charge := clampf(_warning_elapsed / warning_duration, 0.0, 1.0)
	_orb_material.albedo_color.a = 0.35 + 0.6 * charge


func _execute() -> void:
	_indicator.queue_free()
	_orb_material.albedo_color.a = 0.95
	var shape := SphereShape3D.new()
	shape.radius = contact_radius
	var hitbox := make_hitbox(shape, contact_damage, true, 1.2)
	hitbox.position.y = hover_height


func _active_process(delta: float) -> void:
	_shards.rotation.y += 6.0 * delta
	if _phase_time_left < FADE_TIME:
		# Expiring: deflate and slow to a stop.
		var fraction := clampf(_phase_time_left / FADE_TIME, 0.05, 1.0)
		_orb_visual.scale = Vector3.ONE * fraction
		_shards.scale = Vector3.ONE * fraction
		_velocity = _velocity.lerp(Vector3.ZERO, 1.0 - exp(-4.0 * delta))
	else:
		var target := get_tree().get_first_node_in_group(&"player") as Node3D
		if target != null:
			var to_target := target.global_position - global_position
			to_target.y = 0.0
			if to_target.length_squared() > 0.01:
				var desired := to_target.normalized() * chase_speed
				_velocity = _velocity.lerp(desired, 1.0 - exp(-turn_rate * delta))
	global_position += _velocity * delta


func hazard_info() -> Dictionary:
	var info := super()
	info["radius"] = contact_radius
	info["velocity"] = [_velocity.x, _velocity.z]
	return info


## Random arena point at least min_spawn_distance from the player, so the
## hunt always starts with room to react.
func _pick_spawn_point() -> Vector3:
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	for attempt in 12:
		var point := pick_ground_point(2.0)
		if player == null:
			return point
		var offset := point - player.global_position
		if Vector2(offset.x, offset.z).length() >= min_spawn_distance:
			return point
	return pick_ground_point(2.0)
