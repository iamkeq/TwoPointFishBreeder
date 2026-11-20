extends RefCounted
## Saving and loading. A save is one JSON file in user:// holding the books (Game) and the
## world (everything you've built, with the fish in each tank and the stock on each shelf,
## plus where the camera was). Customers aren't saved; they just come back.
##
## Loading works by reloading the main scene: the save is parked in Game.pending_load,
## and main.gd rebuilds the shop from it instead of making the starting shop.

const MANUAL := "user://save.json"
const AUTO := "user://autosave.json"
const VERSION := 1


static func exists(path: String) -> bool:
	return FileAccess.file_exists(path)


## "15 March, Year 1 · $12,340" for the load menu, or "" if there's no save there.
static func describe(path: String) -> String:
	var d := read(path)
	if d.is_empty():
		return ""
	return "%s · $%s" % [d.get("date", "?"), str(d.get("money", "?"))]


static func save(path: String, world: Node) -> bool:
	var data := {
		"version": VERSION,
		"date": Game.date_text(),
		"money": Game.money,
		"game": Game.to_dict(),
		"world": world.to_save(),
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		Game.notify.emit("Couldn't save: " + error_string(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	return intify(parsed)


## Start loading `path`: the scene reloads and main.gd picks it up. False if unreadable.
static func load_game(path: String, tree: SceneTree) -> bool:
	var d := read(path)
	if d.is_empty() or not d.has("game"):
		Game.notify.emit("That save couldn't be read")
		return false
	Game.pending_load = d
	tree.reload_current_scene()
	return true


## JSON turns every number into a float; put whole numbers back as ints (ids, counts, money).
static func intify(v: Variant) -> Variant:
	if v is float and is_equal_approx(v, round(v)) and absf(v) < 1e15:
		return int(v)
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = intify(v[k])
		return out
	if v is Array:
		var out: Array = []
		for x in v:
			out.append(intify(x))
		return out
	return v
