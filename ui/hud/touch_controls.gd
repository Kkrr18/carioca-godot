class_name TouchControls
extends Control

## Controles de toque: metade esquerda é analógico de movimento, metade direita é
## área de olhar. Um toque sem arrasto na área de olhar vale como pulo — assim
## não é preciso desenhar mais um botão em cima da tela.

var move_vector := Vector2.ZERO
var visible_controls := true
var joystick_radius := 72.0

var _move_touch: int = -1
var _look_touch: int = -1
var _move_origin := Vector2.ZERO
var _move_current := Vector2.ZERO
var _look_last := Vector2.ZERO
var _look_delta := Vector2.ZERO
var _look_travel: float = 0.0
var _jump_pending: bool = false


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(true)


func _input(event: InputEvent) -> void:
	if not visible_controls:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_drag(event as InputEventScreenDrag)


func _handle_touch(event: InputEventScreenTouch) -> void:
	var half := size.x * 0.55
	if event.pressed:
		if event.position.x < half and _move_touch < 0:
			_move_touch = event.index
			_move_origin = event.position
			_move_current = event.position
			move_vector = Vector2.ZERO
		elif _look_touch < 0:
			_look_touch = event.index
			_look_last = event.position
			_look_travel = 0.0
	else:
		if event.index == _move_touch:
			_move_touch = -1
			move_vector = Vector2.ZERO
		elif event.index == _look_touch:
			if _look_travel < 12.0:
				_jump_pending = true
			_look_touch = -1
	queue_redraw()


func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index == _move_touch:
		_move_current = event.position
		var offset := _move_current - _move_origin
		var radius := maxf(joystick_radius, 1.0)
		var magnitude := minf(offset.length() / radius, 1.0)
		if offset.length() > 1.0:
			var direction := offset / offset.length()
			move_vector = Vector2(direction.x, -direction.y) * magnitude
		else:
			move_vector = Vector2.ZERO
		queue_redraw()
	elif event.index == _look_touch:
		var delta := event.position - _look_last
		_look_last = event.position
		_look_travel += delta.length()
		_look_delta += delta


func consume_look() -> Vector2:
	var value := _look_delta
	_look_delta = Vector2.ZERO
	return value


func consume_jump() -> bool:
	var value := _jump_pending
	_jump_pending = false
	return value


func reset() -> void:
	_move_touch = -1
	_look_touch = -1
	move_vector = Vector2.ZERO
	_look_delta = Vector2.ZERO
	_jump_pending = false


func _draw() -> void:
	if not visible_controls or _move_touch < 0:
		return
	draw_circle(_move_origin, joystick_radius, Color(1.0, 1.0, 1.0, 0.14))
	draw_arc(_move_origin, joystick_radius, 0.0, TAU, 40, Color(1.0, 1.0, 1.0, 0.35), 2.0)
	draw_circle(_move_current, 26.0, Color(1.0, 1.0, 1.0, 0.38))
