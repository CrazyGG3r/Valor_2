extends CenterContainer
## Level-up choice UI for human play. The GameManager pauses the tree and
## emits upgrade_pending; this panel (PROCESS_MODE_ALWAYS via the UI layer)
## shows one button per option. Hidden entirely during AI control -- the
## agent picks through the step protocol instead.

@onready var options_box: VBoxContainer = $Panel/VBox/Options

var _game: GameManager


func _ready() -> void:
	visible = false
	_game = get_tree().get_first_node_in_group(&"game_manager") as GameManager
	if _game == null:
		return
	_game.upgrade_pending.connect(_on_upgrade_pending)
	_game.upgrade_chosen.connect(func(_upgrade: Upgrade) -> void: visible = false)
	_game.run_started.connect(func() -> void: visible = false)


func _on_upgrade_pending(options: Array[Upgrade]) -> void:
	if AIBridge.is_ai_active():
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	for child in options_box.get_children():
		child.queue_free()
	for i in options.size():
		var button := Button.new()
		button.text = "%s\n%s" % [options[i].display_name, options[i].description]
		button.custom_minimum_size = Vector2(320, 56)
		button.pressed.connect(_choose.bind(i))
		options_box.add_child(button)
	visible = true


func _choose(index: int) -> void:
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# May immediately re-trigger upgrade_pending if level-ups are queued.
	_game.choose_upgrade(index)
