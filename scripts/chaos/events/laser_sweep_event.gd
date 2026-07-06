class_name LaserSweepEvent
extends ChaosEvent
## Chaos hazard: a wall-to-wall laser charges at one edge of the arena, then
## sweeps across it -- horizontally, vertically, or diagonally (8 possible
## directions). The beam is deliberately LOW -- sized against the player's
## jump apex (jump_velocity 4.5 / gravity 9.8 ~= 1.03m of feet clearance) --
## so a well-timed jump clears it. Rewards timing, not position. High
## intensity spawns salvos of beams from different directions.

## Beam occupies y in [0, beam_height]; keep beam_height comfortably under
## the player's jump apex or the sweep becomes undodgeable.
@export var beam_height := 0.7
@export var beam_thickness := 0.6
@export var damage := 14.0
## Constant sweep speed; active_duration is derived per direction so
## diagonal (longer) crossings don't move faster.
@export var sweep_speed := 13.5
## How far past the walls the beam starts/ends so it never pops in mid-arena.
@export var edge_margin := 1.5
@export var chevron_count := 4

## 45-degree increments: 4 cardinal (horizontal/vertical) + 4 diagonal sweeps.
const SWEEP_DIRECTION_COUNT := 8

var _sweep_dir := Vector3.RIGHT
var _travel := 0.0
var _beam: Node3D
var _beam_material: StandardMaterial3D
var _hitbox: Hitbox
var _strip: WarningIndicator
var _chevrons: Array[MeshInstance3D] = []
var _warning_elapsed := 0.0


func _init() -> void:
	event_id = &"laser_sweep"
	warning_duration = 2.0
	active_duration = 3.8  # placeholder; recomputed from sweep_speed per direction
	cooldown = 12.0
	# Full-intensity: up to 3 beams criss-crossing from different directions.
	salvo_max = 3
	salvo_stagger = 0.9


func _start_warning() -> void:
	global_position = arena_center
	var direction_index := rng.randi_range(0, SWEEP_DIRECTION_COUNT - 1)
	var angle := (TAU / SWEEP_DIRECTION_COUNT) * float(direction_index)
	_sweep_dir = Vector3(sin(angle), 0.0, cos(angle))
	# Diagonal crossings of the square arena are sqrt(2) longer.
	var cardinal := direction_index % 2 == 0
	var reach := (arena_half_extent + edge_margin) * (1.0 if cardinal else sqrt(2.0))
	_travel = reach * 2.0
	active_duration = _travel / sweep_speed
	# Long enough to blanket the arena crosswise even on diagonal sweeps.
	var span := (arena_half_extent + edge_margin) * 2.9
	var beam_size := Vector3(span, beam_height, beam_thickness)

	# Yaw = sweep angle: the beam's local Z faces the sweep direction and its
	# local X carries the length, whatever the direction.
	_beam = Node3D.new()
	add_child(_beam)
	_beam.rotation.y = angle
	_beam.position = -_sweep_dir * reach + Vector3.UP * (beam_height * 0.5)
	var box := BoxMesh.new()
	box.size = beam_size
	_beam_material = make_glow_material(Color(1.0, 0.15, 0.1), 0.12, 3.0)
	box.material = _beam_material
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	_beam.add_child(mesh)

	# Ground strip marking the charging edge, rotated to lie under the beam.
	_strip = WarningIndicator.strip(Vector2(span, 1.6), warning_duration)
	add_child(_strip)
	_strip.rotation.y = angle
	_strip.position = -_sweep_dir * reach

	# Chevron dashes flowing away from the edge show the sweep direction.
	var chevron_material := make_glow_material(Color(1.0, 0.35, 0.1), 0.7, 2.0)
	var dash := BoxMesh.new()
	dash.size = Vector3(0.5, 0.05, 0.9)  # long along local Z = sweep direction
	dash.material = chevron_material
	for i in chevron_count:
		var chevron := MeshInstance3D.new()
		chevron.mesh = dash
		chevron.rotation.y = angle
		add_child(chevron)
		_chevrons.append(chevron)

	# The damage volume, inert until the sweep starts.
	var shape := BoxShape3D.new()
	shape.size = beam_size
	_hitbox = make_hitbox(shape, damage, true, 0.8, _beam)
	_hitbox.set_physics_process(false)  # continuous hitboxes poll from _ready


func _warning_process(delta: float) -> void:
	_warning_elapsed += delta
	# Charge-up: the ghost beam brightens as firing approaches.
	var charge := clampf(_warning_elapsed / warning_duration, 0.0, 1.0)
	_beam_material.albedo_color.a = 0.1 + 0.5 * charge + 0.05 * sin(_warning_elapsed * 14.0)
	var cycle := fmod(_warning_elapsed * 3.0, 4.0)
	for i in _chevrons.size():
		_chevrons[i].position = _beam.position * Vector3(1.0, 0.0, 1.0) \
			+ _sweep_dir * (1.5 + cycle + float(i) * 1.1) + Vector3.UP * 0.06


func _execute() -> void:
	_strip.queue_free()
	for chevron in _chevrons:
		chevron.queue_free()
	_chevrons.clear()
	_beam_material.albedo_color.a = 0.85
	_beam_material.emission_energy_multiplier = 5.0
	_hitbox.set_physics_process(true)


func _active_process(delta: float) -> void:
	_beam.position += _sweep_dir * sweep_speed * delta


func hazard_info() -> Dictionary:
	var info := super()
	info["sweep_dir"] = [_sweep_dir.x, _sweep_dir.z]
	info["beam_position"] = [_beam.global_position.x, _beam.global_position.z]
	info["beam_height"] = beam_height
	return info
