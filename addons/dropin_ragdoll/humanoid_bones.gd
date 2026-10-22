@tool
extends RefCounted
## Finds the humanoid bones of any Skeleton3D under Godot's SkeletonProfileHumanoid names (Hips, Spine,
## Chest, Head, LeftUpperArm, ...), whatever the rig calls them: Godot-retargeted skeletons, Mixamo,
## Unreal / MPFB game-engine rigs, Blender-style ".L/.R" rigs, 3ds Max Biped and VRoid all resolve by
## name. Spine and Chest come from the structure (the chest is where the arms and the head meet), so
## rigs with one, three or five spine bones all work. A BoneMap or explicit names win over guessing.

const SIDES := ["Left", "Right"]

# Role → normalized names it may go by (lower case, separators and rig prefixes stripped). Side roles
# list the side-less stems; the side is matched as a prefix or suffix ("left", "l").
const CENTRE := {
	"Hips": ["hips", "hip", "pelvis", "chips"],
	"Neck": ["neck", "neck01", "neck1", "cneck"],
	"Head": ["head", "chead"],
}
const SIDED := {
	"UpperArm": ["upperarm", "arm", "uparm"],
	"LowerArm": ["lowerarm", "forearm", "lowarm"],
	"Hand": ["hand", "wrist"],
	"UpperLeg": ["upperleg", "upleg", "thigh"],
	"LowerLeg": ["lowerleg", "leg", "calf", "shin"],
	"Foot": ["foot", "ankle"],
	"Toes": ["toes", "toe", "toebase", "ball"],
}
const PREFIXES := ["mixamorig", "def", "bip001", "bip01", "jbip"]
const REQUIRED := ["Hips", "Head", "LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm",
	"LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg"]


## Role → bone index for every role found (Spine and Chest included when the rig has them), plus
## "_missing": the required roles that could not be resolved.
static func find(sk: Skeleton3D, bone_map: BoneMap = null, names := {}) -> Dictionary:
	var out := {}
	if bone_map != null:
		for role in ["Hips", "Spine", "Chest", "Neck", "Head"] + _sided_roles():
			var i := sk.find_bone(str(bone_map.get_skeleton_bone_name(role)))
			if i >= 0:
				out[role] = i
	else:
		_guess(sk, out)
	for role in names:
		var i := sk.find_bone(str(names[role]))
		if i >= 0:
			out[str(role)] = i
		else:
			push_warning("DropInRagdoll: no bone named '%s' for %s" % [names[role], role])
	_structure(sk, out)
	var missing := []
	for role in REQUIRED:
		if not out.has(role):
			missing.append(role)
	out["_missing"] = missing
	return out


## The bones as names, for printing ("Hips": "mixamorig:Hips", ...).
static func describe(sk: Skeleton3D, found: Dictionary) -> Dictionary:
	var out := {}
	for role in found:
		if not str(role).begins_with("_"):
			out[role] = sk.get_bone_name(found[role])
	return out


static func normalize(bone: String) -> String:
	var s := bone.to_lower()
	if s.contains(":"):
		s = s.get_slice(":", s.get_slice_count(":") - 1)
	for c in ["_", ".", "-", " "]:
		s = s.replace(c, "")
	for p: String in PREFIXES:
		if s.begins_with(p) and s.length() > p.length():
			s = s.substr(p.length())
			break
	return s


static func _sided_roles() -> Array:
	var out := []
	for side in SIDES:
		for stem in SIDED:
			out.append(side + stem)
	return out


static func _guess(sk: Skeleton3D, out: Dictionary) -> void:
	var wanted := {}                     # normalized name → role
	for role in CENTRE:
		for n in CENTRE[role]:
			wanted[n] = role
	for stem in SIDED:
		for n: String in SIDED[stem]:
			for side: String in SIDES:
				var lo := side.to_lower()
				var s1 := lo.left(1)
				for form in [lo + n, n + lo, s1 + n, n + s1]:
					wanted[form] = side + stem
	# Several bones can answer to one role (KayKit has wrist.l and hand.l): the one nearest the root wins.
	for i in sk.get_bone_count():
		var role: String = wanted.get(normalize(sk.get_bone_name(i)), "")
		if role == "":
			continue
		if not out.has(role) or _depth(sk, i) < _depth(sk, out[role]):
			out[role] = i


## Spine and Chest from the shape of the tree: the chest is the bone where the arms and the head branch
## off; the spine is the first bone above the hips on the way there (none when the chest sits on the hips).
static func _structure(sk: Skeleton3D, out: Dictionary) -> void:
	if not (out.has("Hips") and out.has("Head") and out.has("LeftUpperArm")):
		return
	if not out.has("Chest"):
		var chest := _common_ancestor(sk, out["LeftUpperArm"], out["Head"])
		if out.has("RightUpperArm"):
			chest = _common_ancestor(sk, chest, out["RightUpperArm"])
		if chest >= 0 and chest != out["Hips"] and _is_ancestor(sk, out["Hips"], chest):
			out["Chest"] = chest
	if out.has("Chest") and not out.has("Spine"):
		var spine := child_toward(sk, out["Hips"], out["Chest"])
		if spine >= 0 and spine != out["Chest"]:
			out["Spine"] = spine


## The child of `from` on the way down to `to` (or -1 when `to` is not below `from`).
static func child_toward(sk: Skeleton3D, from: int, to: int) -> int:
	var i := to
	while i >= 0:
		var p := sk.get_bone_parent(i)
		if p == from:
			return i
		i = p
	return -1


static func _is_ancestor(sk: Skeleton3D, a: int, b: int) -> bool:
	var i := sk.get_bone_parent(b)
	while i >= 0:
		if i == a:
			return true
		i = sk.get_bone_parent(i)
	return false


static func _common_ancestor(sk: Skeleton3D, a: int, b: int) -> int:
	var chain := {}
	var i := a
	while i >= 0:
		chain[i] = true
		i = sk.get_bone_parent(i)
	i = b
	while i >= 0:
		if chain.has(i):
			return i
		i = sk.get_bone_parent(i)
	return -1


static func _depth(sk: Skeleton3D, i: int) -> int:
	var d := 0
	while sk.get_bone_parent(i) >= 0:
		i = sk.get_bone_parent(i)
		d += 1
	return d
