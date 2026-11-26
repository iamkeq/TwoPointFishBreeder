extends RefCounted
## Show awards that hang on the walls (built from simple shapes, front facing +Z):
##   rosette      2nd or 3rd place (red or yellow; bigger from a Grand Show)
##   certificate  a 1st place: a framed certificate with a gold seal and a blue rosette
##   plaque       a Grand Show win: a wooden shield with a gold plate and star

const ROSETTE_COLORS := [Color("#2f62d0"), Color("#d0342f"), Color("#e8c23a")]
const GOLD := Color("#e9bf3c")
## Collision layer of the click targets on the awards (picked apart from placeables).
const PICK_LAYER := 8
const PLACES := ["1st", "2nd", "3rd"]
const PLACE_WORDS := ["First Place", "Second Place", "Third Place"]


static func title(a: Dictionary) -> String:
	return "%s, %s" % [a.get("title", "Fish Show"), PLACE_WORDS[clampi(int(a.get("place", 1)), 1, 3) - 1]]


static func date(a: Dictionary) -> String:
	return Game.date_of(int(a.get("day", 0))) if int(a.get("day", 0)) > 0 else ""


static func kind(a: Dictionary) -> String:
	var place := int(a.get("place", 1))
	if place == 1:
		return "plaque" if a.get("grand", false) else "certificate"
	return "rosette"


## The award as a model, with its writing. `clickable` adds a click target (on the wall).
static func make(a: Dictionary, clickable: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "Award"
	root.set_meta("award", a)
	var place := clampi(int(a.get("place", 1)), 1, 3)
	var fish: String = a.get("fish", "")
	var size := Vector3(0.3, 0.42, 0.06)
	match kind(a):
		"plaque":
			size = Vector3(0.42, 0.52, 0.06)
			_box(root, Vector3(0.42, 0.52, 0.04), Vector3(0, 0, 0.02), _mat(Color("#5a3420"), 0.0, 0.5))
			_box(root, Vector3(0.34, 0.44, 0.045), Vector3(0, 0, 0.022), _mat(Color("#7a4a2c"), 0.0, 0.45))
			_box(root, Vector3(0.3, 0.13, 0.05), Vector3(0, -0.13, 0.03), _mat(GOLD, 0.85, 0.25))
			_disc(root, 0.07, 0.02, Vector3(0, 0.12, 0.05), _mat(GOLD, 0.85, 0.25), 5)
			_text(root, "GRAND SHOW\nCHAMPION", Vector3(0, 0.02, 0.046), 50, GOLD.lightened(0.2), 0.3)
			_text(root, "%s\n%s\n%s" % [a.get("title", "Grand Show"), fish, date(a)], Vector3(0, -0.13, 0.056), 38, Color("#3a2410"), 0.28)
		"certificate":
			size = Vector3(0.46, 0.34, 0.06)
			_box(root, Vector3(0.46, 0.34, 0.03), Vector3(0, 0, 0.015), _mat(Color("#2b1c12"), 0.0, 0.5))
			_box(root, Vector3(0.4, 0.28, 0.035), Vector3(0, 0, 0.018), _mat(Color("#f4ecd6"), 0.0, 0.9))
			_text(root, "Certificate of Excellence", Vector3(0, 0.105, 0.037), 40, Color("#6a1f1f"), 0.38)
			_text(root, "First Place", Vector3(0, 0.055, 0.037), 54, Color("#2a2a2a"), 0.38)
			_text(root, "%s\n%s\n%s" % [a.get("title", "Fish Show"), fish, date(a)], Vector3(-0.045, -0.05, 0.037), 36, Color("#3a3a3a"), 0.28)
			_rosette(root, ROSETTE_COLORS[0], Vector3(0.14, -0.07, 0.04), 0.5)
		_:
			var s := 1.3 if a.get("grand", false) else 1.0
			size *= s
			_rosette(root, ROSETTE_COLORS[place - 1], Vector3.ZERO, s)
			_text(root, PLACES[place - 1], Vector3(0, 0, 0.055 * s), 40, Color("#3a2410"), 0.06)
	if clickable:
		var body := StaticBody3D.new()
		body.collision_layer = PICK_LAYER
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		shape.position = Vector3(0, -0.02, size.z * 0.5)
		body.add_child(shape)
		root.add_child(body)
	return root


## Flat writing on the award's face (+Z), wrapped to `width` metres.
static func _text(parent: Node3D, t: String, at: Vector3, font: int, color: Color, width: float) -> Label3D:
	var l := Label3D.new()
	l.text = t
	l.position = at
	l.pixel_size = 0.0004
	l.font_size = font
	l.outline_size = 0
	l.modulate = color
	l.double_sided = false
	l.shaded = false
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.width = width / l.pixel_size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.render_priority = 1
	parent.add_child(l)
	return l


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
