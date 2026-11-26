extends Node3D
## The shop building from Synty Polygon Shops tiles (floors, walls, doors, windows), the
## for-sale plots you can expand into, and the surroundings (street, neighbours, fence,
## alleys, a park) from Polygon City. No ceiling: the camera looks down from above.
## Walls facing the camera drop to a low stub (like a cut-away doll's house), so you can
## always see inside; see update_cutaway(). rebuild() redoes the building after a plot
## is bought; the surroundings are built once, clear of the whole lot.

const Synty := preload("res://scripts/lib/synty.gd")
const BuildUtil := preload("res://scripts/lib/build_util.gd")
const WallAward := preload("res://scripts/world/wall_award.gd")
const L := preload("res://scripts/world/layout.gd")
const Data := preload("res://scripts/data.gd")

const WALL_MATERIAL := "Building_Mats/PolygonShops_Mat_Base_Blank_01_mat"
const SHOW_FLOOR_MATERIAL := "Building_Mats/PolygonShops_Mat_Base_Wood_02_mat"
const BACK_FLOOR_MATERIAL := "Building_Mats/PolygonShops_Mat_Tile_03_mat"
const TRIM_MATERIAL := "Building_Mats/PolygonShops_Mat_Base_Wood_01_mat"
const SHOW_PAINT := Color(0.78, 0.93, 0.95)  # pale aqua for the showroom
const BACK_PAINT := Color(1.0, 0.92, 0.78)  # warm cream for the back room
const HALL_PAINT := Color(0.62, 0.22, 0.27)  # deep red for the Hall of Fame
const HALL_FLOOR_MATERIAL := "Building_Mats/PolygonShops_Mat_Base_Carpet_01_mat"
## Height of the stub left when a wall is cut away.
const STUB := 0.35

## Each wall run: {"normal": Vector3 (outwards, horizontal), "full": [Node3D], "stub": [Node3D]}.
var _walls: Array = []
var _cut_state := {}
var _outside_root: Node3D
var _structure: Node3D
var _plot_root: Node3D
## Wall group of the Hall of Fame's front wall (for its sign), -1 without a hall.
var _hall_front := -1
## Wall groups the show awards hang on: the divider (showroom side) and the hall's back
## and east walls (-1 without a hall).
var _divider_group := -1
var _east_show_group := -1
var _west_group := -1
var _hall_back := -1
var _hall_east := -1
var _award_nodes: Array = []
## Where the awards in the showroom hang (they add appeal to tanks nearby).
var showroom_award_points: Array[Vector3] = []


## Builds the surroundings once and the building itself.
func build() -> void:
	_outside_root = Node3D.new()
	_outside_root.name = "Outside"
	add_child(_outside_root)
	_outside()
	rebuild()


## (Re)build floors, walls and the for-sale plot markers for the current extent.
func rebuild() -> void:
	if _structure != null:
		_structure.free()
	_structure = Node3D.new()
	_structure.name = "Structure"
	add_child(_structure)
	if _plot_root != null:
		_plot_root.free()
	_plot_root = Node3D.new()
	_plot_root.name = "Plots"
	add_child(_plot_root)
	_walls.clear()
	_cut_state.clear()
	_hall_front = -1
	_hall_back = -1
	_hall_east = -1
	_award_nodes.clear()
	_floors()
	_walls_all()
	_signs()
	_plots()
	refresh_awards()


# --- Floors ---------------------------------------------------------------------------

