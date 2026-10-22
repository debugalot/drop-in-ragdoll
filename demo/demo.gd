extends Node3D
## Drop-In Ragdoll demo: four KayKit knights at three sizes. Click one to hit it.
##   Left click   hit what's under the mouse
##   Space        knock everyone over
##   R            everyone gets up now
##   F            show / hide the ragdoll's collision shapes
##   Right drag   orbit the camera, wheel to zoom

const KNIGHT := preload("res://demo/knight.tscn")
const HIT := 80.0                      # kg·m/s

@onready var pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D

var knights: Array[Node] = []
var _yaw := -0.45
var _pitch := -0.32
var _distance := 10.0
var _shapes := false


func _ready() -> void:
	# position, size, walk radius
	for spec in [[Vector3(-3.4, 0, 0.6), 0.6, 0.0], [Vector3(0, 0, 0), 1.0, 0.0], [Vector3(3.8, 0, -0.4), 1.4, 0.0], [Vector3(1.5, 0, -4.5), 1.0, 2.2]]:
		var k := KNIGHT.instantiate()
		k.size = spec[1]
		k.walk_radius = spec[2]
		k.position = spec[0]
		add_child(k)
		knights.append(k)
	_place_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_hit_at(event.position)
			MOUSE_BUTTON_WHEEL_UP:
				_distance = maxf(_distance * 0.9, 3.0)
				_place_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				_distance = minf(_distance * 1.1, 30.0)
				_place_camera()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		_yaw -= event.relative.x * 0.006
		_pitch = clampf(_pitch - event.relative.y * 0.006, -1.4, -0.05)
		_place_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				knock_all()
			KEY_R:
				for k in knights:
					k.stand_up()
			KEY_F:
				_shapes = not _shapes
				for k in knights:
					k.ragdoll.show_shapes = _shapes


## Knocks every knight over, each pushed in its own direction at chest height.
func knock_all() -> void:
	for k in knights:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU) + Vector3.UP * 0.35
		var chest: Vector3 = k.global_position + Vector3.UP * 1.3 * float(k.size)
		k.knock(dir.normalized() * HIT, chest)


func _hit_at(screen: Vector2) -> void:
	var from := camera.project_ray_origin(screen)
	var q := PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(screen) * 100.0, 2 | 4)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var n: Node = hit.collider
	while n != null and not n.has_method("knock"):
		n = n.get_parent()
	if n != null:
		var dir := camera.project_ray_normal(screen)
		n.knock((dir + Vector3.UP * 0.25).normalized() * HIT, hit.position)


func _place_camera() -> void:
	pivot.rotation = Vector3(_pitch, _yaw, 0.0)
	camera.position = Vector3(0, 0, _distance)
