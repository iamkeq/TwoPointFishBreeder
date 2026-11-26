extends "res://scripts/world/placeable.gd"
## A fish tank (display tanks in the showroom, breeding tanks in the back room).
## Holds up to `capacity` fish. Display tanks sell to customers: the better the tank's
## appeal (its size, decor nearby, star quality of its fish, showcasing), the likelier a
## sale and the higher the price. A breeding tank with two fish of the same species makes
## a batch of fry every few days; they go to the back-room fish storage.

const FishSwim := preload("res://scripts/world/fish_swim.gd")
const BuildUtil := preload("res://scripts/lib/build_util.gd")
const FishData := preload("res://scripts/fish_data.gd")
const Genetics := preload("res://scripts/genetics.gd")

## The office tank model's water space, in its own (unscaled) coordinates.
const INSIDE_MIN := Vector3(-0.575, 0.69, -0.282)
const INSIDE_MAX := Vector3(0.575, 1.24, 0.282)

var fish: Array = []
var showcase := false
var breed_days := 0
## 0 clean .. 100 filthy. Rises daily, a fish keeper brings it back to 0.
var dirt := 0.0
## The staff member on their way to clean it (so two keepers don't both come).
var claimed_by: Node
## Already told the player breeding has stopped for dirty water (until it's cleaned).
var _warned_dirty := false
var _water: MeshInstance3D
var _water_mat: StandardMaterial3D
var _inside := AABB()
var _swimmers := {}
var _spot: SpotLight3D
var _sign: Label3D


func is_breeding() -> bool:
	return def["kind"] == "breeding"


## A back-room holding tank: fish from the market arrive here. Nothing breeds in it.
func is_holding() -> bool:
	return def["kind"] == "holding"


func capacity() -> int:
	return int(def["capacity"])


func _build_model() -> void:
	var size: Vector2 = def["size"]
	var h := float(def["height"])
	var tank := Synty.office_tank()
	model.add_child(tank)
	var b := Synty.bounds(tank)
	var s := Vector3(size.x / b.size.x, h / b.size.y, size.y / b.size.z)
	tank.scale = s
	tank.position = Vector3(-(b.position.x + b.size.x * 0.5) * s.x, -b.position.y * s.y, -(b.position.z + b.size.z * 0.5) * s.z)
	if is_breeding():
		Synty.tint(tank, Color(0.6, 0.8, 1.0))
	elif is_holding():
		Synty.tint(tank, Color(0.7, 0.95, 0.75))
	var lo := tank.position + INSIDE_MIN * s
	var hi := tank.position + INSIDE_MAX * s
	_inside = AABB(lo, hi - lo)
	# Tinted water filling the tank, clear when clean and murky green when dirty.
	_water = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = _inside.size * Vector3(0.98, 0.92, 0.96)
	_water.mesh = box
	_water.position = _inside.get_center() - Vector3(0, _inside.size.y * 0.04, 0)
	_water_mat = StandardMaterial3D.new()
	_water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_water_mat.roughness = 0.1
	_water_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_water.material_override = _water_mat
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(_water)
	_update_water()


func _after_setup() -> void:
	if ghost:
		return
	Game.day_passed.connect(_on_day)


func _update_water() -> void:
	if _water_mat == null:
		return
	var t := clampf(dirt / 100.0, 0.0, 1.0)
	_water_mat.albedo_color = Color(0.45, 0.78, 0.95, 0.10).lerp(Color(0.38, 0.45, 0.16, 0.62), t)


## How much dirt costs in appeal: x1 when clean, down to x0.4 when filthy.
func clean_factor() -> float:
	return 1.0 - clampf(dirt / 100.0, 0.0, 1.0) * 0.6


func needs_cleaning() -> bool:
	if in_hall():
		return false
	return dirt >= Data.CLEAN_AT and not fish.is_empty() or dirt >= 50.0


## Tanks in the Hall of Fame never get dirty and their fish never grow old (or get sold).
func in_hall() -> bool:
	return room() == "hall"


