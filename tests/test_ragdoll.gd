extends Node
## Headless checks for DropInRagdoll. Run:
##   godot --headless --fixed-fps 60 --path . res://tests/test_ragdoll.tscn
## Exit code 0 when every check passes.

const Bones := preload("res://addons/dropin_ragdoll/humanoid_bones.gd")
const KNIGHT := preload("res://demo/models/kaykit/Knight.glb")

# A 1.75 m person in a T-pose facing +Z, left on +X: joint → [position, parent].
const BODY := {
	"root": [Vector3(0, 0, 0), ""],
	"hips": [Vector3(0, 0.95, 0), "root"],
	"spine1": [Vector3(0, 1.05, 0), "hips"],
	"spine2": [Vector3(0, 1.18, 0), "spine1"],
	"chest": [Vector3(0, 1.3, 0), "spine2"],
	"neck": [Vector3(0, 1.5, 0), "chest"],
	"head": [Vector3(0, 1.6, 0), "neck"],
	"head_end": [Vector3(0, 1.82, 0), "head"],
	"l_clavicle": [Vector3(0.05, 1.42, 0), "chest"],
	"l_upperarm": [Vector3(0.18, 1.42, 0), "l_clavicle"],
	"l_lowerarm": [Vector3(0.46, 1.42, 0), "l_upperarm"],
	"l_hand": [Vector3(0.72, 1.42, 0), "l_lowerarm"],
	"l_finger": [Vector3(0.82, 1.42, 0), "l_hand"],
	"l_thigh": [Vector3(0.1, 0.92, 0), "hips"],
	"l_calf": [Vector3(0.1, 0.5, 0), "l_thigh"],
	"l_foot": [Vector3(0.1, 0.08, 0), "l_calf"],
	"l_toes": [Vector3(0.1, 0.02, 0.13), "l_foot"],
}
# Joint → bone name, per rig convention ("" drops the joint; the right side mirrors the left).
const RIGS := {
	"godot": {"root": "Root", "hips": "Hips", "spine1": "Spine", "spine2": "Chest", "chest": "UpperChest",
		"neck": "Neck", "head": "Head", "head_end": "", "l_clavicle": "LeftShoulder", "l_upperarm": "LeftUpperArm",
		"l_lowerarm": "LeftLowerArm", "l_hand": "LeftHand", "l_finger": "LeftIndexProximal",
		"l_thigh": "LeftUpperLeg", "l_calf": "LeftLowerLeg", "l_foot": "LeftFoot", "l_toes": "LeftToes"},
	"mixamo": {"root": "", "hips": "mixamorig_Hips", "spine1": "mixamorig_Spine", "spine2": "mixamorig_Spine1",
		"chest": "mixamorig_Spine2", "neck": "mixamorig_Neck", "head": "mixamorig_Head", "head_end": "mixamorig_HeadTop_End",
		"l_clavicle": "mixamorig_LeftShoulder", "l_upperarm": "mixamorig_LeftArm", "l_lowerarm": "mixamorig_LeftForeArm",
		"l_hand": "mixamorig_LeftHand", "l_finger": "mixamorig_LeftHandIndex1", "l_thigh": "mixamorig_LeftUpLeg",
		"l_calf": "mixamorig_LeftLeg", "l_foot": "mixamorig_LeftFoot", "l_toes": "mixamorig_LeftToeBase"},
	"unreal": {"root": "root", "hips": "pelvis", "spine1": "spine_01", "spine2": "spine_02", "chest": "spine_03",
		"neck": "neck_01", "head": "head", "head_end": "", "l_clavicle": "clavicle_l", "l_upperarm": "upperarm_l",
		"l_lowerarm": "lowerarm_l", "l_hand": "hand_l", "l_finger": "index_01_l", "l_thigh": "thigh_l",
		"l_calf": "calf_l", "l_foot": "foot_l", "l_toes": "ball_l"},
	"blender": {"root": "", "hips": "hips", "spine1": "spine", "spine2": "", "chest": "chest", "neck": "neck",
		"head": "head", "head_end": "", "l_clavicle": "shoulder.L", "l_upperarm": "upper_arm.L",
		"l_lowerarm": "forearm.L", "l_hand": "hand.L", "l_finger": "", "l_thigh": "thigh.L", "l_calf": "shin.L",
		"l_foot": "foot.L", "l_toes": "toe.L"},
	"vroid": {"root": "Root", "hips": "J_Bip_C_Hips", "spine1": "J_Bip_C_Spine", "spine2": "J_Bip_C_Chest",
		"chest": "J_Bip_C_UpperChest", "neck": "J_Bip_C_Neck", "head": "J_Bip_C_Head", "head_end": "",
		"l_clavicle": "J_Bip_L_Shoulder", "l_upperarm": "J_Bip_L_UpperArm", "l_lowerarm": "J_Bip_L_LowerArm",
		"l_hand": "J_Bip_L_Hand", "l_finger": "J_Bip_L_Index1", "l_thigh": "J_Bip_L_UpperLeg",
		"l_calf": "J_Bip_L_LowerLeg", "l_foot": "J_Bip_L_Foot", "l_toes": "J_Bip_L_ToeBase"},
	"biped": {"root": "Bip01", "hips": "Bip01 Pelvis", "spine1": "Bip01 Spine", "spine2": "Bip01 Spine1",
		"chest": "Bip01 Spine2", "neck": "Bip01 Neck", "head": "Bip01 Head", "head_end": "",
		"l_clavicle": "Bip01 L Clavicle", "l_upperarm": "Bip01 L UpperArm", "l_lowerarm": "Bip01 L Forearm",
		"l_hand": "Bip01 L Hand", "l_finger": "Bip01 L Finger0", "l_thigh": "Bip01 L Thigh",
		"l_calf": "Bip01 L Calf", "l_foot": "Bip01 L Foot", "l_toes": "Bip01 L Toe0"},
}
const RIGHT := {"godot": ["Left", "Right"], "mixamo": ["Left", "Right"], "unreal": ["_l", "_r"],
	"blender": [".L", ".R"], "vroid": ["_L_", "_R_"], "biped": [" L ", " R "]}

