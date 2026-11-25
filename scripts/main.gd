extends Node3D
## The shop: lighting, the building, everything you've built, the customers, the camera,
## the build tool and the HUD. Also answers questions the objects ask (decor appeal near a
## tank, where the till is) and runs the queue at the till.

const Data := preload("res://scripts/data.gd")
const L := preload("res://scripts/world/layout.gd")
const Building := preload("res://scripts/world/building.gd")
const CameraRig := preload("res://scripts/world/camera_rig.gd")
const BuildTool := preload("res://scripts/world/build_tool.gd")
const Placeable := preload("res://scripts/world/placeable.gd")
const Tank := preload("res://scripts/world/tank.gd")
const Shelf := preload("res://scripts/world/shelf.gd")
const TrophyCase := preload("res://scripts/world/trophy_case.gd")
const Customer := preload("res://scripts/world/customer.gd")
const Staff := preload("res://scripts/world/staff.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const BuildUtil := preload("res://scripts/lib/build_util.gd")
const SaveGame := preload("res://scripts/save_game.gd")

## Seconds (game time at 1x) between customers with no reputation or marketing.
const BASE_SPAWN := 4.5
const MAX_CUSTOMERS := 36

var building: Node3D
var nav: NavigationRegion3D
var objects_root: Node3D
var customers_root: Node3D
var staff_root: Node3D
var rig: Node3D
var tool: Node
var hud: CanvasLayer
var walls_down := false

var _till_queue: Array = []
var _spawn_t := 3.0
var _rebake_pending := false
var _customer_seed := 1
## Counter instance id -> the cashier working it.
var _cashiers := {}
## The 0.5 m placement grid shown over the floor while building.
var _build_grid: MeshInstance3D


func _ready() -> void:
	_environment()
	nav = NavigationRegion3D.new()
	nav.name = "Navigation"
	var nm := NavigationMesh.new()
	nm.cell_size = 0.1
	nm.cell_height = 0.1
	nm.agent_radius = 0.3
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.2
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Placeable.LAYER_SOLID
	nav.navigation_mesh = nm
	add_child(nav)
	NavigationServer3D.map_set_cell_size(get_world_3d().navigation_map, 0.1)
	NavigationServer3D.map_set_cell_height(get_world_3d().navigation_map, 0.1)
	var loading: Dictionary = Game.pending_load
	Game.pending_load = {}
	if not loading.is_empty():
		Game.from_dict(loading["game"])
	L.apply_plots(Game.owned_plots)
	building = Building.new()
	building.name = "Building"
	nav.add_child(building)
	building.build()
	_fit_nav_area()
	Game.plots_changed.connect(_on_plots_changed)
	_build_grid = MeshInstance3D.new()
	_build_grid.name = "BuildGrid"
	_build_grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_grid.visible = false
	add_child(_build_grid)
	_fit_build_grid()
	objects_root = Node3D.new()
	objects_root.name = "Objects"
	nav.add_child(objects_root)
	customers_root = Node3D.new()
	customers_root.name = "Customers"
	add_child(customers_root)
	staff_root = Node3D.new()
	staff_root.name = "Staff"
	add_child(staff_root)
	rig = CameraRig.new()
	rig.name = "Camera"
	add_child(rig)
	rig.look_at_point(Vector3(0, 0, -0.5), 30.0, 25.0)
	tool = BuildTool.new()
	tool.name = "BuildTool"
	tool.world = self
	tool.rig = rig
	add_child(tool)
	hud = Hud.new()
	hud.world = self
	add_child(hud)
	if loading.is_empty():
		_starting_shop()
	else:
		_restore(loading["world"])
		Game.set_speed(0)
		Game.notify.emit.call_deferred("Loaded: " + Game.date_text() + "  (paused; press Space to carry on)")
	Game.autosave_wanted.connect(func(): SaveGame.save(SaveGame.AUTO, self))
	Game.staff_changed.connect(_sync_staff)
	_sync_staff()
	Game.month_ended.connect(func(_r): _count_showcases())
	Game.awards_changed.connect(_refresh_trophies)
	Game.fish_delivered.connect(_on_fish_delivered)
	rebake()


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color("#5d9ad8")
	mat.sky_horizon_color = Color("#cfe5f2")
	mat.ground_horizon_color = Color("#cfe5f2")
	mat.ground_bottom_color = Color("#7a8f6a")
	sky.sky_material = mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, 38.0, 0.0)
	sun.light_energy = 1.25
	sun.light_color = Color("#fff3df")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)


