class_name SpikeEvent
extends ChaosEvent
## Chaos hazard: the ground cracks over a circular patch, then stone spikes
## erupt -- damaging anything caught and popping it upward -- hold briefly,
## and sink away. The knock-up interrupts positioning for player AND enemies.

@export var field_radius := 3.0
@export var damage := 15.0
## Upward pop applied to hit CharacterBody3D targets. The teleport lift
## breaks floor contact (grounded bodies zero out velocity.y themselves),
## then the velocity carries the launch.
@export var knock_up_velocity := 6.0
@export var knock_up_lift := 0.6
@export var spike_count := 8

const RISE_TIME := 0.15
const SINK_TIME := 0.35

var _hitbox: Hitbox
var _indicator: WarningIndicator
## Per spike: {"mesh": MeshInstance3D, "height": float}
var _spikes: Array[Dictionary] = []


func _init() -> void:
	event_id = &"spikes"
	warning_duration = 1.5
	active_duration = 1.6
	cooldown = 7.0
	# Full-intensity: several patches ripple up across the arena.
	salvo_max = 5
	salvo_stagger = 0.25


func _start_warning() -> void:
	global_position = pick_ground_point(2.5)
	_indicator = WarningIndicator.circle(field_radius, warning_duration)
	add_child(_indicator)
	_spawn_cracks()
	var shape := SphereShape3D.new()
	shape.radius = field_radius
	_hitbox = make_hitbox(shape, damage)
	_hitbox.position.y = 0.8
	_hitbox.hit_landed.connect(_on_hit_landed)


func _execute() -> void:
	_indicator.queue_free()
	_hitbox.activate(0.25)
	var rock := make_glow_material(Color(0.45, 0.38, 0.32), 1.0, 0.15)
	for i in spike_count:
		var height := rng.randf_range(1.3, 2.2)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = rng.randf_range(0.25, 0.45)
		cone.height = height
		cone.material = rock
		var mesh := MeshInstance3D.new()
		mesh.mesh = cone
		var angle := rng.randf_range(0.0, TAU)
		var distance := field_radius * sqrt(rng.randf())
		mesh.position = Vector3(cos(angle) * distance, -height * 0.5, sin(angle) * distance)
		add_child(mesh)
		_spikes.append({"mesh": mesh, "height": height})


func _active_process(_delta: float) -> void:
	var elapsed := active_duration - _phase_time_left
	# 0..1 up over RISE_TIME, hold, back down over the final SINK_TIME.
	var extension := clampf(elapsed / RISE_TIME, 0.0, 1.0)
	if _phase_time_left < SINK_TIME:
		extension = clampf(_phase_time_left / SINK_TIME, 0.0, 1.0)
	for spike in _spikes:
		var height: float = spike["height"]
		var mesh: MeshInstance3D = spike["mesh"]
		mesh.position.y = lerpf(-height * 0.5, height * 0.5, extension)


func _on_hit_landed(hurtbox: Hurtbox) -> void:
	var body := hurtbox.get_parent() as CharacterBody3D
	if body == null:
		return
	body.global_position.y += knock_up_lift
	body.velocity.y = maxf(body.velocity.y, knock_up_velocity)


func hazard_info() -> Dictionary:
	var info := super()
	info["radius"] = field_radius
	return info


func _spawn_cracks() -> void:
	# Dark jagged slivers scattered in the circle read as the ground splitting.
	var material := make_glow_material(Color(0.08, 0.05, 0.04), 0.9, 0.3)
	for i in 6:
		var sliver := BoxMesh.new()
		sliver.size = Vector3(rng.randf_range(1.2, 2.4), 0.03, rng.randf_range(0.06, 0.12))
		sliver.material = material
		var mesh := MeshInstance3D.new()
		mesh.mesh = sliver
		var angle := rng.randf_range(0.0, TAU)
		var distance := rng.randf_range(0.0, field_radius * 0.85)
		mesh.position = Vector3(cos(angle) * distance, 0.08, sin(angle) * distance)
		mesh.rotation.y = rng.randf_range(0.0, TAU)
		add_child(mesh)
