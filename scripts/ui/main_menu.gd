extends Control
## Front-end shell shown at boot (see project.godot main_scene). MODE launches
## a run; the other entries open a shared placeholder panel for now. This is the
## foundation the coop flow will hang off of -- MODE will grow into a
## solo/coop picker rather than jumping straight into the arena.

const GAME_SCENE_PATH := "res://main.tscn"

@onready var _placeholder: PanelContainer = $Placeholder
@onready var _placeholder_title: Label = $Placeholder/VBox/Title
@onready var _placeholder_body: Label = $Placeholder/VBox/Body


func _ready() -> void:
	# The arena captures the mouse; make sure it is free when we return here.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_placeholder.visible = false
	$Center/Menu/ModeButton.pressed.connect(_on_mode)
	$Center/Menu/OptionsButton.pressed.connect(_show_placeholder.bind(
		"OPTIONS", "Difficulty and gameplay options land here."))
	$Center/Menu/SettingsButton.pressed.connect(_show_placeholder.bind(
		"SETTINGS", "Audio, video, and control settings land here."))
	$Center/Menu/CreditButton.pressed.connect(_show_placeholder.bind(
		"CREDITS", "VALORIUM\nMade with Godot."))
	$Center/Menu/ExitButton.pressed.connect(_on_exit)
	$Placeholder/VBox/BackButton.pressed.connect(_hide_placeholder)


func _on_mode() -> void:
	# TODO(coop): open a solo/coop selector here instead of launching directly.
	get_tree().change_scene_to_file(GAME_SCENE_PATH)


func _on_exit() -> void:
	get_tree().quit()


func _show_placeholder(title: String, body: String) -> void:
	_placeholder_title.text = title
	_placeholder_body.text = body
	_placeholder.visible = true


func _hide_placeholder() -> void:
	_placeholder.visible = false