func _process(delta: float) -> void:
	building.update_cutaway(rig.view_dir(), walls_down)
	_build_grid.visible = tool.is_busy()
	var ts: float = Game.time_scale()
	if ts <= 0.0:
		return
	_serve_queue()
	_spawn_t -= delta * ts
	if _spawn_t <= 0.0:
		_spawn_t = BASE_SPAWN / customer_rate() * randf_range(0.6, 1.4)
		if counter() != null and customers_root.get_child_count() < MAX_CUSTOMERS:
			_spawn_customer()


## How many times more customers than a bare shop with an average reputation.
func customer_rate() -> float:
	var r := 0.6 + Game.reputation / 100.0
	r *= 1.0 + float(Data.MARKETING[Game.marketing]["boost"])
	r *= 1.0 + minf(showroom_appeal(), 400.0) / 400.0
	r *= 1.0 + hall_bonus()
	return r


## Market fish go into the holding tanks; any that don't fit wait in storage.
func _on_fish_delivered(list: Array) -> void:
	var held := 0
	for f in list:
		var put := false
		for t in holding_tanks():
			if t.fish.size() < t.capacity() and t.add_fish(f):
				put = true
				break
		if put:
			held += 1
		else:
			Game.fish_storage.append(f)
	var over := list.size() - held
	if over == 0:
		Game.notify.emit("%d fish delivered to the holding tank" % held)
	elif held == 0:
		Game.notify.emit("%d fish delivered to storage: %s" % [over,
			"the holding tanks are full" if not holding_tanks().is_empty() else "build a Holding Tank in the back room for them"])
	else:
		Game.notify.emit("%d fish delivered to the holding tank, %d to storage (it's full)" % [held, over])


func holding_tanks() -> Array:
	return objects().filter(func(o): return o is Tank and o.is_holding())


## Room left in the holding tanks, after fish already on order.
func holding_space() -> int:
	var n := 0
	for t in holding_tanks():
		n += t.capacity() - t.fish.size()
	return n - Game.fish_on_order()


## The Hall of Fame's prestige: its fish (stars, ribbons) and the trophies on show.
func hall_prestige() -> int:
	var p := 0
	for o in objects():
		if o.room() != "hall":
			continue
		if o is Tank:
			p += o.hall_prestige()
		elif o is TrophyCase:
			p += o.prestige()
	return p


## Extra customers the Hall of Fame draws: up to +50% (at 150 prestige).
func hall_bonus() -> float:
	return minf(hall_prestige(), 150.0) / 300.0


## Things in the Hall of Fame worth a look (tanks with fish, cabinets with trophies).
func hall_sights() -> Array:
	return objects().filter(func(o): return o.room() == "hall" and (
		(o is Tank and not o.fish.is_empty()) or (o is TrophyCase and not o.awards.is_empty())))


## Hand out the trophies to the cabinets, best first (Grand Show golds, then golds, ...).
func _refresh_trophies() -> void:
	var list := Game.awards.duplicate()
	list.sort_custom(func(a, b): return TrophyCase.award_prestige(a) > TrophyCase.award_prestige(b))
	var i := 0
	for o in objects():
		if o is TrophyCase:
			if o.room() == "hall":
				o.show_awards(list.slice(i, i + TrophyCase.PER_CASE))
				i += TrophyCase.PER_CASE
			else:
				o.show_awards([])


## Sum of tank appeal in the showroom, which word of mouth carries down the street.
func showroom_appeal() -> float:
	var a := 0.0
	for obj in objects():
		if obj is Tank and obj.room() == "show" and not obj.is_breeding():
			a += obj.appeal()
	return a


func _spawn_customer() -> void:
	var c := Customer.new()
	_customer_seed += 1
	c.position = L.STREET_SPOT + Vector3(randf_range(-5.0, 5.0), 0, 0)
	c.setup(self, _customer_seed * 92821 + randi() % 1000)
	customers_root.add_child(c)


