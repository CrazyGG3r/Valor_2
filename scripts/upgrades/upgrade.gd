class_name Upgrade
extends Resource
## One selectable run upgrade. Pure data -- Player.apply_upgrade interprets
## the stat key, so adding a new upgrade of an existing stat is just a new
## .tres file in configs/upgrades/.

enum Operation { ADD, MULTIPLY }

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
## Stat key interpreted by Player.apply_upgrade (e.g. &"move_speed").
@export var stat: StringName
@export var operation := Operation.MULTIPLY
@export var value := 1.0
## Times this upgrade can be taken in one run. 0 = unlimited.
@export var max_stacks := 0
