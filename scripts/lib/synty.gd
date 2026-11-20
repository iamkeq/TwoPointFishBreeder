extends RefCounted
## Loads and places the Synty models the 3D shop is built from (Polygon Shops
## prefabs, plus the fish tank and fish from Polygon Office). Prefab colliders are
## removed: the shop adds its own simple boxes where the player needs to be stopped.

const SHOPS := "res://assets/Synty/PolygonShops/Prefabs/"
const MATERIALS := "res://assets/Synty/PolygonShops/Materials/"
const OFFICE := "res://assets/Synty/PolygonOffice/"
const CITY := "res://assets/Synty/PolygonCity/Prefabs/"
const PIRATES := "res://assets/PolygonPirates/Prefabs/"
const DUNGEON := "res://assets/PolygonDungeon/Prefabs/"

static var _scenes := {}
static var _office_body: StandardMaterial3D
static var _office_glass: StandardMaterial3D


static func _path(rel: String) -> String:
	if rel.begins_with("City/"):
		return CITY + rel.substr(5) + ".tscn"
	if rel.begins_with("Pirates/"):
		return PIRATES + rel.substr(8) + ".tscn"
	if rel.begins_with("Dungeon/"):
		return DUNGEON + rel.substr(8) + ".tscn"
	return SHOPS + rel + ".tscn"


## A fresh copy of a Polygon Shops prefab (path under Prefabs/, no extension), without colliders.
## A path starting "City/", "Pirates/" or "Dungeon/" is a prefab from that pack instead.
static func make(rel: String) -> Node3D:
	if not _scenes.has(rel):
		_scenes[rel] = load(_path(rel))
	var node: Node3D = _scenes[rel].instantiate()
	_strip(node)
	_sharpen(node)
	return node


## Make a prefab and put it in `parent` at `pos`, turned `yaw_deg` degrees about Y.
static func put(parent: Node, rel: String, pos: Vector3, yaw_deg: float = 0.0, scale: Vector3 = Vector3.ONE) -> Node3D:
	var node := make(rel)
	node.position = pos
	node.rotation_degrees.y = yaw_deg
	node.scale = scale
	parent.add_child(node)
	return node


static func _strip(node: Node) -> void:
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	for child in node.get_children():
		if child is CollisionObject3D or child is CollisionShape3D:
			node.remove_child(child)
			child.free()
		else:
			_strip(child)


## Bounding box of every visible mesh under `node`, in the node's parent space.
static func bounds(node: Node, xf: Transform3D = Transform3D.IDENTITY) -> AABB:
	var out := AABB()
	var first := true
	var t := xf
	if node is Node3D:
		t = xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null and (node as MeshInstance3D).visible:
		out = t * (node as MeshInstance3D).get_aabb()
		first = false
	for child in node.get_children():
		var b := bounds(child, t)
		if b.size != Vector3.ZERO:
			out = b if first else out.merge(b)
			first = false
	return out


## Scale `node` evenly so it is `height` metres tall, standing on y = 0 at its own origin.
static func fit_height(node: Node3D, height: float) -> void:
	var b := bounds(node)
	if b.size.y > 0.0:
		node.scale *= height / b.size.y


## Replace the material on every surface of every mesh under `node`.
static func paint(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, material)
	for child in node.get_children():
		paint(child, material)


## Multiply every surface's colour under `node` by `tint` (the texture shows through), so
## one model can stand in for differently coloured things. Copies are shared per material.
static var _tinted := {}


