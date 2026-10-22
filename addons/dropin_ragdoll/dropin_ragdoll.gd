@tool
@icon("res://addons/dropin_ragdoll/icon.svg")
class_name DropInRagdoll
extends SkeletonModifier3D
## A ragdoll for any humanoid Skeleton3D. Add it as a child of the skeleton and call go_limp().
##
## It finds the bones by itself (Godot humanoid names, Mixamo, Unreal-style, ".L/.R", Biped, VRoid),
## sizes its bodies to the character's skinned mesh, and builds sixteen RigidBody3Ds (hips, spine,
## chest, head, upper and lower arms, hands, upper and lower legs, feet) joined by cone-twist joints and
## hinged elbows and knees. The bodies live in world space at the character's true size and this
## modifier writes the bone poses back, so the ragdoll holds at any scale: a character scaled 1.3 or 0.5
## (or a skeleton inside a scaled scene) falls exactly as one at 1.0. PhysicalBone3D does not survive
## that; its bones shrink by the scale while simulating.
##
## The bodies start from the pose on screen, and get_up() blends back into whatever animation plays.

signal went_limp()
signal came_to_rest()
signal got_up()

const Bones := preload("humanoid_bones.gd")

const REST_SPEED := 0.12          # m/s for an adult: every body slower than this for REST_SECONDS = at rest
const REST_SECONDS := 0.5
const SETTLE_SPEED := 0.6         # m/s for an adult: below this the body is settling, and damping rises...
const SETTLE_DAMPING := 8.0       # ...to this many times the inspector's over a second
const SETTLE_SECONDS := 1.5       # settling this long counts as at rest even if a propped limb still rocks

# part → [parent part, shape, share of the mass, share of a throw (the trunk takes more than the feet)]
const PARTS := {
	"Hips": ["", "box", 0.149, 0.8],
	"Spine": ["Hips", "box", 0.122, 1.0],
	"Chest": ["Spine", "box", 0.189, 1.25],
	"Head": ["Chest", "ball", 0.068, 1.3],
	"LeftUpperArm": ["Chest", "capsule", 0.028, 1.15],
	"LeftLowerArm": ["LeftUpperArm", "capsule", 0.019, 1.1],
	"LeftHand": ["LeftLowerArm", "capsule", 0.007, 1.0],
	"RightUpperArm": ["Chest", "capsule", 0.028, 1.15],
	"RightLowerArm": ["RightUpperArm", "capsule", 0.019, 1.1],
	"RightHand": ["RightLowerArm", "capsule", 0.007, 1.0],
	"LeftUpperLeg": ["Hips", "capsule", 0.115, 0.6],
	"LeftLowerLeg": ["LeftUpperLeg", "capsule", 0.054, 0.35],
	"LeftFoot": ["LeftLowerLeg", "box", 0.014, 0.3],
	"RightUpperLeg": ["Hips", "capsule", 0.115, 0.6],
	"RightLowerLeg": ["RightUpperLeg", "capsule", 0.054, 0.35],
	"RightFoot": ["RightLowerLeg", "box", 0.014, 0.3],
}
const EXTREMITIES := ["LeftHand", "RightHand", "LeftFoot", "RightFoot"]

@export_group("Bones")
## Optional: a BoneMap (as made for retargeting) naming this skeleton's bones. Without one the bones
## are found by name.
@export var bone_map: BoneMap:
	set(v):
		bone_map = v
		_fit.clear()
		update_configuration_warnings()
## Optional: humanoid role → this skeleton's bone name, for rigs the guessing gets wrong
## (e.g. {"Head": "DEF-spine.006"}). Roles are Godot's: Hips, Spine, Chest, Neck, Head, LeftUpperArm,
## LeftLowerArm, LeftHand, LeftUpperLeg, LeftLowerLeg, LeftFoot, LeftToes and the Right ones.
@export var bone_names := {}:
	set(v):
		bone_names = v
		_fit.clear()
		update_configuration_warnings()

@export_group("Body")
## Kilograms, shared out over the parts like a person's.
@export_range(1.0, 500.0, 0.5, "or_greater") var total_mass := 70.0
## Size each part from the skinned mesh around its bone (otherwise from the skeleton's proportions).
@export var fit_to_mesh := true
## Grows or shrinks every collision shape.
@export_range(0.3, 2.0, 0.01) var shape_scale := 1.0
## Hands and feet get bodies of their own. Off: they keep the pose they had when the body fell.
@export var simulate_hands_and_feet := true
## While limp, every bone without a body (neck, fingers, toes...) keeps the pose it had at the fall
## instead of following the animation still playing underneath.
@export var freeze_other_bones := true

@export_group("Physics")
@export_flags_3d_physics var collision_layer := 1
@export_flags_3d_physics var collision_mask := 1
@export_range(0.0, 1.0, 0.01) var friction := 0.8
@export_range(0.0, 1.0, 0.01) var bounce := 0.05
@export_range(0.0, 10.0, 0.01) var linear_damp := 0.1
@export_range(0.0, 10.0, 0.01) var angular_damp := 0.9
## How fast each joint stops its two parts turning against each other (per second). It is what stops a
## dangling hand or forearm swinging on and on; it leaves the body's tumble alone.
@export_range(0.0, 30.0, 0.1) var joint_damping := 8.0
## The ragdoll's own parts collide with each other (an arm can't pass through the chest). Off is steadier:
## a light hand caught between a heavy chest and the floor can't be squeezed through either. Parts
## already touching when the body falls never collide with each other.
@export var self_collision := false
## When the skeleton belongs to a CharacterBody3D or RigidBody3D, the ragdoll starts with its velocity
## (a running character tumbles forward) and never collides with it.
@export var inherit_body_velocity := true
## Once the body has nearly stopped, damping rises (to 8× over a second) so arms and legs stop instead of
## rocking for seconds, and after 1.5 s of settling the bodies are put to sleep. A hit() or a new knock
## wakes them.
@export var settle := true

