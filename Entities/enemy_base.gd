class_name Enemy
extends CharacterBody3D
## Base enemy: chases the player. Contact damage is dealt by the continuous
## Hitbox child; death comes from the HealthComponent child. Movement styles
## and attack patterns become subclasses/components later.

@export_group("Movement")
@export var speed := 3.0
@export var gravity := 9.8

@onready var health: HealthComponent = $HealthComponent

var _target: Node3D


func _ready() -> void:
	health.died.connect(queue_free)


func _physics_process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group(&"player") as Node3D

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	velocity.x = 0.0
	velocity.z = 0.0
	if _target != null:
		var to_target := _target.global_position - global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.0001:
			var direction := to_target.normalized()
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed

	move_and_slide()
