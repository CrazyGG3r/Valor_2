class_name Enemy
extends CharacterBody3D
## Base enemy: chases the player. Contact damage is dealt by the continuous
## Hitbox child; death comes from the HealthComponent child. Subclasses
## override _movement_direction() for other movement styles (see
## enemy_ranged.gd).

## Observation type ids sent to the AI. Keep in sync with the one-hot
## encoding in ai/environments/valor_env.py.
const TYPE_MELEE := 0
const TYPE_TANK := 1
const TYPE_RANGED := 2

@export_group("Identity")
## What the AI observation reports this enemy as (TYPE_* constants).
@export var type_id := TYPE_MELEE

@export_group("Movement")
@export var speed := 3.0
@export var gravity := 9.8

@export_group("Rewards")
@export var xp_value := 5.0
@export var xp_orb_scene: PackedScene

@onready var health: HealthComponent = $HealthComponent

var _target: Node3D


func _ready() -> void:
	health.died.connect(_on_died)


func health_fraction() -> float:
	if health == null or health.max_health <= 0.0:
		return 0.0
	return health.health / health.max_health


## Multiplies this enemy's max health (and refills) for per-wave scaling. Called
## by the spawner right after the enemy enters the tree, so it stacks on top of
## the scene-authored base health.
func apply_health_scale(multiplier: float) -> void:
	if health == null or is_equal_approx(multiplier, 1.0):
		return
	health.max_health *= multiplier
	health.health = health.max_health


func _on_died() -> void:
	if xp_orb_scene != null:
		var orb := xp_orb_scene.instantiate() as XPOrb
		orb.xp_value = xp_value
		get_parent().add_child(orb)
		orb.global_position = global_position
	queue_free()


func _physics_process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group(&"player") as Node3D

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	var direction := _movement_direction()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	move_and_slide()


## Unit XZ direction this enemy wants to move in. Base behavior: chase the
## player. Subclasses override for kiting/stationary behavior.
func _movement_direction() -> Vector3:
	if _target == null:
		return Vector3.ZERO
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() <= 0.0001:
		return Vector3.ZERO
	return to_target.normalized()
