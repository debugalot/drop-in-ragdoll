extends CharacterBody3D
## One demo knight: idles (or walks a circle), goes limp when hit, and gets up once it lies still.
## The model is scaled, not the body, so the ragdoll runs on a skeleton inside a scaled scene.

@export var size := 1.0
@export var walk_radius := 0.0         # above 0: walks a circle this wide
@export var walk_speed := 1.3

@onready var model: Node3D = $Model
@onready var ragdoll: DropInRagdoll = $Model/Rig/Skeleton3D/DropInRagdoll
@onready var anim: AnimationPlayer = $Model/AnimationPlayer
@onready var shape: CollisionShape3D = $Shape

var tag := Label3D.new()               # "×1.4" over the knight's head, wherever the body lies
var _centre := Vector3.ZERO
var _angle := 0.0
var _up := false                       # playing the stand-up
var _knocks := 0                       # a new knock cancels a pending stand-up


func _ready() -> void:
	model.scale = Vector3.ONE * size
	var capsule := (shape.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	capsule.radius *= size
	capsule.height *= size
	shape.shape = capsule
	shape.position.y *= size
	for prop in ["1H_Sword_Offhand", "Badge_Shield", "Rectangle_Shield", "Spike_Shield", "2H_Sword"]:
		var n := model.find_child(prop, true, false) as Node3D
		if n != null:
			n.visible = false
	for loop in ["Idle", "Walking_A"]:
		anim.get_animation(loop).loop_mode = Animation.LOOP_LINEAR
	_centre = global_position - Vector3(walk_radius, 0.0, 0.0)
	_play_default()
	ragdoll.came_to_rest.connect(_on_rest)
	tag.text = "×%.1f" % size
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 48
	tag.outline_size = 10
	tag.top_level = true
	add_child(tag)


func _process(_delta: float) -> void:
	var hips := ragdoll.get_part_position("Hips")
	if hips.is_finite():
		tag.global_position = hips + Vector3.UP * 1.0 * size
	else:
		tag.global_position = global_position + Vector3.UP * 2.75 * size


func _physics_process(delta: float) -> void:
	if ragdoll.is_limp() or _up or walk_radius <= 0.0:
		return
	_angle += walk_speed / walk_radius * delta
	var target := _centre + Vector3(cos(_angle), 0.0, sin(_angle)) * walk_radius
	var step := target - global_position
	step.y = 0.0
	velocity = step / delta
	if step.length() > 0.001:
		rotation.y = atan2(step.x, step.z)
	move_and_slide()


## Hit with `impulse` (kg·m/s) at `at` (world space): the knight goes limp and the nearest part takes it.
func knock(impulse: Vector3, at: Vector3) -> void:
	_knocks += 1
	_up = false
	collision_layer = 0                # the standing capsule is out of the way while the body is limp
	velocity = Vector3.ZERO
	ragdoll.hit(impulse, at)


func stand_up() -> void:
	if not ragdoll.is_limp():
		return
	var knocks := _knocks
	var face_up := ragdoll.is_face_up()
	global_transform = ragdoll.get_up_transform(self)
	_up = true
	if face_up:
		anim.play("Lie_StandUp", 0.0)
		ragdoll.get_up(0.25)
		await get_tree().create_timer(anim.get_animation("Lie_StandUp").length * 0.92).timeout
	else:
		# KayKit has no get-up from lying face down: blend slowly straight into the idle.
		anim.play("Idle", 0.0)
		ragdoll.get_up(0.9)
		await ragdoll.got_up
	if knocks != _knocks:
		return
	_up = false
	collision_layer = 2
	_centre = global_position - Vector3(cos(_angle), 0.0, sin(_angle)) * walk_radius
	_play_default()


func _on_rest() -> void:
	var knocks := _knocks
	await get_tree().create_timer(0.7).timeout
	if knocks == _knocks:
		stand_up()


func _play_default() -> void:
	anim.play("Walking_A" if walk_radius > 0.0 else "Idle", 0.3)