var failures := 0
var checks := 0
var floor_body: StaticBody3D


func _ready() -> void:
	floor_body = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	cs.shape = box
	cs.position.y = -0.5
	floor_body.add_child(cs)
	add_child(floor_body)
	await _run()
	print("\n%d checks, %d failed" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL  ", what)
	else:
		print("ok    ", what)


func _run() -> void:
	_test_names()
	for rig in RIGS:
		await _test_drop_synthetic(rig)
	await _test_knight_mapping_and_fit()
	for s in [1.0, 1.3, 0.5]:
		await _test_knight_drop(s)
	await _test_hit_and_get_up()
	await _test_fallback_sizes()
	await _test_freeze()
	await _test_demo()


# --------------------------------------------------------------------------------------- builders

func _synthetic(rig: String, seed_value: int) -> Skeleton3D:
	var names: Dictionary = RIGS[rig]
	var sk := Skeleton3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var global := {}                     # joint → global rest
	var joints := BODY.keys()
	for side in ["l", "r"]:
		for j: String in joints:
			if side == "r" and not j.begins_with("l_"):
				continue
			var key := j if side == "l" else "r" + j.substr(1)
			var name: String = names[j]
			if name == "":
				continue
			if side == "r":
				name = name.replace(RIGHT[rig][0], RIGHT[rig][1])
			var pos: Vector3 = BODY[j][0]
			if side == "r":
				pos.x = -pos.x
			var parent_joint: String = BODY[j][1]
			if side == "r" and parent_joint.begins_with("l_"):
				parent_joint = "r" + parent_joint.substr(1)
			# Skip dropped joints: hang on the nearest kept ancestor.
			while parent_joint != "" and str(names[parent_joint.replace("r_", "l_")]) == "":
				parent_joint = str(BODY[parent_joint.replace("r_", "l_")][1])
				if parent_joint.begins_with("l_") and key.begins_with("r_"):
					parent_joint = "r" + parent_joint.substr(1)
			var i := sk.add_bone(name)
			# Every bone gets a random rest orientation: nothing may assume a bone points down its Y axis.
			var basis := Basis.from_euler(Vector3(rng.randf_range(-PI, PI), rng.randf_range(-PI, PI), rng.randf_range(-PI, PI)))
			var g := Transform3D(basis, pos)
			global[key] = g
			if parent_joint != "":
				var pname: String = names[parent_joint.replace("r_", "l_")]
				if parent_joint.begins_with("r_"):
					pname = pname.replace(RIGHT[rig][0], RIGHT[rig][1])
				sk.set_bone_parent(i, sk.find_bone(pname))
				sk.set_bone_rest(i, (global[parent_joint] as Transform3D).affine_inverse() * g)
			else:
				sk.set_bone_rest(i, g)
	sk.reset_bone_poses()
	return sk


func _knight(scale: float, at: Vector3) -> Dictionary:
	var root := Node3D.new()
	root.scale = Vector3.ONE * scale
	add_child(root)
	root.global_position = at
	var model := KNIGHT.instantiate()
	root.add_child(model)
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var rd := DropInRagdoll.new()
	sk.add_child(rd)
	var ap: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	ap.play("Idle")
	return {"root": root, "sk": sk, "rd": rd, "ap": ap}


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


# --------------------------------------------------------------------------------------- tests

func _test_names() -> void:
	var expect := {
		"godot": {"Hips": "Hips", "Spine": "Spine", "Chest": "UpperChest", "Head": "Head", "LeftUpperArm": "LeftUpperArm", "RightLowerLeg": "RightLowerLeg", "LeftHand": "LeftHand"},
		"mixamo": {"Hips": "mixamorig_Hips", "Spine": "mixamorig_Spine", "Chest": "mixamorig_Spine2", "LeftUpperArm": "mixamorig_LeftArm", "LeftLowerArm": "mixamorig_LeftForeArm", "RightUpperLeg": "mixamorig_RightUpLeg", "RightLowerLeg": "mixamorig_RightLeg"},
		"unreal": {"Hips": "pelvis", "Spine": "spine_01", "Chest": "spine_03", "LeftUpperArm": "upperarm_l", "RightLowerArm": "lowerarm_r", "LeftLowerLeg": "calf_l", "RightFoot": "foot_r"},
		"blender": {"Hips": "hips", "Spine": "spine", "Chest": "chest", "LeftUpperArm": "upper_arm.L", "RightLowerArm": "forearm.R", "LeftLowerLeg": "shin.L"},
		"vroid": {"Hips": "J_Bip_C_Hips", "Spine": "J_Bip_C_Spine", "Chest": "J_Bip_C_UpperChest", "Head": "J_Bip_C_Head", "RightUpperArm": "J_Bip_R_UpperArm", "LeftLowerLeg": "J_Bip_L_LowerLeg"},
		"biped": {"Hips": "Bip01 Pelvis", "Spine": "Bip01 Spine", "Chest": "Bip01 Spine2", "LeftUpperArm": "Bip01 L UpperArm", "RightLowerArm": "Bip01 R Forearm", "RightLowerLeg": "Bip01 R Calf"},
	}
	for rig in RIGS:
		var sk := _synthetic(rig, 7)
		var found := Bones.find(sk)
		var names := Bones.describe(sk, found)
		var wrong := []
		for role in expect[rig]:
			if names.get(role, "") != expect[rig][role]:
				wrong.append("%s=%s (want %s)" % [role, names.get(role, "-"), expect[rig][role]])
		ok((found["_missing"] as Array).is_empty() and wrong.is_empty(), "%s rig: bones found by name %s" % [rig, wrong if not wrong.is_empty() else ""])
		sk.free()
	# A bone name override wins over the guess.
	var sk2 := _synthetic("unreal", 7)
	var f2 := Bones.find(sk2, null, {"Head": "neck_01"})
	ok(sk2.get_bone_name(f2["Head"]) == "neck_01", "bone_names overrides a guessed bone")
	sk2.free()


## Synthetic rigs (random bone orientations, no mesh: proportional sizes) fall, settle and hold together.
func _test_drop_synthetic(rig: String) -> void:
	var holder := Node3D.new()
	add_child(holder)
	holder.position = Vector3(0, 0.05, 18)
	var sk := _synthetic(rig, 11)
	holder.add_child(sk)
	var rd := DropInRagdoll.new()
	sk.add_child(rd)
	await _frames(2)
	ok(rd.go_limp(Vector3(1.5, 0, 0.5)), "%s rig: goes limp" % rig)
	var joints := _anchors(rd)
	var worst: Dictionary = await _simulate(rd, 600)
	_check_drop("%s rig" % rig, rd, joints, worst, 1.0)
	holder.queue_free()
	await _frames(1)


func _test_knight_mapping_and_fit() -> void:
	var k := _knight(1.0, Vector3(0, 0, -30))
	var rd: DropInRagdoll = k.rd
	await _frames(2)
	var report := rd.get_bone_report()
	var want := {"Hips": "hips", "Spine": "spine", "Chest": "chest", "Head": "head", "LeftUpperArm": "upperarm.l",
		"LeftLowerArm": "lowerarm.l", "LeftHand": "wrist.l", "RightUpperLeg": "upperleg.r", "RightLowerLeg": "lowerleg.r", "RightFoot": "foot.r"}
	var wrong := []
	for role in want:
		if report.get(role, "") != want[role]:
			wrong.append("%s=%s" % [role, report.get(role, "-")])
	ok(wrong.is_empty() and report.size() == 16, "knight: 16 parts on the right bones %s" % [wrong if not wrong.is_empty() else ""])
	var head: Vector3 = rd._fit["Head"].size
	var thigh: Vector3 = rd._fit["LeftUpperLeg"].size
	var chest: Vector3 = rd._fit["Chest"].size
	print("      head r %.3f  thigh r %.3f h %.3f  chest %s" % [head.x, thigh.x, thigh.y, chest])
	ok(head.x > 0.3 and head.x < 0.6, "knight: head sized from its mesh (r %.2f m: the knight's head is 1.1 m wide)" % head.x)
	ok(thigh.x > 0.08 and thigh.x < 0.2, "knight: thigh sized from its mesh (r %.2f m)" % thigh.x)
	ok(chest.x > 0.3 and chest.x < 0.9, "knight: chest box as wide as the body (%.2f m)" % chest.x)
	k.root.queue_free()
	await _frames(1)


func _test_knight_drop(s: float) -> void:
	var k := _knight(s, Vector3(5.0 * s, 0, 0))
	var rd: DropInRagdoll = k.rd
	var sk: Skeleton3D = k.sk
	await _frames(10)
	var rested := [false]
	rd.came_to_rest.connect(func() -> void: rested[0] = true)
	ok(rd.go_limp(Vector3(2.5, 1.0, 0)), "knight ×%.1f: goes limp" % s)
	var chest_box: Vector3 = ((rd.get_body("Chest").get_child(0) as CollisionShape3D).shape as BoxShape3D).size
	var fitted: Vector3 = rd._fit["Chest"].size
	ok(chest_box.is_equal_approx(fitted * s), "knight ×%.1f: bodies are built at the character's scale" % s)
	var joints := _anchors(rd)
	var worst: Dictionary = await _simulate(rd, 600)
	ok(rested[0], "knight ×%.1f: came_to_rest fires" % s)
	_check_drop("knight ×%.1f" % s, rd, joints, worst, s)
	# The skeleton follows the bodies: read the pose while the skeleton is updated.
	var err := [INF]
	var check := func() -> void:
		var e := 0.0
		for part in rd._order:
			var rb := rd.get_body(part)
			var cs: Vector3 = rd._scale[part]
			var r := rb.global_basis.orthonormalized()
			var want_bone := Transform3D(Basis(r.x * cs.x, r.y * cs.y, r.z * cs.z), rb.global_position) * (rd._fit[part].offset as Transform3D).affine_inverse()
			var got := sk.global_transform * sk.get_bone_global_pose(rd._fit[part].bone)
			e = maxf(e, want_bone.origin.distance_to(got.origin))
		err[0] = e
	sk.skeleton_updated.connect(check)
	await _frames(3)
	sk.skeleton_updated.disconnect(check)
	ok(err[0] < 0.002 * s, "knight ×%.1f: bones follow the bodies (off by %.4f m)" % [s, err[0]])
	k.root.queue_free()
	await _frames(1)


func _test_hit_and_get_up() -> void:
	var k := _knight(1.0, Vector3(-8, 0, 0))
	var rd: DropInRagdoll = k.rd
	var sk: Skeleton3D = k.sk
	await _frames(10)
	var head_at := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("head"))).origin + Vector3(0, 0.2, 0)
	rd.hit(Vector3(0, 0, -30), head_at)
	ok(rd.is_limp(), "hit: a standing character goes limp")
	await _frames(1)
	var fastest := ""
	for part in rd._order:
		if fastest == "" or rd.get_body(part).linear_velocity.z < rd.get_body(fastest).linear_velocity.z:
			fastest = part
	var head := rd.get_body("Head")
	ok(fastest == "Head" and head.linear_velocity.z < -0.5, "hit: the part nearest the blow takes it (head vz %.2f, fastest part %s)" % [head.linear_velocity.z if head else 0.0, fastest])
	await _simulate(rd, 300)
	var where := rd.get_up_transform(k.root)
	ok(absf(where.origin.y) < 0.05, "get_up_transform: on the ground (y %.3f)" % where.origin.y)
	var hips := rd.get_part_position("Hips")
	ok(Vector2(where.origin.x, where.origin.z).distance_to(Vector2(hips.x, hips.z)) < 0.01, "get_up_transform: under the hips")
	var got_up := [false]
	rd.got_up.connect(func() -> void: got_up[0] = true)
	k.root.global_transform = where
	rd.get_up(0.3)
	await _frames(30)
	ok(got_up[0] and not rd.is_limp() and rd.influence == 0.0 and not rd.active, "get_up: blends out, frees the bodies, got_up fires")
	ok(rd.get_body("Hips") == null, "get_up: no bodies left")
	ok(rd.go_limp(), "goes limp again after getting up")
	await _frames(5)
	rd.get_up(0.1)
	await _frames(15)
	k.root.queue_free()
	await _frames(1)