@export_group("Joint limits (degrees)")
@export_range(0.0, 180.0, 1.0) var spine_swing := 20.0
@export_range(0.0, 180.0, 1.0) var neck_swing := 40.0
@export_range(0.0, 180.0, 1.0) var shoulder_swing := 80.0
@export_range(0.0, 180.0, 1.0) var hip_swing := 75.0
@export_range(0.0, 180.0, 1.0) var wrist_swing := 50.0
@export_range(0.0, 180.0, 1.0) var ankle_swing := 30.0
@export_range(0.0, 180.0, 1.0) var elbow_bend := 135.0
@export_range(0.0, 180.0, 1.0) var knee_bend := 140.0

@export_group("Debug")
## Draws every collision shape while limp (can be switched while limp).
@export var show_shapes := false:
	set(v):
		show_shapes = v
		for part in _bodies:
			var cs := (_bodies[part] as RigidBody3D).get_child(0) as CollisionShape3D
			for c in cs.get_children():
				c.queue_free()
			if v:
				cs.add_child(_shape_mesh(cs.shape))

var _fit := {}                     # part → {bone, shape, size, offset, axis}; built once per skeleton
var _order: Array = []             # parts present, parents before children
var _bodies := {}                  # part → RigidBody3D while limp
var _inertia := {}                 # part → its body's (even) inertia
var _scale := {}                   # part → the body's world scale at the fall (bone poses are written back with it)
var _bone_scale := {}              # part → the bone's own scale at the fall
var _frozen := {}                  # bone → [position, rotation, scale] held while limp
var _root: Node3D                  # holds the bodies and joints, top level (world space)
var _limp := false
var _still := 0.0
var _calm := 0.0                   # seconds the body has been settling (slower than SETTLE_SPEED)
var _damping := 1.0                # current damping multiplier
var _rested := false
var _u := 0.6                      # hips-to-head distance at rest, skeleton units
var _body_size := 1.0              # the character's size against an adult's (hips-to-head in the world / 0.6 m)
var _fade: Tween
var _warned := false
var _forward := Vector3.BACK       # the character's front and up in skeleton space (from the rest pose)
var _up := Vector3.UP


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	active = false
	influence = 0.0
	set_physics_process(false)


# ----------------------------------------------------------------------------------------------- API

## Goes limp, thrown with `velocity` (world space, m/s). Returns false when the skeleton is not a
## humanoid this ragdoll can read (the error says which bones are missing).
func go_limp(velocity := Vector3.ZERO) -> bool:
	var sk := get_skeleton()
	if sk == null or not is_inside_tree():
		return false
	if _fit.is_empty() and not fit():
		return false
	if not _jolt() and not _warned:
		_warned = true
		push_warning("DropInRagdoll is built for Jolt Physics (Project Settings > Physics > 3D > Physics Engine). On Godot Physics its joints stretch and bodies may never settle.")
	_clear()
	var owner_body := _owner_body()
	if inherit_body_velocity and owner_body != null:
		if owner_body is CharacterBody3D:
			velocity += (owner_body as CharacterBody3D).velocity
		elif owner_body is RigidBody3D:
			velocity += (owner_body as RigidBody3D).linear_velocity
	_freeze(sk)
	_root = Node3D.new()
	_root.name = "RagdollBodies"
	_root.top_level = true
	add_child(_root)
	_root.global_transform = Transform3D.IDENTITY
	var shares := _mass_shares()
	var material := PhysicsMaterial.new()
	material.friction = friction
	material.bounce = bounce
	for part in _order:
		var f: Dictionary = _fit[part]
		var g := sk.get_bone_global_pose(f.bone)
		_bone_scale[part] = g.basis.get_scale()
		var world := sk.global_transform * Transform3D(g.basis.orthonormalized(), g.origin) * (f.offset as Transform3D)
		var cs := world.basis.get_scale()
		_scale[part] = cs
		var rb := RigidBody3D.new()
		rb.name = part
		rb.mass = maxf(total_mass * float(shares[part]), 0.05)
		rb.collision_layer = collision_layer
		rb.collision_mask = collision_mask
		rb.continuous_cd = part.ends_with("LowerArm") or part.ends_with("LowerLeg") or part in EXTREMITIES
		rb.linear_damp = linear_damp
		rb.angular_damp = angular_damp
		rb.physics_material_override = material
		rb.add_child(_shape(f, (cs.x + cs.y + cs.z) / 3.0 * shape_scale))
		rb.inertia = _even_inertia(f, rb.mass, (cs.x + cs.y + cs.z) / 3.0 * shape_scale)
		_inertia[part] = rb.inertia.x
		_root.add_child(rb)
		rb.global_transform = Transform3D(world.basis.orthonormalized(), world.origin)
		rb.linear_velocity = velocity * float(PARTS[part][3])
		if owner_body != null:
			rb.add_collision_exception_with(owner_body)
		_bodies[part] = rb
	_except_overlaps()
	for part in _order:
		var parent: String = _parent_of(part)
		if parent != "":
			_joint(sk, part, parent)
	_limp = true
	var sc := sk.global_basis.get_scale()
	_body_size = _u * (sc.x + sc.y + sc.z) / 3.0 / 0.6
	_damping = 1.0
	_wake()
	set_physics_process(true)
	_tween_influence(1.0, 0.04)
	went_limp.emit()
	return true


## Strikes the body: goes limp if it is not already and pushes the part nearest `at` (world space) with
## `impulse` (kg·m/s, world space).
func hit(impulse: Vector3, at: Vector3) -> void:
	if not _limp and not go_limp():
		return
	var best := ""
	var best_d := INF
	for part in _bodies:
		var seg := _segment(part)
		var d := _point_segment(at, seg[0], seg[1]) - float(seg[2])
		if d < best_d:
			best_d = d
			best = part
	if best != "":
		var rb: RigidBody3D = _bodies[best]
		rb.apply_impulse(impulse, at - rb.global_position)
		_wake()