func _floors() -> void:
	var wood := Synty.material(SHOW_FLOOR_MATERIAL)
	var tiles := Synty.material(BACK_FLOOR_MATERIAL)
	for ix in L.bays_x():
		for iz in L.show_bays() + L.back_bays():
			var at := Vector3(L.x0 + ix * L.BAY, 0.0, L.Z0 + iz * L.BAY)
			var tile := Synty.put(_structure, "Buildings/SM_Bld_Base_Floor_01", at)
			Synty.paint(tile, wood if iz < L.show_bays() else tiles)
	# Solid floor for the walkable area (building, plus the pavement out front).
	var b := L.building()
	Synty.solid(_structure, Vector3(b.get_center().x, -0.5, b.get_center().y), Vector3(b.size.x, 1.0, b.size.y))
	if L.has_hall:
		var h := L.hall()
		var carpet := Synty.material(HALL_FLOOR_MATERIAL)
		for ix in int(round(h.size.x / L.BAY)):
			for iz in int(round(h.size.y / L.BAY)):
				var tile := Synty.put(_structure, "Buildings/SM_Bld_Base_Floor_01", Vector3(h.position.x + ix * L.BAY, 0.0, h.position.y + iz * L.BAY))
				Synty.paint(tile, carpet)
		Synty.solid(_structure, Vector3(h.get_center().x, -0.5, h.get_center().y), Vector3(h.size.x, 1.0, h.size.y))
	Synty.solid(_structure, Vector3(0, -0.5, L.Z0 - 2.0), Vector3(8.0, 1.0, 4.0))


# --- Walls ----------------------------------------------------------------------------

func _walls_all() -> void:
	var nx := L.bays_x()
	var ns := L.show_bays()
	var nb := L.back_bays()
	var show_kinds: Array = []
	for i in nx:
		show_kinds.append("door" if i == L.front_door_bay() else ("window" if i % 2 == 1 else "wall"))
	var side: Array = []
	for i in ns + nb:
		side.append("window" if (i < ns and i % 2 == 1) else "wall")
	var divider: Array = []
	for i in nx:
		divider.append("door" if i == L.divider_door_bay() else "wall")
	var back: Array = []
	for i in nx:
		back.append("wall")
	_wall_run(Vector3(L.x0, 0, L.Z0), 0.0, show_kinds, SHOW_PAINT)  # front
	_wall_run(Vector3(L.x1, 0, L.z1), 180.0, back, BACK_PAINT)  # back
	# The side walls in two parts each, so each room gets its own paint. With the Hall of
	# Fame the east showroom wall has its door instead of windows.
	var east_show: Array = side.slice(0, ns)
	if L.has_hall:
		for i in mini(3, ns):
			east_show[i] = "door" if i == L.HALL_DOOR_BAY else "wall"
	_east_show_group = _walls.size()
	_wall_run(Vector3(L.x1, 0, L.Z0), -90.0, east_show, SHOW_PAINT)
	_wall_run(Vector3(L.x1, 0, L.DIVIDER_Z), -90.0, side.slice(ns), BACK_PAINT, _walls.size() - 1)
	var reversed_side := side.duplicate()
	reversed_side.reverse()
	_wall_run(Vector3(L.x0, 0, L.z1), 90.0, reversed_side.slice(0, nb), BACK_PAINT)
	_west_group = _walls.size() - 1
	_wall_run(Vector3(L.x0, 0, L.DIVIDER_Z), 90.0, reversed_side.slice(nb), SHOW_PAINT, _west_group)
	# The divider between the rooms.
	_divider_group = _walls.size()
	_wall_run(Vector3(L.x0, 0, L.DIVIDER_Z), 0.0, divider, BACK_PAINT)
	if L.has_hall:
		var h := L.hall()
		_hall_front = _walls.size()
		_wall_run(Vector3(h.position.x, 0, L.Z0), 0.0, ["wall", "window", "wall"], HALL_PAINT)
		_hall_east = _walls.size()
		_wall_run(Vector3(h.end.x, 0, L.Z0), -90.0, ["wall", "wall", "wall"], HALL_PAINT)
		_hall_back = _walls.size()
		_wall_run(Vector3(h.end.x, 0, h.end.y), 180.0, ["wall", "wall", "wall"], HALL_PAINT)


