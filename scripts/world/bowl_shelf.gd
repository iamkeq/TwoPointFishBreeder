extends "res://scripts/world/placeable.gd"
## A shelf of fish bowls for the Hall of Fame: where prize-winning fish go when they retire.
## Two shelves of three bowls, one fish each. Retired fish never age, never need feeding and
## the bowls never need cleaning. They can't come out again, only be archived (see Game).

const FishSwim := preload("res://scripts/world/fish_swim.gd")
const FishData := preload("res://scripts/fish_data.gd")

const SHELF_Y := [0.42, 1.02]
const BOWL_R := 0.15

## The retired fish here, in bowl order.
var retired: Array = []
var _bowls: Node3D


func capacity() -> int:
	return int(def["capacity"])


func has_room() -> bool:
	return retired.size() < capacity()


func _build_model() -> void:
	var size: Vector2 = def["size"]
	var w := size.x
	var d := size.y
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("#6b4428")
	wood.roughness = 0.6
	_box(Vector3(w, 0.04, d), Vector3(0, 0.02, 0), wood)
	for y in SHELF_Y:
		_box(Vector3(w, 0.04, d), Vector3(0, y - 0.02, 0), wood)
	_box(Vector3(w, 0.04, d), Vector3(0, float(def["height"]) - 0.02, 0), wood)
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.04, float(def["height"]), d), Vector3(sx * (w * 0.5 - 0.02), float(def["height"]) * 0.5, 0), wood)
	_box(Vector3(w, float(def["height"]), 0.02), Vector3(0, float(def["height"]) * 0.5, -d * 0.5 + 0.01), wood)
	_bowls = Node3D.new()
	_bowls.name = "Bowls"
	model.add_child(_bowls)
	if not ghost:
		_refresh_bowls()


func _box(s: Vector3, at: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = s
	mi.mesh = b
	mi.position = at
	mi.material_override = m
	model.add_child(mi)


func _bowl_spot(i: int) -> Vector3:
	var w: float = def["size"].x
	return Vector3(-w * 0.5 + w * (float(i % 3) + 0.5) / 3.0, SHELF_Y[i / 3] + BOWL_R * 0.85, 0.02)


## A glass bowl for every place on the shelf, with water and a fish where one has retired.
func _refresh_bowls() -> void:
	for c in _bowls.get_children():
		c.free()
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.85, 0.95, 1.0, 0.16)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.45, 0.78, 0.95, 0.22)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.1
	for i in capacity():
		var at := _bowl_spot(i)
		var bowl := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = BOWL_R
		sm.height = BOWL_R * 1.7
		bowl.mesh = sm
		bowl.material_override = glass
		bowl.position = at
		bowl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_bowls.add_child(bowl)
		if i >= retired.size():
			continue
		var wm := MeshInstance3D.new()
		var ws := SphereMesh.new()
		ws.radius = BOWL_R * 0.92
		ws.height = BOWL_R * 1.4
		wm.mesh = ws
		wm.material_override = water
		wm.position = at - Vector3(0, BOWL_R * 0.1, 0)
		wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_bowls.add_child(wm)
		# The fish swims round its bowl, at about half its tank size.
		var holder := Node3D.new()
		holder.position = at
		holder.scale = Vector3.ONE * 0.5
		_bowls.add_child(holder)
		var swimmer := FishSwim.new()
		holder.add_child(swimmer)
		swimmer.setup(retired[i], AABB(Vector3(-0.12, -0.1, -0.08), Vector3(0.24, 0.16, 0.16)))


func add_retired(f: Dictionary) -> bool:
	if not has_room():
		return false
	retired.append(f)
	if _bowls != null:
		_refresh_bowls()
	return true


## Take a retired fish off the shelf (to the archive); returns it, or {}.
func take_retired(id: int) -> Dictionary:
	for i in retired.size():
		if int(retired[i]["id"]) == id:
			var f: Dictionary = retired[i]
			retired.remove_at(i)
			_refresh_bowls()
			return f
	return {}


## What its fish add to the Hall of Fame's prestige: stars, 4 per ribbon, 5 for retiring.
func prestige() -> int:
	if room() != "hall":
		return 0
	var p := 0
	for f in retired:
		p += int(f["stars"]) + 4 * int(f.get("ribbon", 0)) + 5
	return p


func refund() -> int:
	return int(def["cost"]) / 2


func info_text() -> String:
	var lines: Array[String] = ["Bowls: %d / %d" % [retired.size(), capacity()]]
	lines.append("Retired prize-winners live here for good: they never grow old, never need feeding and the bowls never need cleaning.")
	if retired.is_empty():
		lines.append("Retire a show winner from its close-up (click its picture).")
	else:
		lines.append("Prestige +%d" % prestige())
	return "\n".join(lines)