# --- Objects --------------------------------------------------------------------------

func objects() -> Array:
	var out: Array = []
	for c in objects_root.get_children():
		if c is Placeable and not c.is_queued_for_deletion():
			out.append(c)
	return out


func make_object(id: String, ghost: bool = false) -> Node3D:
	var kind: String = Data.ITEMS[id]["kind"]
	var obj: Node3D
	if kind == "tank" or kind == "breeding":
		obj = Tank.new()
	elif kind == "shelf":
		obj = Shelf.new()
	elif kind == "holding":
		obj = Tank.new()
	elif kind == "trophies":
		obj = TrophyCase.new()
	else:
		obj = Placeable.new()
	obj.world = self
	obj.setup(id, ghost)
	return obj


func place(id: String, pos: Vector3, rot: int = 0) -> Node3D:
	var obj := make_object(id)
	obj.position = pos
	obj.set_rot(rot)
	objects_root.add_child(obj)
	objects_changed()
	return obj


func sell(obj: Node3D) -> void:
	if obj == null or not is_instance_valid(obj):
		return
	if obj.def["kind"] == "counter" and _count_kind("counter") <= 1:
		Game.notify.emit("You need at least one till counter")
		return
	obj.on_removed()
	Game.earn(obj.refund(), "refunds")
	if tool.selected == obj:
		tool.select(null)
	obj.queue_free()
	objects_changed.call_deferred()


func _count_kind(kind: String) -> int:
	var n := 0
	for o in objects():
		if o.def["kind"] == kind:
			n += 1
	return n


## Something was built, moved or removed: rebake where people can walk.
func objects_changed() -> void:
	_count_showcases()
	_refresh_trophies.call_deferred()
	if not _rebake_pending:
		_rebake_pending = true
		rebake.call_deferred()


func rebake() -> void:
	_rebake_pending = false
	if not is_inside_tree():
		return  # the scene is being replaced (loading a save)
	nav.bake_navigation_mesh(false)


func _count_showcases() -> void:
	var n := 0
	for o in objects():
		if o is Tank and o.showcase:
			n += 1
	Game.showcase_count = n


## Can item `id` go at `r` (floor rectangle)? {"ok": bool, "why": String}
func can_place(id: String, r: Rect2, ignore: Node) -> Dictionary:
	var def: Dictionary = Data.ITEMS[id]
	var room := ""
	for candidate in def["rooms"]:
		if L.room_rect(candidate).encloses(r):
			room = candidate
	if room == "":
		var where := " or ".join(PackedStringArray(def["rooms"].map(func(x): return L.room_name(x))))
		return {"ok": false, "why": "must be inside the " + where}
	if not def.get("walkable", false):
		for z in L.door_zones():
			if z.intersects(r):
				return {"ok": false, "why": "blocks a doorway"}
	for o in objects():
		if o == ignore:
			continue
		# Rugs go under things; everything else needs its own floor.
		if def.get("walkable", false) or o.def.get("walkable", false):
			if def.get("walkable", false) and o.def.get("walkable", false) and o.rect().grow(-0.01).intersects(r):
				return {"ok": false, "why": "overlaps another rug"}
			continue
		if o.rect().grow(-0.01).intersects(r):
			return {"ok": false, "why": "something is in the way"}
	return {"ok": true}


## Appeal that decor near `p` adds to a tank there.
func decor_appeal_near(p: Vector3) -> float:
	var a := 0.0
	for o in objects():
		var kind: String = o.def["kind"]
		if kind != "decor" and kind != "rug":
			continue
		var d := Vector2(o.position.x - p.x, o.position.z - p.z).length()
		if d < Data.APPEAL_RADIUS:
			a += float(o.def.get("appeal", 0.0)) * (1.0 - d / Data.APPEAL_RADIUS * 0.5)
	return a


# --- The till -------------------------------------------------------------------------

func counter() -> Node3D:
	for o in objects():
		if o.def["kind"] == "counter":
			return o
	return null


