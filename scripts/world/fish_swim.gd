extends Node3D
## One fish (the Polygon Office fish model in its species' colour) wandering around inside
## a tank. Position is in the tank's local space, kept inside `bounds`.

const Synty := preload("res://scripts/lib/synty.gd")
const Data := preload("res://scripts/data.gd")
const FishData := preload("res://scripts/fish_data.gd")
const FishArt := preload("res://scripts/fish_art.gd")

var fish: Dictionary
var bounds := AABB(Vector3(-0.4, 0.7, -0.2), Vector3(0.8, 0.4, 0.4))
var _target := Vector3.ZERO
var _speed := 0.15
var _rest := 0.0
var _rng := RandomNumberGenerator.new()
var _model: Node3D
var _sprite: Sprite3D
var _last_dir := Vector3.RIGHT
var _t := 0.0


func setup(p_fish: Dictionary, p_bounds: AABB) -> void:
	fish = p_fish
	bounds = p_bounds
	_rng.seed = int(fish["id"]) * 7919 + 13
	var v := FishData.variety(fish["species"], fish.get("variety", ""))
	if FishArt.has_art(fish["species"]):
		var fr := FishArt.frame(fish.get("variety", ""), fish["species"])
		_sprite = Sprite3D.new()
		_sprite.texture = FishArt.sheet(fish["species"])
		_sprite.region_enabled = true
		_sprite.region_rect = fr["rect"]
		_sprite.modulate = fr["tint"]
		_sprite.pixel_size = FishArt.PIXEL_SIZE[fish["species"]]
		_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		_sprite.shaded = false
		_sprite.double_sided = true
		_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_model = _sprite
		add_child(_model)
		refresh_size()
		position = _random_point()
		_pick_target()
		_t = _rng.randf() * 10.0
		return
	_model = Synty.fish(Color(v["color"]))
	add_child(_model)
	# Fins/tail in the variety's second colour: a small flat fan behind the body.
	var tail := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.09, 0.08, 0.012)
	tail.mesh = prism
	tail.rotation_degrees = Vector3(0, 90, -90)
	tail.position = Vector3(0, 0.0, 0.1)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(v["accent"])
	m.roughness = 1.0
	tail.material_override = m
	_model.add_child(tail)
	refresh_size()
	position = _random_point()
	_pick_target()
	_t = _rng.randf() * 10.0


## Fry are small; they grow to full size as adults.
func refresh_size() -> void:
	var sp: Dictionary = Data.SPECIES[fish["species"]]
	var grown := 1.0 if FishData.is_adult(fish) else 0.45 + 0.15 * int(fish.get("age", 0))
	if _sprite != null:
		_sprite.scale = Vector3.ONE * grown
		return
	_model.scale = Vector3.ONE * float(sp["size"]) * 1.4 * grown


func _random_point() -> Vector3:
	var b := bounds.grow(-0.06)
	return b.position + Vector3(_rng.randf(), _rng.randf(), _rng.randf()) * b.size


func _pick_target() -> void:
	_target = _random_point()
	_speed = _rng.randf_range(0.08, 0.22)


func _process(delta: float) -> void:
	var ts: float = Game.time_scale()
	if ts <= 0.0:
		return
	delta *= minf(ts, 2.0)
	_t += delta
	if _rest > 0.0:
		_rest -= delta
		if _sprite == null:
			_model.rotation.z = sin(_t * 3.0) * 0.05
		return
	var to := _target - position
	if to.length() < 0.03:
		_rest = _rng.randf_range(0.3, 2.0)
		_pick_target()
		return
	var dir := to.normalized()
	position += dir * minf(_speed * delta, to.length())
	if _sprite != null:
		# The picture faces right: flip it when swimming leftwards on screen.
		var cam := get_viewport().get_camera_3d()
		var parent := get_parent() as Node3D
		if cam != null and parent != null:
			var along := (parent.global_transform.basis * dir).dot(cam.global_transform.basis.x)
			if absf(along) > 0.05:
				_sprite.flip_h = along < 0.0
		_sprite.position.y = sin(_t * 4.0) * 0.004
		return
	# Nose (-Z) along the direction of travel, staying level.
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() > 0.01:
		var goal := atan2(-flat.x, -flat.z)
		rotation.y = lerp_angle(rotation.y, goal, minf(1.0, delta * 5.0))
	_model.rotation.y = sin(_t * 9.0) * 0.12
