class_name HealthComponent
extends Node
## Attach as a child of anything that can take damage. Owners react to the
## signals; nothing else in the game reads or writes health directly.

signal damaged(amount: float, source: Node)
signal healed(amount: float)
signal died

@export var max_health := 100.0

var health: float


func _ready() -> void:
	health = max_health


func is_alive() -> bool:
	return health > 0.0


func take_damage(amount: float, source: Node = null) -> void:
	if not is_alive():
		return
	health = maxf(health - amount, 0.0)
	damaged.emit(amount, source)
	if health <= 0.0:
		died.emit()


func heal(amount: float) -> void:
	if not is_alive():
		return
	health = minf(health + amount, max_health)
	healed.emit(amount)


func reset() -> void:
	health = max_health
