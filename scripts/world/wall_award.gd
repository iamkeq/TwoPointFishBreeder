extends RefCounted
## Show awards that hang on the walls (built from simple shapes, front facing +Z):
##   rosette      2nd or 3rd place (red or yellow; bigger from a Grand Show)
##   certificate  a 1st place: a framed certificate with a gold seal and a blue rosette
##   plaque       a Grand Show win: a wooden shield with a gold plate and star

const ROSETTE_COLORS := [Color("#2f62d0"), Color("#d0342f"), Color("#e8c23a")]
const GOLD := Color("#e9bf3c")


static func kind(a: Dictionary) -> String:
	var place := int(a.get("place", 1))
	if place == 1:
		return "plaque" if a.get("grand", false) else "certificate"
	return "rosette"


static func make(a: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Award"
	var place := clampi(int(a.get("place", 1)), 1, 3)
	match kind(a):
		"plaque":
			_box(root, Vector3(0.42, 0.52, 0.04), Vector3(0, 0, 0.02), _mat(Color("#5a3420"), 0.0, 0.5))
			_box(root, Vector3(0.34, 0.44, 0.045), Vector3(0, 0, 0.022), _mat(Color("#7a4a2c"), 0.0, 0.45))
			_box(root, Vector3(0.28, 0.1, 0.05), Vector3(0, -0.12, 0.03), _mat(GOLD, 0.85, 0.25))
			_disc(root, 0.08, 0.02, Vector3(0, 0.08, 0.05), _mat(GOLD, 0.85, 0.25), 5)
		"certificate":
			_box(root, Vector3(0.46, 0.34, 0.03), Vector3(0, 0, 0.015), _mat(Color("#2b1c12"), 0.0, 0.5))
			_box(root, Vector3(0.4, 0.28, 0.035), Vector3(0, 0, 0.018), _mat(Color("#f4ecd6"), 0.0, 0.9))
			for i in 3:  # lines of writing
				_box(root, Vector3(0.26 - i * 0.04, 0.012, 0.037), Vector3(-0.03, 0.08 - i * 0.05, 0.02), _mat(Color("#8a7a66"), 0.0, 0.9))
			_rosette(root, ROSETTE_COLORS[0], Vector3(0.13, -0.07, 0.04), 0.55)
		_:
			_rosette(root, ROSETTE_COLORS[place - 1], Vector3.ZERO, 1.3 if a.get("grand", false) else 1.0)
	return root


static func _rosette(parent: Node3D, color: Color, at: Vector3, s: float) -> void:
	var r := Node3D.new()
	r.position = at
	r.scale = Vector3.ONE * s
	parent.add_child(r)
	var ribbon := _mat(color, 0.0, 0.7)
	for side in [-1.0, 1.0]:
		var tail := _box(r, Vector3(0.06, 0.2, 0.01), Vector3(side * 0.035, -0.12, 0.01), ribbon)
		tail.rotation.z = side * 0.25
	_disc(r, 0.11, 0.02, Vector3(0, 0, 0.02), ribbon, 14)
	_disc(r, 0.065, 0.025, Vector3(0, 0, 0.03), _mat(color.lightened(0.35), 0.0, 0.6))
	_disc(r, 0.035, 0.03, Vector3(0, 0, 0.035), _mat(GOLD, 0.8, 0.3))


static func _mat(c: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


static func _box(parent: Node3D, size: Vector3, at: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = at
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A flat disc facing +Z.
static func _disc(parent: Node3D, radius: float, depth: float, at: Vector3, m: Material, segments: int = 24) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = depth
	c.radial_segments = segments
	mi.mesh = c
	mi.rotation.x = PI * 0.5
	mi.position = at
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