## Blends back into whatever animation is playing over `blend_seconds`, then lets the bodies go.
## Move the character first (get_up_transform()) so it gets up where the body lies.
func get_up(blend_seconds := 0.5) -> void:
	if not _limp:
		return
	_limp = false
	set_physics_process(false)
	_tween_influence(0.0, blend_seconds).tween_callback(_finish_get_up)


func is_limp() -> bool:
	return _limp


## True once the body lies still: every part slow for half a second, or (with settle) settling for
## 1.5 s. The came_to_rest signal fires then.
func is_resting() -> bool:
	return _rested


## Lying on the back (chest facing the sky) rather than on the front.
func is_face_up() -> bool:
	var chest: RigidBody3D = _bodies.get("Chest", _bodies.get("Hips"))
	return chest != null and chest.global_basis.z.y > 0.0


## The body of one part ("Hips", "LeftLowerLeg"...), or null when not limp.
func get_body(part: String) -> RigidBody3D:
	var rb: RigidBody3D = _bodies.get(part)
	return rb if rb != null and is_instance_valid(rb) else null


## Where a part is (world space), or Vector3.INF when not limp.
func get_part_position(part: String) -> Vector3:
	var rb := get_body(part)
	return rb.global_position if rb != null else Vector3.INF


## Where to put the character root (`root`, usually the CharacterBody3D) so that it gets up where the
## body lies: on the ground under the hips, facing the way a person stands up from that pose (towards
## the feet when lying on the back, towards the head when lying on the front).
func get_up_transform(root: Node3D) -> Transform3D:
	var sk := get_skeleton()
	var hips := get_part_position("Hips")
	var head := get_part_position(_head_part())
	if sk == null or not hips.is_finite():
		return root.global_transform
	var ground := hips.y - 0.1
	var space := root.get_world_3d().direct_space_state if root.is_inside_tree() else null
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(hips + Vector3.UP * 0.2, hips + Vector3.DOWN * 4.0, collision_mask)
		var skip: Array[RID] = []
		for part in _bodies:
			skip.append((_bodies[part] as RigidBody3D).get_rid())
		var owner_body := _owner_body()
		if owner_body != null:
			skip.append(owner_body.get_rid())
		q.exclude = skip
		var hit_info := space.intersect_ray(q)
		if not hit_info.is_empty():
			ground = (hit_info.position as Vector3).y
	var t := root.global_transform
	t.origin = Vector3(hips.x, ground, hips.z)
	var facing := (hips - head) if is_face_up() else (head - hips)
	facing.y = 0.0
	var front := sk.global_basis * _forward
	front.y = 0.0
	if facing.length() > 0.01 and front.length() > 0.01:
		t.basis = Basis(Vector3.UP, front.normalized().signed_angle_to(facing.normalized(), Vector3.UP)) * t.basis
	return t


## Reads the skeleton and sizes the parts now (go_limp does it the first time otherwise). Call it again
## after swapping the character's mesh. Returns false when bones are missing.
func fit() -> bool:
	var sk := get_skeleton()
	if sk == null:
		push_error("DropInRagdoll must be a child of a Skeleton3D.")
		return false
	var found := Bones.find(sk, bone_map, bone_names)
	if not (found["_missing"] as Array).is_empty():
		push_error("DropInRagdoll: can't find %s in skeleton '%s'. Name them in bone_names or assign a bone_map. Found: %s"
				% [", ".join(found["_missing"]), sk.name, Bones.describe(sk, found)])
		return false
	_build(sk, found)
	return true


## Which skeleton bone plays each part, e.g. {"Hips": "mixamorig_Hips", ...} (fits first if needed).
func get_bone_report() -> Dictionary:
	var sk := get_skeleton()
	if sk == null or (_fit.is_empty() and not fit()):
		return {}
	var out := {}
	for part in _order:
		out[part] = sk.get_bone_name(_fit[part].bone)
	return out


# ------------------------------------------------------------------------------------------ runtime

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or _bodies.is_empty():
		return
	for i in _frozen:
		var p: Array = _frozen[i]
		sk.set_bone_pose_position(i, p[0])
		sk.set_bone_pose_rotation(i, p[1])
		sk.set_bone_pose_scale(i, p[2])
	var inv := sk.global_transform.affine_inverse()
	for part in _order:
		var rb: RigidBody3D = _bodies.get(part)
		if rb == null or not is_instance_valid(rb):
			continue
		var t := rb.global_transform
		if not t.origin.is_finite():
			continue
		var r := t.basis.orthonormalized()
		var cs: Vector3 = _scale[part]
		var body := inv * Transform3D(Basis(r.x * cs.x, r.y * cs.y, r.z * cs.z), t.origin)
		var g := body * (_fit[part].offset as Transform3D).affine_inverse()
		var bs: Vector3 = _bone_scale[part]
		var gb := g.basis.orthonormalized()
		sk.set_bone_global_pose(_fit[part].bone, Transform3D(Basis(gb.x * bs.x, gb.y * bs.y, gb.z * bs.z), g.origin))


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _bodies.is_empty():
		return
	_damp_joints(delta)
	if not _limp:
		return
	var fastest := 0.0
	for part in _bodies:
		var rb: RigidBody3D = _bodies[part]
		if is_instance_valid(rb):
			fastest = maxf(fastest, rb.linear_velocity.length())
	# Speeds scale with the character: a half-size body comes to rest at half the speed.
	if _rested:
		if fastest > SETTLE_SPEED * _body_size:   # knocked again (by something other than hit())
			_wake()
		return
	_calm = _calm + delta if fastest < SETTLE_SPEED * _body_size else 0.0
	if settle:
		_set_damping(1.0 + (SETTLE_DAMPING - 1.0) * clampf((_calm - 0.25) / 1.0, 0.0, 1.0))
	_still = _still + delta if fastest < REST_SPEED * _body_size else 0.0
	if _still >= REST_SECONDS or (settle and _calm >= SETTLE_SECONDS):
		_rested = true
		if settle:
			for part in _bodies:
				(_bodies[part] as RigidBody3D).sleeping = true
		came_to_rest.emit()


