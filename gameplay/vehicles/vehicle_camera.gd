class_name VehicleCamera
extends PlayerCamera

## Câmera veicular da Etapa 5 — uma subclasse, não uma segunda câmera.
##
## A câmera do personagem (Etapa 4) já resolve a parte cara e cheia de caso:
## colisão por raycast, encurtar na hora e alongar suave, zoom com limites,
## suavização por eixo, toque. Repetir isso numa classe paralela seriam duas
## câmeras podendo discordar. Aqui se herda e se muda só o que o carro pede:
##
## - **Suavização proporcional à velocidade**: parado, a câmera é firme; a
##   100 km/h ela persegue mais rápido, senão o carro foge do quadro.
## - **Acompanhamento atrás do carro**: sem toque recente, o yaw desliza para
##   atrás do carro em movimento (comportamento GTA). Um toque na tela ou um
##   movimento de mouse pausa o acompanhamento por 2 s.
## - **Duas distâncias**: próxima e distante (tecla V / botão de toque),
##   clampadas aos limites da câmera base.
## - **Mudança de altura**: atrás do carro o pivô é mais alto e mais atrás.
##
## O gancho da câmera interna (futura) é `mode`: quando existir cabine para
## olhar, `MODE_CABIN` posiciona a câmera no para-brisa.

const MODE_CHASE := 0
const MODE_FAR := 1
const MODE_CABIN := 2

const VEHICLE_DISTANCE := 6.2
const VEHICLE_DISTANCE_FAR := 9.4
const VEHICLE_HEIGHT := 2.1
const SPEED_GAIN_MAX := 2.2
const ALIGN_RATE := 1.6
const ALIGN_HOLD := 2.0

var mode: int = MODE_CHASE

var _align_timer: float = 0.0


func _init() -> void:
	# _init da base não é herdado automaticamente de forma útil aqui: os campos
	# já têm valores padrão em linha na base.
	pass


## Aplicado pelo jogo quando o alvo passa a ser um veículo.
func enter_vehicle_mode() -> void:
	mode = MODE_CHASE
	height_offset = VEHICLE_HEIGHT
	distance = VEHICLE_DISTANCE_FAR * 0.7
	_align_timer = 0.0


func leave_vehicle_mode() -> void:
	mode = MODE_CHASE
	height_offset = 1.55
	distance = clampf(distance, 1.6, 8.0)


## Alterna próxima/distante. V no PC, botão no toque.
func cycle_distance() -> void:
	mode = MODE_FAR if mode == MODE_CHASE else MODE_CHASE
	var wanted := VEHICLE_DISTANCE_FAR if mode == MODE_FAR else VEHICLE_DISTANCE
	distance = clampf(wanted, min_distance, max_distance)


func _is_vehicle_target() -> bool:
	return target is Vehicle


func _process(delta: float) -> void:
	# O pivô do carro é mais alto e mais atrás; o resto é o caminho da base.
	if _is_vehicle_target():
		height_offset = VEHICLE_HEIGHT
	else:
		height_offset = 1.55
	super._process(delta)


func _follow_target(delta: float) -> void:
	if not _is_vehicle_target():
		super._follow_target(delta)
		return
	var desired := target.global_position + Vector3.UP * height_offset
	var pivot := global_position
	# Suavização proporcional à velocidade: rápido de verdade só em movimento.
	var speed := absf((target as Vehicle).forward_speed())
	var gain := clampf(1.0 + speed / 14.0, 1.0, SPEED_GAIN_MAX)
	var horizontal := clampf(delta * POSITION_LERP * smoothing * gain, 0.0, 1.0)
	var vertical := clampf(delta * VERTICAL_LERP * smoothing, 0.0, 1.0)
	pivot.x = lerpf(pivot.x, desired.x, horizontal)
	pivot.z = lerpf(pivot.z, desired.z, horizontal)
	pivot.y = lerpf(pivot.y, desired.y, vertical)
	global_position = pivot


func _update_distance(delta: float) -> void:
	if _is_vehicle_target() and absf((target as Vehicle).forward_speed()) > 0.5:
		_align_timer -= delta
		if _align_timer <= 0.0:
			# Volta a olhar de trás do carro, suave: é o acompanhamento GTA.
			var heading := target.rotation.y
			yaw = lerp_angle(yaw, heading + PI, clampf(delta * ALIGN_RATE, 0.0, 1.0))
	super._update_distance(delta)


func _touch_align() -> void:
	_align_timer = ALIGN_HOLD


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_touch_align()
	super._unhandled_input(event)
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == InputBindings.primary_key(InputBindings.ACTION_CAMERA_MODE):
			if _is_vehicle_target():
				cycle_distance()
				_touch_align()


func _consume_touch_look() -> void:
	if touch_controls == null:
		super._consume_touch_look()
		return
	if touch_controls.vehicle_mode and touch_controls.consume_look().length_squared() > 0.0001:
		_touch_align()
	super._consume_touch_look()
	if touch_controls.vehicle_mode and touch_controls.consume_camera_mode():
		if _is_vehicle_target():
			cycle_distance()


func describe() -> String:
	var mode_name := "perseguição"
	if mode == MODE_FAR:
		mode_name = "distante"
	elif mode == MODE_CABIN:
		mode_name = "cabine (reservada)"
	return "%s · %s" % [mode_name, super.describe()]
