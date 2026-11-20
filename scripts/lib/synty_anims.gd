extends RefCounted
## Synty animations (the Base Locomotion and Idles packs) on the shop's Synty people.
##
## The clips come on the Synty animation rig (bones "Hips", "Spine_01", "Shoulder_L"...),
## but the Polygon Shops characters were exported with Godot's humanoid bone names
## ("Hips", "Spine", "LeftUpperArm"...) and their own rest pose. So each clip is
## retargeted once per skeleton: every frame, each bone gets the same turn away from its
## rest pose, in skeleton space, that the source bone made from its own rest pose. The
## hips also carry the clip's up-and-down and sideways sway, scaled to the character.
## Results are cached, so a shop full of shoppers costs one bake per clip and skeleton.

const DIR := "res://assets/Synty/Animations/"
const FPS := 30.0

## The clips, by name: [file stem (without _Femn / _Masc), loops].
const CLIPS := {
	"walk": ["A_Walk_F", true],
	"idle": ["A_Idle_Standing", true],
	"check_watch": ["A_POLY_IDL_CheckWatch", false],
	"foot_tap": ["A_POLY_IDL_Bored_FootTap", false],
	"inspect": ["A_POLY_IDL_Inspect_Hands", false],
	"thanks": ["A_POLY_IDL_HeadNod_Thanks", false],
}

## Synty animation rig bone -> the characters' humanoid bone.
const BONES := {
	"Root": "Root", "Hips": "Hips", "Spine_01": "Spine", "Spine_02": "Chest", "Spine_03": "UpperChest",
	"Neck": "Neck", "Head": "Head", "Jaw": "Jaw",
	"Clavicle_L": "LeftShoulder", "Shoulder_L": "LeftUpperArm", "Elbow_L": "LeftLowerArm", "Hand_L": "LeftHand",
	"Thumb_01": "LeftThumbMetacarpal", "Thumb_02": "LeftThumbProximal", "Thumb_03": "LeftThumbDistal",
	"IndexFinger_01": "LeftIndexProximal", "IndexFinger_02": "LeftIndexIntermediate", "IndexFinger_03": "LeftIndexDistal",
	"Finger_01": "LeftMiddleProximal", "Finger_02": "LeftMiddleIntermediate", "Finger_03": "LeftMiddleDistal",
	"Clavicle_R": "RightShoulder", "Shoulder_R": "RightUpperArm", "Elbow_R": "RightLowerArm", "Hand_R": "RightHand",
	"Thumb_01_1": "RightThumbMetacarpal", "Thumb_02_1": "RightThumbProximal", "Thumb_03_1": "RightThumbDistal",
	"IndexFinger_01_1": "RightIndexProximal", "IndexFinger_02_1": "RightIndexIntermediate", "IndexFinger_03_1": "RightIndexDistal",
	"Finger_01_1": "RightMiddleProximal", "Finger_02_1": "RightMiddleIntermediate", "Finger_03_1": "RightMiddleDistal",
	"UpperLeg_L": "LeftUpperLeg", "LowerLeg_L": "LeftLowerLeg", "Ankle_L": "LeftFoot", "Ball_L": "Ball_L", "Toes_L": "LeftToes",
	"UpperLeg_R": "RightUpperLeg", "LowerLeg_R": "RightLowerLeg", "Ankle_R": "RightFoot", "Ball_R": "Ball_R", "Toes_R": "RightToes",
}

## For lining up the two rest poses: the bone each bone points at (source rig names).
## The clips' rest pose has the arms down at an angle, the characters' has them straight
## out, so each bone's rest is first turned to point the same way as the source's.
const AIM := {
	"Spine_01": "Spine_02", "Spine_02": "Spine_03", "Spine_03": "Neck", "Neck": "Head",
	"Clavicle_L": "Shoulder_L", "Shoulder_L": "Elbow_L", "Elbow_L": "Hand_L",
	"Clavicle_R": "Shoulder_R", "Shoulder_R": "Elbow_R", "Elbow_R": "Hand_R",
	"UpperLeg_L": "LowerLeg_L", "LowerLeg_L": "Ankle_L", "UpperLeg_R": "LowerLeg_R", "LowerLeg_R": "Ankle_R",
}

