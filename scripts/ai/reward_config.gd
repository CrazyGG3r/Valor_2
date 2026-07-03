class_name RewardConfig
extends Resource
## Tunable reward shaping for RL training. Edit res://configs/reward_config.tres
## in the inspector instead of touching code. Values are per event unless noted.

@export var survive_per_second := 0.1
@export var kill := 1.0
## Per point of damage received (negative).
@export var damage_taken := -0.05
@export var death := -10.0
## Granted each time a new wave spawns after the first (you survived one).
@export var wave_survived := 2.0

@export_group("Reserved for future systems")
@export var xp_collected := 0.5
@export var level_up := 5.0
## Per point of damage dealt.
@export var damage_dealt := 0.02
