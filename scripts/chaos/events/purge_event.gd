class_name PurgeEvent
extends ChaosEvent
## Chaos hazard: the ENTIRE arena ignites -- except a few green safe zones.
## Inverts every other telegraph in the mode: instead of "don't stand there"
## it says "be HERE before the timer runs out", forcing a sprint across the
## map while everything else is still happening. Jumping does not help;
## only position does. Enemies caught outside the zones burn too.
##
## The long warning is the event: with move speed 5 (+dash) the player can
## cover ~20m, so zone spacing and warning length are tuned together.

@export var safe_zone_count := 3
@export var safe_zone_radius := 3.0
## Zones reject positions closer than this to each other, spreading them out
## so one is always plausibly reachable.
@export var min_zone_spacing := 14.0
@export var damage := 20.0
@export var flame_count := 24

const SAFE_COLOR := Color(0.25, 1.0, 0.4)

var _safe_zones: Array[Vector3] = []
var _field: WarningIndicator
var _flames: Array[MeshInstance3D] = []
var _flame_material: StandardMaterial3D


func _init() -> void:
	event_id = &"arena_purge"
	warning_duration = 3.5
	active_duration = 1.0
	cooldown = 18.0
	salvo_max = 1  # a purge never stacks; it IS the moment


func _start_warning() -> void:
	global_position = arena_center
	_pick_safe_zones()
	# Arena-wide red field (radius covers the square's corners) with green
	# holes stacked above it marking the only places that survive.
	_field = WarningIndicator.circle(arena_half_extent * 1.42, warning_duration)
	add_child(_field)
	for zone in _safe_zones:
		var marker := WarningIndicator.circle(safe_zone_radius, warning_duration, false, SAFE_COLOR)
		add_child(marker)
		marker.position = (zone - global_position) + Vector3.UP * 0.08


func _execute() -> void:
	_field.queue_free()
	_burn_targets()
	# Flame columns erupt everywhere outside the safe zones, then gutter out.
	var pillar := CylinderMesh.new()
	pillar.top_radius = 0.15
	pillar.bottom_radius = 0.55
	pillar.height = 3.0
	_flame_material = make_glow_material(Color(1.0, 0.45, 0.05), 0.7, 3.0)
	pillar.material = _flame_material
	for i in flame_count:
		var point := pick_ground_point(1.0)
		if _in_safe_zone(point):
			continue
		var flame := MeshInstance3D.new()
		flame.mesh = pillar
		flame.position = (point - global_position) + Vector3.UP * 1.5
		add_child(flame)
		_flames.append(flame)


func _active_process(_delta: float) -> void:
	var fraction := clampf(_phase_time_left / active_duration, 0.0, 1.0)
	_flame_material.albedo_color.a = 0.7 * fraction
	for flame in _flames:
		flame.scale = Vector3(fraction, 1.0, fraction)


func hazard_info() -> Dictionary:
	var info := super()
	var zones: Array = []
	for zone in _safe_zones:
		zones.append([zone.x, zone.z])
	info["safe_zones"] = zones
	info["safe_zone_radius"] = safe_zone_radius
	return info


func _pick_safe_zones() -> void:
	_safe_zones.clear()
	for i in safe_zone_count:
		var point := pick_ground_point(4.0)
		for attempt in 20:
			point = pick_ground_point(4.0)
			var spaced := true
			for other in _safe_zones:
				if Vector2(point.x - other.x, point.z - other.z).length() < min_zone_spacing:
					spaced = false
					break
			if spaced:
				break
		_safe_zones.append(point)


func _in_safe_zone(point: Vector3) -> bool:
	for zone in _safe_zones:
		if Vector2(point.x - zone.x, point.z - zone.z).length() <= safe_zone_radius:
			return true
	return false


## One burst at ignition: everything outside every safe zone takes the hit,
## routed through Hurtboxes so i-frames still apply.
func _burn_targets() -> void:
	for group in [&"player", &"enemies"]:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body == null or _in_safe_zone(body.global_position):
				continue
			var hurtbox := body.get_node_or_null(^"Hurtbox") as Hurtbox
			if hurtbox != null:
				hurtbox.receive_hit(damage, self)