func _test_fallback_sizes() -> void:
	var k := _knight(1.0, Vector3(-16, 0, 0))
	var rd: DropInRagdoll = k.rd
	rd.fit_to_mesh = false
	rd.simulate_hands_and_feet = false
	await _frames(5)
	ok(rd.go_limp(), "no mesh fitting, no hands or feet: goes limp")
	ok(rd._order.size() == 12 and rd.get_body("LeftHand") == null, "no hands or feet: 12 bodies")
	var joints := _anchors(rd)
	var worst: Dictionary = await _simulate(rd, 600)
	_check_drop("no mesh fitting", rd, joints, worst, 1.0)
	k.root.queue_free()
	await _frames(1)


func _test_freeze() -> void:
	var k := _knight(1.0, Vector3(-24, 0, 0))
	var rd: DropInRagdoll = k.rd
	var sk: Skeleton3D = k.sk
	var ap: AnimationPlayer = k.ap
	ap.play("Running_A")
	await _frames(20)
	var toe := sk.find_bone("toes.l")
	rd.go_limp()
	var held: Quaternion = rd._frozen[toe][1]
	await _frames(5)                     # past the fade-in: influence is 1 from here
	var drift := [0.0]
	var check := func() -> void:
		drift[0] = maxf(drift[0], sk.get_bone_pose_rotation(toe).angle_to(held))
	sk.skeleton_updated.connect(check)
	await _frames(40)
	sk.skeleton_updated.disconnect(check)
	ok(drift[0] < 0.001, "freeze: bones without bodies hold their pose while the run animation plays (drift %.4f)" % drift[0])
	k.root.queue_free()
	await _frames(1)


