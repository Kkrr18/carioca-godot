class_name PlayerCamera
extends Node3D

## Câmera em terceira pessoa, com colisão, zoom e suavização.
##
## Sem `SpringArm3D` de propósito, e a razão continua a da Etapa 1: o braço de
## colisão fica explícito num raio só, o que evita a ambiguidade de eixo do
## SpringArm e mantém a distância da câmera independente da orientação do
## jogador.
##
## O que mudou na Etapa 4, e por quê:
##
## - **Suavização separada por eixo.** O pivô persegue o alvo mais rápido na
##   horizontal que na vertical. Perseguir a altura com a mesma pressa fazia a
##   câmera sacudir em cada degrau de calçada e em cada pulo.
## - **Encurtar é imediato, alongar é suave.** Se uma parede entra entre a câmera
##   e o jogador, esperar a interpolação significa ver o interior da parede por
##   alguns quadros. O encurtamento é instantâneo; a volta é interpolada.
## - **Zoom** com roda do mouse, teclas e pinça de dois dedos, com limites.
## - **Ombro deslocado** proporcional à distância: perto da parede o deslocamento
##   lateral encolhe junto, senão a câmera atravessa pelo lado.
##
## `yaw` e `pitch` continuam sendo **variáveis públicas**, porque o
## `InteriorManager` escreve `player.camera_rig.yaw = PI` ao entrar no
## apartamento. Trocar por propriedade com setter quebraria isso.

const MIN_DISTANCE := 1.2
const POSITION_LERP := 18.0
const VERTICAL_LERP := 9.0
const DISTANCE_LERP := 14.0
const PITCH_MIN := -1.19
const PITCH_MAX := 0.80

var target: Node3D = null
var yaw: float = 0.0
var pitch: float = -0.22
var distance: float = 4.4
var height_offset: float = 1.55
var sensitivity: float = 0.0022
var touch_controls: TouchControls = null
var camera: Camera3D = null

var min_distance: float = 1.6
var max_distance: float = 7.5
var zoom_step: float = 0.6
var smoothing: float = 1.0
var collision_margin: float = 0.35
var shoulder_offset: float = 0.42
var invert_y: bool = false

var _current_distance: float = 4.4
var _collision_mask: int = 1


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 75.0
	camera.near = 0.08
	camera.far = 2400.0
	camera.current = true
	add_child(camera)
	_current_distance = clampf(distance, min_distance, max_distance)


func set_target(new_target: Node3D) -> void:
	target = new_target
	if target != null:
		global_position = target.global_position + Vector3.UP * height_offset


## Aplica sensibilidade, distância e suavização de um perfil de qualidade.
func apply_preset(preset: Dictionary) -> void:
	sensitivity = maxf(float(preset.get("camera_sensitivity", sensitivity)), 0.0004)
	min_distance = maxf(float(preset.get("camera_min_distance", min_distance)), 0.8)
	max_distance = maxf(float(preset.get("camera_max_distance", max_distance)), min_distance + 0.5)
	distance = clampf(float(preset.get("camera_distance", distance)), min_distance, max_distance)
	smoothing = clampf(float(preset.get("camera_smoothing", smoothing)), 0.2, 2.0)
	collision_margin = clampf(float(preset.get("camera_collision_margin", collision_margin)), 0.1, 1.0)


func set_sensitivity(value: float) -> void:
	sensitivity = maxf(value, 0.0004)


func set_invert_y(value: bool) -> void:
	invert_y = value


## Zoom por passo. Positivo aproxima.
func zoom(steps: float) -> void:
	distance = clampf(distance - steps * zoom_step, min_distance, max_distance)


func reset_yaw() -> void:
	if target == null:
		yaw = 0.0
		return
	yaw = target.rotation.y


func pitch_degrees() -> float:
	return rad_to_deg(pitch)


func current_distance() -> float:
	return _current_distance


func yaw_angle() -> float:
	return yaw


func _process(delta: float) -> void:
	if target == null:
		return
	_follow_target(delta)
	rotation = Vector3(pitch, yaw, 0.0)
	_consume_touch_look()
	_consume_zoom_actions()
	_update_distance(delta)


func _follow_target(delta: float) -> void:
	var desired := target.global_position + Vector3.UP * height_offset
	var pivot := global_position
	var horizontal := clampf(delta * POSITION_LERP * smoothing, 0.0, 1.0)
	var vertical := clampf(delta * VERTICAL_LERP * smoothing, 0.0, 1.0)
	pivot.x = lerpf(pivot.x, desired.x, horizontal)
	pivot.z = lerpf(pivot.z, desired.z, horizontal)
	pivot.y = lerpf(pivot.y, desired.y, vertical)
	global_position = pivot


func _consume_touch_look() -> void:
	if touch_controls == null:
		return
	var look := touch_controls.consume_look()
	if look.length_squared() < 0.0001:
		return
	var scale := touch_controls.look_sensitivity
	yaw -= look.x * scale
	var vertical := -look.y * scale
	if invert_y:
		vertical = -vertical
	pitch = clampf(pitch + vertical, PITCH_MIN, PITCH_MAX)


func _consume_zoom_actions() -> void:
	if touch_controls != null:
		var pinch := touch_controls.consume_zoom()
		if absf(pinch) > 0.0001:
			zoom(-pinch * 0.6)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		yaw -= motion.relative.x * sensitivity
		var vertical := -motion.relative.y * sensitivity
		if invert_y:
			vertical = -vertical
		pitch = clampf(pitch + vertical, PITCH_MIN, PITCH_MAX)
		return
	if event is InputEventMouseButton and event.pressed:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(1.0)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(-1.0)


func _update_distance(delta: float) -> void:
	if camera == null:
		return
	var wanted := clampf(distance, min_distance, max_distance)
	var allowed := _clear_arm(wanted)
	if allowed < _current_distance:
		# Encurtar na hora: é o caso "parede entre a câmera e o jogador".
		_current_distance = allowed
	else:
		_current_distance = lerpf(_current_distance, allowed, clampf(delta * DISTANCE_LERP, 0.0, 1.0))
	_current_distance = clampf(_current_distance, MIN_DISTANCE, max_distance)

	var ratio := clampf(_current_distance / maxf(distance, 0.01), 0.0, 1.0)
	camera.position = Vector3(shoulder_offset * ratio, 0.0, _current_distance)


## Comprimento do braço antes de bater em geometria do mundo.
func _clear_arm(wanted: float) -> float:
	var world := get_world_3d()
	if world == null:
		return wanted
	var space := world.direct_space_state
	if space == null:
		return wanted
	var from := global_position
	var to := from + global_transform.basis.z * wanted
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = _collision_mask
	var excluded: Array[RID] = []
	var body := target as CollisionObject3D
	if body != null:
		excluded.append(body.get_rid())
	query.exclude = excluded
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return wanted
	var hit_position: Vector3 = hit["position"]
	var reach := maxf(from.distance_to(hit_position) - collision_margin, MIN_DISTANCE)
	return minf(reach, wanted)


## Distância livre do braço hoje, sem suavização — número de diagnóstico.
func clear_distance() -> float:
	return _clear_arm(clampf(distance, min_distance, max_distance))


func describe() -> String:
	return "distância %.2f/%.2f m · inclinação %.0f° · sensibilidade %.4f" % [
		_current_distance,
		distance,
		pitch_degrees(),
		sensitivity,
	]
