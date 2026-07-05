class_name RangedEnemy
extends Enemy
## Kiting shooter: walks toward the player only until preferred_distance,
## backs off when crowded, and fires its ProjectileLauncher when it has a
## clear line of sight. Creates dodge/kite pressure for the player and AI.

const WORLD_LAYER := 1  # obstacles and walls block line of sight

@export_group("Ranged Behavior")
## Stops approaching once within this distance of the player.
@export var preferred_distance := 9.0
## Backs away when the player gets closer than this.
@export var retreat_distance := 5.0
## Only fires when the player is within this range.
@export var attack_range := 16.0
## Shots originate this far above the enemy's origin.
@export var muzzle_height := 0.6

@onready var launcher: ProjectileLauncher = $ProjectileLauncher


func _physics_process(delta: float) -> void:
	super(delta)
	if _target == null:
		return
	_face_target()
	_try_shoot()


func _movement_direction() -> Vector3:
	if _target == null:
		return Vector3.ZERO
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	if distance <= 0.0001:
		return Vector3.ZERO
	if distance > preferred_distance:
		return to_target / distance
	if distance < retreat_distance:
		return -to_target / distance
	return Vector3.ZERO


func _face_target() -> void:
	var flat_target := _target.global_position
	flat_target.y = global_position.y
	if global_position.distance_squared_to(flat_target) > 0.01:
		look_at(flat_target, Vector3.UP)


func _try_shoot() -> void:
	var to_target := _target.global_position - global_position
	if to_target.length() > attack_range:
		return
	if _line_of_sight_blocked():
		return
	var direction := to_target
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		return
	launcher.try_fire(direction.normalized())


func _line_of_sight_blocked() -> bool:
	var from := global_position + Vector3.UP * muzzle_height
	var to := _target.global_position + Vector3.UP * muzzle_height
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_LAYER)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
