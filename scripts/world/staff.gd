extends "res://scripts/world/walker.gd"
## A member of staff. What they do depends on their role:
##   cashier  stands behind a till counter; customers at the front of the queue pay them.
##   stocker  takes a box from the stockroom (back room) to a shelf that's running low.
##   keeper   cleans the dirtiest tank that needs it.
## With nothing to do they wait in the back room.

const Tank := preload("res://scripts/world/tank.gd")
const Shelf := preload("res://scripts/world/shelf.gd")

const PICK_TIME := 1.5
const FILL_TIME := 2.0
const CLEAN_TIME := 3.5
const RETHINK := 1.0

var info: Dictionary  # {"id", "role", "name", "wage"}
var role := ""
## idle, to_break, resting, to_till, at_till, to_stock, picking, to_shelf, filling, to_tank, cleaning
var state := "idle"

var _task: Node3D  # the shelf or tank they're working on
var _carry := 0
var _carry_product := ""
var _slot := 0  # which shelf slot they are filling
var _box: Node3D
var _timer := 0.0
var _rethink := 0.0
var _rng := RandomNumberGenerator.new()


func setup(p_world: Node, p_info: Dictionary) -> void:
	world = p_world
	info = p_info
	role = p_info["role"]
	_rng.seed = int(p_info["id"]) * 4241 + 77
	var r: Dictionary = Data.STAFF[role]
	var models: Array = r["models"]
	_make_body(models[_rng.randi() % models.size()])
	walk_speed = 1.7
	var tag := BuildUtil.label(self, "%s · %s" % [info["name"], r["name"]], Vector3(0, 2.0, 0), 0.0028)
	tag.modulate = r["color"]


## What they're up to, for the Staff panel.
func task_text() -> String:
	match state:
		"to_till":
			return "Going to the till"
		"at_till":
			return "Serving at the till"
		"to_stock", "picking":
			return "Fetching %s" % Data.PRODUCTS[_carry_product]["name"] if _carry_product != "" else "Going to the stockroom"
		"to_shelf", "filling":
			return "Filling a shelf with %s" % Data.PRODUCTS[_carry_product]["name"]
		"to_tank":
			return "Going to clean a tank"
		"cleaning":
			return "Cleaning a tank"
	if role == "cashier" and world.counter() == null:
		return "No till counter to work at"
	return "Waiting for work"


func is_serving() -> bool:
	return state == "at_till"


## Fired (or the shop is closing): give back whatever they're holding.
func dismiss() -> void:
	_drop_task()
	queue_free()


func _physics_process(delta: float) -> void:
	var ts := _ts()
	if ts <= 0.0:
		return
	delta *= ts
	match state:
		"idle", "resting":
			_rethink -= delta
			if _rethink <= 0.0:
				_rethink = RETHINK
				if not _find_work() and state == "idle":
					state = "to_break"
					_go(_break_spot())
		"to_break":
			if _step(delta):
				state = "resting"
				_play("idle")
			else:
				_rethink -= delta
				if _rethink <= 0.0:
					_rethink = RETHINK
					_find_work()
		"to_till":
			var c: Node3D = world.counter()
			if c == null:
				_reset()
			elif _step(delta):
				state = "at_till"
				_play("idle")
		"at_till":
			var c: Node3D = world.counter()
			if c == null:
				_reset()
			else:
				_face(c.global_position, true)
				# The counter was moved: walk round to its new staff side.
				if global_position.distance_to(_till_spot(c)) > 0.8:
					state = "to_till"
					_go(_till_spot(c))
		"to_stock":
			if not _task_ok():
				_reset()
			elif _step(delta):
				state = "picking"
				_timer = PICK_TIME
				_play("inspect")
		"picking":
			_timer -= delta
			if _timer <= 0.0:
				if not _task_ok():
					_reset()
					return
				_carry_product = _task.product(_slot)
				_carry = Game.take_stock(_carry_product, _task.space(_slot))
				if _carry <= 0:
					_reset()
					return
				_hold_box(true)
				state = "to_shelf"
				_go(_task.visit_point())
		"to_shelf":
			if not _task_ok() or _task.product(_slot) != _carry_product:
				_reset()
			elif _step(delta):
				state = "filling"
				_timer = FILL_TIME
				_play("inspect")
				_face(_task.global_position, true)
		"filling":
			_timer -= delta
			if _timer <= 0.0:
				if _task_ok() and _task.product(_slot) == _carry_product:
					var room: int = _task.space(_slot)
					var put := mini(room, _carry)
					_task.add_units(_slot, put)
					_carry -= put
				_reset()
		"to_tank":
			if not _task_ok():
				_reset()
			elif _step(delta):
				state = "cleaning"
				_timer = CLEAN_TIME
				_play("inspect")
				_face(_task.global_position, true)
		"cleaning":
			_timer -= delta
			if _timer <= 0.0:
				if _task_ok():
					_task.clean()
					_say("✨", Color("#bff6ff"))
				_reset()


func _task_ok() -> bool:
	return _task != null and is_instance_valid(_task) and _task.is_inside_tree() and not _task.is_queued_for_deletion() and _task.visible


## Give up the current job: unclaim it and put back anything carried.
func _drop_task() -> void:
	if _task != null and is_instance_valid(_task) and _task.claimed_by == self:
		_task.claimed_by = null
	_task = null
	if _carry > 0 and _carry_product != "":
		Game.stockroom[_carry_product] = int(Game.stockroom.get(_carry_product, 0)) + _carry
		Game.stock_changed.emit()
	_carry = 0
	_carry_product = ""
	_hold_box(false)


func _reset() -> void:
	_drop_task()
	state = "idle"
	_rethink = 0.2


## Look for something to do; true if they started a job.
func _find_work() -> bool:
	match role:
		"cashier":
			var c: Node3D = world.counter()
			if c != null and world.cashier_for(c) == null:
				world.set_cashier(c, self)
			if c != null and world.cashier_for(c) == self:
				state = "to_till"
				_go(_till_spot(c))
				return true
		"stocker":
			var best: Node3D = null
			for o in world.objects():
				if o is Shelf and o.claimed_by == null and o.wants_stock():
					if best == null or o.total_units() < best.total_units():
						best = o
			if best != null:
				_task = best
				best.claimed_by = self
				_slot = best.wants_slot()
				_carry_product = best.product(_slot)
				state = "to_stock"
				_go(world.stockroom_spot())
				return true
		"keeper":
			var best: Node3D = null
			for o in world.objects():
				if o is Tank and o.claimed_by == null and o.needs_cleaning():
					if best == null or o.clean_priority() > best.clean_priority():
						best = o
			if best != null:
				_task = best
				best.claimed_by = self
				state = "to_tank"
				_go(best.visit_point())
				return true
	return false


func _till_spot(c: Node3D) -> Vector3:
	var depth: float = (c.def["size"] as Vector2).y
	return c.global_position - c.front() * (depth * 0.5 + 0.45)


func _break_spot() -> Vector3:
	var base: Vector3 = world.break_spot()
	return base + Vector3(_rng.randf_range(-1.5, 1.5), 0, _rng.randf_range(-0.8, 0.8))


func _hold_box(on: bool) -> void:
	if on and _box == null:
		_box = Synty.make("Props/SM_Prop_Cardboard_Box_01")
		var b := Synty.bounds(_box)
		if b.size.y > 0.0:
			_box.scale = Vector3.ONE * (0.38 / maxf(b.size.x, maxf(b.size.y, b.size.z)))
		_box.position = Vector3(0, 0.95, 0.35)
		_model.add_child(_box)
	elif not on and _box != null:
		_box.queue_free()
		_box = null
