class_name EnemySpawner
extends Node3D
## Spawns waves mixing melee (fast), tank, and ranged enemies. Spawn points
## are uniform over a disk, rejected when too close to the player or inside
## an obstacle's keep-out radius. Uses its own RandomNumberGenerator so a
## seed makes an entire run's spawning reproducible (required for RL).

signal enemy_spawned(enemy: Node3D)
signal wave_spawned(wave_index: int)

@export_group("Enemy Types")
@export var melee_scene: PackedScene
@export var tank_scene: PackedScene
@export var ranged_scene: PackedScene
## First wave each type appears in.
@export var tank_start_wave := 3
@export var ranged_start_wave := 2
## Relative pick weight once fully ramped in (melee is always 1.0).
@export var tank_weight := 0.35
@export var ranged_weight := 0.45
## Waves a newly unlocked type takes to reach its full weight.
@export var weight_ramp_waves := 3

@export_group("Difficulty")
enum HealthCurve { EXPONENTIAL, LOGARITHMIC, LINEAR }
## Shape of the enemy max-health ramp across waves. EXPONENTIAL compounds (keeps
## pace with the player's upgrade snowball); LOGARITHMIC ramps hard early then
## flattens; LINEAR is a flat per-tier increase.
@export var health_curve := HealthCurve.EXPONENTIAL
## Health is re-scaled once per this many waves (a difficulty "tier").
@export var health_scale_interval := 3
## Growth strength per tier. e.g. EXPONENTIAL 0.12 => x1.12 health each tier.
@export var health_scale_rate := 0.12

@export_group("Placement")
@export var spawn_radius := 16.0
@export var spawn_height := 1.0
## Melee/tank enemies never spawn closer to the player than this.
@export var min_player_distance := 4.0
## Ranged enemies spawn farther out so they open with pressure, not contact.
@export var ranged_min_player_distance := 10.0
## Extra clearance between spawn points and obstacle keep-out radii.
@export var obstacle_clearance := 1.0

@export_group("Pacing")
@export var spawn_count := 5
## Extra enemies added per elapsed wave (fractional accumulates).
@export var spawn_count_growth := 0.5
@export var spawn_interval := 5.0
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
	# Physics callback: wave timing must count simulated physics frames, not
	# rendered frames, or seeded runs diverge under the AI bridge's lockstep.
	_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
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
	if melee_scene == null:
		push_warning("EnemySpawner: no melee scene assigned.")
		return
	if get_tree().get_nodes_in_group(&"enemies").size() >= max_alive:
		return
	wave_index += 1
	var count := spawn_count + int(spawn_count_growth * (wave_index - 1))
	for i in count:
		_spawn_one()
	wave_spawned.emit(wave_index)


func _spawn_one() -> void:
	var entry := _pick_type()
	var enemy := (entry["scene"] as PackedScene).instantiate() as Node3D
	add_child(enemy)  # must enter the tree BEFORE global_position is valid
	enemy.global_position = _random_position(float(entry["min_distance"]))
	if enemy is Enemy:
		(enemy as Enemy).apply_health_scale(health_scale_multiplier(wave_index))
	enemy_spawned.emit(enemy)


## Deterministic max-health multiplier for enemies spawned on the given wave.
## Purely a function of the wave index (no RNG), so seeded runs stay
## reproducible. Tier = how many full intervals of waves have elapsed.
func health_scale_multiplier(wave: int) -> float:
	var tier := float(maxi(wave - 1, 0) / maxi(health_scale_interval, 1))
	if tier <= 0.0:
		return 1.0
	match health_curve:
		HealthCurve.LOGARITHMIC:
			return 1.0 + health_scale_rate * log(1.0 + tier)
		HealthCurve.LINEAR:
			return 1.0 + health_scale_rate * tier
		_:  # EXPONENTIAL
			return pow(1.0 + health_scale_rate, tier)


## Weighted pick over the types unlocked at the current wave. New types fade
## in over weight_ramp_waves so the mix shifts gradually.
func _pick_type() -> Dictionary:
	var entries: Array[Dictionary] = [
		{"scene": melee_scene, "weight": 1.0, "min_distance": min_player_distance},
	]
	if ranged_scene != null and wave_index >= ranged_start_wave:
		entries.append({
			"scene": ranged_scene,
			"weight": ranged_weight * _ramp(ranged_start_wave),
			"min_distance": ranged_min_player_distance,
		})
	if tank_scene != null and wave_index >= tank_start_wave:
		entries.append({
			"scene": tank_scene,
			"weight": tank_weight * _ramp(tank_start_wave),
			"min_distance": min_player_distance,
		})
	var total := 0.0
	for entry in entries:
		total += float(entry["weight"])
	var roll := _rng.randf() * total
	for entry in entries:
		roll -= float(entry["weight"])
		if roll <= 0.0:
			return entry
	return entries[0]


func _ramp(start_wave: int) -> float:
	return clampf(
		float(wave_index - start_wave + 1) / float(maxi(weight_ramp_waves, 1)), 0.0, 1.0)


func _random_position(min_distance: float) -> Vector3:
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	for attempt in 24:
		var angle := _rng.randf_range(0.0, TAU)
		var distance := spawn_radius * sqrt(_rng.randf())  # sqrt = uniform over disk
		var pos := global_position + Vector3(cos(angle) * distance, spawn_height, sin(angle) * distance)
		if player != null and _horizontal_distance(pos, player.global_position) < min_distance:
			continue
		if not _clear_of_obstacles(pos):
			continue
		return pos
	# Player/obstacles cover most of the disk; spawn at the rim rather than stall.
	return global_position + Vector3(spawn_radius, spawn_height, 0.0)


func _clear_of_obstacles(pos: Vector3) -> bool:
	for node in get_tree().get_nodes_in_group(&"obstacles"):
		var obstacle := node as Node3D
		if obstacle == null or obstacle.is_queued_for_deletion():
			continue
		var radius := float(obstacle.get_meta(&"clear_radius", 1.5))
		if _horizontal_distance(pos, obstacle.global_position) < radius + obstacle_clearance:
			return false
	return true


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
