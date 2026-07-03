class_name LevelSystem
extends Node
## Run-scoped XP and levels. The owning body gains XP; whoever cares about
## level-ups (GameManager, UI, AI bridge) listens to the signals.

signal xp_gained(amount: float, total: float)
signal leveled_up(new_level: int)

@export var base_xp_to_level := 20.0
## Each level's requirement multiplies by this.
@export var xp_growth := 1.35

var level := 1
var xp := 0.0


func xp_to_next() -> float:
	return ceilf(base_xp_to_level * pow(xp_growth, level - 1))


func xp_fraction() -> float:
	return clampf(xp / xp_to_next(), 0.0, 1.0)


func add_xp(amount: float) -> void:
	xp += amount
	xp_gained.emit(amount, xp)
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		leveled_up.emit(level)


func reset() -> void:
	level = 1
	xp = 0.0
