class_name XPOrb
extends Area3D
## XP pickup dropped by dying enemies. Drifts toward the player inside
## magnet_radius; collected on body contact.

const PLAYER_BODY_LAYER := 2  # physics layer 2

@export var xp_value := 5.0
@export var magnet_radius := 4.0
@export var magnet_speed := 8.0
@export var lifetime := 20.0

var _player: Node3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = PLAYER_BODY_LAYER
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Node3D
		if _player == null:
			return
	var to_player := _player.global_position - global_position
	if to_player.length() <= magnet_radius:
		global_position += to_player.normalized() * magnet_speed * delta


func _on_body_entered(body: Node3D) -> void:
	if body is Player and body.health.is_alive():
		body.level_system.add_xp(xp_value)
		queue_free()
