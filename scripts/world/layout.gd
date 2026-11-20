extends RefCounted
## The floor plan. -Z is the street. Every wall tile (a "bay") is 2.5 m.
## The lot is a grid of bays. You start with the middle of it:
##   showroom   x -11.25..11.25, z -7.5..5     (front door in the middle of the front wall)
##   back room  x -11.25..11.25, z 5..12.5     (door through the divider at x 6.25..8.75)
## and can buy up to three plots: a west wing and an east wing (3 bays wide, both rooms
## grow sideways) and a rear extension (3 bays deep, the back room grows). The building
## always stays a rectangle: a wing bought after the rear extension covers that corner too.

const BAY := 2.5
const WALL_HEIGHT := 3.0
const Z0 := -7.5
const DIVIDER_Z := 5.0
const BASE_X0 := -11.25
const BASE_X1 := 11.25
const BASE_Z1 := 12.5
const WING := 7.5  # 3 bays
## Left edge of the front door bay and of the divider door bay (fixed as the shop grows).
const FRONT_DOOR_X := -1.25
const DIVIDER_DOOR_X := 6.25
## Everything you could ever own.
const LOT := Rect2(BASE_X0 - WING, Z0, (BASE_X1 - BASE_X0) + WING * 2.0, (BASE_Z1 + WING) - Z0)
## How far in from the wall line things may stand.
const WALL_MARGIN := 0.15

## Where customers appear and leave (on the pavement outside the front door).
const STREET_SPOT := Vector3(0.0, 0.0, -10.5)
const DOOR_INSIDE := Vector3(0.0, 0.0, -6.3)

## The building's current extent (changes as plots are bought).
static var x0 := BASE_X0
static var x1 := BASE_X1
static var z1 := BASE_Z1


## Set the extent from the plots owned ("west", "east", "back").
static func apply_plots(owned: Array) -> void:
	x0 = BASE_X0 - (WING if owned.has("west") else 0.0)
	x1 = BASE_X1 + (WING if owned.has("east") else 0.0)
	z1 = BASE_Z1 + (WING if owned.has("back") else 0.0)


## The area a plot adds, given what else is owned (for the for-sale markers).
static func plot_rect(id: String, owned: Array) -> Rect2:
	var wx0 := BASE_X0 - (WING if owned.has("west") else 0.0)
	var wx1 := BASE_X1 + (WING if owned.has("east") else 0.0)
	var wz1 := BASE_Z1 + (WING if owned.has("back") else 0.0)
	match id:
		"west":
			return Rect2(BASE_X0 - WING, Z0, WING, wz1 - Z0)
		"east":
			return Rect2(BASE_X1, Z0, WING, wz1 - Z0)
		_:
			return Rect2(wx0, BASE_Z1, wx1 - wx0, WING)


static func bays_x() -> int:
	return int(round((x1 - x0) / BAY))


static func show_bays() -> int:
	return int(round((DIVIDER_Z - Z0) / BAY))


static func back_bays() -> int:
	return int(round((z1 - DIVIDER_Z) / BAY))


static func front_door_bay() -> int:
	return int(round((FRONT_DOOR_X - x0) / BAY))


static func divider_door_bay() -> int:
	return int(round((DIVIDER_DOOR_X - x0) / BAY))


static func showroom() -> Rect2:
	return Rect2(x0, Z0, x1 - x0, DIVIDER_Z - Z0)


static func backroom() -> Rect2:
	return Rect2(x0, DIVIDER_Z, x1 - x0, z1 - DIVIDER_Z)


static func building() -> Rect2:
	return Rect2(x0, Z0, x1 - x0, z1 - Z0)


static func room_rect(room: String) -> Rect2:
	var r := showroom() if room == "show" else backroom()
	return r.grow(-WALL_MARGIN)


static func room_at(p: Vector2) -> String:
	if showroom().has_point(p):
		return "show"
	if backroom().has_point(p):
		return "back"
	return ""


## Areas kept clear so doors stay usable (x/z rects).
static func door_zones() -> Array[Rect2]:
	return [
		Rect2(FRONT_DOOR_X - 0.25, Z0, BAY + 0.5, 1.75),
		Rect2(DIVIDER_DOOR_X - 0.25, DIVIDER_Z - 1.5, BAY + 0.5, 3.0),
	]