static var _sources := {}  # file -> {"skeleton": Skeleton3D, "animation": Animation}
static var _libraries := {}  # skeleton key -> AnimationLibrary


## An AnimationPlayer for `skeleton` holding every clip (feminine or masculine set),
## added as the skeleton's child. Its tracks address the skeleton as ".".
static func attach(skeleton: Skeleton3D, feminine: bool) -> AnimationPlayer:
	var player := AnimationPlayer.new()
	player.name = "SyntyAnimations"
	skeleton.add_child(player)
	player.root_node = NodePath("..")
	var library := library_for(skeleton, feminine)
	if library != null:
		player.add_animation_library("", library)
	return player


static func library_for(skeleton: Skeleton3D, feminine: bool) -> AnimationLibrary:
	var key := "%s|%d|%s" % [skeleton.get_bone_name(0), skeleton.get_bone_count(), feminine]
	# The shop characters all share one rig, but their rests differ per body type; key on
	# a few rest values too so two different rigs never share a bake.
	var hips := skeleton.find_bone("Hips")
	if hips >= 0:
		key += "|%s" % skeleton.get_bone_global_rest(hips).origin.snapped(Vector3.ONE * 0.001)
	if _libraries.has(key):
		return _libraries[key]
	var library := AnimationLibrary.new()
	for clip_name in CLIPS:
		var file: String = DIR + CLIPS[clip_name][0] + ("_Femn" if feminine else "_Masc") + ".fbx"
		var source := _source(file)
		if source.is_empty():
			continue
		var anim := _retarget(source["skeleton"], source["animation"], skeleton)
		anim.loop_mode = Animation.LOOP_LINEAR if CLIPS[clip_name][1] else Animation.LOOP_NONE
		library.add_animation(clip_name, anim)
	_libraries[key] = library
	return library


static func _source(file: String) -> Dictionary:
	if _sources.has(file):
		return _sources[file]
	var result := {}
	if ResourceLoader.exists(file):
		var scene: Node = (load(file) as PackedScene).instantiate()
		var skeletons := scene.find_children("*", "Skeleton3D", true, false)
		var players := scene.find_children("*", "AnimationPlayer", true, false)
		if not skeletons.is_empty() and not players.is_empty():
			var player := players[0] as AnimationPlayer
			var names := player.get_animation_list()
			if not names.is_empty():
				var skeleton := skeletons[0] as Skeleton3D
				skeleton.get_parent().remove_child(skeleton)
				result = {"skeleton": skeleton, "animation": player.get_animation(names[0])}
		scene.free()
	_sources[file] = result
	return result


