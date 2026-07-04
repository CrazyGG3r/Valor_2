extends Node
## AIBridge autoload -- Gym-style reset/step API over TCP, one JSON object per
## line. Full protocol documentation lives in ai/README.md.
##
##   -> {"type": "reset", "seed": 123}
##   <- {"type": "obs", "observation": {...}, "reward": 0.0, "done": false, "info": {}}
##   -> {"type": "step", "action": {"move": [x,y], "look": [x,y], "jump": false, ...}}
##   <- {"type": "obs", ...}
##
## Lockstep: while a client is connected the SceneTree is paused except for
## the exact FRAMES_PER_STEP physics frames that execute each step. The
## simulation therefore never advances while Python is thinking, which keeps
## training deterministic regardless of how slow the agent is.
##
## User command-line args (after "--" on the Godot command line):
##   --ai-port=11008   listen port
##   --speed=8         Engine.time_scale multiplier for faster training

const DEFAULT_PORT := 11008
## Physics frames simulated per step() call (action repeat).
const FRAMES_PER_STEP := 4
## Radians of yaw applied per step at look_x = +/-1.
const MAX_LOOK_PER_STEP := 0.15
const PROTOCOL_VERSION := 3
const REWARD_CONFIG_PATH := "res://configs/reward_config.tres"

## Shown in the stats UI while a client drives the player.
var agent_name := ""

var _server := TCPServer.new()
var _client: StreamPeerTCP
var _buffer := ""
var _reward_config: RewardConfig
var _game: GameManager
var _ai_provider: AIInputProvider
var _human_provider: InputProvider
var _frames_left := 0
var _step_in_flight := false
var _reward := 0.0
var _done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_reward_config = _load_reward_config()

	var port := DEFAULT_PORT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ai-port="):
			port = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--speed="):
			var speed := arg.get_slice("=", 1).to_float()
			Engine.time_scale = speed
			Engine.max_physics_steps_per_frame = maxi(8, int(speed) * 2)

	var err := _server.listen(port, "127.0.0.1")
	if err == OK:
		print("AIBridge listening on 127.0.0.1:%d" % port)
	else:
		push_error("AIBridge failed to listen on port %d: %s" % [port, error_string(err)])


func _process(_delta: float) -> void:
	if _server.is_listening() and _server.is_connection_available():
		_accept_client()
	if _client == null:
		return
	_client.poll()
	var status := _client.get_status()
	if status != StreamPeerTCP.STATUS_CONNECTED:
		if status != StreamPeerTCP.STATUS_CONNECTING:
			_drop_client()
		return
	var available := _client.get_available_bytes()
	if available > 0:
		_buffer += _client.get_utf8_string(available)
		_drain_buffer()


func _physics_process(delta: float) -> void:
	if not _step_in_flight:
		return
	if _frames_left > 0:
		# The bridge (an autoload) processes before scene nodes, so gameplay
		# for this frame runs after the decrement; pausing at zero on the
		# NEXT frame yields exactly FRAMES_PER_STEP simulated frames.
		_frames_left -= 1
		_reward += _reward_config.survive_per_second * delta
	else:
		get_tree().paused = true
		_step_in_flight = false
		_send_state(_reward, _done)


# --- connection lifecycle ---------------------------------------------------


func _accept_client() -> void:
	var incoming := _server.take_connection()
	if incoming == null:
		return
	if _client != null:
		incoming.disconnect_from_host()  # single-client protocol
		return
	_game = get_tree().get_first_node_in_group(&"game_manager") as GameManager
	if _game == null:
		push_error("AIBridge: no GameManager in the scene; rejecting client.")
		incoming.disconnect_from_host()
		return
	_client = incoming
	_client.set_no_delay(true)
	_buffer = ""
	_attach_ai_control()
	get_tree().paused = true
	_send({
		"type": "hello",
		"version": PROTOCOL_VERSION,
		"frames_per_step": FRAMES_PER_STEP,
		"max_tracked_enemies": ObservationBuilder.MAX_TRACKED_ENEMIES,
	})
	print("AIBridge: client connected, simulation under AI control.")


func is_ai_active() -> bool:
	return _client != null


func _attach_ai_control() -> void:
	_game.auto_restart = false
	_game.ai_controlled = true
	_game.player_damaged.connect(_on_player_damaged)
	_game.player_damage_dealt.connect(_on_damage_dealt)
	_game.enemy_killed.connect(_on_enemy_killed)
	_game.run_ended.connect(_on_run_ended)
	_game.xp_collected.connect(_on_xp_collected)
	_game.leveled_up.connect(_on_leveled_up)
	_game.spawner.wave_spawned.connect(_on_wave_spawned)

	var player := _game.player
	_human_provider = player.input_provider
	_ai_provider = AIInputProvider.new()
	_ai_provider.name = &"AIInputProvider"
	player.add_child(_ai_provider)
	player.input_provider = _ai_provider