static func tint(node: Node, tint_color: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var m := mi.get_surface_override_material(s)
				if m == null:
					m = mi.mesh.surface_get_material(s)
				if m is BaseMaterial3D:
					var key := "%d|%s" % [m.get_instance_id(), tint_color.to_html()]
					if not _tinted.has(key):
						var copy := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
						copy.albedo_color = (m as BaseMaterial3D).albedo_color * tint_color
						_tinted[key] = copy
					mi.set_surface_override_material(s, _tinted[key])
	for child in node.get_children():
		tint(child, tint_color)


static func material(name: String) -> Material:
	return _sharpened(load(MATERIALS + name + ".tres"))


## A Synty material with its colour multiplied by `tint` (to warm up a plain surface).
static func tinted(name: String, tint: Color) -> Material:
	var m: StandardMaterial3D = (load(MATERIALS + name + ".tres") as StandardMaterial3D).duplicate()
	m.albedo_color = tint
	return _sharpened(m)


## Anisotropic filtering on every material under `node`, so floors and walls seen at a
## low angle stay crisp instead of shimmering as you walk. Materials are shared, so each
## is only changed once.
static func _sharpen(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			_sharpened(mi.mesh.surface_get_material(s))
			_sharpened(mi.get_surface_override_material(s))
	for child in node.get_children():
		_sharpen(child)


static func _sharpened(m: Material) -> Material:
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		if b.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
			b.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## A box the player (and nothing else) bumps into, with no picture.
static func solid(parent: Node, pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	return body


# --- Polygon Office fish tank and fish ----------------------------------------------

## The tank model (cabinet, glass and water surface) with its texture applied.
## Dimensions in metres: about 1.29 wide, 0.67 deep, 1.34 tall.
static func office_tank() -> Node3D:
	var node: Node3D = load(OFFICE + "Models/SM_Prop_Fishtank_01.fbx").instantiate()
	_strip(node)
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var glassy := String(mi.name).contains("Glass") or String(mi.name).contains("FX")
		mi.material_override = _glass_material() if glassy else _body_material()
		if not glassy:
			mi.mesh = _empty_tank_mesh(mi.mesh)
	var player := node.find_child("AnimationPlayer", true, false)
	if player != null:
		player.free()
	return node


## The model has a little baked-in scene inside the glass (torii, kelp, driftwood). Drop every
## triangle inside the water space so only the cabinet, frame and floor remain, and the tank
## can show the decor you place instead. (Model metres; the tank is 1.29 x 1.34 x 0.67.)
static var _empty_meshes := {}
const INSIDE_MIN := Vector3(-0.575, 0.69, -0.282)
const INSIDE_MAX := Vector3(0.575, 1.24, 0.282)


static func _empty_tank_mesh(mesh: Mesh) -> Mesh:
	if _empty_meshes.has(mesh):
		return _empty_meshes[mesh]
	var out := ArrayMesh.new()
	var src := mesh as ArrayMesh
	for surface in src.get_surface_count():
		var mdt := MeshDataTool.new()
		if mdt.create_from_surface(src, surface) != OK:
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for face in mdt.get_face_count():
			var ids: Array[int] = [mdt.get_face_vertex(face, 0), mdt.get_face_vertex(face, 1), mdt.get_face_vertex(face, 2)]
			var centre := (mdt.get_vertex(ids[0]) + mdt.get_vertex(ids[1]) + mdt.get_vertex(ids[2])) / 3.0
			if AABB(INSIDE_MIN, INSIDE_MAX - INSIDE_MIN).has_point(centre):
				continue
			for id in ids:
				st.set_normal(mdt.get_vertex_normal(id))
				st.set_uv(mdt.get_vertex_uv(id))
				st.add_vertex(mdt.get_vertex(id))
		st.commit(out)
	_empty_meshes[mesh] = out
	return out


## Polygon Office fish (one model, about 17 cm long, nose towards -Z) in `color`.
static func fish(color: Color) -> Node3D:
	var node: Node3D = load(OFFICE + "Models/SM_Prop_Fish_01.fbx").instantiate()
	_strip(node)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	paint(node, mat)
	var player := node.find_child("AnimationPlayer", true, false)
	if player != null:
		player.free()
	return node


static func _body_material() -> StandardMaterial3D:
	if _office_body == null:
		_office_body = StandardMaterial3D.new()
		_office_body.albedo_color = Color("#93602f")  # warm wood for the cabinet
		_office_body.roughness = 1.0
	return _office_body


static func _glass_material() -> StandardMaterial3D:
	if _office_glass == null:
		_office_glass = StandardMaterial3D.new()
		_office_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_office_glass.albedo_color = Color(0.55, 0.82, 0.92, 0.12)
		_office_glass.roughness = 0.2
		_office_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _office_glass