## The demo scene: everyone knocked over, then everyone back on their feet by themselves.
func _test_demo() -> void:
	floor_body.collision_layer = 0          # the demo has its own floor
	var demo: Node3D = load("res://demo/demo.tscn").instantiate()
	add_child(demo)
	await _frames(30)
	demo.knock_all()
	var limp := 0
	for k in demo.knights:
		limp += 1 if k.ragdoll.is_limp() else 0
	ok(limp == demo.knights.size(), "demo: knock_all knocks all %d knights over" % demo.knights.size())
	var standing := 0
	var start := Engine.get_physics_frames()
	for i in 900:
		await get_tree().physics_frame
		standing = 0
		for k in demo.knights:
			standing += 1 if not k.ragdoll.is_limp() and not k._up and k.collision_layer == 2 else 0
		if standing == demo.knights.size():
			break
	ok(standing == demo.knights.size(), "demo: every knight gets back up by itself (%d of %d, %.1f s)" % [standing, demo.knights.size(), (Engine.get_physics_frames() - start) / 60.0])
	demo.queue_free()
	await _frames(1)
	floor_body.collision_layer = 1


# --------------------------------------------------------------------------------------- measuring

## Each joint's anchor in its two bodies' frames, taken at the fall.
func _anchors(rd: DropInRagdoll) -> Array:
	var out := []
	for j: Joint3D in rd.find_children("Joint_*", "Joint3D", true, false):
		var a := j.get_node(j.node_a) as RigidBody3D
		var b := j.get_node(j.node_b) as RigidBody3D
		out.append([a, b, a.global_transform.affine_inverse() * j.global_position, b.global_transform.affine_inverse() * j.global_position])
	return out