## Whether this is a breeding tank with a pair in it that's spawning (or would be).
func is_breeding_pair() -> bool:
	return is_breeding() and breeding_plan()["ok"]


## Which tank a keeper goes to first. A breeding pair stops spawning at
## BREED_DIRT_LIMIT, so its tank jumps the queue well before then; then showroom tanks
## (they earn money); then the dirtiest.
func clean_priority() -> float:
	if is_breeding_pair():
		return dirt + 60.0
	return dirt + (30.0 if room() == "show" else 0.0)


func clean() -> void:
	dirt = 0.0
	_warned_dirty = false
	_update_water()
	Game.add_stat("tanks_cleaned")


func add_fish(f: Dictionary) -> bool:
	if fish.size() >= capacity():
		return false
	fish.append(f)
	var swimmer := FishSwim.new()
	add_child(swimmer)
	swimmer.setup(f, _inside)
	_swimmers[int(f["id"])] = swimmer
	breed_days = 0
	return true


func remove_fish(id: int) -> Dictionary:
	for i in fish.size():
		if int(fish[i]["id"]) == id:
			var f: Dictionary = fish[i]
			fish.remove_at(i)
			if _swimmers.has(id):
				(_swimmers[id] as Node).queue_free()
				_swimmers.erase(id)
			breed_days = 0
			return f
	return {}


func on_removed() -> void:
	for f in fish.duplicate():
		Game.store_fish(remove_fish(int(f["id"])))


func refund() -> int:
	return int(def["cost"]) / 2


## What this tank's fish add to the Hall of Fame's prestige (0 outside it).
func hall_prestige() -> int:
	if not in_hall():
		return 0
	var p := 0
	for f in fish:
		if FishData.is_adult(f):
			p += int(f["stars"]) + 4 * int(f.get("ribbon", 0))
	return p


# --- Appeal and sales -----------------------------------------------------------------

## How attractive this tank is to customers (0 = bare, ~100 = superb).
func appeal() -> float:
	if is_breeding() or is_holding():
		return 0.0
	var a := float(def["appeal"])
	if world != null:
		a += world.decor_appeal_near(global_position)
	if not fish.is_empty():
		var stars := 0.0
		for f in fish:
			stars += float(f["stars"])
		a += stars / fish.size() * 6.0
		a += minf(fish.size(), 8) * 1.5  # a busy tank looks better than a lonely fish
	if showcase:
		a *= Data.SHOWCASE_MULT
	return a * clean_factor()


## Price bonus from appeal: up to +50%.
func price_bonus() -> float:
	return minf(appeal(), 100.0) / 200.0


func price_of(f: Dictionary) -> int:
	return int(round(Data.fish_price(f) * (1.0 + price_bonus())))


## A customer decides whether to buy here. Returns the fish (taken out of the tank) and
## its price, or {} if they don't. Fry aren't for sale.
func try_sell(rng: RandomNumberGenerator) -> Dictionary:
	if is_breeding() or is_holding() or in_hall():
		return {}
	var adults := fish.filter(func(f): return FishData.is_adult(f))
	if adults.is_empty():
		return {}
	var chance := 0.18 + minf(appeal(), 120.0) / 200.0
	if rng.randf() > chance:
		return {}
	var f: Dictionary = adults[rng.randi() % adults.size()]
	var price := price_of(f)
	remove_fish(int(f["id"]))
	return {"kind": "fish", "fish": f, "name": Data.fish_label(f), "price": price}


func set_showcase(on: bool) -> void:
	showcase = on
	if on and _spot == null:
		_spot = SpotLight3D.new()
		_spot.position = Vector3(0, 3.2, 0.6)
		_spot.rotation_degrees.x = -75.0
		_spot.spot_range = 5.0
		_spot.spot_angle = 28.0
		_spot.light_energy = 2.2
		_spot.light_color = Color("#fff1c9")
		_spot.shadow_enabled = false
		add_child(_spot)
		_sign = BuildUtil.label(self, "★ Showcase ★", Vector3(0, float(def["height"]) + 0.35, 0), 0.0035)
		_sign.modulate = Color("#ffd45c")
	if _spot != null:
		_spot.visible = on
		_sign.visible = on


