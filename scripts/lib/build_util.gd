extends RefCounted
## Small helpers for the 3D shop. (The models themselves come from Synty: see synty.gd.)

const Synty := preload("res://scripts/lib/synty.gd")
## Synty's blank sign strip (2.03 x 0.41 m, facing +Z), used as the plate behind sign text.
const PLATE := "Signs/SM_Sign_Text_Backing_01"
const PLATE_SIZE := Vector2(2.028, 0.415)
const SIGN_TEXT := Color("#3b2a1c")


## A text label that always faces the player (or fixed, facing +Z, if not billboard).
static func label(parent: Node, text: String, pos: Vector3, pixel_size: float = 0.004, billboard: bool = true) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.pixel_size = pixel_size
	l.font_size = 64
	l.outline_size = 12
	l.modulate = Color("#fffaf0")
	l.outline_modulate = Color("#3d3a36")
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(l)
	return l


## A name sign: `text` on a Synty sign plate, `height` metres tall, sized to fit the text,
## standing at `pos` and facing +Z turned by `yaw_deg`. Mount it on a wall or the side of a
## tank. The text is the child named "Text" (a Label3D), so it can be changed later.
static func sign(parent: Node, text: String, pos: Vector3, yaw_deg: float = 0.0, height: float = 0.1) -> Node3D:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation_degrees.y = yaw_deg
	parent.add_child(holder)
	var plate := Synty.make(PLATE)
	holder.add_child(plate)
	var l := Label3D.new()
	l.name = "Text"
	l.font_size = 64
	l.outline_size = 0
	l.modulate = SIGN_TEXT
	l.pixel_size = height * 0.62 / 64.0
	l.position = Vector3(0, 0, 0.02)
	l.double_sided = false
	holder.add_child(l)
	set_sign_text(holder, text, height)
	return holder


## Change a sign's words; the plate grows or shrinks to fit them.
static func set_sign_text(holder: Node3D, text: String, height: float = -1.0) -> void:
	var l := holder.get_node("Text") as Label3D
	l.text = text
	var plate := holder.get_child(0) as Node3D
	if height < 0.0:
		height = plate.scale.y * PLATE_SIZE.y
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x * l.pixel_size + height * 0.8
	plate.scale = Vector3(width / PLATE_SIZE.x, height / PLATE_SIZE.y, 1.0)
