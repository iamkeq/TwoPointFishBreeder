extends "res://scripts/world/placeable.gd"
## A supply shelf. It has a few slots (one per board), and each slot holds one product with
## limited room, so a shelf can sell a few different things but not much of each.
## A stocker carries boxes from the stockroom in the back room to fill the slots up.
## Customers take items off it and pay at the till.

## One per board: {"product": id or "", "units": n}.
var slots: Array = []
## The stocker on their way with a box for it.
var claimed_by: Node
var _stock_node: Node3D


func _after_setup() -> void:
	slots = []
	for i in slot_count():
		slots.append({"product": "", "units": 0})
	if ghost:
		return
	_stock_node = Node3D.new()
	_stock_node.name = "Stock"
	add_child(_stock_node)


func slot_count() -> int:
	return int(def.get("slots", 1))


## Room for each product slot.
func capacity() -> int:
	return int(def["capacity"])


func product(i: int) -> String:
	return slots[i]["product"]


func units(i: int) -> int:
	return int(slots[i]["units"])


## How many of a product are on this shelf (all slots).
func units_of(id: String) -> int:
	var n := 0
	for s in slots:
		if s["product"] == id:
			n += int(s["units"])
	return n


func total_units() -> int:
	var n := 0
	for s in slots:
		n += int(s["units"])
	return n


func set_product(id: String, i: int = 0) -> void:
	if id == product(i):
		return
	# Whatever was in the slot goes back to the stockroom.
	if product(i) != "" and units(i) > 0:
		Game.stockroom[product(i)] = int(Game.stockroom.get(product(i), 0)) + units(i)
	slots[i] = {"product": id, "units": 0}
	_refresh()
	Game.stock_changed.emit()


## Room left in a slot.
func space(i: int) -> int:
	return capacity() - units(i) if product(i) != "" else 0


## The slot most worth a stocker's trip (half empty or more and the stockroom has some),
## or -1.
func wants_slot() -> int:
	var best := -1
	for i in slots.size():
		if product(i) == "" or int(Game.stockroom.get(product(i), 0)) <= 0:
			continue
		if space(i) * 2 >= capacity() and (best < 0 or units(i) < units(best)):
			best = i
	return best


func wants_stock() -> bool:
	return wants_slot() >= 0


## A stocker puts `n` units in slot `i`.
func add_units(i: int, n: int) -> void:
	slots[i]["units"] = mini(capacity(), units(i) + n)
	_refresh()


## Straight from the stockroom, no stocker (only used for the shop you start with).
func fill_now() -> void:
	for i in slots.size():
		if product(i) != "":
			add_units(i, Game.take_stock(product(i), space(i)))


func has_stock() -> bool:
	return total_units() > 0


## A customer takes up to `n` of something from a random stocked slot.
## Returns [product id, how many they got].
func take_any(rng: RandomNumberGenerator, n: int) -> Array:
	var stocked: Array = []
	for i in slots.size():
		if units(i) > 0:
			stocked.append(i)
	if stocked.is_empty():
		return ["", 0]
	var i: int = stocked[rng.randi() % stocked.size()]
	var got := mini(n, units(i))
	slots[i]["units"] = units(i) - got
	_refresh()
	return [product(i), got]


func on_removed() -> void:
	for i in slots.size():
		if product(i) != "" and units(i) > 0:
			Game.stockroom[product(i)] = int(Game.stockroom.get(product(i), 0)) + units(i)
			slots[i]["units"] = 0
	Game.stock_changed.emit()


func to_save() -> Array:
	return slots.duplicate(true)


func restore(saved: Variant, old_product: String = "", old_units: int = 0) -> void:
	if saved is Array:
		for i in mini(slots.size(), (saved as Array).size()):
			slots[i] = {"product": str(saved[i].get("product", "")), "units": mini(capacity(), int(saved[i].get("units", 0)))}
	elif old_product != "":
		# Saves from before shelves had slots: one product, any extra goes to the stockroom.
		slots[0] = {"product": old_product, "units": mini(capacity(), old_units)}
		if old_units > capacity():
			Game.stockroom[old_product] = int(Game.stockroom.get(old_product, 0)) + old_units - capacity()
	_refresh()


func info_text() -> String:
	var lines: Array = ["%d slots, room for %d of each" % [slots.size(), capacity()]]
	var empty := 0
	for i in slots.size():
		if product(i) == "":
			empty += 1
			lines.append("Slot %d: empty" % (i + 1))
			continue
		var p: Dictionary = Data.PRODUCTS[product(i)]
		lines.append("Slot %d: %s %d/%d ($%d each, %d in stockroom)" % [i + 1, p["name"], units(i), capacity(),
			int(p["price"]), int(Game.stockroom.get(product(i), 0))])
	if empty == slots.size():
		lines.append("Pick a product for each slot below.")
	elif Game.staff_count("stocker") == 0:
		lines.append("Hire a Stocker to fill it from the stockroom.")
	return "\n".join(lines)


## Product models on the boards: one board per slot, one model per unit.
func _refresh() -> void:
	if _stock_node == null:
		return
	for c in _stock_node.get_children():
		c.queue_free()
	var b := Synty.bounds(model)
	var boards := [0.21, 0.58, 0.925]
	var width: float = (def["size"] as Vector2).x - 0.25
	var per_board := maxi(1, int(width / 0.17))
	for si in mini(slots.size(), boards.size()):
		var id := product(si)
		var n := mini(units(si), per_board)
		if id == "" or n <= 0:
			continue
		var proto := Synty.make(Data.PRODUCTS[id]["model"])
		var pb := Synty.bounds(proto)
		proto.free()
		if pb.size.y <= 0.0:
			continue
		var s := minf(0.24 / pb.size.y, 0.14 / maxf(pb.size.x, pb.size.z))
		var board: float = boards[si] if slots.size() >= 3 else boards[si * 2]
		for k in n:
			var item := Synty.make(Data.PRODUCTS[id]["model"])
			item.scale = Vector3.ONE * s
			var x := -width * 0.5 + (float(k) + 0.5) * (width / per_board)
			item.position = Vector3(x, b.size.y * board - pb.position.y * s + 0.01, 0.05)
			_stock_node.add_child(item)
