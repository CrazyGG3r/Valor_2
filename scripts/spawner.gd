extends Node3D

@export var enemy_scenes: Array[PackedScene]
@export var spawn_count: int = 5

@onready var a_out: Marker3D = $A_out
@onready var b_out: Marker3D = $B_out
@onready var a_in: Marker3D = $A_in
@onready var b_in: Marker3D = $B_in


func _ready():
	randomize()
	spawn_enemies()
	print("spawned")

func spawn_enemies():
	if enemy_scenes.is_empty():
		push_warning("No enemy scenes assigned!")
		return
	for i in spawn_count:
		var enemy_scene = enemy_scenes.pick_random()
		var enemy = enemy_scene.instantiate()
		enemy.global_position = get_random_spawn_position()
		get_tree().current_scene.add_child(enemy)
		print("Spawned enemy at: ", enemy.global_position)
func get_random_spawn_position():
	var outer_min = Vector3(
		min(a_out.global_position.x, b_out.global_position.x),
		a_out.global_position.y,
		min(a_out.global_position.z, b_out.global_position.z)
	)
	var outer_max = Vector3(
		max(a_out.global_position.x, b_out.global_position.x),
		a_out.global_position.y,
		max(a_out.global_position.z, b_out.global_position.z)
	)
	var inner_min = Vector3(
		min(a_in.global_position.x, b_in.global_position.x),
		a_in.global_position.y,
		min(a_in.global_position.z, b_in.global_position.z)
	)
	var inner_max = Vector3(
		max(a_in.global_position.x, b_in.global_position.x),
		a_in.global_position.y,
		max(a_in.global_position.z, b_in.global_position.z)
	)

	var max_attempts = 100
	for i in max_attempts:
		var pos = Vector3(
			randf_range(outer_min.x, outer_max.x),
			outer_min.y,
			randf_range(outer_min.z, outer_max.z)
		)
		var inside_inner = (
			pos.x >= inner_min.x and pos.x <= inner_max.x
			and pos.z >= inner_min.z and pos.z <= inner_max.z
		)
		if not inside_inner:
			return pos

	push_warning("Couldn't find valid spawn position after %d attempts - check your marker setup!" % max_attempts)
	return Vector3(outer_min.x, outer_min.y, outer_min.z)  # fallback so it never hangs
