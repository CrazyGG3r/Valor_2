class_name EnemySpawner
extends Node3D
## Spawns waves of enemies at random points inside spawn_radius, uniformly
## distributed over the disk. Uses its own RandomNumberGenerator so a seed
## makes an entire run's spawning reproducible (required for RL training).

signal enemy_spawned(enemy: Node3D)
signal wave_spawned(wave_index: int)

@export var enemy_scenes: Array[PackedScene] = []
@export var spawn_radius := 10.0
@export var spawn_count := 5
@export var spawn_interval := 5.0
@export var spawn_height := 1.0
## Enemies never spawn closer to the player than this.
@export var min_player_distance := 3.0
## Spawning skips while this many enemies are already alive.
@export var max_alive := 40
## 0 = random every run; any other value makes spawning reproducible.
@export var random_seed := 0
## Off by default: the GameManager drives restart(). Enable for test scenes.
@export var auto_start := false

var wave_index := 0

var _rng := RandomNumberGenerator.new()
var _timer: Timer


func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = false
	_timer.timeout.connect(spawn_wave)
	add_child(_timer)
	if auto_start:
		restart(random_seed)


## Clears all enemies and starts spawning from wave 1 again.
func restart(seed_value: int = 0) -> void:
	clear_enemies()
	wave_index = 0
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	_timer.start(spawn_interval)
	spawn_wave()


func stop() -> void:
	_timer.stop()


func clear_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		enemy.queue_free()


func spawn_wave() -> void:
	if enemy_scenes.is_empty():
		push_warning("EnemySpawner: no enemy scenes assigned.")
		return
	if get_tree().get_nodes_in_group(&"enemies").size() >= max_alive:
		return
	wave_index += 1
	for i in spawn_count:
		_spawn_one()
	wave_spawned.emit(wave_index)


func _spawn_one() -> void:
	var scene: PackedScene = enemy_scenes[_rng.randi_range(0, enemy_scenes.size() - 1)]
	var enemy := scene.instantiate() as Node3D
	add_child(enemy)  # must enter the tree BEFORE global_position is valid
	enemy.global_position = _random_position()
	enemy_spawned.emit(enemy)


func _random_position() -> Vector3:
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	for attempt in 16:
		var angle := _rng.randf_range(0.0, TAU)
		var distance := spawn_radius * sqrt(_rng.randf())  # sqrt = uniform over disk
		var pos := global_position + Vector3(cos(angle) * distance, spawn_height, sin(angle) * distance)
		if player == null or pos.distance_to(player.global_position) >= min_player_distance:
			return pos
	# Player covers most of the radius; spawn at the rim rather than stall.
	return global_position + Vector3(spawn_radius, spawn_height, 0.0)
