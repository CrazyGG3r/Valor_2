class_name UpgradePool
extends Resource
## The set of upgrades a run can offer. Kept as a Resource so designers edit
## configs/upgrades/upgrade_pool.tres, never code. Array order is the stable
## index used to encode upgrade options in AI observations.

@export var upgrades: Array[Upgrade] = []
