extends Control
## A little picture of a fish for the menus: body in the variety's colour, tail and fins in
## its accent colour, and its pattern (spots, stripes, half, fade). Fry are drawn smaller.

const FishData := preload("res://scripts/fish_data.gd")
const FishArt := preload("res://scripts/fish_art.gd")

var fish: Dictionary = {}


static func make(f: Dictionary, size: Vector2 = Vector2(58, 34)) -> Control:
	var icon := new()
	icon.fish = f
	icon.custom_minimum_size = size
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _draw() -> void:
	if fish.is_empty():
		return
	if FishArt.has_art(fish["species"]):
		_draw_sprite()
		_draw_sex()
		return
	var v := FishData.variety(fish["species"], fish.get("variety", ""))
	var body := Color(v["color"])
	var accent := Color(v["accent"])
	var s := 1.0 if FishData.is_adult(fish) else 0.65
	var c := size * 0.5 + Vector2(-size.x * 0.06, 0)
	var rx := size.x * 0.3 * s
	var ry := size.y * 0.3 * s
	if fish["species"] == "angelfish" or fish["species"] == "discus":
		ry *= 1.5
	# Tail: big and flowing for guppies, bettas and fancy goldfish.
	var fancy: bool = fish["species"] == "guppy" or fish["species"] == "betta" or (fish["species"] == "goldfish" and v["kind"] != "common")
	var tail_len := rx * (1.3 if fancy else 0.8)
	var tail_h := ry * (1.5 if fancy else 1.0)
	var tx := c.x + rx * 0.85
	draw_colored_polygon(PackedVector2Array([Vector2(tx, c.y), Vector2(tx + tail_len, c.y - tail_h), Vector2(tx + tail_len * 0.8, c.y), Vector2(tx + tail_len, c.y + tail_h)]), accent)
	# Dorsal fin.
	draw_colored_polygon(PackedVector2Array([Vector2(c.x - rx * 0.2, c.y - ry * 0.8), Vector2(c.x + rx * 0.5, c.y - ry * 1.5), Vector2(c.x + rx * 0.6, c.y - ry * 0.7)]), accent)
	# Body.
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, body)
	match v["pattern"]:
		"spots":
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(str(fish.get("variety", "")))
			for i in 6:
				var p := c + Vector2(rng.randf_range(-0.6, 0.6) * rx, rng.randf_range(-0.5, 0.5) * ry)
				draw_circle(p, ry * 0.18, accent)
		"stripes":
			for i in 3:
				var x := c.x - rx * 0.35 + i * rx * 0.35
				draw_line(Vector2(x, c.y - ry * 0.8), Vector2(x, c.y + ry * 0.8), accent, maxf(1.5, rx * 0.12))
		"half":
			var half := PackedVector2Array()
			for i in 13:
				var a := -PI * 0.5 + PI * i / 12.0
				half.append(c + Vector2(cos(a) * rx, sin(a) * ry))
			draw_colored_polygon(half, accent)
		"fade":
			var fade := PackedVector2Array()
			for i in 13:
				var a := -PI * 0.5 + PI * i / 12.0
				fade.append(c + Vector2(cos(a) * rx, sin(a) * ry))
			draw_colored_polygon(fade, Color(accent, 0.55))
	# Eye.
	draw_circle(c + Vector2(-rx * 0.55, -ry * 0.15), maxf(1.5, ry * 0.18), Color.WHITE)
	draw_circle(c + Vector2(-rx * 0.58, -ry * 0.15), maxf(1.0, ry * 0.09), Color.BLACK)
	_draw_sex()


## The guppy's own picture, fitted into the icon (smaller for fry).
func _draw_sprite() -> void:
	var fr := FishArt.frame(fish.get("variety", ""), fish["species"])
	var src: Rect2 = fr["rect"]
	var grown := 1.0 if FishData.is_adult(fish) else 0.6
	var fit := minf((size.x - 6.0) / src.size.x, size.y / src.size.y) * grown
	var dst_size := src.size * fit
	var dst := Rect2((size - dst_size) * 0.5 + Vector2(-3, 0), dst_size)
	draw_texture_rect_region(FishArt.sheet(fish["species"]), dst, src, fr["tint"])


func _draw_sex() -> void:
	var font := get_theme_default_font()
	var male: bool = fish.get("sex", "m") == "m"
	draw_string(font, Vector2(size.x - 13, 13), "♂" if male else "♀", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color("#7fc4ff") if male else Color("#ff8fc4"))
