extends RefCounted
## Fish pictures, one per variety, facing right.
## Guppies: the hand-drawn sheet from the guppy breeding game (assets/fish/guppy_sheet.png);
## varieties without their own picture reuse a close one with a tint, as the guppy game does.
## Goldfish: assets/fish/goldfish_sheet.png, cut-out Wikimedia Commons photos packed by
## tools/build_goldfish_photos.py (credits in assets/fish/CREDITS.md).
## Other species have no sprites yet and are drawn by fish_icon.gd / shown as the 3D model.

const SHEET_PATH := "res://assets/fish/guppy_sheet.png"
const GOLDFISH_SHEET_PATH := "res://assets/fish/goldfish_sheet.png"
const GoldfishCells := preload("res://scripts/goldfish_cells.gd")
## Metres per sprite pixel in the tanks (a guppy picture is ~80 px, a goldfish photo ~190 px).
const PIXEL_SIZE := {"guppy": 0.002, "goldfish": 0.00125}

## variety -> [x, y, w, h] on the sheet.
const GUPPY := {
	"normal": [24, 474, 85, 42], "red": [123, 469, 79, 46], "blue": [218, 469, 77, 46],
	"yellow": [311, 469, 78, 45], "orange": [400, 469, 76, 46], "black": [487, 466, 77, 48],
	"white": [583, 469, 78, 47], "albino": [676, 469, 73, 45], "gold": [761, 467, 75, 47],
	"koi": [849, 471, 75, 45], "dalmatian": [937, 468, 78, 46], "mosaic": [1027, 465, 78, 50],
	"tuxedo": [25, 561, 82, 45], "half_black": [120, 560, 80, 45], "pastel": [211, 560, 78, 44],
	"neon": [306, 559, 76, 45], "leopard": [395, 559, 78, 46], "snakeskin": [486, 558, 77, 48],
	"glass": [578, 560, 76, 45], "sunset": [672, 559, 74, 46], "grass": [759, 559, 74, 46],
	"purple": [846, 559, 76, 46], "pink": [942, 559, 74, 46], "turquoise": [1027, 559, 76, 46],
}
## variety -> [stand-in variety, tint]
const STAND_INS := {
	"lavender": ["white", "#C9B4F2"], "platinum": ["white", "#E4ECF5"], "galaxy": ["neon", "#7068F0"],
	"dragon": ["half_black", "#FF8A3D"], "phoenix": ["sunset", "#FFB347"], "calico": ["koi", "#F2D9B8"],
	"midnight": ["tuxedo", "#5A6FD8"], "opal": ["pastel", "#9FE8E0"], "tiger": ["leopard", "#FF9A3C"],
}

static var _sheets := {}


static func has_art(species: String) -> bool:
	return species == "guppy" or species == "goldfish"


static func sheet(species: String = "guppy") -> Texture2D:
	if not _sheets.has(species):
		_sheets[species] = load(GOLDFISH_SHEET_PATH if species == "goldfish" else SHEET_PATH)
	return _sheets[species]


## {"rect": Rect2, "tint": Color} for a variety's picture.
static func frame(variety: String, species: String = "guppy") -> Dictionary:
	if species == "goldfish":
		var g: Array = GoldfishCells.CELLS.get(variety, GoldfishCells.CELLS["common"])
		return {"rect": Rect2(g[0], g[1], g[2], g[3]), "tint": Color.WHITE}
	var tint := Color.WHITE
	var look := variety
	if STAND_INS.has(variety):
		look = STAND_INS[variety][0]
		tint = Color(STAND_INS[variety][1])
	var r: Array = GUPPY.get(look, GUPPY["normal"])
	return {"rect": Rect2(r[0], r[1], r[2], r[3]), "tint": tint}