## One straight wall of tiles starting at `from`, heading along local +X turned `yaw_deg`,
## inside face on local +Z. Adds to wall group `group` (or a new group).
func _wall_run(from: Vector3, yaw_deg: float, kinds: Array, paint: Color, group: int = -1) -> void:
	var along := Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(yaw_deg))
	var outward := -Vector3.BACK.rotated(Vector3.UP, deg_to_rad(yaw_deg))
	var wall_mat := Synty.tinted(WALL_MATERIAL, paint)
	var wood := Synty.material(TRIM_MATERIAL)
	var g: Dictionary
	if group >= 0:
		g = _walls[group]
	else:
		g = {"normal": outward, "full": [], "stub": []}
		_walls.append(g)
	for i in kinds.size():
		var at := from + along * (L.BAY * i)
		var rel := "Buildings/SM_Bld_Base_Wall_01"
		match kinds[i]:
			"window":
				rel = "Buildings/SM_Bld_Base_Wall_Window_Double_01"
			"door":
				rel = "Buildings/SM_Bld_Base_Wall_Door_Double_01"
		var tile := Synty.put(_structure, rel, at, yaw_deg)
		_paint_walls(tile, wall_mat)
		g["full"].append(tile)
		g["full"].append(Synty.put(_structure, "Buildings/SM_Bld_Trim_Ceiling_01", at, yaw_deg))
		Synty.paint(g["full"].back(), wood)
		if kinds[i] != "door":
			Synty.paint(Synty.put(_structure, "Buildings/SM_Bld_Trim_Wall_Low_01", at, yaw_deg), wood)
			# The stub shown when the wall is cut away: a squashed plain wall tile.
			var stub := Synty.put(_structure, "Buildings/SM_Bld_Base_Wall_01", at, yaw_deg, Vector3(1, STUB / L.WALL_HEIGHT, 1))
			_paint_walls(stub, wall_mat)
			stub.visible = false
			g["stub"].append(stub)
		# Colliders (people walk around these; the navigation mesh is baked from them).
		if kinds[i] == "door":
			_tile_solid(tile, Vector3(0.12, 1.5, 0.0), Vector3(0.24, 3.0, 0.3))
			_tile_solid(tile, Vector3(L.BAY - 0.12, 1.5, 0.0), Vector3(0.24, 3.0, 0.3))
		else:
			_tile_solid(tile, Vector3(L.BAY * 0.5, 1.5, 0.0), Vector3(L.BAY, 3.0, 0.3))


func _paint_walls(tile: Node, wall_mat: Material) -> void:
	for node in [tile] + tile.find_children("*", "MeshInstance3D", true, false):
		if not (node is MeshInstance3D):
			continue
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m: Material = mi.get_surface_override_material(s)
			if m == null:
				m = mi.mesh.surface_get_material(s)
			if m != null and String(m.resource_name).contains("Brick"):
				mi.set_surface_override_material(s, wall_mat)


func _tile_solid(tile: Node3D, local_pos: Vector3, size: Vector3) -> void:
	var body := Synty.solid(tile, local_pos, size)
	body.position = local_pos


## Walls between the camera and the middle of the shop are cut down to stubs.
## `view_dir`: horizontal direction from the shop towards the camera.
func update_cutaway(view_dir: Vector3, walls_down: bool) -> void:
	view_dir.y = 0.0
	view_dir = view_dir.normalized()
	for i in _walls.size():
		var g: Dictionary = _walls[i]
		var cut: bool = walls_down or (g["normal"] as Vector3).dot(view_dir) > 0.25
		if _cut_state.get(i, null) == cut:
			continue
		_cut_state[i] = cut
		for n in g["full"]:
			(n as Node3D).visible = not cut
		for n in g["stub"]:
			(n as Node3D).visible = cut


func _signs() -> void:
	var front_x := L.FRONT_DOOR_X + L.BAY * 0.5
	# Over the door, facing the street; it goes with the front wall when that is cut away.
	_walls[0]["full"].append(BuildUtil.sign(_structure, "Fig Tree Fish Store", Vector3(front_x, 3.25, L.Z0 - 0.2), 180.0, 0.45))
	if _hall_front >= 0:
		_walls[_hall_front]["full"].append(BuildUtil.sign(_structure, "Hall of Fame", Vector3(L.hall().get_center().x, 3.25, L.Z0 - 0.2), 180.0, 0.4))


# --- Show awards on the walls ----------------------------------------------------------

