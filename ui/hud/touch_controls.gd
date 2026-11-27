class_name TouchControls
extends Control

## Controles de toque: analógico de movimento, área de olhar e botões.
##
## Na Etapa 1 eram dois retângulos invisíveis e um toque curto valia como pulo.
## Funcionava, mas escondia a metade das ações: sprint e interação só existiam no
## teclado, e o jogador de celular não tinha como descobrir que havia uma
## interação ao alcance.
##
## Agora há botões desenhados — pulo, sprint e interação — além de:
##
##   - analógico na metade esquerda, com amplitude analógica (andar/correr);
##   - olhar arrastando na metade direita;
##   - **pinça de dois dedos** para o zoom da câmera;
##   - layout derivado do tamanho da tela, com escala por `layout_scale`;
##   - sensibilidade de olhar configurável (`look_sensitivity`).
##
## A lógica de toque é toda por `handle_touch`/`handle_drag`, que recebem números
## em vez de `InputEvent`. É o que permite testar "tocar no botão de pulo marca
## pedido de pulo" sem emular evento de tela.

signal interact_requested()

const LOOK_SENSITIVITY := 0.0038

var move_vector := Vector2.ZERO
var visible_controls := true
var joystick_radius := 72.0

var sprint_active: bool = false
var walk_active: bool = false
var look_sensitivity: float = LOOK_SENSITIVITY
var layout_scale: float = 1.0

## Toque curto na área de olhar continua valendo como pulo (comportamento da
## Etapa 1). Desligue para exigir o botão.
var tap_to_jump := true

var _move_touch: int = -1
var _look_touch: int = -1
var _pinch_touch: int = -1
var _move_origin := Vector2.ZERO
var _move_current := Vector2.ZERO
var _look_last := Vector2.ZERO
var _look_delta := Vector2.ZERO
var _look_travel: float = 0.0
var _pinch_last: float = 0.0
## Posição atual do dedo de pinça: a abertura é a distância real entre os dois
## dedos. Sem isto, a distância era medida contra a posição sobrescrita do dedo
## de olhar — dava sempre 0, e o zoom acumulava desvio a cada arrasto.
var _pinch_position := Vector2.ZERO
var _zoom_delta: float = 0.0
var _jump_pending: bool = false
var _interact_pending: bool = false
var _sprint_touch: int = -1
var _jump_touch: int = -1
var _interact_touch: int = -1
var _interact_label: String = ""
var _interact_available: bool = false

## Etapa 5 — modo veículo. O HUD liga e desliga conforme o motorista entra e
## sai. O analógico continua na metade esquerda, mas agora é o volante; a
## direita troca os botões de movimento pelos pedais, buzina, freio de mão,
## câmera e sair.
var vehicle_mode: bool = false
var handbrake_active: bool = false
var horn_active: bool = false
var _throttle_touch: int = -1
var _brake_touch: int = -1
var _handbrake_touch: int = -1
var _horn_touch: int = -1
var _camera_mode_pending: bool = false


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(true)
	_layout()


func _input(event: InputEvent) -> void:
	if not visible_controls:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		handle_touch(touch.index, touch.position, touch.pressed)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		handle_drag(drag.index, drag.position)


# --- geometria do layout -----------------------------------------------------


func _layout() -> void:
	var shortest := minf(size.x, size.y)
	if shortest <= 0.0:
		shortest = 720.0
	layout_scale = clampf(shortest / 420.0, 0.8, 1.7)
	joystick_radius = 72.0 * layout_scale


func button_radius(button: String) -> float:
	var base := 34.0
	if button == "sprint":
		base = 30.0
	if button == "throttle" or button == "brake":
		base = 42.0
	if button == "handbrake" or button == "horn" or button == "camera" or button == "exit":
		base = 26.0
	return base * layout_scale


func button_center(button: String) -> Vector2:
	var margin := 96.0 * layout_scale
	match button:
		"jump":
			return Vector2(size.x - margin, size.y - margin)
		"sprint":
			return Vector2(size.x - margin * 2.0, size.y - margin * 0.62)
		"interact":
			return Vector2(size.x - margin * 0.92, size.y - margin * 1.86)
		# Modo veículo: pedais grandes embaixo, mão/buzina em cima,
		# câmera e sair nas bordas onde o polegar não fica em cima do pedal.
		"throttle":
			return Vector2(size.x - margin * 1.0, size.y - margin * 0.62)
		"brake":
			return Vector2(size.x - margin * 2.35, size.y - margin * 0.62)
		"handbrake":
			return Vector2(size.x - margin * 1.68, size.y - margin * 1.8)
		"horn":
			return Vector2(size.x - margin * 0.5, size.y - margin * 1.8)
		"camera":
			return Vector2(size.x - margin * 3.3, size.y - margin * 0.62)
		"exit":
			return Vector2(size.x - margin * 3.3, size.y - margin * 1.8)
		_:
			return Vector2(size.x - margin, size.y - margin)