## Joint damping: each joint takes away part of the turn between its two bodies, by equal and opposite
## torque impulses (so the body's tumble as a whole is untouched).
func _damp_joints(delta: float) -> void:
	if joint_damping <= 0.0:
		return
	var a := 1.0 - exp(-joint_damping * delta)
	var impulses := {}
	for part in _order:
		var parent := _parent_of(part)
		if parent == "":
			continue
		var child: RigidBody3D = _bodies[part]
		var above: RigidBody3D = _bodies[parent]
		if child.sleeping and above.sleeping:
			continue
		var ic: float = _inertia[part]
		var ip: float = _inertia[parent]
		var j := (child.angular_velocity - above.angular_velocity) * (a * ic * ip / (ic + ip))
		impulses[part] = impulses.get(part, Vector3.ZERO) - j
		impulses[parent] = impulses.get(parent, Vector3.ZERO) + j
	for part in impulses:
		(_bodies[part] as RigidBody3D).apply_torque_impulse(impulses[part])


## Every body's damping times `m` (1 = as set in the inspector).
func _set_damping(m: float) -> void:
	if absf(m - _damping) < 0.02:
		return
	_damping = m
	for part in _bodies:
		var rb: RigidBody3D = _bodies[part]
		rb.linear_damp = linear_damp * m
		rb.angular_damp = angular_damp * m


func _wake() -> void:
	_still = 0.0
	_calm = 0.0
	_rested = false
	_set_damping(1.0)


func _get_configuration_warnings() -> PackedStringArray:
	var out := PackedStringArray()
	if not _jolt():
		out.append("Built for Jolt Physics: set Project Settings > Physics > 3D > Physics Engine to Jolt Physics. On Godot Physics the joints stretch and bodies may never settle.")
	var sk := get_parent() as Skeleton3D
	if sk == null:
		out.append("DropInRagdoll must be a child of a Skeleton3D.")
		return out
	var found := Bones.find(sk, bone_map, bone_names)
	if not (found["_missing"] as Array).is_empty():
		out.append("Can't find these bones: %s. Name them in Bone Names or assign a Bone Map." % ", ".join(found["_missing"]))
	return out


# ------------------------------------------------------------------------------------------ fitting

## Sizes every part from the rest pose. Everything here is in skeleton space at rest; offsets carry a
## bone's frame to its body's (centred on the shape, Y along the limb, X to the character's left).
func _build(sk: Skeleton3D, found: Dictionary) -> void:
	_fit.clear()
	_order.clear()
	var rest := func(role: String) -> Vector3:
		return sk.get_bone_global_rest(found[role]).origin
	var hips: Vector3 = rest.call("Hips")
	var head: Vector3 = rest.call("Head")
	_up = (head - hips).normalized()
	var left: Vector3 = (rest.call("LeftUpperLeg") as Vector3) - (rest.call("RightUpperLeg") as Vector3)
	left = (left - _up * left.dot(_up)).normalized()
	_forward = left.cross(_up).normalized()
	var u := hips.distance_to(head)             # about 0.6 m on an adult: fallback sizes scale with it
	_u = u

	var bone := {}                              # part → bone index
	for part in PARTS:
		if found.has(part):
			bone[part] = found[part]
	var cut := []                               # hands and feet left without bodies
	for side in ["Left", "Right"]:
		if not bone.has(side + "Hand"):
			var kids := sk.get_bone_children(bone[side + "LowerArm"])
			if kids.size() > 0:
				bone[side + "Hand"] = kids[0]
		if not simulate_hands_and_feet:
			for stem in ["Hand", "Foot"]:
				if bone.has(side + stem):
					cut.append(bone[side + stem])
					bone.erase(side + stem)

	# Segment ends: where each part's bone runs to.
	var ends := {}
	if bone.has("Spine"):
		ends["Spine"] = rest.call("Chest")
	if bone.has("Chest"):
		var neck := Bones.child_toward(sk, bone["Chest"], found["Head"])
		ends["Chest"] = sk.get_bone_global_rest(neck if neck >= 0 else found["Head"]).origin
	for side in ["Left", "Right"]:
		ends[side + "UpperArm"] = rest.call(side + "LowerArm")
		ends[side + "UpperLeg"] = rest.call(side + "LowerLeg")
		var hand: int = found.get(side + "Hand", bone.get(side + "Hand", -1))
		var arm_len := (rest.call(side + "UpperArm") as Vector3).distance_to(ends[side + "UpperArm"])
		var lower_arm: Vector3 = rest.call(side + "LowerArm")
		ends[side + "LowerArm"] = sk.get_bone_global_rest(hand).origin if hand >= 0 \
				else lower_arm + (lower_arm - (rest.call(side + "UpperArm") as Vector3)).normalized() * arm_len * 0.9
		var lower_leg: Vector3 = rest.call(side + "LowerLeg")
		ends[side + "LowerLeg"] = rest.call(side + "Foot") if found.has(side + "Foot") \
				else lower_leg + (lower_leg - (rest.call(side + "UpperLeg") as Vector3)) * 0.95
		if bone.has(side + "Hand"):
			var at := sk.get_bone_global_rest(bone[side + "Hand"]).origin
			var dir := (at - lower_arm).normalized()
			ends[side + "Hand"] = _farthest(sk, bone[side + "Hand"], at, dir, 0.3 * u)
		if bone.has(side + "Foot"):
			var at: Vector3 = rest.call(side + "Foot")
			ends[side + "Foot"] = _farthest(sk, bone[side + "Foot"], at, _forward, 0.42 * u)

	var points := _mesh_points(sk, bone, cut) if fit_to_mesh else {}
	for part in PARTS:
		if not bone.has(part):
			continue
		var origin := sk.get_bone_global_rest(bone[part]).origin
		var end: Vector3 = ends.get(part, origin + _up * 0.3 * u)
		var axis := (end - origin).normalized() if origin.distance_to(end) > 0.0001 else _up
		if part == "Hips":
			axis = _up
		elif part.ends_with("Foot"):
			axis = _forward                     # a flat box, sole on the ground, not tilted down the instep
		var frame := _frame(axis, left if not part.contains("Arm") and not part.contains("Hand") else _forward, part.contains("Arm") or part.contains("Hand"))
		var pts: PackedVector3Array = points.get(part, PackedVector3Array())
		var local := PackedVector3Array()
		for p in pts:
			local.append(frame.inverse() * (p - origin))
		var length := origin.distance_to(end)
		var f := _size(part, local, length, u, sk, bone, frame, origin)
		var body := Transform3D(frame, origin + frame * (f.centre as Vector3))
		var bone_rest := sk.get_bone_global_rest(bone[part])
		f.offset = Transform3D(bone_rest.basis.orthonormalized(), bone_rest.origin).affine_inverse() * body
		f.bone = bone[part]
		f.rest = frame                              # the body's turn at rest: joint limits are centred on it
		# Hinges: the elbow folds the forearm towards the front, the knee folds the shin towards the back.
		if part.ends_with("LowerArm") or part.ends_with("LowerLeg"):
			var towards := _forward if part.ends_with("LowerArm") else -_forward
			var a := axis.cross(towards)
			if a.length() < 0.1:
				a = axis.cross(_up)
			f.axis = frame.inverse() * a.normalized()
		_fit[part] = f
		_order.append(part)
	_fit_together(sk)


