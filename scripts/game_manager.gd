class_name GameManager
extends Node3D
## Root of the main scene. Owns the run lifecycle (start, death, reset),
## run-scoped progression (XP -> level -> upgrade choice), and aggregates
## gameplay events into signals the AI bridge and UI consume. Also spawns
## damage numbers centrally, since it already hears every damage signal.

signal run_started
signal run_ended(stats: Dictionary)
signal enemy_killed(enemy: Node3D)
signal player_damaged(amount: float)
signal player_damage_dealt(amount: float)
signal xp_collected(amount: float)
signal leveled_up(level: int)
signal upgrade_pending(options: Array[Upgrade])
signal upgrade_chosen(upgrade: Upgrade)

## Restart automatically after death (human play loop). The AI bridge turns
## this off and drives resets through its own protocol.
@export var auto_restart := true
@export var restart_delay := 1.5

@export_group("Upgrades")
@export var upgrade_pool: UpgradePool
@export var upgrade_choices := 3

@onready var player: Player = $Player
@onready var spawner: EnemySpawner = $Spawner
@onready var obstacle_field: ObstacleField = get_node_or_null(^"ObstacleField")

var run_time := 0.0
var kills := 0
var shots_fired := 0
var dashes := 0
var melee_swings := 0
## Running totals for research-grade episode stats (see episode_stats()).
var damage_dealt_total := 0.0
var damage_taken_total := 0.0
var peak_speed := 0.0
## Per enemy-type breakdowns: {"melee"/"tank"/"ranged"/"unknown": count/amount}.
var kills_by_type: Dictionary = {}
var damage_taken_by_type: Dictionary = {}
var run_active := false
## Set by the AI bridge; suppresses the pause-driven human upgrade flow.
var ai_controlled := false
var pending_upgrade_options: Array[Upgrade] = []

var _initial_player_transform: Transform3D
var _pending_level_ups := 0
var _upgrade_stacks: Dictionary = {}
## Upgrades in the order they were chosen this run (display names).
var _upgrade_history: Array[String] = []
var _upgrade_rng := RandomNumberGenerator.new()


func _enter_tree() -> void:
	# Registered here, not in _ready(): this node is the scene root, whose
	# _ready() runs AFTER its children's. The UI panels look this node up by
	# group in their own _ready(), so it must be discoverable before then.
	add_to_group(&"game_manager")


func _ready() -> void:
	_initial_player_transform = player.global_transform
	player.health.died.connect(_on_player_died)
	player.health.damaged.connect(_on_player_damaged)
	player.level_system.xp_gained.connect(
		func(amount: float, _total: float) -> void: xp_collected.emit(amount))
	player.level_system.leveled_up.connect(_on_leveled_up)
	# Action-usage tallies for episode stats. Only the player's components are
	# connected, so enemy shots never count.
	player.projectile_launcher.fired.connect(func() -> void: shots_fired += 1)
	player.melee_weapon.attacked.connect(func() -> void: melee_swings += 1)
	player.dashed.connect(func() -> void: dashes += 1)
	spawner.enemy_spawned.connect(_on_enemy_spawned)
	start_run()


func _physics_process(delta: float) -> void:
	if run_active:
		# Divide out --speed (Engine.time_scale scales delta) so run_time is in
		# real game-seconds regardless of training speed. See survive reward in
		# ai_bridge.gd, kept normalized the same way.
		run_time += delta / maxf(Engine.time_scale, 0.0001)
		var horizontal_speed := Vector2(player.velocity.x, player.velocity.z).length()
		peak_speed = maxf(peak_speed, horizontal_speed)


func start_run(seed_value: int = 0) -> void:
	run_time = 0.0
	kills = 0
	shots_fired = 0
	dashes = 0
	melee_swings = 0
	damage_dealt_total = 0.0
	damage_taken_total = 0.0
	peak_speed = 0.0
	# Seeded with every type so the JSONL schema is stable even at zero.
	kills_by_type = {"melee": 0, "tank": 0, "ranged": 0, "unknown": 0}
	damage_taken_by_type = {"melee": 0.0, "tank": 0.0, "ranged": 0.0, "unknown": 0.0}
	pending_upgrade_options = []
	_pending_level_ups = 0
	_upgrade_stacks.clear()
	_upgrade_history.clear()
	if seed_value == 0:
		_upgrade_rng.randomize()
	else:
		_upgrade_rng.seed = seed_value + 1  # decorrelated from the spawner stream
	for orb in get_tree().get_nodes_in_group(&"xp_orbs"):
		orb.queue_free()
	for projectile in get_tree().get_nodes_in_group(&"projectiles"):
		projectile.queue_free()
	player.global_transform = _initial_player_transform
	player.velocity = Vector3.ZERO
	player.reset_stats()
	player.health.reset()
	player.level_system.reset()
	# Obstacles first: the spawner rejects spawn points inside them.
	if obstacle_field != null:
		obstacle_field.generate(seed_value)
	spawner.restart(seed_value)
	run_active = true
	if not ai_controlled:
		get_tree().paused = false
	run_started.emit()


func get_wave() -> int:
	return spawner.wave_index


# --- upgrades ---------------------------------------------------------------


func has_pending_upgrade() -> bool:
	return not pending_upgrade_options.is_empty()


## Pool indices of the current options; the AI observation encoding.
func get_upgrade_option_indices() -> Array[int]:
	var indices: Array[int] = []
	for upgrade in pending_upgrade_options:
		indices.append(upgrade_pool.upgrades.find(upgrade))
	return indices


## Upgrades in the exact order the player/agent chose them this run, e.g.
## ["Sharp Blade", "Swift Boots", "Sharp Blade"]. Useful for studying the AI's
## skill-selection strategy over a run.
func acquired_upgrade_order() -> Array[String]:
	return _upgrade_history.duplicate()


