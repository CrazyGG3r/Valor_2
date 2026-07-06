class_name LightningEvent
extends ChaosEvent
## Chaos hazard: electric sparks crackle over a random spot, then a bolt
## strikes it for burst area damage. Short and snappy -- the bread-and-butter
## "keep moving" pressure event.

@export var strike_radius := 2.6
@export var damage := 18.0
@export var spark_count := 7

var _hitbox: Hitbox
var _indicator: WarningIndicator
var _sparks: Array[MeshInstance3D] = []
var _spark_timer := 0.0
var _bolt_material: StandardMaterial3D
var _light: OmniLight3D


func _init() -> void:
	event_id = &"lightning"
	warning_duration = 1.2
	active_duration = 0.35
	cooldown = 5.0
	# Full-intensity storm: up to 10 near-simultaneous strikes.
	salvo_max = 10
	salvo_stagger = 0.12


func _start_warning() -> void:
	global_position = pick_ground_point(2.0)
	_indicator = WarningIndicator.circle(strike_radius, warning_duration, true)
	add_child(_indicator)
	# Sphere centered at torso height covers grounded capsule hurtboxes.
	var shape := SphereShape3D.new()
	shape.radius = strike_radius
	_hitbox = make_hitbox(shape, damage)
	_hitbox.position.y = 1.0
	var spark_material := make_glow_material(Color(0.5, 0.85, 1.0), 1.0, 3.0)
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.12, 0.12, 0.12)
	spark_mesh.material = spark_material
	for i in spark_count:
		var spark := MeshInstance3D.new()
		spark.mesh = spark_mesh
		add_child(spark)
		_sparks.append(spark)


func _warning_process(delta: float) -> void:
	# Jittering sparks: reposition the cluster every few frames.
	_spark_timer -= delta
	if _spark_timer > 0.0:
		return
	_spark_timer = 0.06
	for spark in _sparks:
		var angle := rng.randf_range(0.0, TAU)
		var distance := rng.randf_range(0.0, strike_radius * 0.8)
		spark.position = Vector3(
			cos(angle) * distance, rng.randf_range(0.1, 1.6), sin(angle) * distance)


func _execute() -> void:
	_indicator.queue_free()
	for spark in _sparks:
		spark.queue_free()
	_sparks.clear()
	_hitbox.activate(0.15)
	# The bolt: a tall glowing column plus a flash of light, faded over ACTIVE.
	var bolt := MeshInstance3D.new()
	var column := CylinderMesh.new()
	column.top_radius = 0.3
	column.bottom_radius = 0.15
	column.height = 14.0
	_bolt_material = make_glow_material(Color(0.75, 0.9, 1.0), 0.9, 4.0)
	column.material = _bolt_material
	bolt.mesh = column
	bolt.position.y = 7.0
	add_child(bolt)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.7, 0.85, 1.0)
	_light.light_energy = 6.0
	_light.omni_range = 10.0
	_light.position.y = 2.0
	add_child(_light)


func _active_process(_delta: float) -> void:
	var fraction := clampf(_phase_time_left / active_duration, 0.0, 1.0)
	_bolt_material.albedo_color.a = 0.9 * fraction
	_light.light_energy = 6.0 * fraction


func hazard_info() -> Dictionary:
	var info := super()
	info["radius"] = strike_radius
	return info