## Makes the parts' sizes agree where they meet, so no resting pose is impossible (an impossible one
## jitters forever: the joint holds the limb where the floor won't let it be).
##  - A limb is never fatter than the part it hangs from (forearm vs upper arm, hand vs forearm, shin vs
##    thigh): an upper arm lying on the floor holds the elbow one radius up, and the forearm must fit.
##  - The chest's box takes in the roots of the arms and the hips' box the roots of the legs: lying on
##    its side, the body rests on that box, and the shoulder joint sits far enough above the floor for
##    the upper arm's thickness. On a person that is the width of the shoulders and of the hips.
func _fit_together(sk: Skeleton3D) -> void:
	for chain in [["UpperArm", "LowerArm", "Hand"], ["UpperLeg", "LowerLeg"]]:
		for side in ["Left", "Right"]:
			for i in range(1, chain.size()):
				var parent: String = side + chain[i - 1]
				var part: String = side + chain[i]
				if _fit.has(parent) and _fit.has(part) and str(_fit[parent].shape) == "capsule" and str(_fit[part].shape) == "capsule":
					var size: Vector3 = _fit[part].size
					size.x = minf(size.x, (_fit[parent].size as Vector3).x)
					size.y = maxf((_fit[part].centre as Vector3).y * 2.0, size.x * 2.05)
					_fit[part].size = size
	for pair in [["Chest", "UpperArm"], ["Hips", "UpperLeg"]]:
		var torso: String = pair[0]
		if not _fit.has(torso) or str(_fit[torso].shape) != "box":
			continue
		var f: Dictionary = _fit[torso]
		var frame: Basis = f.rest
		var origin := sk.get_bone_global_rest(f.bone).origin
		var centre: Vector3 = f.centre
		var lo: Vector3 = centre - (f.size as Vector3) * 0.5
		var hi: Vector3 = centre + (f.size as Vector3) * 0.5
		for side in ["Left", "Right"]:
			var limb: String = side + pair[1]
			if not _fit.has(limb):
				continue
			var root := frame.inverse() * (sk.get_bone_global_rest(_fit[limb].bone).origin - origin)
			var r: float = (_fit[limb].size as Vector3).x
			lo.x = minf(lo.x, root.x - r)
			hi.x = maxf(hi.x, root.x + r)
			lo.z = minf(lo.z, root.z - r)
			hi.z = maxf(hi.z, root.z + r)
		f.centre = (lo + hi) * 0.5
		f.size = hi - lo
		var bone_rest := sk.get_bone_global_rest(f.bone)
		f.offset = Transform3D(bone_rest.basis.orthonormalized(), bone_rest.origin).affine_inverse() * Transform3D(frame, origin + frame * (f.centre as Vector3))


## An orthonormal frame with Y along `axis` and X as near `side` as Y allows (or Z near `side`).
func _frame(axis: Vector3, side: Vector3, side_is_z := false) -> Basis:
	var y := axis.normalized()
	var s := side - y * side.dot(y)
	if s.length() < 0.05:
		s = _up - y * _up.dot(y)
		if s.length() < 0.05:
			s = _forward - y * _forward.dot(y)
	s = s.normalized()
	if side_is_z:
		return Basis(y.cross(s), y, s)
	return Basis(s, y, s.cross(y))


