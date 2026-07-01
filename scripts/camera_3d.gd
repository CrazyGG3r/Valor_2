extends Camera3D

@export var target_path: NodePath = "../Player"
@export var offset := Vector3(0.0, 2.5, 4.0)
@export var follow_speed := 5.0

@onready var target: Node3D = get_node(target_path)

func _process(delta: float) -> void:
	if target == null:
		return

	var desired_position := target.global_position + offset
	global_position = global_position.lerp(desired_position, follow_speed * delta)
	look_at(target.global_position + Vector3.UP * 1.2, Vector3.UP)