func _active_buttons() -> Array:
	if vehicle_mode:
		return ["throttle", "brake", "handbrake", "horn", "camera", "exit"]
	return ["jump", "sprint", "interact"]


func hit_button(position: Vector2) -> String:
	for button in _active_buttons():
		if button == "interact" and not _interact_available:
			continue
		if position.distance_to(button_center(button)) <= button_radius(button) * 1.15:
			return button
	return ""


func look_area_starts_at() -> float:
	return size.x * 0.55


# --- entrada -----------------------------------------------------------------


func handle_touch(index: int, position: Vector2, pressed: bool) -> void:
	_layout()
	if pressed:
		var button := hit_button(position)
		if vehicle_mode:
			match button:
				"throttle":
					if _throttle_touch < 0:
						_throttle_touch = index
					queue_redraw()
					return
				"brake":
					if _brake_touch < 0:
						_brake_touch = index
					queue_redraw()
					return
				"handbrake":
					if _handbrake_touch < 0:
						_handbrake_touch = index
						handbrake_active = true
					queue_redraw()
					return
				"horn":
					if _horn_touch < 0:
						_horn_touch = index
						horn_active = true
					queue_redraw()
					return
				"camera":
					_camera_mode_pending = true
					queue_redraw()
					return
				"exit":
					if _interact_touch < 0:
						_interact_touch = index
						_interact_pending = true
						interact_requested.emit()
					queue_redraw()
					return
		if button == "jump" and _jump_touch < 0:
			_jump_touch = index
			_jump_pending = true
			queue_redraw()
			return
		if button == "sprint" and _sprint_touch < 0:
			_sprint_touch = index
			sprint_active = true
			queue_redraw()
			return
		if button == "interact" and _interact_touch < 0:
			_interact_touch = index
			_interact_pending = true
			interact_requested.emit()
			queue_redraw()
			return

		if position.x < look_area_starts_at() and _move_touch < 0:
			_move_touch = index
			_move_origin = position
			_move_current = position
			move_vector = Vector2.ZERO
		elif _look_touch < 0:
			_look_touch = index
			_look_last = position
			_look_travel = 0.0
		elif _pinch_touch < 0 and position.x >= look_area_starts_at():
			# Pinça de zoom: só o **segundo dedo na área de olhar**, com o
			# primeiro ainda olhando. Um toque na metade esquerda (ou um
			# terceiro em qualquer lugar) era tratado como pinça com uma
			# distância inicial arbitrária — e a câmera desbocava no zoom
			# justamente quando se andava com o analógico e olhava com o dedo.
			_pinch_touch = index
			_pinch_position = position
			_pinch_last = position.distance_to(_look_last)
		# Dedos além de analógico + olhar + pinça não têm papel: ignorados.
		queue_redraw()
		return

	if index == _move_touch:
		_move_touch = -1
		move_vector = Vector2.ZERO
	elif index == _look_touch:
		if tap_to_jump and _look_travel < 12.0 and not vehicle_mode:
			_jump_pending = true
		_look_touch = -1
		_pinch_touch = -1
		_pinch_last = 0.0
		_pinch_position = Vector2.ZERO
	elif index == _pinch_touch:
		_pinch_touch = -1
		_pinch_last = 0.0
		_pinch_position = Vector2.ZERO
	elif index == _jump_touch:
		_jump_touch = -1
	elif index == _sprint_touch:
		_sprint_touch = -1
		sprint_active = false
	elif index == _interact_touch:
		_interact_touch = -1
	elif index == _throttle_touch:
		_throttle_touch = -1
	elif index == _brake_touch:
		_brake_touch = -1
	elif index == _handbrake_touch:
		_handbrake_touch = -1
		handbrake_active = false
	elif index == _horn_touch:
		_horn_touch = -1
		horn_active = false
	queue_redraw()


func handle_drag(index: int, position: Vector2) -> void:
	if index == _move_touch:
		_move_current = position
		var offset := _move_current - _move_origin
		var radius := maxf(joystick_radius, 1.0)
		var magnitude := minf(offset.length() / radius, 1.0)
		if offset.length() > 1.0:
			var direction := offset / offset.length()
			move_vector = Vector2(direction.x, -direction.y) * magnitude
		else:
			move_vector = Vector2.ZERO
		queue_redraw()
	elif index == _look_touch:
		var delta := position - _look_last
		_look_last = position
		_look_travel += delta.length()
		_look_delta += delta
		if _pinch_touch >= 0:
			# Abertura real entre os dois dedos: o dedo de olhar e o de pinça.
			# Medir contra `_look_last` depois de sobrescrevê-lo dava sempre 0,
			# e `_zoom_delta` acumulava - _pinch_last por evento de arrasto.
			var span := position.distance_to(_pinch_position)
			_zoom_delta += span - _pinch_last
			_pinch_last = span
	elif index == _pinch_touch:
		_pinch_position = position
		if _look_touch >= 0:
			var span := _look_last.distance_to(_pinch_position)
			_zoom_delta += span - _pinch_last
			_pinch_last = span