## The shape of one part in its frame: from the mesh points around its bone when there are enough,
## else from the skeleton's proportions (u = hips-to-head distance).
func _size(part: String, pts: PackedVector3Array, length: float, u: float, sk: Skeleton3D, bone: Dictionary, frame: Basis, origin: Vector3) -> Dictionary:
	var kind: String = PARTS[part][1]
	var enough := pts.size() >= 12
	match kind:
		"ball":
			if enough:
				var lo := Vector3(_pct(pts, 0, 0.05), _pct(pts, 1, 0.05), _pct(pts, 2, 0.05))
				var hi := Vector3(_pct(pts, 0, 0.95), _pct(pts, 1, 0.95), _pct(pts, 2, 0.95))
				var half := (hi - lo) * 0.5
				return {"shape": kind, "centre": (lo + hi) * 0.5, "size": Vector3.ONE * maxf((half.x + half.y + half.z) / 3.0, 0.02 * u)}
			return {"shape": kind, "centre": Vector3(0.0, 0.17 * u, 0.02 * u), "size": Vector3.ONE * 0.17 * u}
		"capsule":
			var radii := {"LeftUpperArm": 0.077, "LeftLowerArm": 0.063, "LeftHand": 0.06, "LeftUpperLeg": 0.12, "LeftLowerLeg": 0.087}
			var r: float = radii.get(part.replace("Right", "Left"), 0.07) * u
			var c := Vector2.ZERO
			var hand := part.ends_with("Hand")
			if enough:
				var mid := PackedVector3Array()
				for p in pts:
					if hand or (p.y > length * 0.1 and p.y < length * 0.9):
						mid.append(p)
				if mid.size() < 8:
					mid = pts
				c = Vector2(_pct(mid, 0, 0.5), _pct(mid, 2, 0.5))
				var radial := PackedFloat32Array()
				for p in mid:
					radial.append(Vector2(p.x, p.z).distance_to(c))
				radial.sort()
				r = maxf(radial[int((radial.size() - 1) * 0.8)], 0.015 * u)
				c = c.limit_length(r * 0.5)
				if hand:
					length = maxf(_pct(pts, 1, 0.97), r * 2.0)
			var h := maxf(length, r * 2.05)
			return {"shape": kind, "centre": Vector3(c.x, length * 0.5, c.y), "size": Vector3(r, h, 0.0)}
		_:
			var lo := Vector3.ZERO
			var hi := Vector3.ZERO
			if part.ends_with("Foot"):
				if enough:
					lo = Vector3(_pct(pts, 0, 0.02), _pct(pts, 1, 0.02), _pct(pts, 2, 0.02))
					hi = Vector3(_pct(pts, 0, 0.98), _pct(pts, 1, 0.98), _pct(pts, 2, 0.98))
				else:
					lo = Vector3(-0.085 * u, -0.05 * u, -0.1 * u)
					hi = Vector3(0.085 * u, length, 0.03 * u)
			else:
				var width: float = {"Hips": 0.55, "Spine": 0.5, "Chest": 0.6}[part] * u
				var depth := 0.36 * u
				lo = Vector3(-width * 0.5, 0.0, -depth * 0.5)
				hi = Vector3(width * 0.5, length, depth * 0.5)
				if part == "Hips":
					var top := length
					if bone.has("Spine") or bone.has("Chest"):
						var above: int = bone.get("Spine", bone.get("Chest"))
						top = (frame.inverse() * (sk.get_bone_global_rest(above).origin - origin)).y
					var legs := (frame.inverse() * (sk.get_bone_global_rest(bone["LeftUpperLeg"]).origin - origin)).y
					lo.y = minf(legs - 0.08 * u, -0.05 * u)
					hi.y = maxf(top, 0.05 * u)
				if enough:
					lo.x = _pct(pts, 0, 0.05)
					hi.x = _pct(pts, 0, 0.95)
					lo.z = _pct(pts, 2, 0.1)
					hi.z = _pct(pts, 2, 0.9)
					if part == "Hips":
						lo.y = maxf(_pct(pts, 1, 0.05), lo.y)
			var size := (hi - lo).max(Vector3.ONE * 0.02 * u)
			return {"shape": kind, "centre": (lo + hi) * 0.5, "size": size}


## The skinned vertices around each part's bone, at rest, in skeleton space. A vertex belongs to the part
## of its heaviest bone (or of that bone's nearest ancestor with a part); hands and feet left without
## bodies keep their vertices out of the forearms and shins.
func _mesh_points(sk: Skeleton3D, bone: Dictionary, cut: Array) -> Dictionary:
	var part_of := {}
	for part in bone:
		part_of[bone[part]] = part
	var owner_of := PackedStringArray()
	owner_of.resize(sk.get_bone_count())
	for i in sk.get_bone_count():
		var j := i
		while j >= 0 and not part_of.has(j):
			j = sk.get_bone_parent(j)
		owner_of[i] = part_of.get(j, "")
	for i in cut:
		_disown(sk, i, owner_of)
	var out := {}
	var search: Node = sk.get_parent() if sk.get_parent() != null else sk
	for mi: MeshInstance3D in search.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.skin == null or mi.get_node_or_null(mi.skeleton) != sk:
			continue
		var skin := mi.skin
		var to_bone := PackedInt32Array()
		var bind := []
		for b in skin.get_bind_count():
			var bi := skin.get_bind_bone(b)
			if bi < 0:
				bi = sk.find_bone(skin.get_bind_name(b))
			to_bone.append(bi)
			bind.append(sk.get_bone_global_rest(bi) * skin.get_bind_pose(b) if bi >= 0 else Transform3D.IDENTITY)
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null or arr[Mesh.ARRAY_BONES] == null or arr[Mesh.ARRAY_WEIGHTS] == null:
				continue
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			if verts.is_empty():
				continue
			var stride := bones.size() / verts.size()
			for v in verts.size():
				var p := Vector3.ZERO
				var total := 0.0
				var heaviest := -1
				var most := 0.0
				for k in stride:
					var w := weights[v * stride + k]
					var b := bones[v * stride + k]
					if w <= 0.0 or b < 0 or b >= to_bone.size():
						continue
					p += ((bind[b] as Transform3D) * verts[v]) * w
					total += w
					if w > most:
						most = w
						heaviest = to_bone[b]
				if heaviest < 0 or total <= 0.0:
					continue
				var part := owner_of[heaviest]
				if part == "":
					continue
				if not out.has(part):
					out[part] = []             # an Array: a packed array in a dictionary appends to a copy
				(out[part] as Array).append(p / total)
	for part in out:
		out[part] = PackedVector3Array(out[part])
	return out