func _gaps(rd: DropInRagdoll, joints: Array) -> float:
	var worst := 0.0
	for j in joints:
		var a: RigidBody3D = j[0]
		var b: RigidBody3D = j[1]
		worst = maxf(worst, (a.global_transform * (j[2] as Vector3)).distance_to(b.global_transform * (j[3] as Vector3)))
	return worst


## Steps the physics `frames` times (or until at rest), tracking the worst joint gap, the lowest point of
## any body and how far an elbow or knee went past straight (hyper) or past its bend limit (over), degrees.
func _simulate(rd: DropInRagdoll, frames: int) -> Dictionary:
	var joints := _anchors(rd)
	var worst := {"gap": 0.0, "floor": INF, "hyper": 0.0, "over": 0.0, "seconds": 0.0}
	var rested_for := 0
	for i in frames:
		await get_tree().physics_frame
		worst.seconds = (i + 1) / float(Engine.physics_ticks_per_second)
		worst.gap = maxf(worst.gap, _gaps(rd, joints))
		for part in rd._order:
			var seg := rd._segment(part)
			worst.floor = minf(worst.floor, minf((seg[0] as Vector3).y, (seg[1] as Vector3).y) - float(seg[2]))
		var h := _hinges(rd)
		worst.hyper = maxf(worst.hyper, h[0])
		worst.over = maxf(worst.over, h[1])
		rested_for = rested_for + 1 if rd.is_resting() else 0
		if rested_for > 5:
			break
	return worst


