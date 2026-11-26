extends Node3D
## Management-sim camera: looks down at the shop from an angle.
##   WASD / arrow keys or dragging with the right mouse button: pan
##   Q / E or dragging with the middle mouse button: turn
##   Mouse wheel / + -: zoom

const PAN_SPEED := 12.0
const TURN_SPEED := 90.0  # degrees per second
const ZOOM_MIN := 7.0
const ZOOM_MAX := 42.0
const PITCH_NEAR := 42.0
const PITCH_FAR := 58.0
const BOUNDS := Rect2(-30.0, -16.0, 66.0, 48.0)

var camera: Camera3D
var yaw := 30.0
var distance := 24.0
var _yaw_goal := 30.0
var _dist_goal := 24.0
var _pivot_goal := Vector3.ZERO
var _turning := false
var _panning := false


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 40.0
	camera.near = 0.3
	camera.far = 400.0
	add_child(camera)
	_pivot_goal = position
	_apply()


func look_at_point(p: Vector3, dist: float = -1.0, yaw_deg: float = INF) -> void:
	position = p
	_pivot_goal = p
	if dist > 0.0:
		distance = dist
		_dist_goal = dist
	if yaw_deg != INF:
		yaw = yaw_deg
		_yaw_goal = yaw_deg
	_apply()


## Horizontal direction from the pivot towards the camera.
func view_dir() -> Vector3:
	return Vector3(sin(deg_to_rad(yaw)), 0.0, -cos(deg_to_rad(yaw)))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist_goal = clampf(_dist_goal * 0.88, ZOOM_MIN, ZOOM_MAX)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist_goal = clampf(_dist_goal / 0.88, ZOOM_MIN, ZOOM_MAX)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_turning = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_RIGHT and not mb.pressed:
			_panning = false
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _turning:
			_yaw_goal -= mm.relative.x * 0.3
		elif _panning:
			var scale := distance * 0.0018
			_pivot_goal -= _right() * mm.relative.x * scale + _forward() * -mm.relative.y * scale
			_clamp_goal()


## Called by the build tool when a right-press wasn't used to cancel anything.
func start_drag_pan() -> void:
	_panning = true


func _right() -> Vector3:
	return Vector3(-cos(deg_to_rad(yaw)), 0.0, -sin(deg_to_rad(yaw)))


## Away from the camera, along the ground.
func _forward() -> Vector3:
	return -view_dir()


func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if not _typing():
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			move.y += 1
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			move.y -= 1
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			move.x += 1
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			move.x -= 1
		if Input.is_physical_key_pressed(KEY_Q):
			_yaw_goal += TURN_SPEED * delta
		if Input.is_physical_key_pressed(KEY_E):
			_yaw_goal -= TURN_SPEED * delta
		if Input.is_physical_key_pressed(KEY_EQUAL) or Input.is_physical_key_pressed(KEY_KP_ADD):
			_dist_goal = clampf(_dist_goal - 20.0 * delta, ZOOM_MIN, ZOOM_MAX)
		if Input.is_physical_key_pressed(KEY_MINUS) or Input.is_physical_key_pressed(KEY_KP_SUBTRACT):
			_dist_goal = clampf(_dist_goal + 20.0 * delta, ZOOM_MIN, ZOOM_MAX)
	if move != Vector2.ZERO:
		var speed := PAN_SPEED * (0.5 + distance / ZOOM_MAX)
		_pivot_goal += (_right() * move.x + _forward() * move.y).normalized() * speed * delta
		_clamp_goal()
	var k := 1.0 - exp(-delta * 10.0)
	position = position.lerp(_pivot_goal, k)
	yaw = lerpf(yaw, _yaw_goal, k)
	distance = lerpf(distance, _dist_goal, k)
	_apply()


func _clamp_goal() -> void:
	_pivot_goal.x = clampf(_pivot_goal.x, BOUNDS.position.x, BOUNDS.end.x)
	_pivot_goal.z = clampf(_pivot_goal.z, BOUNDS.position.y, BOUNDS.end.y)


func _apply() -> void:
	var t := inverse_lerp(ZOOM_MIN, ZOOM_MAX, distance)
	var pitch := deg_to_rad(lerpf(PITCH_NEAR, PITCH_FAR, t))
	var dir := view_dir()
	camera.position = dir * cos(pitch) * distance + Vector3.UP * sin(pitch) * distance
	camera.look_at(global_position, Vector3.UP)


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit
