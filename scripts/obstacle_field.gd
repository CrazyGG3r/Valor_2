class_name ObstacleField
extends Node3D
## Scatters static box obstacles across the arena at run start. Uses its own
## RandomNumberGenerator seeded from the run seed so layouts are reproducible
## for RL training. Obstacles sit on world layer 1, so they block movement,
## projectiles, and the ranged enemy's line-of-sight ray.

## Offset added to the run seed so this stream is decorrelated from the
## spawner (seed) and upgrade (seed + 1) streams.
const SEED_OFFSET := 2

@export var obstacle_count := 15
## Obstacles are placed within this half-extent from the field's origin.
@export var arena_half_extent := 24.0
## Keeps the player spawn (arena center) open.
@export var center_clearance := 6.0
## Minimum distance between obstacle centers, so the arena never closes up.
@export var min_spacing := 3.0
@export var min_size := Vector3(1.5, 5.5, 1.5)
@export var max_size := Vector3(4.0, 3.0, 4.0)
@export var color := Color(0.35, 0.33, 0.3)

var _rng := RandomNumberGenerator.new()


## Clears the previous layout and generates a new one. 0 = random layout.
func generate(seed_value: int = 0) -> void:
	clear()
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value + SEED_OFFSET
	var placed: Array[Vector3] = []
	for i in obstacle_count:
		for attempt in 24:
			var pos := Vector3(
				_rng.randf_range(-arena_half_extent, arena_half_extent),
				0.0,
				_rng.randf_range(-arena_half_extent, arena_half_extent))
			if pos.length() < center_clearance:
				continue
			if not _spaced_from(placed, pos):
				continue
			var size := Vector3(
				_rng.randf_range(min_size.x, max_size.x),
				_rng.randf_range(min_size.y, max_size.y),
				_rng.randf_range(min_size.z, max_size.z))
			_spawn_obstacle(pos, size, _rng.randf_range(0.0, TAU))
			placed.append(pos)
			break


func clear() -> void:
	for child in get_children():
		child.queue_free()


func _spaced_from(placed: Array[Vector3], pos: Vector3) -> bool:
	for other in placed:
		if pos.distance_to(other) < min_spacing:
			return false
	return true


func _spawn_obstacle(pos: Vector3, size: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1  # world layer: blocks bodies, projectiles, LOS
	body.collision_mask = 0
	body.add_to_group(&"obstacles")
	# Spawner keep-out radius: half the footprint diagonal covers any yaw.
	body.set_meta(&"clear_radius", Vector2(size.x, size.z).length() / 2.0)

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box.material = material
	mesh.mesh = box
	body.add_child(mesh)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

	add_child(body)
	body.global_position = global_position + pos + Vector3(0.0, size.y / 2.0, 0.0)
	body.rotation.y = yaw
