extends Control
## Front-end shell shown at boot (see project.godot main_scene). The MODE picker
## and the LEADERBOARD pages are both generated from MODES, so the whole
## front-end stays in sync as modes come online -- adding a mode is one entry.

const GAME_SCENE_PATH := "res://main.tscn"

## Single source of truth for game modes. `implemented` gates whether selecting
## the mode launches a run or shows a "coming soon" placeholder, and drives the
## leaderboard page content.
const MODES: Array[Dictionary] = [
	{"id": "ai_only", "label": "AI ONLY", "implemented": true,
		"blurb": "Watch a trained agent clear the arena."},
	{"id": "coop", "label": "COOP", "implemented": false,
		"blurb": "Two players, one arena. Coming soon."},
	{"id": "multi_coop", "label": "MULTI-COOP", "implemented": false,
		"blurb": "Bigger squads, bigger swarms. Coming soon."},
	{"id": "chaos", "label": "CHAOS", "implemented": false,
		"blurb": "All rules off. Coming soon."},
]

@onready var _mode_panel: PanelContainer = $ModePanel
@onready var _leaderboard_panel: PanelContainer = $LeaderboardPanel
@onready var _placeholder: PanelContainer = $Placeholder
@onready var _placeholder_title: Label = $Placeholder/VBox/Title
@onready var _placeholder_body: Label = $Placeholder/VBox/Body
@onready var _mode_buttons: VBoxContainer = $ModePanel/VBox/ModeButtons
@onready var _mode_tabs: TabContainer = $LeaderboardPanel/VBox/ModeTabs


func _ready() -> void:
	# The arena captures the mouse; make sure it is free when we return here.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_hide_all_panels()
	_build_mode_buttons()
	_build_leaderboard_tabs()
	var buttons := $Center/Menu/MainButtons
	buttons.get_node(^"ModeButton").pressed.connect(_open_mode_panel)
	buttons.get_node(^"LeaderboardButton").pressed.connect(_open_leaderboard)
	buttons.get_node(^"OptionsButton").pressed.connect(_show_placeholder.bind(
		"OPTIONS", "Difficulty and gameplay options land here."))
	buttons.get_node(^"SettingsButton").pressed.connect(_show_placeholder.bind(
		"SETTINGS", "Audio, video, and control settings land here."))
	buttons.get_node(^"CreditButton").pressed.connect(_show_placeholder.bind(
		"CREDITS", "VALORIUM\nMade with Godot."))
	buttons.get_node(^"ExitButton").pressed.connect(_on_exit)
	$ModePanel/VBox/BackButton.pressed.connect(_hide_all_panels)
	$LeaderboardPanel/VBox/BackButton.pressed.connect(_hide_all_panels)
	$Placeholder/VBox/BackButton.pressed.connect(_hide_all_panels)


func _build_mode_buttons() -> void:
	for mode in MODES:
		var button := Button.new()
		button.custom_minimum_size = Vector2(280, 44)
		button.text = String(mode["label"])
		button.pressed.connect(_on_mode_selected.bind(mode))
		_mode_buttons.add_child(button)


func _build_leaderboard_tabs() -> void:
	# One page per mode. Real run results get wired in later; unimplemented modes
	# show a dummy page so the navigation is complete today.
	for mode in MODES:
		var page := VBoxContainer.new()
		page.name = String(mode["label"])
		var body := Label.new()
		body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if bool(mode["implemented"]):
			body.text = "No runs recorded yet.\nTop scores will appear here."
		else:
			body.text = "%s is not implemented yet." % String(mode["label"])
		page.add_child(body)
		_mode_tabs.add_child(page)


func _on_mode_selected(mode: Dictionary) -> void:
	if bool(mode["implemented"]):
		# TODO(coop): route each implemented mode to its own setup instead of
		# always loading the single-arena scene.
		get_tree().change_scene_to_file(GAME_SCENE_PATH)
	else:
		_show_placeholder(String(mode["label"]), String(mode["blurb"]))


func _on_exit() -> void:
	get_tree().quit()


func _open_mode_panel() -> void:
	_hide_all_panels()
	_mode_panel.visible = true


func _open_leaderboard() -> void:
	_hide_all_panels()
	_leaderboard_panel.visible = true


func _show_placeholder(title: String, body: String) -> void:
	_hide_all_panels()
	_placeholder_title.text = title
	_placeholder_body.text = body
	_placeholder.visible = true


func _hide_all_panels() -> void:
	_mode_panel.visible = false
	_leaderboard_panel.visible = false
	_placeholder.visible = false