func _disown(sk: Skeleton3D, i: int, owner_of: PackedStringArray) -> void:
	owner_of[i] = ""
	for k in sk.get_bone_children(i):
		_disown(sk, k, owner_of)


## The farthest rest joint below `from` along `dir` (fingertips, toe ends), or `fallback` metres along it.
func _farthest(sk: Skeleton3D, from: int, at: Vector3, dir: Vector3, fallback: float) -> Vector3:
	var best := at + dir * fallback
	var reach := 0.0
	var stack := Array(sk.get_bone_children(from))
	while not stack.is_empty():
		var i: int = stack.pop_back()
		var p := sk.get_bone_global_rest(i).origin
		var d := (p - at).dot(dir)
		if d > reach:
			reach = d
			best = p
		stack.append_array(Array(sk.get_bone_children(i)))
	return best


## Each part's share of the mass: a person's, leaning towards the part's actual volume (between 0.4 and
## 2.5 times the person's share) so a cartoon character's big hands and head weigh what they look like.
## Masses that match the shapes keep the joints from stretching.
func _mass_shares() -> Dictionary:
	var person := {}
	var volume := {}
	var person_total := 0.0
	var volume_total := 0.0
	for part in _order:
		person[part] = float(PARTS[part][2])
		person_total += person[part]
		var size: Vector3 = _fit[part].size
		match str(_fit[part].shape):
			"ball":
				volume[part] = 4.0 / 3.0 * PI * pow(size.x, 3.0)
			"capsule":
				volume[part] = PI * size.x * size.x * maxf(size.y - 2.0 * size.x, 0.0) + 4.0 / 3.0 * PI * pow(size.x, 3.0)
			_:
				volume[part] = size.x * size.y * size.z
		volume_total += volume[part]
	var out := {}
	var total := 0.0
	for part in _order:
		var p: float = person[part] / person_total
		out[part] = clampf(float(volume[part]) / maxf(volume_total, 1e-9), p * 0.4, p * 2.5)
		total += out[part]
	for part in out:
		out[part] = float(out[part]) / total
	return out


## The part's inertia made the same about every axis (its largest): long thin bodies (forearms, hands)
## otherwise spin about their length too easily, and a fast-spinning light hand pumps energy into the
## joints so an arm never settles.
static func _even_inertia(f: Dictionary, mass: float, s: float) -> Vector3:
	var size: Vector3 = (f.size as Vector3) * s
	var big := 0.0
	match str(f.shape):
		"ball":
			big = 0.4 * mass * size.x * size.x
		"capsule":
			big = mass * (3.0 * size.x * size.x + size.y * size.y) / 12.0
		_:
			big = mass * maxf(size.y * size.y + size.z * size.z, maxf(size.x * size.x + size.z * size.z, size.x * size.x + size.y * size.y)) / 12.0
	return Vector3.ONE * big


static func _pct(pts: PackedVector3Array, axis: int, q: float) -> float:
	var vals := PackedFloat32Array()
	for p in pts:
		vals.append(p[axis])
	vals.sort()
	return vals[int(round((vals.size() - 1) * q))]


# ------------------------------------------------------------------------------------------ bodies

func _shape(f: Dictionary, s: float) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var size: Vector3 = f.size
	match str(f.shape):
		"ball":
			var ball := SphereShape3D.new()
			ball.radius = size.x * s
			cs.shape = ball
		"capsule":
			var cap := CapsuleShape3D.new()
			cap.radius = size.x * s
			cap.height = maxf(size.y * s, cap.radius * 2.0)
			cs.shape = cap
		_:
			var box := BoxShape3D.new()
			box.size = size * s
			cs.shape = box
	if show_shapes:
		cs.add_child(_shape_mesh(cs.shape))
	return cs