func _queue_spot(i: int) -> Vector3:
	var c := counter()
	if c == null:
		return L.DOOR_INSIDE
	var f: Vector3 = c.front()
	var side := f.cross(Vector3.UP).normalized()
	return c.visit_point() + f * (0.9 * i) + side * (0.15 * (i % 2))


## A customer with a full basket heads for the till; returns where they should stand.
func join_queue(cust: Node3D) -> Vector3:
	_till_queue.append(cust)
	return _queue_spot(_till_queue.size() - 1)


func left_till(cust: Node3D) -> void:
	_till_queue.erase(cust)
	for i in _till_queue.size():
		var c: Node3D = _till_queue[i]
		if is_instance_valid(c):
			c.set_queue_spot(_queue_spot(i))


## The customer at the front pays once they're standing there and a cashier is serving.
func _serve_queue() -> void:
	while not _till_queue.is_empty() and not is_instance_valid(_till_queue[0]):
		_till_queue.pop_front()
	if _till_queue.is_empty():
		return
	var front: Node3D = _till_queue[0]
	if front.state != "waiting":
		return
	var c := counter()
	var cashier: Node3D = cashier_for(c) if c != null else null
	if cashier != null and cashier.is_serving():
		front.start_paying()


# --- Staff ------------------------------------------------------------------------------

## Make the people in the shop match Game.staff (someone hired or fired).
func _sync_staff() -> void:
	var have := {}
	for n in staff_root.get_children():
		if n.is_queued_for_deletion():
			continue
		var still := Game.staff.any(func(p): return int(p["id"]) == int(n.info["id"]))
		if still:
			have[int(n.info["id"])] = true
		else:
			n.dismiss()
	for person in Game.staff:
		if have.has(int(person["id"])):
			continue
		var st := Staff.new()
		st.name = "%s_%d" % [person["role"], person["id"]]
		st.position = break_spot() + Vector3(randf_range(-1.0, 1.0), 0, randf_range(-0.5, 0.5))
		st.setup(self, person)
		staff_root.add_child(st)


func staff_nodes() -> Array:
	return staff_root.get_children().filter(func(n): return not n.is_queued_for_deletion())


func cashier_for(c: Node3D) -> Node3D:
	if c == null:
		return null
	var who: Variant = _cashiers.get(c.get_instance_id())
	if who == null or not is_instance_valid(who) or (who as Node).is_queued_for_deletion():
		_cashiers.erase(c.get_instance_id())
		return null
	return who


func set_cashier(c: Node3D, who: Node3D) -> void:
	_cashiers[c.get_instance_id()] = who


## Where stockers pick up boxes: by the back-room stock if there is any, else by the door.
func stockroom_spot() -> Vector3:
	for o in objects():
		if (o.item_id == "pallet" or o.item_id == "boxes") and o.room() == "back":
			return o.visit_point()
	return Vector3(L.DIVIDER_DOOR_X + L.BAY * 0.5, 0, L.DIVIDER_Z + 1.6)


## Where staff wait with nothing to do: by the back-room desk if there is one.
func break_spot() -> Vector3:
	for o in objects():
		if o.item_id == "desk" and o.room() == "back":
			return o.visit_point()
	return Vector3(0, 0, (L.DIVIDER_Z + L.z1) * 0.5)


func float_text(p: Vector3, text: String, color: Color) -> void:
	var l := BuildUtil.label(self, text, p, 0.0045)
	l.modulate = color
	var tw := create_tween()
	tw.tween_property(l, "position", p + Vector3(0, 1.2, 0), 1.4)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.4).set_delay(0.5)
	tw.tween_callback(l.queue_free)


# --- The shop you start with ------------------------------------------------------------