## Hang every show award (top 3) on the walls, best first: round the Hall of Fame if you
## have one, then on the showroom's side walls (between the windows, where customers see
## them), then along the divider. Each hides with its wall when that is cut away.
func refresh_awards() -> void:
	for n in _award_nodes:
		if is_instance_valid(n):
			for g in _walls:
				g["full"].erase(n)
			n.free()
	_award_nodes.clear()
	showroom_award_points.clear()
	var list: Array = Game.awards.duplicate()
	list.sort_custom(func(a, b): return _award_rank(a) > _award_rank(b))
	var slots := _award_slots()
	for i in mini(list.size(), slots.size()):
		var s: Array = slots[i]
		var node := WallAward.make(list[i])
		node.position = s[0]
		node.rotation.y = deg_to_rad(s[1])
		_structure.add_child(node)
		_award_nodes.append(node)
		var g: Dictionary = _walls[s[2]]
		g["full"].append(node)
		node.visible = not _cut_state.get(s[2], false)
		if s[3] == "show":
			showroom_award_points.append(s[0])


static func _award_rank(a: Dictionary) -> int:
	return (4 - int(a.get("place", 1))) * 10 + (5 if a.get("grand", false) else 0)


## [position, yaw, wall group, room] for each spot an award can hang, in order.
func _award_slots() -> Array:
	var out: Array = []
	const INSET := 0.17  # half the wall's thickness, plus a little
	var show: Array = []
	# Side walls: the plain bays (windows are on the odd ones, the hall door on bay 1).
	for i in L.show_bays():
		if i % 2 == 1:
			continue
		for k in 3:
			var z := L.Z0 + i * L.BAY + 0.55 + k * 0.7
			show.append([Vector3(L.x1 - INSET, 2.35, z), -90.0, _east_show_group, "show"])
			show.append([Vector3(L.x0 + INSET, 2.35, z), 90.0, _west_group, "show"])
	if _divider_group >= 0:
		var x := L.x0 + 0.6
		while x < L.x1 - 0.5:
			if x < L.DIVIDER_DOOR_X - 0.4 or x > L.DIVIDER_DOOR_X + L.BAY + 0.4:
				show.append([Vector3(x, 2.35, L.DIVIDER_Z - INSET), 180.0, _divider_group, "show"])
			x += 0.75
	if _hall_back >= 0:
		var h := L.hall()
		var x := h.position.x + 0.6
		while x < h.end.x - 0.5:
			out.append([Vector3(x, 2.4, h.end.y - INSET), 180.0, _hall_back, "hall"])
			x += 0.75
		var z := L.Z0 + 0.6
		while z < h.end.y - 0.5:
			out.append([Vector3(h.end.x - INSET, 2.4, z), -90.0, _hall_east, "hall"])
			z += 0.75
	return out + show


# --- For-sale plots ---------------------------------------------------------------------

## Each plot you could still buy: a grid of its bays on the grass and a FOR SALE sign.
func _plots() -> void:
	for id in Data.PLOTS:
		if Game.owned_plots.has(id):
			continue
		var r := L.plot_rect(id, Game.owned_plots)
		var plane := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = r.size
		plane.mesh = pm
		var col := Color(1.0, 0.75, 0.8, 0.7) if id == "hall" else Color(1.0, 0.95, 0.6, 0.6)
		plane.material_override = grid_material(r.size, L.BAY, col, 0.08)
		plane.position.y = 0.04 if id == "hall" else 0.03
		plane.position = Vector3(r.get_center().x, 0.03, r.get_center().y)
		plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_plot_root.add_child(plane)
		var p: Dictionary = Data.PLOTS[id]
		var tag := BuildUtil.label(_plot_root, "FOR SALE\n%s  $%s" % [p["name"], _commas(int(p["cost"]))],
			Vector3(r.get_center().x, 2.6 if id == "hall" else 1.8, r.get_center().y), 0.012)
		tag.modulate = Color("#ffb3c1") if id == "hall" else Color("#ffe07a")


