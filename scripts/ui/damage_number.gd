class_name DamageNumber
extends Label3D
## Floating combat text. Spawn via the static helper; it animates upward,
## fades, and frees itself. Uses the global RNG for jitter -- cosmetic only,
## so it does not touch the seeded simulation streams.


static func spawn(parent: Node, world_position: Vector3, amount: float,
		color: Color = Color.RED) -> void:
	var number := DamageNumber.new()
	number.text = str(int(roundf(amount)))
	number.modulate = color
	number.font_size = 48
	number.outline_size = 10
	number.pixel_size = 0.008
	number.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	number.no_depth_test = true
	parent.add_child(number)
	number.global_position = world_position + Vector3(
		randf_range(-0.25, 0.25), 0.0, randf_range(-0.25, 0.25))

	var tween := number.create_tween()
	tween.tween_property(number, "position:y", number.position.y + 1.2, 0.7) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(number, "modulate:a", 0.0, 0.7)
	tween.tween_callback(number.queue_free)
