extends SceneTree
## Temporary headless smoke test (deleted after use) for Arena Purge and
## Beam Turbine. Verifies: purge exposes its safe zones and burns a player
## caught outside them; the turbine's arms measurably rotate; both damage
## paths flow through the Hurtbox pipeline.

var _wall_frames := 0
var _wired := false
var _game: GameManager
var _director: ChaosDirector
var _seen := {}
var _purge_hits := 0
var _turbine_hits := 0
var _purge_zone_count := -1
var _turbine_angle_min := INF
var _turbine_angle_max := -INF


func _initialize() -> void:
	Engine.time_scale = 8.0
	Engine.max_physics_steps_per_frame = 32
	change_scene_to_file("res://main_chaos.tscn")


func _process(_delta: float) -> bool:
	_wall_frames += 1
	if not _wired:
		_game = get_first_node_in_group(&"game_manager") as GameManager
		_director = get_first_node_in_group(&"chaos_director") as ChaosDirector
		if _game != null and _director != null:
			_wired = true
			_director.ramp_duration = 20.0
			_game.spawner.stop()
			_game.spawner.clear_enemies()
			_game.player.health.max_health = 1000000.0
			_game.player.health.health = 1000000.0
			_game.player.hurtbox.hit_received.connect(
				func(_amount: float, source: Node) -> void:
					var node := source
					while node != null and not (node is ChaosEvent):
						node = node.get_parent()
					if node is PurgeEvent:
						_purge_hits += 1
					elif node is TurbineEvent:
						_turbine_hits += 1)
		return false

	for hazard in _director.get_active_hazards():
		var key := String(hazard["type"])
		_seen[key] = true
		if key == "arena_purge" and hazard.has("safe_zones"):
			_purge_zone_count = (hazard["safe_zones"] as Array).size()
		elif key == "beam_turbine" and String(hazard["phase"]) == "active":
			_turbine_angle_min = minf(_turbine_angle_min, float(hazard["arm_angle"]))
			_turbine_angle_max = maxf(_turbine_angle_max, float(hazard["arm_angle"]))

	var rotation_span := _turbine_angle_max - _turbine_angle_min
	var enough := _purge_hits >= 1 and rotation_span > 1.0 and _seen.size() >= 9
	if enough or _wall_frames >= 8000:
		print("SMOKE: events_seen=%s (%d types)" % [str(_seen.keys()), _seen.size()])
		print("SMOKE: purge_hits=%d safe_zones_reported=%d" % [_purge_hits, _purge_zone_count])
		print("SMOKE: turbine_rotation_span=%.2f rad turbine_hits=%d" % [
			rotation_span, _turbine_hits])
		print("SMOKE: player_hp=%.0f run_time=%.1f" % [
			_game.player.health.health, _game.run_time])
		quit()
		return true
	return false
