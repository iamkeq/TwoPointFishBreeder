extends "res://scripts/world/placeable.gd"

const WallAward := preload("res://scripts/world/wall_award.gd")
## A glass-fronted cabinet for the Hall of Fame that shows your fish show trophies: gold,
## silver and bronze for 1st, 2nd and 3rd, swirl statues from Grand Shows (see wall_award.gd). Three shelves of
## three; the world hands each cabinet its share of the trophies, best first (see main.gd).

const PER_CASE := 9
const SHELF_Y := [0.22, 0.8, 1.38]
const CUP_COLORS := [Color("#f2c440"), Color("#d4dbe3"), Color("#c07a3a")]
## Prestige a trophy adds to the Hall of Fame: 1st, 2nd, 3rd (doubled for a Grand Show).
const PRESTIGE := [8, 5, 3]

## The trophies on show here: entries of Game.awards.
var awards: Array = []
var _cups: Node3D


func _build_model() -> void:
	var size: Vector2 = def["size"]
	var w := size.x
	var d := size.y
	var h := float(def["height"])
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("#4a2c1a")
	wood.roughness = 0.6
	var felt := StandardMaterial3D.new()
	felt.albedo_color = Color("#6e1f2c")
	felt.roughness = 0.9
	_box(Vector3(w, 0.18, d), Vector3(0, 0.09, 0), wood)  # plinth
	_box(Vector3(w, 0.06, d), Vector3(0, h - 0.03, 0), wood)  # top
	_box(Vector3(w, h, 0.04), Vector3(0, h * 0.5, -d * 0.5 + 0.02), felt)  # back
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.05, h, d), Vector3(sx * (w * 0.5 - 0.025), h * 0.5, 0), wood)
	for y in SHELF_Y.slice(1):
		_box(Vector3(w - 0.1, 0.03, d - 0.06), Vector3(0, y - 0.015, 0), wood)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.8, 0.92, 1.0, 0.12)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic_specular = 1.0
	var pane := _box(Vector3(w - 0.1, h - 0.24, 0.02), Vector3(0, 0.18 + (h - 0.24) * 0.5, d * 0.5 - 0.02), glass)
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cups = Node3D.new()
	_cups.name = "Trophies"
	model.add_child(_cups)


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.position = pos
	m.material_override = mat
	model.add_child(m)
	return m


## Put these trophies on the shelves (at most PER_CASE).
func show_awards(list: Array) -> void:
	awards = list.slice(0, PER_CASE)
	if _cups == null:
		return
	for c in _cups.get_children():
		c.free()
	var w: float = def["size"].x
	for i in awards.size():
		var a: Dictionary = awards[i]
		var x := -w * 0.5 + w * (float(i % 3) + 0.5) / 3.0
		var t := WallAward.make_trophy(a, 0.52 if a.get("grand", false) else 0.48)
		t.position = Vector3(x, SHELF_Y[i / 3], 0.0)
		_cups.add_child(t)


static func award_prestige(a: Dictionary) -> int:
	return PRESTIGE[clampi(int(a.get("place", 1)), 1, 3) - 1] * (2 if a.get("grand", false) else 1)


## What this cabinet adds to the Hall of Fame's prestige.
func prestige() -> int:
	var p := 0
	for a in awards:
		p += award_prestige(a)
	return p


static func place_text(place: int) -> String:
	return ["1st", "2nd", "3rd"][clampi(place, 1, 3) - 1]


func info_text() -> String:
	if room() != "hall":
		return "Trophy cabinets only work in the Hall of Fame."
	if awards.is_empty():
		return "No trophies in here yet. Finish in the top 3 at a fish show to win one.\n(%d trophies fit in each cabinet.)" % PER_CASE
	var lines: Array[String] = ["Prestige +%d" % prestige()]
	for a in awards:
		lines.append("%s %s, %s: %s" % ["🏆" if int(a.get("place", 1)) == 1 else "•", place_text(int(a.get("place", 1))),
			a.get("title", "Fish Show"), a.get("fish", "")])
	return "\n".join(lines)
