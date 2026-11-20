extends StaticBody3D
## Anything built in the shop: a tank, shelf, counter or piece of decor. Occupies a
## rectangle of floor (its footprint) and can be moved, turned in quarter turns and sold.
## The front of every model faces local +Z: that's where customers stand to look at it.
## A "ghost" copy (no collision, see-through) follows the mouse while placing.

const Data := preload("res://scripts/data.gd")
const Synty := preload("res://scripts/lib/synty.gd")
const L := preload("res://scripts/world/layout.gd")

## Layer 1: blocks people (navigation is baked from it). Layer 2: clickable.
const LAYER_SOLID := 1
const LAYER_PICK := 2

var item_id := ""
var def: Dictionary = {}
var rot := 0
var ghost := false
## The main scene (for appeal, the counter and so on); set by the world.
var world: Node
var model: Node3D

var _select_mark: MeshInstance3D
var _ghost_ok: StandardMaterial3D
var _ghost_bad: StandardMaterial3D


func setup(id: String, p_ghost: bool = false) -> void:
	item_id = id
	def = Data.ITEMS[id]
	ghost = p_ghost
	name = id
	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	_build_model()
	if ghost:
		collision_layer = 0
		collision_mask = 0
		_ghost_ok = _ghost_material(Color(0.3, 1.0, 0.5, 0.45))
		_ghost_bad = _ghost_material(Color(1.0, 0.3, 0.25, 0.45))
		set_valid(true)
	else:
		collision_mask = 0
		collision_layer = LAYER_PICK if def.get("walkable", false) else (LAYER_SOLID | LAYER_PICK)
		var size: Vector2 = def["size"]
		var h := float(def.get("height", 1.0))
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(size.x, maxf(h, 0.1) if not def.get("walkable", false) else 0.05, size.y)
		shape.shape = box
		shape.position.y = box.size.y * 0.5
		add_child(shape)
	_after_setup()


## Kinds override this to add their own bits (fish, stock, signs).
func _after_setup() -> void:
	pass


func display_name() -> String:
	return def["name"]


## Text for the info panel.
func info_text() -> String:
	return ""


func size2() -> Vector2:
	var s: Vector2 = def["size"]
	return Vector2(s.y, s.x) if rot % 2 == 1 else s


func rect_at(p: Vector3) -> Rect2:
	var s := size2()
	return Rect2(Vector2(p.x, p.z) - s * 0.5, s)


func rect() -> Rect2:
	return rect_at(position)


func set_rot(r: int) -> void:
	rot = posmod(r, 4)
	rotation.y = -rot * PI * 0.5


func room() -> String:
	return L.room_at(Vector2(position.x, position.z))


## World direction the front faces.
func front() -> Vector3:
	return global_transform.basis.z.normalized()


## Where a customer stands to look at this.
func visit_point() -> Vector3:
	var depth: float = (def["size"] as Vector2).y
	return global_position + front() * (depth * 0.5 + 0.6)


func set_valid(ok: bool) -> void:
	_paint_ghost(model, _ghost_ok if ok else _ghost_bad)


func set_selected(on: bool) -> void:
	if on and _select_mark == null:
		_select_mark = MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = (def["size"] as Vector2) + Vector2(0.3, 0.3)
		_select_mark.mesh = plane
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1.0, 0.85, 0.2, 0.45)
		_select_mark.material_override = m
		_select_mark.position.y = 0.03
		add_child(_select_mark)
	if _select_mark != null:
		_select_mark.visible = on


## What a removed object gives back.
func refund() -> int:
	return int(def["cost"]) / 2


## Called when sold or moved away from the shop: hand back anything inside.
func on_removed() -> void:
	pass


func _paint_ghost(node: Node, mat: Material) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).material_override = mat
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in node.get_children():
		_paint_ghost(c, mat)


func _ghost_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.no_depth_test = false
	return m


# --- Models ---------------------------------------------------------------------------

func _build_model() -> void:
	var size: Vector2 = def["size"]
	match item_id:
		"plant":
			var pot := Synty.put(model, "Props/SM_Prop_Planter_Vase_01", Vector3.ZERO, 0.0, Vector3(0.55, 0.55, 0.55))
			pot.name = "Pot"
			Synty.put(model, "Environments/SM_Env_Plant_01", Vector3(0, 0.5, 0), 0.0, Vector3(0.45, 0.9, 0.45))
		"rug":
			var rug := Synty.make("Buildings/SM_Bld_Base_Floor_01")
			model.add_child(rug)
			Synty.paint(rug, Synty.material("Building_Mats/PolygonShops_Mat_Carpet_01_mat"))
			fit(rug, size, 0.02, true)
			rug.position.y = 0.012
		_:
			if def.has("model"):
				var node := Synty.make(def["model"])
				model.add_child(node)
				fit(node, size)
				if item_id == "counter":
					var top := Synty.bounds(model).end.y
					Synty.put(model, "Props/SM_Prop_Shop_Cash_Register_02", Vector3(0.55, top, -0.1), 180.0)
					Synty.put(model, "Props/SM_Prop_Shop_Payment_Terminal_01", Vector3(-0.2, top, 0.15), 180.0)


## Scale `node` evenly to fit inside `size` (x by z) and stand it centred on the origin.
## `stretch`: fill the footprint exactly instead (flat things like rugs).
static func fit(node: Node3D, size: Vector2, height: float = -1.0, stretch: bool = false) -> void:
	node.scale = Vector3.ONE
	node.position = Vector3.ZERO
	var b := Synty.bounds(node)
	if b.size.x <= 0.0 or b.size.z <= 0.0:
		return
	var s := Vector3.ONE * minf(size.x / b.size.x, size.y / b.size.z)
	if stretch:
		s = Vector3(size.x / b.size.x, 1.0 if height < 0.0 or b.size.y <= 0.0 else height / b.size.y, size.y / b.size.z)
	node.scale = s
	node.position = Vector3(-(b.position.x + b.size.x * 0.5) * s.x, -b.position.y * s.y, -(b.position.z + b.size.z * 0.5) * s.z)