func _starting_shop() -> void:
	# A bare shop: the till by the door, one display tank, one supply shelf, and one
	# breeding tank and a holding tank in the back room. Everything else is up to the player.
	place("counter", Vector3(5.0, 0, -5.75), 0)
	var tank := place("tank_medium", Vector3(-4.0, 0, -1.0), 2) as Tank
	var shelf := place("shelf", Vector3(10.625, 0, -2.0), 1) as Shelf
	var breeder := place("tank_breeding", Vector3(-5.5, 0, 11.75), 2) as Tank
	place("tank_holding", Vector3(-1.5, 0, 11.8), 2)  # market deliveries arrive here

	# Stock: guppies to sell, a pair to breed, a goldfish pair waiting in storage.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 5:
		tank.add_fish(Game.new_fish("guppy", rng.randi_range(1, 3)))
	# Red x yellow guppies can make Orange.
	breeder.add_fish(Game.new_fish("guppy", 3, "red", "m"))
	breeder.add_fish(Game.new_fish("guppy", 2, "yellow", "f"))
	breeder.add_fish(Game.new_fish("guppy", 2, "red", "f"))
	for spec in [["goldfish", "comet", "m"], ["goldfish", "fantail", "f"]]:
		Game.fish_storage.append(Game.new_fish(spec[0], 2, spec[1], spec[2]))
	Game.stockroom = {"food": 24, "conditioner": 12, "gravel": 6, "plants": 10, "filter": 4, "net": 12}
	shelf.set_product("food", 0)
	shelf.set_product("conditioner", 1)
	shelf.set_product("plants", 2)
	shelf.fill_now()
	# Two people to start with: someone on the till and someone to fill the shelf.
	Game.hire("cashier")
	Game.hire("stocker")
	_count_showcases()


# --- Screenshot mode: godot --path . -- --screenshot=res://screenshots/x.png [--wait=8] ---

func _enter_tree() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			_shoot.call_deferred(arg.substr(13))