func _drop_client() -> void:
	_client = null
	_buffer = ""
	_step_in_flight = false
	_done = false
	agent_name = ""
	if _game != null and is_instance_valid(_game):
		_game.auto_restart = true
		_game.ai_controlled = false
		_disconnect_signal(_game.player_damaged, _on_player_damaged)
		_disconnect_signal(_game.player_damage_dealt, _on_damage_dealt)
		_disconnect_signal(_game.enemy_killed, _on_enemy_killed)
		_disconnect_signal(_game.run_ended, _on_run_ended)
		_disconnect_signal(_game.xp_collected, _on_xp_collected)
		_disconnect_signal(_game.leveled_up, _on_leveled_up)
		_disconnect_signal(_game.spawner.wave_spawned, _on_wave_spawned)
		if _human_provider != null and is_instance_valid(_human_provider):
			_game.player.input_provider = _human_provider
	if _ai_provider != null and is_instance_valid(_ai_provider):
		_ai_provider.queue_free()
	_ai_provider = null
	_human_provider = null
	_game = null
	get_tree().paused = false
	print("AIBridge: client disconnected, control returned to human.")


func _disconnect_signal(sig: Signal, callable: Callable) -> void:
	if sig.is_connected(callable):
		sig.disconnect(callable)


# --- reward events ----------------------------------------------------------


func _on_player_damaged(amount: float) -> void:
	_reward += _reward_config.damage_taken * amount


func _on_damage_dealt(amount: float) -> void:
	_reward += _reward_config.damage_dealt * amount


func _on_enemy_killed(_enemy: Node3D) -> void:
	_reward += _reward_config.kill


func _on_run_ended(_stats: Dictionary) -> void:
	_reward += _reward_config.death
	_done = true


func _on_wave_spawned(wave_index: int) -> void:
	if wave_index > 1:
		_reward += _reward_config.wave_survived


func _on_xp_collected(amount: float) -> void:
	_reward += _reward_config.xp_collected * amount


func _on_leveled_up(_level: int) -> void:
	_reward += _reward_config.level_up


# --- protocol ---------------------------------------------------------------


func _drain_buffer() -> void:
	while true:
		var newline := _buffer.find("\n")
		if newline == -1:
			return
		var line := _buffer.substr(0, newline).strip_edges()
		_buffer = _buffer.substr(newline + 1)
		if not line.is_empty():
			_handle_message(line)


func _handle_message(line: String) -> void:
	var parsed: Variant = JSON.parse_string(line)
	if parsed == null or not (parsed is Dictionary):
		_send({"type": "error", "message": "invalid JSON: " + line.left(80)})
		return
	var msg: Dictionary = parsed
	match String(msg.get("type", "")):
		"reset":
			_handle_reset(msg)
		"step":
			_handle_step(msg)
		"close":
			_drop_client()
		_:
			_send({"type": "error", "message": "unknown message type"})


func _handle_reset(msg: Dictionary) -> void:
	agent_name = String(msg.get("agent", "AI"))
	_game.start_run(int(msg.get("seed", 0)))
	_ai_provider.reset()
	_reward = 0.0
	_done = false
	_send_state(0.0, false)


func _handle_step(msg: Dictionary) -> void:
	if _done:
		_send_state(0.0, true)  # episode is over; Python must reset()
		return
	if _step_in_flight:
		_send({"type": "error", "message": "step already in flight"})
		return
	var action: Dictionary = msg.get("action", {})
	if _game.has_pending_upgrade():
		# Decision step: consumes the upgrade choice, no sim time passes.
		# Mirrors the pause a human player gets on the upgrade screen.
		_reward = 0.0
		_game.choose_upgrade(int(action.get("upgrade", 0)))
		_send_state(_reward, _done)
		return
	_apply_action(action)
	_reward = 0.0
	_frames_left = FRAMES_PER_STEP
	_step_in_flight = true
	get_tree().paused = false


func _apply_action(action: Dictionary) -> void:
	var move: Array = action.get("move", [0.0, 0.0])
	var look: Array = action.get("look", [0.0, 0.0])
	_ai_provider.set_move_vector(Vector2(
		clampf(float(move[0]), -1.0, 1.0),
		clampf(float(move[1]), -1.0, 1.0)))
	_ai_provider.add_look_delta(Vector2(
		clampf(float(look[0]), -1.0, 1.0) * MAX_LOOK_PER_STEP,
		clampf(float(look[1]), -1.0, 1.0) * MAX_LOOK_PER_STEP))
	_ai_provider.set_button(InputProvider.ACTION_JUMP, bool(action.get("jump", false)))
	_ai_provider.set_button(InputProvider.ACTION_ATTACK, bool(action.get("attack", false)))
	_ai_provider.set_button(InputProvider.ACTION_SHOOT, bool(action.get("shoot", false)))
	_ai_provider.set_button(InputProvider.ACTION_DASH, bool(action.get("dash", false)))


func _send_state(reward: float, done: bool) -> void:
	_send({
		"type": "obs",
		"observation": ObservationBuilder.build(_game),
		"reward": reward,
		"done": done,
		"info": {"kills": _game.kills, "time": _game.run_time, "wave": _game.get_wave()},
	})


func _send(message: Dictionary) -> void:
	if _client == null:
		return
	_client.put_data((JSON.stringify(message) + "\n").to_utf8_buffer())


func _load_reward_config() -> RewardConfig:
	if ResourceLoader.exists(REWARD_CONFIG_PATH):
		var config := load(REWARD_CONFIG_PATH)
		if config is RewardConfig:
			return config
	return RewardConfig.new()
