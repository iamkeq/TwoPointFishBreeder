extends Node
## Placing, moving, turning, selecting and selling things with the mouse.
##   Left click: place (or select something when not placing)
##   R or mouse wheel while holding Shift: turn a quarter
##   Right click / Esc: cancel placing (right-drag pans the camera when not placing)
## Edit mode (M): click anything to pick it up and put it somewhere else, R turns what's
## under the mouse, Delete sells it. Esc or M again to finish.

const Placeable := preload("res://scripts/world/placeable.gd")
const L := preload("res://scripts/world/layout.gd")
const Data := preload("res://scripts/data.gd")

signal selection_changed(obj: Node)
signal mode_changed

var world: Node
var rig: Node3D

var placing_id := ""
var moving: Node3D  # the object being moved (hidden while its ghost follows the mouse)
var selected: Node3D
var _ghost: Node3D
var _rot := 0
var _valid := false
var _reason := ""
var edit_mode := false
var _hover: Node3D  # in edit mode, what the mouse is over


func toggle_edit(on: bool = not edit_mode) -> void:
	if on == edit_mode:
		return
	cancel()
	select(null)
	_set_hover(null)
	edit_mode = on
	mode_changed.emit()


func _set_hover(obj: Node3D) -> void:
	if obj == _hover:
		return
	if _hover != null and is_instance_valid(_hover) and _hover != selected:
		_hover.set_selected(false)
	_hover = obj
	if _hover != null:
		_hover.set_selected(true)


func is_busy() -> bool:
	return _ghost != null


func start_place(id: String) -> void:
	cancel()
	select(null)
	placing_id = id
	_make_ghost(id, _rot)
	mode_changed.emit()


func start_move(obj: Node3D) -> void:
	cancel()
	select(null)
	_set_hover(null)
	moving = obj
	placing_id = obj.item_id
	_rot = obj.rot
	obj.visible = false
	_make_ghost(obj.item_id, obj.rot)
	_ghost.position = obj.position
	mode_changed.emit()


func cancel() -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	if moving != null and is_instance_valid(moving):
		moving.visible = true
	moving = null
	placing_id = ""
	mode_changed.emit()


func select(obj: Node3D) -> void:
	if selected != null and is_instance_valid(selected):
		selected.set_selected(false)
	selected = obj
	if selected != null:
		selected.set_selected(true)
	selection_changed.emit(selected)


func rotate_ghost() -> void:
	if _ghost == null:
		return
	_rot = posmod(_rot + 1, 4)
	_ghost.set_rot(_rot)
	_update_ghost(get_viewport().get_mouse_position())


func status_text() -> String:
	if _ghost == null:
		if edit_mode:
			return "EDIT MODE: click something to pick it up and move it   [R] turn   [Del] sell   [M] or [Esc] done"
		return ""
	var verb := "Moving" if moving != null else "Placing"
	var cost := "" if moving != null else "  ($%d)" % int(Data.ITEMS[placing_id]["cost"])
	var why := "" if _valid else "   ✖ " + _reason
	return "%s %s%s   [R] turn   [Right click] cancel%s" % [verb, Data.ITEMS[placing_id]["name"], cost, why]


func _make_ghost(id: String, r: int) -> void:
	_ghost = world.make_object(id, true)
	_ghost.set_rot(r)
	world.add_child(_ghost)
	_update_ghost(get_viewport().get_mouse_position())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _ghost != null:
		_update_ghost((event as InputEventMouseMotion).position)
	elif event is InputEventMouseMotion and edit_mode:
		_set_hover(_pick((event as InputEventMouseMotion).position))
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if _ghost != null:
				_confirm()
			elif edit_mode:
				var obj := _pick(mb.position)
				if obj != null:
					start_move(obj)
			else:
				var award := _pick_award(mb.position)
				if not award.is_empty():
					world.hud.show_award(award)
				else:
					select(_pick(mb.position))
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if _ghost != null:
				cancel()
				get_viewport().set_input_as_handled()
			else:
				rig.start_drag_pan()
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		match (event as InputEventKey).physical_keycode:
			KEY_R:
				if _ghost == null and edit_mode and _hover != null and is_instance_valid(_hover):
					_turn(_hover)
				else:
					rotate_ghost()
			KEY_ESCAPE:
				if _ghost != null:
					cancel()
				elif edit_mode:
					toggle_edit(false)
				else:
					select(null)
			KEY_DELETE:
				if edit_mode and _ghost == null and _hover != null and is_instance_valid(_hover):
					var obj := _hover
					_set_hover(null)
					world.sell(obj)
				elif selected != null:
					world.sell(selected)