func _shape_mesh(shape: Shape3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if shape is SphereShape3D:
		var m := SphereMesh.new()
		m.radius = (shape as SphereShape3D).radius
		m.height = m.radius * 2.0
		mi.mesh = m
	elif shape is CapsuleShape3D:
		var m := CapsuleMesh.new()
		m.radius = (shape as CapsuleShape3D).radius
		m.height = (shape as CapsuleShape3D).height
		mi.mesh = m
	else:
		var m := BoxMesh.new()
		m.size = (shape as BoxShape3D).size
		mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.25, 0.85, 1.0, 0.35)
	mat.no_depth_test = true
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## The joint at `part`'s bone, between its body and its parent's. A joint's limits are measured from the
## pose its bodies are in when it is made, so the child is first turned (about the joint) to its rest pose
## relative to the parent, the joint made, and the child put back: an elbow already bent when the body
## falls can still only bend `elbow_bend` from straight. Cone-twist joints twist about their X axis,
## hinges turn about their Z, so the frames are turned onto the limb and onto the bend axis.
func _joint(sk: Skeleton3D, part: String, parent: String) -> void:
	var at := (sk.global_transform * sk.get_bone_global_pose(_fit[part].bone)).origin
	var child: RigidBody3D = _bodies[part]
	var actual := child.global_transform
	var rel := (_fit[parent].rest as Basis).transposed() * (_fit[part].rest as Basis)
	var turn := ((_bodies[parent] as RigidBody3D).global_basis.orthonormalized() * rel) * actual.basis.transposed()
	child.global_transform = Transform3D(turn * actual.basis, at + turn * (actual.origin - at))
	var r := child.global_basis.orthonormalized()
	var j: Joint3D
	if (_fit[part] as Dictionary).has("axis"):
		var h := HingeJoint3D.new()
		var z := (r * (_fit[part].axis as Vector3)).normalized()
		var x := r.y - z * r.y.dot(z)
		x = x.normalized()
		h.transform = Transform3D(Basis(x, z.cross(x), z), at)
		var bend := deg_to_rad(elbow_bend if part.ends_with("LowerArm") else knee_bend)
		var rest_bend := flexion((_bodies[parent] as RigidBody3D).global_basis.orthonormalized().y, r.y, z)
		# A positive turn of the child about the axis is a negative hinge angle; zero is the rest pose.
		h.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
		h.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, rest_bend - bend)
		h.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, rest_bend + 0.05)
		j = h
	else:
		var c := ConeTwistJoint3D.new()
		c.transform = Transform3D(r * Basis(Vector3.BACK, PI * 0.5), at)
		var swing := spine_swing
		var twist := 12.0
		match part.trim_prefix("Left").trim_prefix("Right"):
			"Head":
				swing = neck_swing
				twist = 35.0
			"UpperArm":
				swing = shoulder_swing
				twist = 40.0
			"UpperLeg":
				swing = hip_swing
				twist = 15.0
			"Hand":
				swing = wrist_swing
				twist = 30.0
			"Foot":
				swing = ankle_swing
				twist = 10.0
		c.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(swing))
		c.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(twist))
		j = c
	j.name = "Joint_" + part
	_root.add_child(j)
	j.node_a = j.get_path_to(_bodies[parent])
	j.node_b = j.get_path_to(child)
	child.global_transform = actual


## How far a hinge is bent (radians, folding positive): the turn from `upper` to `lower` about `axis`,
## both seen square-on to the axis.
static func flexion(upper: Vector3, lower: Vector3, axis: Vector3) -> float:
	var a := upper - axis * upper.dot(axis)
	var b := lower - axis * lower.dot(axis)
	if a.length_squared() < 1e-9 or b.length_squared() < 1e-9:
		return 0.0
	return a.signed_angle_to(b, axis)


## Without self_collision no two parts collide. With it, parts that already overlap when the body falls
## (an arm against the chest, thighs together) still don't; everything else does, if the mask includes
## the ragdoll's own layer.
func _except_overlaps() -> void:
	var parts := _bodies.keys()
	for a in parts.size():
		var sa := _segment(parts[a])
		for b in range(a + 1, parts.size()):
			var sb := _segment(parts[b])
			if not self_collision or _segment_distance(sa[0], sa[1], sb[0], sb[1]) < float(sa[2]) + float(sb[2]) + 0.01:
				(_bodies[parts[a]] as RigidBody3D).add_collision_exception_with(_bodies[parts[b]])


## A part as a world-space capsule: [end a, end b, radius] (boxes become their longest-axis capsule).
func _segment(part: String) -> Array:
	var rb: RigidBody3D = _bodies[part]
	var shape := (rb.get_child(0) as CollisionShape3D).shape
	var t := rb.global_transform
	if shape is SphereShape3D:
		return [t.origin, t.origin, (shape as SphereShape3D).radius]
	if shape is CapsuleShape3D:
		var cap := shape as CapsuleShape3D
		var half := maxf(cap.height * 0.5 - cap.radius, 0.0)
		return [t * Vector3(0.0, -half, 0.0), t * Vector3(0.0, half, 0.0), cap.radius]
	var size := (shape as BoxShape3D).size
	var longest := 0 if size.x >= size.y and size.x >= size.z else (1 if size.y >= size.z else 2)
	var others := [size.x, size.y, size.z]
	others.remove_at(longest)
	var r := minf(others[0], others[1]) * 0.5
	var along := Vector3.ZERO
	along[longest] = maxf(size[longest] * 0.5 - r, 0.0)
	return [t * -along, t * along, r]


static func _point_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := 0.0 if ab.length_squared() < 1e-9 else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _segment_distance(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var c := Geometry3D.get_closest_points_between_segments(p1, q1, p2, q2)
	return c[0].distance_to(c[1])


# ------------------------------------------------------------------------------------------ helpers

func _parent_of(part: String) -> String:
	var p: String = PARTS[part][0]
	while p != "" and not _bodies.has(p):
		p = PARTS[p][0]
	return p


func _head_part() -> String:
	return "Head" if _bodies.has("Head") else "Chest"


static func _jolt() -> bool:
	return str(ProjectSettings.get_setting("physics/3d/physics_engine", "")).contains("Jolt")


func _owner_body() -> PhysicsBody3D:
	var n := get_parent()
	while n != null:
		if n is PhysicsBody3D:
			return n
		n = n.get_parent()
	return null


## Holds every bone without a body at the pose it had at the fall.
func _freeze(sk: Skeleton3D) -> void:
	_frozen.clear()
	if not freeze_other_bones:
		return
	var driven := {}
	for part in _order:
		driven[_fit[part].bone] = true
	for i in sk.get_bone_count():
		if not driven.has(i):
			_frozen[i] = [sk.get_bone_pose_position(i), sk.get_bone_pose_rotation(i), sk.get_bone_pose_scale(i)]


func _tween_influence(to: float, seconds: float) -> Tween:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	active = true
	_fade = create_tween()
	_fade.tween_property(self, "influence", to, maxf(seconds, 0.01)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return _fade


func _finish_get_up() -> void:
	_clear()
	got_up.emit()


func _clear() -> void:
	if _root != null and is_instance_valid(_root):
		remove_child(_root)
		_root.queue_free()
	_root = null
	_bodies.clear()
	_inertia.clear()
	_scale.clear()
	_bone_scale.clear()
	if not _limp:
		_frozen.clear()
		influence = 0.0
		active = false
