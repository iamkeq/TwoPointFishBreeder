extends "res://scripts/world/walker.gd"
## A shopper. Comes in the front door, wanders between a few tanks and shelves looking at
## them, picks up fish or supplies they like, queues at the till and pays the cashier, then
## leaves. With nobody at the till they give up after a while, put everything back and
## leave disappointed, as does anyone who wanted something and found nothing.

const LOOK_TIME := Vector2(2.0, 4.5)
const PAY_TIME := 1.6
## Game seconds they'll wait in the till queue before giving up.
const PATIENCE := 35.0
const PEOPLE := [
	"Characters/Characters/SM_Chr_Shopper_Female_01", "Characters/Characters/SM_Chr_Shopper_Male_01",
	"Characters/Characters/SM_Chr_Gym_Female_01", "Characters/Characters/SM_Chr_Gym_Male_01",
	"Characters/Characters/SM_Chr_Musician_Female_01", "Characters/Characters/SM_Chr_Musician_Male_01",
	"Characters/Characters/SM_Chr_Hunter_Male_01", "Characters/Characters/SM_Chr_Shopper_Female_01",
]

var wants_fish := false
var wants_supplies := false
## [{"kind": "fish"/"item", "name", "price", "fish": {...} or "product": id}]
var basket: Array = []
var done := false
## walk, look, queue, waiting (at their queue spot), pay, leave
var state := "walk"

var _rng := RandomNumberGenerator.new()
var _plan: Array = []
var _target_obj: Node3D
var _timer := 0.0
var _patience := PATIENCE


func setup(p_world: Node, seed_value: int) -> void:
	world = p_world
	walk_speed = 1.7
	_rng.seed = seed_value
	var roll := _rng.randf()
	wants_fish = roll < 0.75
	wants_supplies = roll > 0.45
	_make_body(PEOPLE[_rng.randi() % PEOPLE.size()])
	_plan_visits()


func _ready() -> void:
	_next_stop()


func _plan_visits() -> void:
	var options: Array = []
	for obj in world.objects():
		if obj.room() != "show":
			continue
		if obj.def["kind"] == "tank" or obj.def["kind"] == "shelf" or (obj.def["kind"] == "decor" and float(obj.def.get("appeal", 0.0)) >= 10.0):
			options.append(obj)
	# Better-looking tanks draw people in: rank by appeal plus a bit of chance.
	var scored: Array = []
	for o in options:
		scored.append([_interest(o), o])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	var n := mini(scored.size(), _rng.randi_range(2, 4))
	_plan = scored.slice(0, n).map(func(x): return x[1])
	_plan.shuffle()
	# Some come to see the Hall of Fame as well.
	var sights: Array = world.hall_sights()
	if not sights.is_empty() and _rng.randf() < 0.35 + world.hall_bonus():
		_plan.insert(_rng.randi() % (_plan.size() + 1), sights[_rng.randi() % sights.size()])


func _interest(obj: Node) -> float:
	var v := _rng.randf() * 40.0
	if obj.def["kind"] == "tank":
		v += obj.appeal() * (1.0 if wants_fish else 0.4)
	elif obj.def["kind"] == "shelf":
		v += 30.0 if wants_supplies else 0.0
	else:
		v += float(obj.def.get("appeal", 0.0))
	return v


func _next_stop() -> void:
	while not _plan.is_empty():
		var obj: Node3D = _plan.pop_front()
		if is_instance_valid(obj) and obj.is_inside_tree():
			_target_obj = obj
			_go(obj.visit_point())
			state = "walk"
			return
	_target_obj = null
	if not basket.is_empty() and world.counter() != null:
		state = "queue"
		_go(world.join_queue(self))
	else:
		_leave()


