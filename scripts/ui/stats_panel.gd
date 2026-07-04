extends PanelContainer
## Hover-to-expand stats dropdown (top-left). Collapsed it shows only the
## header; hovering reveals the full list. Needs a visible cursor -- press
## Esc in-game to free the mouse.

@onready var header: Label = $VBox/Header
@onready var body: Label = $VBox/Body

var _game: GameManager


func _ready() -> void:
	_game = get_tree().get_first_node_in_group(&"game_manager") as GameManager
	mouse_entered.connect(_set_expanded.bind(true))
	mouse_exited.connect(_set_expanded.bind(false))


func _set_expanded(expanded: bool) -> void:
	body.visible = expanded
	header.text = "Stats ▴" if expanded else "Stats ▾"


func _process(_delta: float) -> void:
	if not body.visible or _game == null:
		return
	var levels := _game.player.level_system
	var lines := [
		"Controller: %s" % (AIBridge.agent_name if AIBridge.is_ai_active() else "Human"),
		"Wave: %d" % _game.get_wave(),
		"Kills: %d" % _game.kills,
		"Time: %.1f s" % _game.run_time,
		"Level: %d" % levels.level,
		"XP: %.0f / %.0f" % [levels.xp, levels.xp_to_next()],
		"Enemies: %d" % get_tree().get_nodes_in_group(&"enemies").size(),
		"FPS: %d" % Engine.get_frames_per_second(),
	]
	var upgrades := _game.acquired_upgrade_summary()
	if not upgrades.is_empty():
		lines.append("Upgrades:")
		for entry in upgrades:
			lines.append("  " + entry)
	body.text = "\n".join(lines)
