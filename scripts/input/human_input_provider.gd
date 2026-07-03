class_name HumanInputProvider
extends InputProvider
## Feeds keyboard/mouse/gamepad hardware into the InputProvider contract.
## Owns mouse capture, so the player body never touches input devices.

@export var mouse_sensitivity := 0.002

var _mouse_motion := Vector2.ZERO


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			_mouse_motion += event.relative
	elif event.is_action_pressed(&"ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif event is InputEventMouseButton and event.pressed \
			and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _gather() -> void:
	_move_vector = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	_look_delta = _mouse_motion * mouse_sensitivity
	_mouse_motion = Vector2.ZERO
	_buttons[ACTION_JUMP] = Input.is_action_pressed(&"jump")
	_buttons[ACTION_ATTACK] = Input.is_action_pressed(&"attack")
	_buttons[ACTION_SHOOT] = Input.is_action_pressed(&"shoot")
	_buttons[ACTION_DASH] = Input.is_action_pressed(&"dash")