## The limits these checks hold the ragdoll to. Hard impacts at 60 Hz stretch joints and push elbows and
## knees past their limits for a few frames (measured over many throws: gaps up to ~8 cm, ~18° past
## straight, ~26° past the bend limit); once at rest everything must be back within a few degrees.
func _check_drop(what: String, rd: DropInRagdoll, joints: Array, worst: Dictionary, s: float) -> void:
	ok(rd.is_resting(), "%s: comes to rest (%.1f s)" % [what, worst.seconds])
	ok(worst.gap < 0.1 * s, "%s: joints hold through the fall (worst stretch %.3f m)" % [what, worst.gap])
	# Jolt lets resting bodies sink up to its penetration slop (2 cm by default) whatever their size.
	ok(worst.floor > -0.05, "%s: stays on the floor (deepest %.3f m)" % [what, worst.floor])
	ok(worst.hyper < 20.0 and worst.over < 30.0, "%s: knees and elbows bend the right way (worst %.1f° past straight, %.1f° past the limit)" % [what, worst.hyper, worst.over])
	var h := _hinges(rd)
	ok(_gaps(rd, joints) < 0.04 * s and h[0] < 10.0 and h[1] < 10.0, "%s: at rest, joints together and within limits (stretch %.3f m, %.1f° / %.1f°)" % [what, _gaps(rd, joints), h[0], h[1]])


## [worst bend past straight, worst bend past the limit] over elbows and knees, degrees.
func _hinges(rd: DropInRagdoll) -> Array:
	var hyper := 0.0
	var over := 0.0
	for part in ["LeftLowerArm", "RightLowerArm", "LeftLowerLeg", "RightLowerLeg"]:
		var rb := rd.get_body(part)
		var upper := rd.get_body(part.replace("Lower", "Upper"))
		if rb == null or upper == null:
			continue
		var axis: Vector3 = rb.global_basis.orthonormalized() * (rd._fit[part].axis as Vector3)
		var bend := rad_to_deg(DropInRagdoll.flexion(upper.global_basis.orthonormalized().y, rb.global_basis.orthonormalized().y, axis))
		if bend < -90.0:
			bend += 360.0                      # folded past 180°, not bent backwards
		hyper = maxf(hyper, -bend)
		over = maxf(over, bend - (rd.elbow_bend if part.ends_with("LowerArm") else rd.knee_bend))
	return [hyper, over]