# --- Breeding ---------------------------------------------------------------------------

## What this tank's fish will do (see genetics.gd).
func breeding_plan() -> Dictionary:
	return Genetics.plan(fish)


func _on_day() -> void:
	if in_hall():
		if dirt > 0.0:
			dirt = 0.0
			_update_water()
		return  # time stands still in the Hall of Fame
	dirt = minf(100.0, dirt + Data.DIRT_PER_DAY + Data.DIRT_PER_FISH * fish.size())
	_update_water()
	# Every fish gets a day older: fry grow, old fish die.
	var dead: Array = []
	for f in fish:
		var was_fry := not FishData.is_adult(f)
		if Game.age_fish(f, display_name(), is_breeding()):
			dead.append(int(f["id"]))
		elif was_fry and _swimmers.has(int(f["id"])):
			_swimmers[int(f["id"])].refresh_size()
	for id in dead:
		remove_fish(id)
	if not is_breeding():
		return
	var p := breeding_plan()
	if not p["ok"]:
		breed_days = 0
		return
	if dirt > Data.BREED_DIRT_LIMIT:
		if not _warned_dirty:
			_warned_dirty = true
			Game.notify.emit("⚠ %s: breeding paused, the water is too dirty. %s" % [display_name(),
				"Your Fish Keeper will clean it." if Game.staff_count("keeper") > 0 else "Hire a Fish Keeper (Staff) to clean it."])
		return  # too dirty to spawn; the count waits
	breed_days += 1
	if breed_days < Data.BREED_DAYS:
		return
	breed_days = 0
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var fry: Array = []
	var females: Array = p["females"].duplicate()
	females.shuffle()
	for i in int(p["broods"]):
		var mother: Dictionary = females[i % females.size()]
		var father: Dictionary = p["males"][rng.randi() % p["males"].size()]
		fry.append_array(Genetics.brood(rng, mother, father, dirt, Game.unlocked))
	Game.add_bred(fry)
	var names := {}
	for f in fry:
		names[FishData.full_name(f, Data.SPECIES[f["species"]]["name"])] = true
	Game.notify.emit("%d fry hatched: %s (in storage)" % [fry.size(), ", ".join(PackedStringArray(names.keys()))])


func info_text() -> String:
	var lines: Array[String] = []
	lines.append("Fish: %d / %d   ·   running cost $%d/month" % [fish.size(), capacity(), int(def.get("upkeep", 0))])
	if is_holding():
		lines.append("Fish bought from the market arrive here. Nothing breeds in a holding tank: move fish to a breeding tank or a display tank.")
	if in_hall():
		lines.append("Hall of Fame: these fish never grow old and the water never gets dirty. They aren't for sale.")
		lines.append("Prestige +%d (stars, plus 4 for each show ribbon)" % hall_prestige())
		return "\n".join(lines)
	var water := "clean" if dirt < Data.CLEAN_AT else ("a bit dirty" if dirt < 50.0 else ("dirty" if dirt < 75.0 else "filthy"))
	lines.append("Water: %s (%d%%)" % [water, int(dirt)])
	if dirt >= Data.CLEAN_AT and Game.staff_count("keeper") == 0:
		lines.append("Hire a Fish Keeper to clean it.")
	if is_breeding():
		var p := breeding_plan()
		if p["ok"]:
			lines.append("%d ♂ : %d ♀  →  %d brood%s every %d days (day %d)" % [p["males"].size(), p["females"].size(),
				p["broods"], "" if p["broods"] == 1 else "s", Data.BREED_DAYS, breed_days])
			if dirt > Data.BREED_DIRT_LIMIT:
				lines.append("Too dirty to breed!")
		lines.append(p["note"])
		if int(p["others"]) > 0:
			lines.append("%d fish of another species won't breed here." % p["others"])
	elif not is_holding():
		lines.append("Appeal: %d  (price +%d%%)" % [int(appeal()), int(price_bonus() * 100.0)])
		if room() != "show":
			lines.append("Customers only see tanks in the showroom.")
	return "\n".join(lines)