static func _retarget(src: Skeleton3D, anim: Animation, dst: Skeleton3D) -> Animation:
	var out := Animation.new()
	out.length = anim.length
	# Source tracks by bone name.
	var rot_tracks := {}
	var pos_tracks := {}
	for t in anim.get_track_count():
		var bone := String(anim.track_get_path(t).get_concatenated_subnames())
		match anim.track_get_type(t):
			Animation.TYPE_ROTATION_3D:
				rot_tracks[bone] = t
			Animation.TYPE_POSITION_3D:
				pos_tracks[bone] = t
	# Rest poses in skeleton space.
	var src_rest := []
	for i in src.get_bone_count():
		src_rest.append(src.get_bone_global_rest(i).basis.get_rotation_quaternion())
	var dst_rest := []
	for i in dst.get_bone_count():
		dst_rest.append(dst.get_bone_global_rest(i).basis.get_rotation_quaternion())
	# Which destination bone each source bone drives.
	var dst_of := {}  # dst index -> src index
	for s in src.get_bone_count():
		var name := src.get_bone_name(s)
		if BONES.has(name):
			var d := dst.find_bone(BONES[name])
			if d >= 0:
				dst_of[d] = s
	# Rest alignment per driven bone (see AIM): turns the destination rest bone onto the
	# direction the source rest bone points.
	var align := {}  # dst index -> Quaternion
	for d in dst_of:
		var s: int = dst_of[d]
		var s_name := src.get_bone_name(s)
		if not AIM.has(s_name):
			continue
		var s_child := src.find_bone(AIM[s_name])
		var d_child := dst.find_bone(BONES.get(AIM[s_name], ""))
		if s_child < 0 or d_child < 0:
			continue
		var dir_s := src.get_bone_global_rest(s_child).origin - src.get_bone_global_rest(s).origin
		var dir_d := dst.get_bone_global_rest(d_child).origin - dst.get_bone_global_rest(d).origin
		if dir_s.length() > 0.0001 and dir_d.length() > 0.0001:
			align[d] = Quaternion(dir_d.normalized(), dir_s.normalized())
	# Hands and fingers keep the same turn as the forearm they hang from.
	for d in dst.get_bone_count():
		var parent := dst.get_bone_parent(d)
		if dst_of.has(d) and not align.has(d) and parent >= 0 and align.has(parent):
			align[d] = align[parent]
	var dst_tracks := {}
	for d in dst_of:
		var track := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(track, NodePath(".:" + dst.get_bone_name(d)))
		dst_tracks[d] = track
	# Hips sway, scaled by how tall the hips are on each rig.
	var src_hips := src.find_bone("Hips")
	var dst_hips := dst.find_bone("Hips")
	var hips_track := -1
	var scale := 1.0
	if src_hips >= 0 and dst_hips >= 0 and pos_tracks.has("Hips"):
		hips_track = out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(hips_track, NodePath(".:Hips"))
		var sh := src.get_bone_global_rest(src_hips).origin.y
		var dh := dst.get_bone_global_rest(dst_hips).origin.y
		scale = dh / sh if absf(sh) > 0.0001 else 1.0
	var frames := maxi(int(ceil(anim.length * FPS)), 1)
	for f in frames + 1:
		var time := minf(float(f) / FPS, anim.length)
		# Source pose, skeleton space.
		var src_global := []
		src_global.resize(src.get_bone_count())
		for s in src.get_bone_count():
			var name := src.get_bone_name(s)
			var local: Quaternion = anim.rotation_track_interpolate(rot_tracks[name], time) \
				if rot_tracks.has(name) else src.get_bone_rest(s).basis.get_rotation_quaternion()
			var parent := src.get_bone_parent(s)
			src_global[s] = (src_global[parent] * local) if parent >= 0 else local
		# Destination pose: driven bones copy the source's turn from rest; others stay at rest.
		var dst_global := []
		dst_global.resize(dst.get_bone_count())
		for d in dst.get_bone_count():
			var parent := dst.get_bone_parent(d)
			var g: Quaternion
			if dst_of.has(d):
				var s: int = dst_of[d]
				var rest: Quaternion = (align[d] as Quaternion) * (dst_rest[d] as Quaternion) if align.has(d) else dst_rest[d]
				g = (src_global[s] * (src_rest[s] as Quaternion).inverse()) * rest
			else:
				var rest_local := dst.get_bone_rest(d).basis.get_rotation_quaternion()
				g = (dst_global[parent] * rest_local) if parent >= 0 else rest_local
			dst_global[d] = g.normalized()
			if dst_tracks.has(d):
				var local_q: Quaternion = ((dst_global[parent] as Quaternion).inverse() * g) if parent >= 0 else g
				out.rotation_track_insert_key(dst_tracks[d], time, local_q.normalized())
		if hips_track >= 0:
			var src_pos: Vector3 = anim.position_track_interpolate(pos_tracks["Hips"], time)
			var src_parent := src.get_bone_parent(src_hips)
			var src_parent_rot: Quaternion = src_global[src_parent] if src_parent >= 0 else Quaternion.IDENTITY
			var moved: Vector3 = src_parent_rot * (src_pos - src.get_bone_rest(src_hips).origin) * scale
			var dst_parent := dst.get_bone_parent(dst_hips)
			var dst_parent_rot: Quaternion = dst_global[dst_parent] if dst_parent >= 0 else Quaternion.IDENTITY
			out.position_track_insert_key(hips_track, time,
				dst.get_bone_rest(dst_hips).origin + dst_parent_rot.inverse() * moved)
	return out