func _leave() -> void:
	if not done:
		done = true
		Game.add_stat("customers")
		var wanted := wants_fish or wants_supplies
		if basket.is_empty() and wanted:
			Game.add_stat("unhappy")
			Game.rate_visit(false)
			_say("☹", Color("#ff8a7a"))
		else:
			Game.add_stat("happy")
			Game.rate_visit(true)
	state = "leave"
	_go(L.STREET_SPOT + Vector3(_rng.randf_range(-6.0, 6.0), 0, 0))


## The till queue shuffled forward.
func set_queue_spot(p: Vector3) -> void:
	if state == "queue" or state == "waiting":
		state = "queue"
		_go(p)


## Called by the world when they're at the front and a cashier is ready.
func start_paying() -> void:
	state = "pay"
	_timer = PAY_TIME
	_play("idle")


func _physics_process(delta: float) -> void:
	var ts := _ts()
	if ts <= 0.0:
		return
	delta *= ts
	match state:
		"walk", "queue", "leave":
			if _step(delta):
				_arrived()
		"look":
			_timer -= delta
			if _target_obj != null and is_instance_valid(_target_obj):
				_face(_target_obj.global_position)
			if _timer <= 0.0:
				_decide()
				_next_stop()
		"waiting":
			var counter: Node3D = world.counter()
			if counter != null:
				_face(counter.global_position)
			_patience -= delta
			if _patience < PATIENCE * 0.5 and _clip != "foot_tap" and _rng.randf() < 0.01:
				_play("foot_tap")
			if _patience <= 0.0:
				_give_up()
		"pay":
			_timer -= delta
			if _timer <= 0.0:
				_pay()


func _arrived() -> void:
	match state:
		"walk":
			state = "look"
			_timer = _rng.randf_range(LOOK_TIME.x, LOOK_TIME.y)
			_play("inspect" if _rng.randf() < 0.5 else "idle")
		"queue":
			state = "waiting"
			_play("idle")
		"leave":
			queue_free()


func _decide() -> void:
	if _target_obj == null or not is_instance_valid(_target_obj):
		return
	var kind: String = _target_obj.def["kind"]
	if _target_obj.room() == "hall":
		_say("★", Color("#ffd45c"))
	elif kind == "tank" and wants_fish and _count("fish") < 2:
		var got: Dictionary = _target_obj.try_sell(_rng)
		if not got.is_empty():
			basket.append(got)
			_say("♥", Color("#ff8fb0"))
	elif kind == "shelf" and wants_supplies and _target_obj.has_stock():
		var got: Array = _target_obj.take_any(_rng, _rng.randi_range(1, 3))
		var n: int = got[1]
		if n > 0:
			var id: String = got[0]
			var p: Dictionary = Data.PRODUCTS[id]
			for i in n:
				basket.append({"kind": "item", "name": p["name"], "price": int(p["price"]), "product": id})
			_say("✓", Color("#9dffa8"))


func _count(kind: String) -> int:
	var n := 0
	for b in basket:
		if b["kind"] == kind:
			n += 1
	return n


func _pay() -> void:
	var total := 0
	for b in basket:
		total += int(b["price"])
		if b["kind"] == "fish":
			Game.earn(int(b["price"]), "fish_sales")
			Game.add_stat("fish_sold")
		else:
			Game.earn(int(b["price"]), "supply_sales")
			Game.add_stat("items_sold")
	world.left_till(self)
	if total > 0:
		world.float_text(global_position + Vector3(0, 2.3, 0), "+$%d" % total, Color("#7dff8a"))
	_leave()


## Nobody served them: everything goes back (fish to storage, supplies to the stockroom).
func _give_up() -> void:
	for b in basket:
		if b["kind"] == "fish":
			Game.store_fish(b["fish"])
		else:
			Game.stockroom[b["product"]] = int(Game.stockroom.get(b["product"], 0)) + 1
	basket.clear()
	Game.stock_changed.emit()
	Game.add_stat("gave_up")
	world.left_till(self)
	_leave()
	_say("☹ No one at the till!", Color("#ff8a7a"))