## Full per-episode stat blob for offline analysis (ai_progress_viz). Kept out
## of the training console on purpose -- this is written to disk per episode.
func episode_stats() -> Dictionary:
	return {
		"wave": get_wave(),
		"time": run_time,
		"kills": kills,
		"shots_fired": shots_fired,
		"dashes": dashes,
		"melee_swings": melee_swings,
		"damage_dealt": damage_dealt_total,
		"damage_taken": damage_taken_total,
		"kills_by_type": kills_by_type.duplicate(),
		"damage_taken_by_type": damage_taken_by_type.duplicate(),
		"final_health": player.health.health,
		"max_health": player.health.max_health,
		"move_speed": player.speed,
		"peak_speed": peak_speed,
		"level": player.level_system.level,
		"upgrade_order": acquired_upgrade_order(),
		"upgrade_counts": _upgrade_stacks.duplicate(),
	}


## Lines like "Swift Boots x2" for the stats panel.
func acquired_upgrade_summary() -> Array[String]:
	var lines: Array[String] = []
	if upgrade_pool == null:
		return lines
	for upgrade in upgrade_pool.upgrades:
		var count := int(_upgrade_stacks.get(upgrade.id, 0))
		if count > 0:
			lines.append("%s x%d" % [upgrade.display_name, count])
	return lines


func choose_upgrade(index: int) -> void:
	if pending_upgrade_options.is_empty():
		return
	var choice := pending_upgrade_options[clampi(index, 0, pending_upgrade_options.size() - 1)]
	_upgrade_stacks[choice.id] = int(_upgrade_stacks.get(choice.id, 0)) + 1
	_upgrade_history.append(choice.display_name)
	player.apply_upgrade(choice)
	pending_upgrade_options = []
	_pending_level_ups = maxi(_pending_level_ups - 1, 0)
	upgrade_chosen.emit(choice)
	if _pending_level_ups > 0:
		_present_next_upgrade()
	elif not ai_controlled:
		get_tree().paused = false


func _on_leveled_up(new_level: int) -> void:
	leveled_up.emit(new_level)
	_pending_level_ups += 1
	if pending_upgrade_options.is_empty():
		_present_next_upgrade()


func _present_next_upgrade() -> void:
	pending_upgrade_options = _roll_options()
	if pending_upgrade_options.is_empty():
		# Entire pool is maxed out; skip the choice silently.
		_pending_level_ups = 0
		if not ai_controlled:
			get_tree().paused = false
		return
	if not ai_controlled:
		get_tree().paused = true
	upgrade_pending.emit(pending_upgrade_options)


func _roll_options() -> Array[Upgrade]:
	var available: Array[Upgrade] = []
	if upgrade_pool != null:
		for upgrade in upgrade_pool.upgrades:
			if upgrade.max_stacks <= 0 \
					or int(_upgrade_stacks.get(upgrade.id, 0)) < upgrade.max_stacks:
				available.append(upgrade)
	var options: Array[Upgrade] = []
	while options.size() < upgrade_choices and not available.is_empty():
		options.append(available.pop_at(_upgrade_rng.randi_range(0, available.size() - 1)))
	return options


# --- combat events ----------------------------------------------------------


func _on_player_damaged(amount: float, source: Node) -> void:
	damage_taken_total += amount
	var key := _damage_source_type_key(source)
	damage_taken_by_type[key] = float(damage_taken_by_type.get(key, 0.0)) + amount
	player_damaged.emit(amount)
	DamageNumber.spawn(self, player.global_position + Vector3.UP * 1.6, amount, Color.RED)


## "melee"/"tank"/"ranged"/"unknown" for an enemy node.
func _enemy_type_key(node: Node) -> String:
	if not (node is Enemy):
		return "unknown"
	match (node as Enemy).type_id:
		Enemy.TYPE_TANK: return "tank"
		Enemy.TYPE_RANGED: return "ranged"
		Enemy.TYPE_MELEE: return "melee"
		_: return "unknown"


## Resolves a damage source to an enemy type. Contact hits come from an enemy's
## Hitbox (walk up to the Enemy); projectiles are only fired at the player by
## ranged enemies.
func _damage_source_type_key(source: Node) -> String:
	var node := source
	while node != null:
		if node is Enemy:
			return _enemy_type_key(node)
		node = node.get_parent()
	if source is Projectile:
		return "ranged"
	return "unknown"


func _on_enemy_spawned(enemy: Node3D) -> void:
	var health: HealthComponent = enemy.get_node_or_null(^"HealthComponent")
	if health == null:
		return
	# Captured now so the tally survives the node being freed on death.
	var type_key := _enemy_type_key(enemy)
	# All damage to enemies counts as player-dealt until enemy friendly fire exists.
	health.damaged.connect(
		func(amount: float, _source: Node) -> void:
			damage_dealt_total += amount
			player_damage_dealt.emit(amount)
			if is_instance_valid(enemy):
				DamageNumber.spawn(
					self, enemy.global_position + Vector3.UP * 1.8, amount,
					Color(1.0, 0.85, 0.3)))
	health.died.connect(
		func() -> void:
			kills += 1
			kills_by_type[type_key] = int(kills_by_type.get(type_key, 0)) + 1
			enemy_killed.emit(enemy))


func _on_player_died() -> void:
	run_active = false
	spawner.stop()
	run_ended.emit({
		"time": run_time,
		"kills": kills,
		"wave": spawner.wave_index,
		"shots_fired": shots_fired,
		"dashes": dashes,
		"melee_swings": melee_swings,
	})
	if auto_restart:
		get_tree().create_timer(restart_delay).timeout.connect(
			func() -> void:
				if auto_restart:
					start_run())
