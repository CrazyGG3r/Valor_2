class_name AIInputProvider
extends InputProvider
## Driven by code instead of hardware. The eventual Python/RL bridge (or any
## scripted test) controls the player through the setters below.
##
## Move and button commands persist until changed, matching a key being held.
## Look commands accumulate and are consumed on the next poll, matching how
## mouse deltas work in HumanInputProvider.

var _cmd_move := Vector2.ZERO
var _cmd_look := Vector2.ZERO
var _cmd_buttons: Dictionary = {}


func set_move_vector(move: Vector2) -> void:
	_cmd_move = move


func add_look_delta(look: Vector2) -> void:
	_cmd_look += look


func set_button(action: StringName, held: bool) -> void:
	_cmd_buttons[action] = held


## Clears all pending commands. Call between RL episodes.
func reset() -> void:
	_cmd_move = Vector2.ZERO
	_cmd_look = Vector2.ZERO
	_cmd_buttons.clear()


func _gather() -> void:
	_move_vector = _cmd_move
	_look_delta = _cmd_look
	_cmd_look = Vector2.ZERO
	for action: StringName in _cmd_buttons:
		_buttons[action] = _cmd_buttons[action]
