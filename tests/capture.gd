extends Node
## Windowed: plays the demo through a knock-down and get-up and saves screenshots.
##   godot --path . res://tests/capture.tscn -- --out=<folder> [--close]
## --close follows the ×1.0 knight up close, a frame every quarter second from the hit to standing.

var demo: Node3D
var out := "user://shots"
var close := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		close = close or a == "--close"
	DirAccess.make_dir_recursive_absolute(out)
	seed(4)
	demo = load("res://demo/demo.tscn").instantiate()
	add_child(demo)
	await _wait(1.5)
	if close:
		await _close_up()
	else:
		await _overview()
	get_tree().quit()


func _overview() -> void:
	await _shot("1_standing")
	demo.knock_all()
	await _wait(0.35)
	await _shot("2_hit")
	await _wait(2.2)
	await _shot("3_down")
	for k in demo.knights:
		k.ragdoll.show_shapes = true
	await _shot("4_shapes")
	for k in demo.knights:
		k.ragdoll.show_shapes = false
	await _wait(2.6)
	await _shot("5_getting_up")
	await _wait(2.0)
	await _shot("6_up_again")


func _close_up() -> void:
	var k: Node3D = demo.knights[1]
	demo._distance = 5.0
	demo._yaw = 0.9
	demo._place_camera()
	k.knock(Vector3(-1, 0.3, 0.2).normalized() * demo.HIT, k.global_position + Vector3(0, 1.3, 0))
	for i in 34:
		demo.pivot.global_position = demo.pivot.global_position.lerp(k.ragdoll.get_part_position("Hips") if k.ragdoll.is_limp() else k.global_position + Vector3.UP, 0.5)
		await _shot("c%02d" % i)
		await _wait(0.25)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
