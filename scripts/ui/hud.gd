extends Control
## Player vitals: health bar (green -> red), XP bar, level label.
## Reads state each frame; all styling is code-driven so the scene stays thin.

@onready var health_bar: ProgressBar = $HealthBar
@onready var xp_bar: ProgressBar = $XPBar
@onready var level_label: Label = $LevelLabel

var _game: GameManager
var _health_fill := StyleBoxFlat.new()
var _xp_fill := StyleBoxFlat.new()


func _ready() -> void:
	_game = get_tree().get_first_node_in_group(&"game_manager") as GameManager
	_health_fill.bg_color = Color.GREEN
	_health_fill.set_corner_radius_all(3)
	_xp_fill.bg_color = Color(0.35, 0.75, 1.0)
	_xp_fill.set_corner_radius_all(3)
	health_bar.add_theme_stylebox_override("fill", _health_fill)
	xp_bar.add_theme_stylebox_override("fill", _xp_fill)


func _process(_delta: float) -> void:
	if _game == null:
		return
	var health := _game.player.health
	health_bar.max_value = health.max_health
	health_bar.value = health.health
	var fraction := clampf(health.health / health.max_health, 0.0, 1.0)
	_health_fill.bg_color = Color(1.0 - fraction, fraction, 0.0)

	var levels := _game.player.level_system
	xp_bar.value = levels.xp_fraction()
	level_label.text = "Lv %d" % levels.level
