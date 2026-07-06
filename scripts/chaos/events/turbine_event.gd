class_name TurbineEvent
extends ChaosEvent
## Chaos hazard: a pillar rises and spins two low beam arms around itself
## like clock hands for several seconds. Unlike the one-pass laser sweep this
## is SUSTAINED rotating pressure -- orbit ahead of the arms, leave its
## reach, or jump them (same height rule as the laser: arms sit under the
## player's ~1.03m jump apex). Spin direction is random per spawn.

@export var arm_length := 12.0
## Arms occupy y in [0, arm_height]; keep under the jump apex (see laser).
@export var arm_height := 0.7
@export var arm_thickness := 0.5
@export var pillar_radius := 0.8
## Radians/second once live. Tip speed = spin * (pillar_radius + arm_length);
## keep the tip outrunnable-by-orbit slower than a panicked sprint arc.
@export var spin_speed := 0.9
@export var damage := 13.0

const FADE_TIME := 0.5
const PILLAR_HEIGHT := 2.4

var _rotor: Node3D
var _pillar: MeshInstance3D
var _arm_material: StandardMaterial3D
var _hitboxes: Array[Hitbox] = []
var _spin_dir := 1.0
var _warning_elapsed := 0.0


func _init() -> void:
	event_id = &"beam_turbine"
	warning_duration = 2.0
	active_duration = 6.0
	cooldown = 14.0
	# Full-intensity: twin turbines carving the arena into moving slices.
	salvo_max = 2
	salvo_stagger = 1.5


func _start_warning() -> void:
	global_position = pick_ground_point(8.0)
	_spin_dir = 1.0 if rng.randf() < 0.5 else -1.0
	var reach := pillar_radius + arm_length
	add_child(WarningIndicator.circle(reach, warning_duration))
	# The pillar rises out of the ground over the warning.
	var column := CylinderMesh.new()
	column.top_radius = pillar_radius * 0.7
	column.bottom_radius = pillar_radius
	column.height = PILLAR_HEIGHT
	column.material = make_glow_material(Color(0.9, 0.25, 0.05), 1.0, 1.2)
	_pillar = MeshInstance3D.new()
	_pillar.mesh = column
	_pillar.position.y = -PILLAR_HEIGHT * 0.5
	add_child(_pillar)
	# Ghost arms preview the spin (and its direction) at low alpha; their
	# hitboxes exist now but stay disabled until _execute (laser pattern).
	_rotor = Node3D.new()
	add_child(_rotor)
	_arm_material = make_glow_material(Color(1.0, 0.2, 0.05), 0.15, 3.0)
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(arm_length, arm_height, arm_thickness)
	arm_mesh.material = _arm_material
	var arm_shape := BoxShape3D.new()
	arm_shape.size = arm_mesh.size
	for i in 2:
		var arm := Node3D.new()
		arm.rotation.y = PI * float(i)
		_rotor.add_child(arm)
		var mesh := MeshInstance3D.new()
		mesh.mesh = arm_mesh
		mesh.position = Vector3(pillar_radius + arm_length * 0.5, arm_height * 0.5, 0.0)
		arm.add_child(mesh)
		var hitbox := make_hitbox(arm_shape, damage, true, 0.9, arm)
		hitbox.position = mesh.position
		hitbox.set_physics_process(false)  # continuous hitboxes poll from _ready
		_hitboxes.append(hitbox)


func _warning_process(delta: float) -> void:
	_warning_elapsed += delta
	var charge := clampf(_warning_elapsed / warning_duration, 0.0, 1.0)
	_pillar.position.y = lerpf(-PILLAR_HEIGHT * 0.5, PILLAR_HEIGHT * 0.5, charge)
	_rotor.rotation.y += _spin_dir * spin_speed * 0.3 * delta  # lazy preview spin
	_arm_material.albedo_color.a = 0.15 + 0.25 * charge


func _execute() -> void:
	_arm_material.albedo_color.a = 0.85
	_arm_material.emission_energy_multiplier = 5.0
	for hitbox in _hitboxes:
		hitbox.set_physics_process(true)


func _active_process(delta: float) -> void:
	_rotor.rotation.y += _spin_dir * spin_speed * delta
	if _phase_time_left < FADE_TIME:
		var fraction := clampf(_phase_time_left / FADE_TIME, 0.0, 1.0)
		_arm_material.albedo_color.a = 0.85 * fraction
		_pillar.position.y = lerpf(-PILLAR_HEIGHT * 0.5, PILLAR_HEIGHT * 0.5, fraction)
		for hitbox in _hitboxes:
			if hitbox != null and is_instance_valid(hitbox):
				hitbox.set_physics_process(false)  # sinking turbine stops hurting


func hazard_info() -> Dictionary:
	var info := super()
	info["radius"] = pillar_radius + arm_length
	info["arm_angle"] = _rotor.rotation.y
	info["spin"] = _spin_dir * spin_speed
	info["arm_height"] = arm_height
	return info
