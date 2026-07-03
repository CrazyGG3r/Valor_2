class_name GameManager
extends Node3D
## Root of the main scene. Owns the run lifecycle (start, death, reset) and
## aggregates gameplay events into signals the AI bridge and future UI consume.

signal run_started
signal run_ended(stats: Dictionary)
signal enemy_killed(enemy: Node3D)
signal player_damaged(amount: float)
signal player_damage_dealt(amount: float)

## Restart automatically after death (human play loop). The AI bridge turns
## this off and drives resets through its own protocol.
@export var auto_restart := true
@export var restart_delay := 1.5

@onready var player: Player = $Player
@onready var spawner: EnemySpawner = $Spawner

var run_time := 0.0
var kills := 0
var run_active := false

var _initial_player_transform: Transform3D


func _ready() -> void:
	add_to_group(&"game_manager")
	_initial_player_transform = player.global_transform
	player.health.died.connect(_on_player_died)
	player.health.damaged.connect(
		func(amount: float, _source: Node) -> void: player_damaged.emit(amount))
	spawner.enemy_spawned.connect(_on_enemy_spawned)
	start_run()


func _physics_process(delta: float) -> void:
	if run_active:
		run_time += delta


func start_run(seed_value: int = 0) -> void:
	run_time = 0.0
	kills = 0
	player.global_transform = _initial_player_transform
	player.velocity = Vector3.ZERO
	player.health.reset()
	spawner.restart(seed_value)
	run_active = true
	run_started.emit()


func get_wave() -> int:
	return spawner.wave_index


func _on_enemy_spawned(enemy: Node3D) -> void:
	var health: HealthComponent = enemy.get_node_or_null(^"HealthComponent")
	if health != null:
		# All damage to enemies is player-dealt until enemy friendly fire exists.
		health.damaged.connect(
			func(amount: float, _source: Node) -> void: player_damage_dealt.emit(amount))
		health.died.connect(
			func() -> void:
				kills += 1
				enemy_killed.emit(enemy))


func _on_player_died() -> void:
	run_active = false
	spawner.stop()
	run_ended.emit({"time": run_time, "kills": kills, "wave": spawner.wave_index})
	if auto_restart:
		get_tree().create_timer(restart_delay).timeout.connect(
			func() -> void:
				if auto_restart:
					start_run())