func _shoot(path: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--load") and not Game.has_meta("did_load"):
		Game.set_meta("did_load", true)
		load_game()
		return
	var start := "none"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--start="):
			start = arg.substr(8)
	if start != "menu" and not Game.has_meta("did_load"):
		Game.choose_start(start)
	var wait := 10.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--wait="):
			wait = float(arg.substr(7))
		elif arg == "--fast" or arg == "--smart":
			Game.set_speed(3)
			Game.autoplay = true
			Game.day_passed.connect(_smart_player if arg == "--smart" else _test_player)
			Game.notify.connect(func(t): if t.contains("old age") or t.contains("getting old") or t.contains("trophy"): print("NOTE day=", Game.abs_day, " ", t))
			Game.month_ended.connect(func(r): print("REPORT ", r["title"], " cust=", r["customers"], " happy=", r["happy"], "/", r["unhappy"], " gaveup=", r["gave_up"], " fish=", r["fish_sold"], " items=", r["items_sold"], " income=", r["income"], " exp=", r["expenses"], " profit=", r["profit"], " bal=", r["balance"], " debt=", r["debt"], " bred=", r["fish_bred"], " book=", Game.discovered, " stars=", Game.stars_earned, " ach=", Game.achievements_done.size(), " shows=", Game.totals["shows_won"]))
		elif arg.begins_with("--cam="):
			var v := arg.substr(6).split(",")
			rig.look_at_point(Vector3(float(v[0]), 0, float(v[1])), float(v[2]), float(v[3]))
		elif arg == "--forecast":
			await get_tree().process_frame
			if tool.selected != null:
				hud._breeding_forecast(tool.selected)
		elif arg == "--hall" or arg == "--hall-east":
			# Test only: buy the Hall of Fame and fill it (then the east wing, to check it moves).
			Game.money += 40000
			Game.buy_plot("hall")
			var h := L.hall()
			var t := place("tank_large", Vector3(h.get_center().x, 0, h.position.y + 0.75), 0) as Tank
			for i in 6:
				var f := Game.new_fish("goldfish", 4 + i % 2, ["ranchu", "oranda", "lionhead", "celestial", "pearlscale", "bubble_eye"][i])
				f["ribbon"] = i % 3
				t.add_fish(f)
			for i in 7:
				Game.awards.append({"title": "Grand Show" if i == 0 else "Fish Show %d" % i, "place": 1 + i % 3, "grand": i == 0, "day": i, "fish": "Test fish"})
			place("trophy_case", Vector3(h.get_center().x - 1.5, 0, h.end.y - 0.5), 2)
			place("trophy_case", Vector3(h.get_center().x + 1.5, 0, h.end.y - 0.5), 2)
			place("plant", Vector3(h.end.x - 0.6, 0, h.position.y + 0.6), 0)
			Game.awards_changed.emit()
			if arg == "--hall-east":
				Game.buy_plot("east")
			print("HALL prestige=", hall_prestige(), " bonus=", hall_bonus(), " rect=", L.hall(), " tank_room=", t.room())
		elif arg.begins_with("--order-fish="):
			for i in int(arg.substr(13)):
				Game.order_fish("guppy", "red", "m" if i % 2 == 0 else "f", 2)
			Game.notify.connect(func(t): print("NOTE ", t))
		elif arg == "--steps-min":
			Game.steps_minimized = true
		elif arg == "--edit":
			tool.toggle_edit(true)
		elif arg == "--fishpop":
			await get_tree().process_frame
			if not Game.fish_storage.is_empty():
				hud._fish_details(int(Game.fish_storage[0]["id"]))
		elif arg.begins_with("--buy="):
			Game.money += 50000
			for plot in arg.substr(6).split(","):
				Game.buy_plot(plot)
		elif arg.begins_with("--panel="):
			var pv := arg.substr(8).split(":")
			if pv.size() > 1:
				hud._order_tab = pv[1]
			hud._open.call_deferred(pv[0])
		elif arg.begins_with("--hire="):
			for role in arg.substr(7).split(","):
				Game.hire(role)
		elif arg.begins_with("--place="):
			_side_demo_place.call_deferred(arg.substr(8))
		elif arg.begins_with("--select="):
			var v := arg.substr(9).split(",")
			for o in objects():
				if o.rect().has_point(Vector2(float(v[0]), float(v[1]))):
					tool.select(o)
	await get_tree().create_timer(wait).timeout
	if args.has("--save"):
		save_game()
	print("STATE day=", Game.abs_day, " money=", Game.money, " objects=", objects().size(), " storage=", Game.fish_storage.size(),
		" tankfish=", objects().filter(func(o): return o is Tank).reduce(func(a, o): return a + o.fish.size(), 0),
		" staff=", Game.staff.size(), " loans=", Game.loans.size(), " book=", Game.discovered.size(), " rep=", Game.reputation)
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	img.save_png(path)
	print("saved ", path)
	get_tree().quit()


## Screenshot helper: open the Build panel and hold `id` over the middle of the screen.
func _side_demo_place(id: String) -> void:
	await get_tree().create_timer(1.0).timeout
	hud._build_cat = Data.ITEMS[id]["cat"]
	hud._open("build")
	tool.start_place(id)
	var mid := get_viewport().get_visible_rect().size * Vector2(0.5, 0.55)
	Input.warp_mouse(mid)
	await get_tree().process_frame
	tool._update_ghost(mid)


## Test mode only (--fast): play the routine moves a player would, so a long run shows
## whether the economy works: keep the stockroom ordered and move stored fish into the
## showroom tanks (keeping two of each species back for breeding).
func _test_player() -> void:
	if Game.show_entry.is_empty():
		var best: Dictionary = {}
		for f in Game.fish_storage:
			if Game.can_enter(f) and (best.is_empty() or Game.show_score(f) > Game.show_score(best)):
				best = f
		if not best.is_empty():
			Game.enter_show(Game.take_stored_fish(int(best["id"])))
	for id in Data.PRODUCTS:
		if int(Game.stockroom.get(id, 0)) + Game.units_ordered(id) < 12 and Game.money > 1500:
			Game.order_supplies(id)
	for o in objects():
		if o is Tank and o.room() == "show" and not o.is_breeding():
			var species: String = o.fish[0]["species"] if not o.fish.is_empty() else ""
			for f in Game.fish_storage.duplicate():
				if o.fish.size() >= o.capacity():
					break
				if species == "" or f["species"] == species:
					o.add_fish(Game.take_stored_fish(int(f["id"])))


## Test mode only (--smart): play like a sensible new player. Hire a keeper, breed the
## goldfish pair too, keep showroom tanks full of adults, add tanks and decor as money
## allows. Prints a DAY line every 5 days so a run shows where the money goes.
func _smart_player() -> void:
	var d := Game.abs_day
	if d == 2:
		Game.hire("keeper")
		var b := _build_free("tank_breeding", "back")
		if b != null:
			for f in Game.fish_storage.duplicate():
				if f["species"] == "goldfish":
					b.add_fish(Game.take_stored_fish(int(f["id"])))
	# Keep breeding tanks going: retire old breeders, top up with young adults of the
	# same species (1 male, 2 females), as a player would.
	for b in objects().filter(func(o): return o is Tank and o.is_breeding()):
		if not b.fish.is_empty():
			b.set_meta("sp", b.fish[0]["species"])
		var sp: String = b.get_meta("sp", "guppy")
		for f in b.fish.duplicate():
			if Data.FishData.days_left(f) <= 12:
				Game.store_fish(b.remove_fish(int(f["id"])))
		for sex in ["m", "f"]:
			var want := 1 if sex == "m" else 2
			var have: int = b.fish.filter(func(f): return f.get("sex", "m") == sex).size()
			while have < want:
				var pick: Dictionary = {}
				for f in Game.fish_storage:
					if f["species"] == sp and f.get("sex", "m") == sex and Data.FishData.is_adult(f) and Data.FishData.days_left(f) > 30:
						if pick.is_empty() or int(f["stars"]) > int(pick["stars"]):
							pick = f
				if pick.is_empty():
					break
				b.add_fish(Game.take_stored_fish(int(pick["id"])))
				have += 1
	# Supplies: same as the plain test player.
	for id in Data.PRODUCTS:
		if int(Game.stockroom.get(id, 0)) + Game.units_ordered(id) < 12 and Game.money > 800:
			Game.order_supplies(id)
	if Game.show_entry.is_empty():
		var best: Dictionary = {}
		for f in Game.fish_storage:
			if Game.can_enter(f) and (best.is_empty() or Game.show_score(f) > Game.show_score(best)):
				best = f
		if not best.is_empty() and Game.fish_storage.size() > 4:
			Game.enter_show(Game.take_stored_fish(int(best["id"])))
	# Adults from storage into the showroom.
	var shows := objects().filter(func(o): return o is Tank and o.room() == "show")
	for o in shows:
		for f in Game.fish_storage.duplicate():
			if o.fish.size() >= o.capacity():
				break
			if Data.FishData.is_adult(f):
				o.add_fish(Game.take_stored_fish(int(f["id"])))
	var adults_waiting := Game.fish_storage.filter(func(f): return Data.FishData.is_adult(f)).size()
	if adults_waiting > 12 and shows.size() >= 6:
		for f in Game.market_surplus(3):
			Game.sell_to_market(int(f["id"]))
	if adults_waiting >= 4 and Game.money > 2000 and shows.size() < 6:
		var t := _build_free("tank_medium", "show")
		if t != null:
			_build_free("plant", "show", t.position)
	print("DAY ", d, " cust_in_shop=", customers_root.get_child_count(), " hall=", hall_prestige(), " died=", Game.stats.get("fish_died", 0), " money=", Game.money, " storage=", Game.fish_storage.size(), " waiting_adults=", adults_waiting,
		" show_tanks=", shows.size(), " show_fish=", shows.reduce(func(a, o): return a + o.fish.size(), 0),
		" appeal=", int(showroom_appeal()), " rate=", snappedf(customer_rate(), 0.01), " rep=", int(Game.reputation),
		" dirt=", objects().filter(func(o): return o is Tank).map(func(o): return int(o.dirt)),
		" shelf=", objects().filter(func(o): return o is Shelf).map(func(o): return o.total_units()),
		" stockroom=", Game.stockroom.values().reduce(func(a, v): return a + int(v), 0)) if d % 5 == 0 else null


## Test helper: build `id` at the first free spot in `room` (near `near` if given).
func _build_free(id: String, room: String, near = null) -> Node3D:
	var cost := int(Data.ITEMS[id]["cost"])
	if Game.money < cost:
		return null
	var r := L.room_rect(room)
	var spots: Array = []
	var x := r.position.x + 1.0
	while x < r.end.x - 0.5:
		var z := r.position.y + 1.0
		while z < r.end.y - 0.5:
			spots.append(Vector3(x, 0, z))
			z += 0.5
		x += 0.5
	if near != null:
		spots.sort_custom(func(a, b): return a.distance_to(near) < b.distance_to(near))
	var size: Vector2 = Data.ITEMS[id]["size"]
	for p in spots:
		var rect := Rect2(Vector2(p.x, p.z) - size * 0.5, size).grow(0.6)
		if can_place(id, Rect2(Vector2(p.x, p.z) - size * 0.5, size), null)["ok"] and can_place("rug", rect, null)["ok"] and _clear_of_all(rect):
			Game.spend(cost, "construction")
			return place(id, p, 0)
	return null


func _clear_of_all(r: Rect2) -> bool:
	for o in objects():
		if o.rect().intersects(r):
			return false
	return true


# --- Expansion --------------------------------------------------------------------------

func _on_plots_changed() -> void:
	var old_hall := L.hall() if L.has_hall else Rect2()
	L.apply_plots(Game.owned_plots)
	# The east wing pushes the Hall of Fame out: everything in it goes along.
	if L.has_hall and old_hall.has_area() and not is_equal_approx(old_hall.position.x, L.hall().position.x):
		var shift := L.hall().position.x - old_hall.position.x
		var movers: Array = objects() + customers_root.get_children() + staff_root.get_children()
		for n in movers:
			if old_hall.has_point(Vector2(n.position.x, n.position.z)):
				n.position.x += shift
	building.rebuild()
	_fit_nav_area()
	_fit_build_grid()
	objects_changed()


## Only bake navigation over the building and the pavement out front.
func _fit_nav_area() -> void:
	var b := L.indoors()
	nav.navigation_mesh.filter_baking_aabb = AABB(Vector3(b.position.x - 1.0, -1.0, b.position.y - 5.0),
		Vector3(b.size.x + 2.0, 4.0, b.size.y + 6.0))


func _fit_build_grid() -> void:
	var b := L.indoors()
	var pm := PlaneMesh.new()
	pm.size = b.size
	_build_grid.mesh = pm
	_build_grid.material_override = Building.grid_material(b.size, 0.5, Color(1, 1, 1, 0.22))
	_build_grid.position = Vector3(b.get_center().x, 0.025, b.get_center().y)



# --- Saving -----------------------------------------------------------------------------

## The world part of a save: everything built (with tank fish and shelf stock) and the camera.
func to_save() -> Dictionary:
	var objs: Array = []
	for o in objects():
		var e := {"id": o.item_id, "x": o.position.x, "z": o.position.z, "rot": o.rot}
		if o is Tank:
			e["fish"] = o.fish.duplicate(true)
			e["showcase"] = o.showcase
			e["dirt"] = o.dirt
			e["breed_days"] = o.breed_days
		elif o is Shelf:
			e["slots"] = o.to_save()
		objs.append(e)
	return {"objects": objs, "camera": [rig.position.x, rig.position.z, rig.distance, rig.yaw]}


func _restore(w: Dictionary) -> void:
	for e in w.get("objects", []):
		if not Data.ITEMS.has(e["id"]):
			continue
		var o := place(e["id"], Vector3(float(e["x"]), 0, float(e["z"])), int(e["rot"]))
		if o is Tank:
			for f in e.get("fish", []).filter(func(x): return Data.SPECIES.has(x.get("species", ""))):
				o.add_fish(f)
			o.breed_days = int(e.get("breed_days", 0))
			o.dirt = float(e.get("dirt", 0.0))
			o._update_water()
			if e.get("showcase", false):
				o.set_showcase(true)
		elif o is Shelf:
			o.restore(e.get("slots"), str(e.get("product", "")), int(e.get("units", 0)))
	var cam: Array = w.get("camera", [])
	if cam.size() == 4:
		rig.look_at_point(Vector3(float(cam[0]), 0, float(cam[1])), float(cam[2]), float(cam[3]))
	_count_showcases()


func save_game(path: String = SaveGame.MANUAL) -> void:
	if SaveGame.save(path, self):
		Game.notify.emit("Game saved")


func load_game(path: String = SaveGame.MANUAL) -> void:
	SaveGame.load_game(path, get_tree())


func new_game() -> void:
	Game.reset()
	get_tree().reload_current_scene()
