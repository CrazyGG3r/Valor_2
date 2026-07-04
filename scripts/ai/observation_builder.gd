class_name ObservationBuilder
extends RefCounted
## Builds the structured observation sent to Python each step.
##
## Enemy data is egocentric (rotated into the player's local frame) so the
## policy doesn't have to learn to undo its own yaw. The Python side flattens
## this dict into a fixed vector -- keep ai/environments/valor_env.py in sync.

const MAX_TRACKED_ENEMIES := 5


static func build(game: GameManager) -> Dictionary:
	var player := game.player
	var yaw := player.rotation.y
	var velocity_local := player.velocity.rotated(Vector3.UP, -yaw)

	var candidates: Array[Node3D] = []
	for node in game.get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Node3D
		if enemy != null and not enemy.is_queued_for_deletion():
			candidates.append(enemy)
	candidates.sort_custom(
		func(a: Node3D, b: Node3D) -> bool:
			return a.global_position.distance_squared_to(player.global_position) \
				< b.global_position.distance_squared_to(player.global_position))

	var enemies: Array[Dictionary] = []
	for i in mini(candidates.size(), MAX_TRACKED_ENEMIES):
		var rel := (candidates[i].global_position - player.global_position) \
			.rotated(Vector3.UP, -yaw)
		enemies.append({
			"position": [rel.x, rel.y, rel.z],
			"distance": rel.length(),
		})

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
		"enemies": enemies,
		"enemy_count": candidates.size(),
		"wave": game.get_wave(),
		"time": game.run_time,
		"upgrade": {
			"pending": game.has_pending_upgrade(),
			"options": game.get_upgrade_option_indices(),
		},
	}