## An unshaded see-through grid of `cell`-metre squares over an area of `size`.
static func grid_material(size: Vector2, cell: float, color: Color, fill: float = 0.0) -> StandardMaterial3D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(color.r, color.g, color.b, fill))
	for i in 64:
		for w in 2:
			img.set_pixel(i, w, color)
			img.set_pixel(w, i, color)
			img.set_pixel(i, 63 - w, color)
			img.set_pixel(63 - w, i, color)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.uv1_scale = Vector3(size.x / cell, size.y / cell, 1.0)
	m.texture_repeat = true
	return m


static func _commas(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


# --- Outside --------------------------------------------------------------------------

func _outside() -> void:
	var o := _outside_root
	var c := "City/"
	var grass := Synty.put(o, c + "Environments/SM_Env_Grass_01", Vector3(150, -0.16, 150), 0.0, Vector3(60, 1, 60))
	grass.name = "Grass"
	# Pavement along the front (z -12.5..-7.5), the road beyond it, the far pavement.
	for ix in range(-8, 8):
		var x := ix * 5.0
		Synty.put(o, c + "Environments/SM_Env_Sidewalk_01", Vector3(x, 0.0, -7.5))
		Synty.put(o, c + "Environments/SM_Env_Sidewalk_Straight_01", Vector3(x, 0.0, -12.5))
		Synty.put(o, c + "Environments/SM_Env_Road_Lines_01", Vector3(x, 0.0, -12.5))
		Synty.put(o, c + "Environments/SM_Env_Road_Lines_01", Vector3(x, 0.0, -17.5), 180.0)
		Synty.put(o, c + "Environments/SM_Env_Sidewalk_Straight_01", Vector3(x, 0.0, -22.5), 180.0)
		Synty.put(o, c + "Environments/SM_Env_Sidewalk_01", Vector3(x, 0.0, -22.5))
	for x in [-24.0, -16.0, -8.5, 8.5, 16.0, 24.0]:
		Synty.put(o, c + "Environments/SM_Env_Tree_01", Vector3(x, 0.0, -11.5))
	Synty.put(o, c + "Props/SM_Prop_ParkBench_01", Vector3(5.0, 0.0, -8.6), 180.0)
	Synty.put(o, c + "Props/SM_Prop_ParkBench_01", Vector3(-12.0, 0.0, -8.6), 180.0)
	Synty.put(o, c + "Props/SM_Prop_Trashbin_01", Vector3(-4.0, 0.0, -11.6))
	Synty.put(o, c + "Props/SM_Prop_PotPlant_01", Vector3(-2.2, 0.0, -8.1))
	Synty.put(o, c + "Props/SM_Prop_PotPlant_02", Vector3(2.2, 0.0, -8.1))
	for x in [-20.0, 0.0, 20.0]:
		Synty.put(o, c + "Props/SM_Prop_LightPole_Base_01", Vector3(x, 0.0, -11.8))
	Synty.put(o, c + "Props/SM_Prop_BusStop_01", Vector3(12.0, 0.0, -10.6))
	var cars := [["Sedan_01", -10.0, -14.8, 90.0], ["Taxi_01", 15.0, -14.8, 90.0], ["Van_01", -1.0, -19.8, -90.0], ["Small_01", 22.0, -19.8, -90.0]]
	for car in cars:
		Synty.put(o, c + "Vehicles/SM_Veh_Car_" + car[0], Vector3(car[1], 0.0, car[2]), car[3])
	# Shops across the road.
	var row := ["Shop_03", "Shop_01", "Shop_05", "Shop_02", "Shop_06", "Shop_04", "Shop_01", "Shop_03"]
	var x := -37.5
	for name in row:
		var wide := 10.0 if name == "Shop_03" else 5.0
		Synty.put(o, c + "Buildings/SM_Bld_" + name, Vector3(x, 0.0, -27.5))
		x += wide
	# Neighbours either side, an alley's width clear of the lot.
	var lot := L.LOT
	var edge := lot.position.x - 2.5
	for name in ["Shop_01", "Shop_05", "Shop_04"]:
		Synty.put(o, c + "Buildings/SM_Bld_" + name, Vector3(edge, 0.0, L.Z0 + 0.5), 180.0)
		edge -= 5.0
	edge = lot.end.x + 2.5
	for name in ["Shop_02", "Shop_06", "Shop_01"]:
		Synty.put(o, c + "Buildings/SM_Bld_" + name, Vector3(edge + 5.0, 0.0, L.Z0 + 0.5), 180.0)
		edge += 5.0
	_fence(lot)
	_alleys(lot)
	_park(lot)


## A low fence round the sides and back of the lot (the front is the street).
func _fence(lot: Rect2) -> void:
	var probe := Synty.make("City/Environments/SM_Env_Fence_01")
	var seg := Synty.bounds(probe).size.x
	probe.free()
	if seg <= 0.1:
		return
	# [start, direction, length, yaw]
	var runs := [
		[Vector3(lot.position.x - 0.4, 0, lot.position.y + 4.0), Vector3(0, 0, 1), lot.size.y - 3.6, -90.0],
		[Vector3(lot.end.x + 0.4, 0, lot.position.y + 4.0), Vector3(0, 0, 1), lot.size.y - 3.6, -90.0],
		[Vector3(lot.position.x - 0.4, 0, lot.end.y + 0.4), Vector3(1, 0, 0), lot.size.x + 0.8, 0.0],
	]
	for r in runs:
		var dir: Vector3 = r[1]
		var n := int(floor(float(r[2]) / seg))
		for i in n:
			Synty.put(_outside_root, "City/Environments/SM_Env_Fence_01", r[0] + dir * (seg * i), r[3])


## Bins and clutter in the alleys between the lot and the neighbours, trees behind them.
func _alleys(lot: Rect2) -> void:
	var o := _outside_root
	var c := "City/Props/"
	var lx := lot.position.x - 1.4
	var rx := lot.end.x + 1.4
	Synty.put(o, c + "SM_Prop_Trashbin_02", Vector3(lx, 0, -2.0))
	Synty.put(o, c + "SM_Prop_TrashBag_01", Vector3(lx, 0, -0.8))
	Synty.put(o, c + "SM_Prop_CardboardBox_01", Vector3(lx, 0, 6.0))
	Synty.put(o, c + "SM_Prop_Pallet_01", Vector3(rx, 0, 1.0), 20.0)
	Synty.put(o, c + "SM_Prop_Aircon_01", Vector3(rx, 0, -3.0), -90.0)
	Synty.put(o, c + "SM_Prop_Trashbin_01", Vector3(rx, 0, 9.0))
	for p in [Vector3(-27, 0, 6), Vector3(-31, 0, 13), Vector3(-25, 0, 18), Vector3(27, 0, 6), Vector3(31, 0, 12), Vector3(25, 0, 17)]:
		Synty.put(o, "City/Environments/SM_Env_Tree_0%d" % (1 + int(absf(p.x + p.z)) % 3), p)
	for p in [Vector3(-24, 0, 3), Vector3(-29, 0, 9), Vector3(24, 0, 3), Vector3(29, 0, 9), Vector3(-23, 0, 14), Vector3(23, 0, 14)]:
		Synty.put(o, "City/Environments/SM_Env_Flower_01", p, absf(p.x) * 20.0)


## A small park behind the lot: a path, trees, benches, flowers and planters.
func _park(lot: Rect2) -> void:
	var o := _outside_root
	var z := lot.end.y + 5.0
	for i in 9:
		var px := -28.0 + i * 7.0
		Synty.put(o, "City/Environments/SM_Env_Tree_0%d" % (1 + i % 3), Vector3(px, 0, z + 7.0 + (i % 2) * 2.0))
		Synty.put(o, "City/Environments/SM_Env_Flower_01", Vector3(px + 3.0, 0, z - 2.5), i * 40.0)
	for px in [-14.0, 0.0, 14.0]:
		Synty.put(o, "City/Props/SM_Prop_ParkBench_01", Vector3(px, 0, z + 3.5))
		Synty.put(o, "City/Props/SM_Prop_Planter_01", Vector3(px + 3.5, 0, z + 3.5))
	Synty.put(o, "City/Props/SM_Prop_LightPole_Base_01", Vector3(-7.0, 0, z + 3.8))
	Synty.put(o, "City/Props/SM_Prop_LightPole_Base_01", Vector3(7.0, 0, z + 3.8))
