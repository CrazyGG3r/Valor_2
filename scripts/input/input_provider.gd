class_name InputProvider
extends Node
## Source-agnostic controller interface for a player body.
##
## The controlled body calls poll() exactly once per physics tick, then reads
## the resulting state. Button edges (just_pressed / just_released) are
## computed here so every input source gets identical semantics -- a human
## tapping a key and an AI toggling a bool are indistinguishable downstream.
##
## Conventions (also the contract for the future RL action space):
##  - move vector: x = strafe (+right), y = forward/back (+back, Godot's +Z).
##    Length is clamped to 1 but NOT normalized, so analog / continuous
##    actions keep their magnitude.
##  - look delta: radians of yaw (x) and pitch (y) to apply THIS tick only.

## Gameplay button actions. Add new buttons here.
const ACTION_JUMP := &"jump"
const ACTION_ATTACK := &"attack"
const ACTION_SHOOT := &"shoot"
const ACTION_DASH := &"dash"

var _move_vector := Vector2.ZERO
var _look_delta := Vector2.ZERO
var _buttons: Dictionary = {}
var _buttons_prev: Dictionary = {}


func poll() -> void:
	_buttons_prev = _buttons.duplicate()
	_move_vector = Vector2.ZERO
	_look_delta = Vector2.ZERO
	_gather()


func get_move_vector() -> Vector2:
	return _move_vector.limit_length(1.0)


func get_look_delta() -> Vector2:
	return _look_delta


func is_pressed(action: StringName) -> bool:
	return _buttons.get(action, false)


func is_just_pressed(action: StringName) -> bool:
	return _buttons.get(action, false) and not _buttons_prev.get(action, false)


func is_just_released(action: StringName) -> bool:
	return not _buttons.get(action, false) and _buttons_prev.get(action, false)


## Virtual. Subclasses fill _move_vector, _look_delta and _buttons here.
func _gather() -> void:
	pass