func _ground_point(screen: Vector2) -> Variant:
	var cam: Camera3D = rig.camera
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return null
	var t := -from.y / dir.y
	if t < 0.0:
		return null
	return from + dir * t


func _update_ghost(screen: Vector2) -> void:
	var p: Variant = _ground_point(screen)
	if p == null:
		return
	var pos := Vector3(snappedf((p as Vector3).x, 0.25), 0.0, snappedf((p as Vector3).z, 0.25))
	# Keep edges on the 0.25 m grid when half the footprint isn't a multiple of 0.25.
	var s: Vector2 = _ghost.size2()
	if fmod(s.x * 0.5, 0.25) > 0.01:
		pos.x += 0.125
	if fmod(s.y * 0.5, 0.25) > 0.01:
		pos.z += 0.125
	_ghost.position = pos
	var check: Dictionary = world.can_place(placing_id, _ghost.rect_at(pos), moving)
	_valid = check["ok"]
	_reason = check.get("why", "")
	if moving == null and _valid and not Game.can_afford(int(Data.ITEMS[placing_id]["cost"])):
		_valid = false
		_reason = "not enough money"
	_ghost.set_valid(_valid)
	mode_changed.emit()


func _confirm() -> void:
	if not _valid:
		Game.notify.emit("Can't put it there: " + _reason)
		return
	if moving != null:
		moving.position = _ghost.position
		moving.set_rot(_rot)
		moving.visible = true
		var moved := moving
		moving = null
		_ghost.queue_free()
		_ghost = null
		placing_id = ""
		world.objects_changed()
		if not edit_mode:
			select(moved)
		mode_changed.emit()
		return
	var id := placing_id
	if not Game.spend(int(Data.ITEMS[id]["cost"]), "construction"):
		return
	world.place(id, _ghost.position, _rot)
	# Keep placing more of the same (shift not needed), like the sim games.
	_update_ghost(get_viewport().get_mouse_position())


## The show award on a wall under the mouse ({} if none).
func _pick_award(screen: Vector2) -> Dictionary:
	var cam: Camera3D = rig.camera
	var from := cam.project_ray_origin(screen)
	var q := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(screen) * 300.0, 8)
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {}
	var n: Node = hit["collider"]
	while n != null and not n.has_meta("award"):
		n = n.get_parent()
	if n == null or not (n as Node3D).is_visible_in_tree():
		return {}
	return n.get_meta("award")


func _pick(screen: Vector2) -> Node3D:
	var cam: Camera3D = rig.camera
	var from := cam.project_ray_origin(screen)
	var to := from + cam.project_ray_normal(screen) * 300.0
	var q := PhysicsRayQueryParameters3D.create(from, to, Placeable.LAYER_PICK)
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	var n: Node = hit["collider"]
	while n != null and not (n is Placeable):
		n = n.get_parent()
	return n as Node3D


## Turn something a quarter where it stands, if there's room.
func _turn(obj: Node3D) -> void:
	var old: int = obj.rot
	obj.set_rot(old + 1)
	if not world.can_place(obj.item_id, obj.rect(), obj)["ok"]:
		obj.set_rot(old)
		Game.notify.emit("No room to turn it there")
	else:
		world.objects_changed()
