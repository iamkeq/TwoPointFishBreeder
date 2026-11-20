extends Node3D
## A person who walks around the shop on the navigation mesh: a Synty Polygon Shops
## character animated with Synty's walk and idle clips. Customers and staff build on this.
## Everything runs on game time, so people freeze when the game is paused.

const Synty := preload("res://scripts/lib/synty.gd")
const SyntyAnims := preload("res://scripts/lib/synty_anims.gd")
const BuildUtil := preload("res://scripts/lib/build_util.gd")
const Data := preload("res://scripts/data.gd")
const L := preload("res://scripts/world/layout.gd")

var world: Node
var walk_speed := 1.4

var _agent: NavigationAgent3D
var _anim: AnimationPlayer
var _model: Node3D
var _clip := ""
var _bubble: Label3D
var _bubble_t := 0.0


func _make_body(who: String) -> void:
	_model = Node3D.new()
	_model.name = "Body"
	add_child(_model)
	var person := Synty.make(who)
	_model.add_child(person)
	var skeleton := person.find_child("GeneralSkeleton", true, false) as Skeleton3D
	if skeleton != null:
		for part in skeleton.get_children():  # the prefab leaves its skinned meshes unbound
			if part is MeshInstance3D and (part as MeshInstance3D).skin != null:
				(part as MeshInstance3D).skeleton = NodePath("..")
		_anim = SyntyAnims.attach(skeleton, who.contains("Female"))
		if not _anim.has_animation("walk"):
			_anim.queue_free()
			_anim = null
		else:
			_play("idle")  # so nobody stands in the T-pose while the game is paused
	_agent = NavigationAgent3D.new()
	_agent.path_desired_distance = 0.4
	_agent.target_desired_distance = 0.35
	_agent.radius = 0.3
	add_child(_agent)


## Game-time scale (0 while paused). Also keeps the animation speed in step.
func _ts() -> float:
	var ts: float = Game.time_scale()
	if _anim != null:
		_anim.speed_scale = ts
	if _bubble != null and _bubble.visible and ts > 0.0:
		_bubble_t -= get_physics_process_delta_time() * ts
		if _bubble_t <= 0.0:
			_bubble.visible = false
	return ts


func _go(p: Vector3) -> void:
	_agent.target_position = p
	_play("walk")


## One step towards the target; true once there.
func _step(delta: float) -> bool:
	if _agent.is_navigation_finished():
		return true
	var next := _agent.get_next_path_position()
	var to := next - global_position
	to.y = 0.0
	if to.length() < 0.01:
		return false
	global_position += to.normalized() * minf(walk_speed * delta, to.length())
	global_position.y = 0.0
	_face(global_position + to)
	_play("walk")
	return false


func _face(p: Vector3, snap: bool = false) -> void:
	var d := p - global_position
	d.y = 0.0
	if d.length() > 0.05:
		var goal := atan2(d.x, d.z)  # the models face +Z
		_model.rotation.y = goal if snap else lerp_angle(_model.rotation.y, goal, 0.2)


func _play(clip: String) -> void:
	if _anim == null or clip == _clip or not _anim.has_animation(clip):
		return
	_clip = clip
	_anim.play(clip, 0.25)


## A little symbol over their head for a moment.
func _say(text: String, color: Color = Color("#fffaf0")) -> void:
	if _bubble == null:
		_bubble = BuildUtil.label(self, "", Vector3(0, 2.2, 0), 0.006)
	_bubble.text = text
	_bubble.modulate = color
	_bubble.visible = true
	_bubble_t = 2.5