func consume_look() -> Vector2:
	var value := _look_delta
	_look_delta = Vector2.ZERO
	return value


func consume_jump() -> bool:
	var value := _jump_pending
	_jump_pending = false
	return value


func consume_interact() -> bool:
	var value := _interact_pending
	_interact_pending = false
	return value


func consume_zoom() -> float:
	var value := _zoom_delta
	_zoom_delta = 0.0
	return value


## Pedal do modo veículo: +1 acelerador pisado, -1 freio/ré, 0 pé solto.
## Segurar o dedo é pisar — sem estado para consumir, é leitura direta.
func pedal_value() -> float:
	if _throttle_touch >= 0:
		return 1.0
	if _brake_touch >= 0:
		return -1.0
	return 0.0


func consume_camera_mode() -> bool:
	var value := _camera_mode_pending
	_camera_mode_pending = false
	return value


## Chamado pelo HUD quando a interação disponível muda. Sem rótulo, o botão some.
func set_interaction(label: String) -> void:
	var available := not label.is_empty()
	if available == _interact_available and label == _interact_label:
		return
	_interact_available = available
	_interact_label = label
	queue_redraw()


func is_interaction_visible() -> bool:
	return _interact_available


func reset() -> void:
	_move_touch = -1
	_look_touch = -1
	_pinch_touch = -1
	_pinch_last = 0.0
	_pinch_position = Vector2.ZERO
	_jump_touch = -1
	_sprint_touch = -1
	_interact_touch = -1
	_throttle_touch = -1
	_brake_touch = -1
	_handbrake_touch = -1
	_horn_touch = -1
	move_vector = Vector2.ZERO
	_look_delta = Vector2.ZERO
	_jump_pending = false
	_interact_pending = false
	_zoom_delta = 0.0
	sprint_active = false
	handbrake_active = false
	horn_active = false
	_camera_mode_pending = false


func _draw() -> void:
	if not visible_controls:
		return
	_layout()
	_draw_stick()
	if vehicle_mode:
		_draw_button("throttle", "acelerar", _throttle_touch >= 0)
		_draw_button("brake", "freio/ré", _brake_touch >= 0)
		_draw_button("handbrake", "mão", handbrake_active)
		_draw_button("horn", "buzina", horn_active)
		_draw_button("camera", "câmera", false)
		_draw_button("exit", "sair", _interact_touch >= 0)
	else:
		_draw_button("sprint", "correr", sprint_active)
		_draw_button("jump", "pular", _jump_touch >= 0)
		if _interact_available:
			_draw_button("interact", _short_label(_interact_label), _interact_touch >= 0)


func _draw_stick() -> void:
	if _move_touch < 0:
		# Base do analógico sempre visível: sem ela o jogador novo não sabe onde
		# encostar o dedo.
		var home := Vector2(size.x * 0.16, size.y * 0.74)
		draw_circle(home, joystick_radius * 0.62, Color(1.0, 1.0, 1.0, 0.06))
		draw_arc(home, joystick_radius * 0.62, 0.0, TAU, 28, Color(1.0, 1.0, 1.0, 0.16), 2.0)
		return
	draw_circle(_move_origin, joystick_radius, Color(1.0, 1.0, 1.0, 0.14))
	draw_arc(_move_origin, joystick_radius, 0.0, TAU, 40, Color(1.0, 1.0, 1.0, 0.35), 2.0)
	draw_circle(_move_current, 26.0 * layout_scale, Color(1.0, 1.0, 1.0, 0.38))


func _draw_button(button: String, label: String, active: bool) -> void:
	var center := button_center(button)
	var radius := button_radius(button)
	var alpha := 0.34 if active else 0.18
	draw_circle(center, radius, Color(1.0, 1.0, 1.0, alpha))
	draw_arc(center, radius, 0.0, TAU, 28, Color(1.0, 1.0, 1.0, 0.4 if active else 0.24), 2.0)
	var font := ThemeDB.fallback_font
	var font_size := int(11.0 * layout_scale)
	var text_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, center + Vector2(-text_width * 0.5, font_size * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 1.0, 1.0, 0.9))


static func _short_label(text: String) -> String:
	var clean := text.strip_edges()
	if clean.length() <= 10:
		return clean
	return clean.substr(0, 9) + "…"
