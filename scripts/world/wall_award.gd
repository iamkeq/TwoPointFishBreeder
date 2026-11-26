extends RefCounted
## Show awards, drawn from the pixel-art award sheet (assets/awards/award_NN.png, cut from
## G:/Game Ideas/_shared-assets/awards/show-awards-pixel). The metal tells the placing
## (gold 1st, silver 2nd, bronze 3rd) and the fish on it matches the winner's species:
##   on the wall      goldfish plaques, guppy rosettes, betta ovals, medals for the rest;
##                    a shield for any Grand Show placing
##   in the cabinet   fish-on-cup trophies and statues; swirl statues from Grand Shows

const SPRITE := "res://assets/awards/award_%02d.png"
## [1st, 2nd, 3rd] sprite numbers.
const WALL := {"goldfish": [3, 2, 1], "guppy": [33, 32, 31], "betta": [15, 14, 13], "other": [30, 29, 28]}
const WALL_GRAND := [6, 5, 4]
const CABINET := {"goldfish": [19, 8, 7], "guppy": [27, 20, 16], "betta": [24, 23, 22], "other": [21, 17, 16]}
const CABINET_GRAND := [42, 41, 40]
## Collision layer of the click targets on the awards (picked apart from placeables).
const PICK_LAYER := 8
const PLACES := ["1st", "2nd", "3rd"]
const PLACE_WORDS := ["First Place", "Second Place", "Third Place"]

static var _textures := {}


static func place_of(a: Dictionary) -> int:
	return clampi(int(a.get("place", 1)), 1, 3)


## The winner's species (older awards only kept the fish's name).
static func species(a: Dictionary) -> String:
	var sp: String = a.get("species", "")
	if sp == "":
		var fish: String = a.get("fish", "")
		for s in ["goldfish", "guppy", "betta"]:
			if fish.to_lower().contains(s):
				sp = s
	return sp if WALL.has(sp) else "other"


static func kind(a: Dictionary) -> String:
	if a.get("grand", false):
		return "shield"
	return {"goldfish": "plaque", "guppy": "rosette", "betta": "oval", "other": "medal"}[species(a)]


static func kind_name(a: Dictionary) -> String:
	var metal: String = ["Gold", "Silver", "Bronze"][place_of(a) - 1]
	return "%s %s" % [metal, {"shield": "Grand Show shield", "plaque": "plaque", "rosette": "rosette",
		"oval": "oval plaque", "medal": "medal"}[kind(a)]]


static func title(a: Dictionary) -> String:
	return "%s, %s" % [a.get("title", "Fish Show"), PLACE_WORDS[place_of(a) - 1]]


static func date(a: Dictionary) -> String:
	return Game.date_of(int(a.get("day", 0))) if int(a.get("day", 0)) > 0 else ""


static func wall_sprite(a: Dictionary) -> int:
	return (WALL_GRAND if a.get("grand", false) else WALL[species(a)])[place_of(a) - 1]


static func cabinet_sprite(a: Dictionary) -> int:
	return (CABINET_GRAND if a.get("grand", false) else CABINET[species(a)])[place_of(a) - 1]


## The sprite as a texture with mipmaps (so it stays clean when small and far away).
static func texture(n: int) -> Texture2D:
	if not _textures.has(n):
		var src: Texture2D = load(SPRITE % n)
		var img := src.get_image()
		if img.is_compressed():
			img.decompress()
		img.generate_mipmaps()
		_textures[n] = ImageTexture.create_from_image(img)
	return _textures[n]


## A flat sprite facing +Z, `size` metres on its longest side, centred on the origin.
static func _sprite(n: int, size: float) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = texture(n)
	s.pixel_size = size / float(maxi(s.texture.get_width(), s.texture.get_height()))
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = true
	s.double_sided = false
	return s


## The award that hangs on a wall. `clickable` adds a click target.
static func make(a: Dictionary, clickable: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "Award"
	root.set_meta("award", a)
	var spr := _sprite(wall_sprite(a), 0.5 if a.get("grand", false) else 0.42)
	spr.position.z = 0.02
	root.add_child(spr)
	if clickable:
		var body := StaticBody3D.new()
		body.collision_layer = PICK_LAYER
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var px: Vector2 = Vector2(spr.texture.get_size()) * spr.pixel_size
		box.size = Vector3(px.x, px.y, 0.06)
		shape.shape = box
		shape.position.z = 0.03
		body.add_child(shape)
		root.add_child(body)
	return root


## The trophy for a cabinet shelf, standing on its base (origin at the bottom), `height` tall.
static func make_trophy(a: Dictionary, height: float) -> Sprite3D:
	var spr := _sprite(cabinet_sprite(a), height)
	spr.offset = Vector2(0, spr.texture.get_height() * 0.5)
	return spr
