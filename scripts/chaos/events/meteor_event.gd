class_name MeteorEvent
extends ChaosEvent
## Chaos hazard: a shrinking warning circle counts down to a meteor impact
## (burst damage), and the rock then STAYS on the arena as a solid obstacle
## with a damaging heat aura -- standing near it ticks small damage until you
## leave. The rock sinks away when the event expires.
##
## The landed rock joins the "obstacles" group with a clear_radius meta, so
## the enemy spawner treats it exactly like authored obstacles.

@export var impact_radius := 3.5
@export var impact_damage := 25.0
@export var aura_radius := 3.2
## Small ticking damage; the pressure is leaving the area, not the number.
@export var aura_damage := 3.0
@export var aura_interval := 0.8
## Seconds (at the end of the warning) the rock visibly falls, landing at impact.
@export var fall_time := 0.5
@export var rock_radius := 1.2

const FALL_START_HEIGHT := 26.0
const FADE_TIME := 1.2

var _impact_hitbox: Hitbox
var _aura_hitbox: Hitbox
var _indicator: WarningIndicator
var _falling_rock: MeshInstance3D
var _rock_body: StaticBody3D
var _rest_height := 0.0


func _init() -> void:
	event_id = &"meteor"
	warning_duration = 2.2
	active_duration = 11.0
	cooldown = 15.0
	# Full-intensity meteor shower: up to 6 impacts drumming in.
	salvo_max = 6
	salvo_stagger = 0.5


func _start_warning() -> void:
	global_position = pick_ground_point(4.0)
	_rest_height = rock_radius * 0.7  # embedded in the ground
	_indicator = WarningIndicator.circle(impact_radius, warning_duration, true)
	add_child(_indicator)
	var shape := SphereShape3D.new()
	shape.radius = impact_radius
	_impact_hitbox = make_hitbox(shape, impact_damage)
	_impact_hitbox.position.y = 1.0
	# The rock mesh exists from the start (hidden) so the fall is a pure
	# position animation over the last fall_time seconds of the warning.
	var sphere := SphereMesh.new()
	sphere.radius = rock_radius
	sphere.height = rock_radius * 2.0
	sphere.material = make_glow_material(Color(0.9, 0.35, 0.1), 1.0, 0.8)
	_falling_rock = MeshInstance3D.new()
	_falling_rock.mesh = sphere
	_falling_rock.visible = false
	_falling_rock.position.y = FALL_START_HEIGHT
	add_child(_falling_rock)


func _warning_process(_delta: float) -> void:
	if _phase_time_left > fall_time:
		return
	_falling_rock.visible = true
	var progress := clampf(1.0 - _phase_time_left / fall_time, 0.0, 1.0)
	_falling_rock.position.y = lerpf(FALL_START_HEIGHT, _rest_height, progress)


func _execute() -> void:
	_indicator.queue_free()
	_impact_hitbox.activate(0.15)
	# Solidify: the fallen rock becomes a world-layer obstacle.
	_rock_body = StaticBody3D.new()
	_rock_body.collision_layer = 1  # world: blocks movement, projectiles, LOS
	_rock_body.collision_mask = 0
	_rock_body.add_to_group(&"obstacles")
	_rock_body.set_meta(&"clear_radius", rock_radius + 0.5)
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = rock_radius
	collision.shape = shape
	_rock_body.add_child(collision)
	add_child(_rock_body)
	_rock_body.position.y = _rest_height
	_falling_rock.reparent(_rock_body)
	_falling_rock.position = Vector3.ZERO
	# Heat aura: continuous ticking damage while anything stays in range.
	var aura_shape := SphereShape3D.new()
	aura_shape.radius = aura_radius
	_aura_hitbox = make_hitbox(aura_shape, aura_damage, true, aura_interval)
	_aura_hitbox.position.y = 1.0
	var ring := CylinderMesh.new()
	ring.top_radius = aura_radius
	ring.bottom_radius = aura_radius
	ring.height = 0.02
	ring.material = make_glow_material(Color(1.0, 0.4, 0.05), 0.22, 1.5)
	var aura_visual := MeshInstance3D.new()
	aura_visual.mesh = ring
	aura_visual.position.y = 0.07
	add_child(aura_visual)


func _active_process(_delta: float) -> void:
	if _phase_time_left > FADE_TIME:
		return
	# Expiring: stop the aura damage and sink the rock into the ground.
	if _aura_hitbox != null:
		_aura_hitbox.queue_free()
		_aura_hitbox = null
	var progress := clampf(1.0 - _phase_time_left / FADE_TIME, 0.0, 1.0)
	_rock_body.position.y = lerpf(_rest_height, -rock_radius * 2.2, progress)


func hazard_info() -> Dictionary:
	var info := super()
	info["radius"] = impact_radius if phase == Phase.WARNING else aura_radius
	info["landed"] = phase == Phase.ACTIVE
	return info
