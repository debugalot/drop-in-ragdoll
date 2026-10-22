# Drop-In Ragdoll

[![ExcaliBug](https://img.shields.io/badge/Website-ExcaliBug.com-F4B544?style=flat-square)](https://excalibug.com/addons/drop-in-ragdoll/)
[![Godot 4.7](https://img.shields.io/badge/Godot-4.7-478CBF?style=flat-square&logo=godotengine&logoColor=white)](https://godotengine.org)
[![itch.io](https://img.shields.io/badge/itch.io-Drop--In%20Ragdoll-FA5C5C?style=flat-square&logo=itch.io&logoColor=white)](https://debugalot.itch.io/drop-in-ragdoll)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support-FF5E5B?style=flat-square&logo=kofi&logoColor=white)](https://ko-fi.com/debugalot)
[![License: MIT](https://img.shields.io/badge/License-MIT-43D1C6?style=flat-square)](LICENSE)

A ragdoll for any humanoid `Skeleton3D` in Godot 4. Add one node under the skeleton, call
`go_limp()`, and the character falls. Call `get_up()` and it blends back into its animation.

Part of **[ExcaliBug](https://excalibug.com)** — *Godot addons for the parts that fight back.*  
Read the technical breakdown: **[Why PhysicalBone3D ragdolls shrink scaled characters, and the fix](https://excalibug.com/notes/ragdolls-on-scaled-characters/)**.

- **No setup per character.** It finds the bones by name (Godot humanoid, Mixamo, Unreal/MPFB,
  Blender `.L/.R`, 3ds Max Biped, VRoid) and works out the spine and chest from the shape of the
  skeleton. A `BoneMap` or a few explicit names cover anything else.
- **Sized to the character's mesh.** Each part's collision shape is fitted to the skinned vertices
  around its bone, so a cartoon knight with a huge head gets a huge head sphere.
- **Any scale.** The bodies are built at the character's real size in world space and the bone
  poses are written back, so a character scaled ×0.5 or ×1.4 (or a skeleton inside a scaled scene)
  falls the same way as one at ×1.0. Godot's `PhysicalBone3D` shrinks its bones under a scaled rig.
- **Anatomical limits.** Elbows and knees are hinges that only bend one way. Every limit is
  measured from the skeleton's rest pose, not from the pose the character happened to fall in.
- **Settles cleanly.** Joint damping stops dangling hands swinging, and once the body has nearly
  stopped it settles and sleeps. In the tests, bodies come to rest in about 2–4.5 seconds.

## Requirements

- **Godot 4.7.** Built and tested on 4.7.2 (the .NET build; the addon is plain GDScript). It uses
  `SkeletonModifier3D` (Godot 4.3+), but versions before 4.7 are untested.
- **Jolt Physics.** Set *Project Settings → Physics → 3D → Physics Engine* to **Jolt Physics**. On
  Godot Physics the joints stretch badly (over 20 cm in the tests) and bodies may never settle. The
  node shows an editor warning until Jolt is set.

## Install

Copy `addons/dropin_ragdoll/` into your project's `addons/` folder. There is no plugin to enable:
`DropInRagdoll` shows up in the *Add Child Node* dialog.

## Quick start

1. Open your character's scene. If the model is an imported `.glb`/`.fbx`, right-click it and turn on
   *Editable Children*, or add the node from code (see below).
2. Add a **DropInRagdoll** node as a child of the **Skeleton3D**.
3. Make sure the floor is on a layer in the ragdoll's *Collision Mask* (layer 1 by default).

```gdscript
@onready var ragdoll: DropInRagdoll = $Model/Rig/Skeleton3D/DropInRagdoll

func die(push: Vector3) -> void:
    $CollisionShape3D.disabled = true      # your character's own capsule, out of the way
    ragdoll.go_limp(push)                  # push: world-space velocity, m/s

func shot(impulse: Vector3, at: Vector3) -> void:
    ragdoll.hit(impulse, at)               # goes limp if needed; the part nearest `at` takes the blow
```

From code instead of the editor:

```gdscript
var ragdoll := DropInRagdoll.new()
$Model.find_children("*", "Skeleton3D", true, false)[0].add_child(ragdoll)
```

The ragdoll never collides with the `CharacterBody3D` or `RigidBody3D` that owns the skeleton, and it
starts with that body's velocity, so a running character tumbles forward.

## Getting up

The character root stays where it was while the body is limp. Move it under the body first, then
blend back into an animation:

```gdscript
func _ready() -> void:
    ragdoll.came_to_rest.connect(stand_up)

func stand_up() -> void:
    global_transform = ragdoll.get_up_transform(self)   # on the ground under the hips, facing the right way
    $AnimationPlayer.play("get_up_from_back" if ragdoll.is_face_up() else "get_up_from_front", 0.0)
    ragdoll.get_up(0.25)                                # blend from the limp pose into that animation
    await ragdoll.got_up
    $CollisionShape3D.disabled = false
```

`get_up_transform()` faces the character towards its feet when it lies on its back (the way you sit
up) and towards its head when it lies on its front. Without a get-up animation, a longer
`get_up(0.8)` straight into the idle also works.

## Bones

The bones are found when the body first goes limp. `get_bone_report()` shows which bone plays each
part. If something is missing, `go_limp()` returns `false` and prints which parts it couldn't find,
and the editor shows a warning on the node. To fix it, either:

- assign the `BoneMap` you already use for retargeting to **Bone Map**, or
- name the bones in **Bone Names**, using Godot's humanoid names as keys:
  `{"Head": "DEF-spine.006", "LeftUpperArm": "DEF-upper_arm.L"}`.

Required: Hips, Head, and the upper and lower arms and legs. Spine, Chest, hands and feet are used
when present.

## Inspector

| Group | Setting | Default | What it does |
|---|---|---|---|
| Bones | Bone Map, Bone Names | none | Name the bones when guessing isn't enough. |
| Body | Total Mass | 70 kg | Shared over the parts like a person's, adjusted towards each part's actual size. |
| | Fit To Mesh | on | Size the shapes from the skinned mesh. Off: from the skeleton's proportions. |
| | Shape Scale | 1.0 | Grows or shrinks every shape. |
| | Simulate Hands And Feet | on | Off: 12 bodies instead of 16. Hands and feet keep their pose. |
| | Freeze Other Bones | on | Bones without a body (neck, fingers, toes) hold their pose instead of following the animation still playing underneath. |
| Physics | Collision Layer / Mask | 1 / 1 | Layers for the ragdoll's bodies. |
| | Friction, Bounce | 0.8, 0.05 | Surface of every part. |
| | Linear / Angular Damp | 0.1 / 0.9 | Per-body damping. |
| | Joint Damping | 8 /s | How fast each joint stops its two parts turning against each other. It stops dangling limbs swinging and doesn't slow the body's tumble. |
| | Self Collision | off | Parts of the same body collide with each other. Off is steadier. Different ragdolls always collide if their layers and masks allow it. |
| | Inherit Body Velocity | on | Start with the owning body's velocity. |
| | Settle | on | Near rest, damping rises over a second and the bodies sleep after 1.5 s of settling. |
| Joint limits | spine, neck, shoulder, hip, wrist, ankle swing; elbow, knee bend | 20, 40, 80, 75, 50, 30; 135, 140 | Degrees, measured from the rest pose. |
| Debug | Show Shapes | off | Draws the collision shapes while limp. Can be switched on and off live. |

## API

| | |
|---|---|
| `go_limp(velocity := Vector3.ZERO) -> bool` | Go limp, thrown with `velocity` (m/s, world). |
| `hit(impulse: Vector3, at: Vector3)` | Go limp if needed, and push the part nearest `at` with `impulse` (kg·m/s). |
| `get_up(blend_seconds := 0.5)` | Blend back into the playing animation, then free the bodies. |
| `get_up_transform(root: Node3D) -> Transform3D` | Where to put the character root before getting up. |
| `is_limp()`, `is_resting()`, `is_face_up()` | State. |
| `get_body(part) -> RigidBody3D`, `get_part_position(part) -> Vector3` | One part while limp (`"Hips"`, `"Head"`, `"LeftLowerLeg"`...). |
| `fit() -> bool` | Read the skeleton now (otherwise done on the first fall). Call it again after swapping meshes. |
| `get_bone_report() -> Dictionary` | Part → bone name. |
| signals `went_limp`, `came_to_rest`, `got_up` | |

Parts: Hips, Spine, Chest, Head, Left/Right UpperArm, LowerArm, Hand, UpperLeg, LowerLeg, Foot.

## How it works

- At the first fall the skeleton's rest pose is read. Each part gets a frame (Y along the limb), a
  shape fitted to the vertices whose heaviest bone belongs to it, and an offset from its bone. Shapes
  are then made to agree: a limb is never fatter than the part it hangs from, and the chest and hips
  boxes take in the roots of the arms and legs. This leaves no resting pose that the joints and the
  floor can't both satisfy, which is the usual cause of a ragdoll that jitters forever.
- At each fall the bodies are created from the pose on screen. Each joint is made with its child
  briefly turned to the rest pose, so the limits are anatomical.
- Every frame the modifier writes each bone's pose from its body (`SkeletonModifier3D`, so it
  composes with your other modifiers and with `influence`). Place it after IK and look-at modifiers
  and before cloth or spring bones.
- Masses lean towards each shape's volume, inertia is made even (long thin parts can't spin up), and
  joint damping takes away relative spin with equal and opposite impulses.

## Known limits

- **Hard impacts stretch joints for a few frames.** At Godot's default 60 physics ticks per second,
  throws of 1–4 m/s stretch joints by about 2–4 cm (up to ~6 cm), and push elbows and knees up to
  ~15° past their limits for a few frames. At rest, everything is back within about 3° of its
  limits. Raising *Physics Ticks per Second* to 120 reduces the stretch.
- **Humanoids only:** two arms, two legs, one head.
- **Uniform scale only.** Non-uniformly scaled characters are not supported.
- **Limits are centred on the rest pose.** T-poses and A-poses both work. A rig whose rest pose is
  unusual, such as arms forward, gets limits centred there.

## Demo

`demo/demo.tscn` (the project's main scene): four KayKit knights at ×0.6, ×1.0 and ×1.4 share one
setup. Click a knight to hit it, Space knocks everyone over, R makes everyone get up, F shows the
collision shapes, right-drag orbits and the wheel zooms. Each knight gets up by itself a moment after
it comes to rest.

## Tests

```
godot --headless --fixed-fps 60 --path . res://tests/test_ragdoll.tscn
```

91 checks: bone finding on six rig conventions (with random bone orientations), falls on all of them,
the knight at three scales (bodies at scale, joints holding, elbows and knees within limits, bones
following bodies), hits, getting up, the fallback sizes, frozen bones, and the demo's own knock-down
and get-up loop. The exit code is 0 when everything passes.

`tests/capture.tscn` runs the demo in a window and saves screenshots
(`-- --out=<folder>`, add `--close` for a close-up of one knight falling and getting up).

## Support

If Drop-In Ragdoll saved you time or a headache, consider [buying me a coffee on Ko-fi](https://ko-fi.com/debugalot) or checking out more Godot tools on [ExcaliBug](https://excalibug.com).

## Credits

Demo model: [KayKit Character Pack: Adventurers](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0)
by Kay Lousberg, CC0 (`demo/models/kaykit/LICENSE.txt`). It is included only for the demo.
