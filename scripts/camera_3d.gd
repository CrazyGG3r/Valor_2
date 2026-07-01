extends Camera3D

@export var target_path: NodePath = "../Player"
@export var offset := Vector3(0.0, 2.5, 4.0)
@export var rotation_follow_speed := 20.0  # higher = snappier turning
@export var position_follow_speed := 20.0  # higher = snappier position catch-up

@onready var target: Node3D = get_node(target_path)
var current_yaw := 0.0

func _ready() -> void:
	if target:
		current_yaw = target.rotation.y

func _process(delta: float) -> void:
	if target == null:
		return

	# Smoothly chase the player's yaw the SHORT way around, never cutting through the center
	current_yaw = lerp_angle(current_yaw, target.rotation.y, 1.0 - exp(-rotation_follow_speed * delta))

	var rotated_offset := offset.rotated(Vector3.UP, current_yaw)
	var desired_position := target.global_position + rotated_offset

	# Frame-rate independent smoothing (feels tighter than raw lerp)
	global_position = global_position.lerp(desired_position, 1.0 - exp(-position_follow_speed * delta))
	look_at(target.global_position + Vector3.UP * 1.2, Vector3.UP)
