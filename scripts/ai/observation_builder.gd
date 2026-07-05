class_name ObservationBuilder
extends RefCounted
## Builds the structured observation sent to Python each step.
##
## Enemy and projectile data is egocentric (rotated into the player's local
## frame) so the policy doesn't have to learn to undo its own yaw. The Python
## side flattens this dict into a fixed vector -- keep
## ai/environments/valor_env.py perfectly in sync.

const MAX_TRACKED_ENEMIES := 5
const MAX_TRACKED_PROJECTILES := 4
## Only enemy projectiles within this many units of the player are reported.
const PROJECTILE_TRACK_RADIUS := 12.0


static func build(game: GameManager) -> Dictionary:
	var player := game.player
	var yaw := player.rotation.y
	var velocity_local := player.velocity.rotated(Vector3.UP, -yaw)
	var live_enemies := _live_enemies(game, player)

	return {
		"player": {
			"position": [
				player.global_position.x,
				player.global_position.y,
				player.global_position.z,
			],
			"velocity_local": [velocity_local.x, velocity_local.y, velocity_local.z],
			"yaw": yaw,
			"health": player.health.health,
			"max_health": player.health.max_health,
			"cooldowns": player.get_cooldowns(),
			"level": player.level_system.level,
			"xp_fraction": player.level_system.xp_fraction(),
		},
		"enemies": _nearest_enemies(live_enemies, player, yaw),
		"enemy_count": live_enemies.size(),
		"projectiles": _incoming_projectiles(game, player, yaw),
		"wave": game.get_wave(),
		"time": game.run_time,
		"upgrade": {
			"pending": game.has_pending_upgrade(),
			"options": game.get_upgrade_option_indices(),
		},
	}


## Live enemies sorted nearest-first.
static func _live_enemies(game: GameManager, player: Player) -> Array[Node3D]:
	var candidates: Array[Node3D] = []
	for node in game.get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Node3D
		if enemy != null and not enemy.is_queued_for_deletion():
			candidates.append(enemy)
	candidates.sort_custom(
		func(a: Node3D, b: Node3D) -> bool:
			return a.global_position.distance_squared_to(player.global_position) \
				< b.global_position.distance_squared_to(player.global_position))
	return candidates


static func _nearest_enemies(candidates: Array[Node3D], player: Player, yaw: float) -> Array[Dictionary]:
	var enemies: Array[Dictionary] = []
	for i in mini(candidates.size(), MAX_TRACKED_ENEMIES):
		var rel := (candidates[i].global_position - player.global_position) \
			.rotated(Vector3.UP, -yaw)
		var typed := candidates[i] as Enemy
		enemies.append({
			"position": [rel.x, rel.y, rel.z],
			"distance": rel.length(),
			"type": typed.type_id if typed != null else Enemy.TYPE_MELEE,
			"health_fraction": typed.health_fraction() if typed != null else 1.0,
		})
	return enemies


## Enemy-faction projectiles within PROJECTILE_TRACK_RADIUS, nearest first.
## Velocity is in the player's local frame so "toward me" reads the same at
## any yaw.
static func _incoming_projectiles(game: GameManager, player: Player, yaw: float) -> Array[Dictionary]:
	var candidates: Array[Projectile] = []
	for node in game.get_tree().get_nodes_in_group(&"projectiles"):
		var projectile := node as Projectile
		if projectile == null or projectile.is_queued_for_deletion():
			continue
		if projectile.faction == &"player":
			continue
		if projectile.global_position.distance_to(player.global_position) \
				> PROJECTILE_TRACK_RADIUS:
			continue
		candidates.append(projectile)
	candidates.sort_custom(
		func(a: Projectile, b: Projectile) -> bool:
			return a.global_position.distance_squared_to(player.global_position) \
				< b.global_position.distance_squared_to(player.global_position))

	var projectiles: Array[Dictionary] = []
	for i in mini(candidates.size(), MAX_TRACKED_PROJECTILES):
		var projectile := candidates[i]
		var rel := (projectile.global_position - player.global_position) \
			.rotated(Vector3.UP, -yaw)
		var vel := (projectile.direction * projectile.speed).rotated(Vector3.UP, -yaw)
		projectiles.append({
			"position": [rel.x, rel.y, rel.z],
			"velocity": [vel.x, vel.y, vel.z],
			"distance": rel.length(),
		})
	return projectiles
