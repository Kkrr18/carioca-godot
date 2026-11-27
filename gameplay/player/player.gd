class_name Player
extends CharacterBody3D

## Jogador em terceira pessoa — Etapa 4.
##
## A API pública da Etapa 1 foi preservada de propósito: `read_move_input()`,
## `try_interact()`, `enter_vehicle()/exit_vehicle()`, `teleport_to_local()`,
## `metric_position()`, `ground_height()`, as constantes `VEHICLE_RADIUS` e
## `DOOR_RADIUS`, os sinais de veículo e os campos que o bootstrap, o HUD, o
## interior e os veículos já usavam. Nada disso mudou de nome.
##
## O que mudou é **por dentro**, e a divisão é o ponto da etapa:
##
##   MovementProfile      números (velocidades, aceleração, janelas de pulo)
##   PlayerMotor          a matemática: aceleração, gravidade, pulo, rampa
##   MovementStateMachine estados explícitos: parado, andando, pulo, queda…
##   CharacterAnimator    pose procedural (e gancho para árvore importada)
##   PlaceholderCharacter boneco provisório com juntas de verdade
##   PlayerInteraction    interação extensível por provedores
##
## Este arquivo só liga essas peças ao corpo físico: lê a entrada, entrega a
## intenção, aplica `move_and_slide`, alinha o corpo ao movimento e publica o
## estado. Toda a regra que dá para testar sem física mora fora dele.
##
## Correção de defeito da Etapa 1 encontrada na auditoria: o código chamava
## `camera_rig.yaw()`, mas `yaw` é **variável** em `PlayerCamera`, não método. Isso
## levantava erro a cada passo de física e derrubava o movimento com câmera
## ativa — ou seja, no jogo inteiro. A leitura correta (`camera_rig.yaw`) está em
## `_camera_yaw()`.

signal entered_vehicle(vehicle: Vehicle)
signal exited_vehicle(vehicle: Vehicle)
signal state_changed(state: int, previous: int)
signal landed(impact_speed: float)
signal interacted(kind: String, id: String)

## Constantes mantidas por compatibilidade. Os valores que o motor usa vêm de
## `profile`; estas existem porque o HUD e o bootstrap as leem.
const WALK_SPEED := MovementProfile.LEGACY_WALK_SPEED
const RUN_SPEED := MovementProfile.LEGACY_RUN_SPEED
const ACCELERATION := 26.0
const AIR_CONTROL := 9.0
const JUMP_SPEED := MovementProfile.LEGACY_JUMP_SPEED
const GRAVITY := MovementProfile.LEGACY_GRAVITY
const INTERACT_COOLDOWN := 0.35
const VEHICLE_RADIUS := 4.5
const DOOR_RADIUS := 4.5

const COLLISION_LAYER := 2
const COLLISION_MASK := 1

var camera_rig: PlayerCamera = null
var touch_controls: TouchControls = null
var vehicle_manager: VehicleManager = null
var interior_manager: InteriorManager = null
var floating: FloatingOrigin = null
var terrain: TerrainService = null

var current_vehicle: Vehicle = null
var can_move: bool = true
var sprinting: bool = false

var profile: MovementProfile = null
var motor: PlayerMotor = null
var states: MovementStateMachine = null
var animator: CharacterAnimator = null
var interaction: PlayerInteraction = null
var character: PlaceholderCharacter = null

var _jump_requested: bool = false
var _jump_held: bool = false
var _interact_cooldown: float = 0.0
var _walking: bool = false
var _turning: bool = false
var _was_on_floor: bool = false
var _vehicle_provider: bool = false
var _door_provider: bool = false
var _group_provider: bool = false


func _init() -> void:
	profile = MovementProfile.new()
	motor = PlayerMotor.new(profile)
	states = MovementStateMachine.new()
	animator = CharacterAnimator.new()
	interaction = PlayerInteraction.new()
	interaction.interacted.connect(_on_interaction)


func _ready() -> void:
	up_direction = Vector3.UP
	floor_max_angle = deg_to_rad(profile.max_slope_degrees)
	floor_snap_length = 0.4
	floor_stop_on_slope = true
	collision_layer = COLLISION_LAYER
	collision_mask = COLLISION_MASK
	_build_collision()
	_build_character()


func _build_collision() -> void:
	var shape := CollisionShape3D.new()
	shape.name = "Collision"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.9, 0.0)
	add_child(shape)


func _build_character() -> void:
	if character != null:
		return
	character = PlaceholderCharacter.new()
	character.name = "Character"
	add_child(character)


## Aplica um perfil de movimento vindo do perfil gráfico/plataforma.
func apply_movement_profile(new_profile: MovementProfile) -> void:
	if new_profile == null:
		return
	profile = new_profile
	motor.profile = new_profile
	floor_max_angle = deg_to_rad(new_profile.max_slope_degrees)


func _physics_process(delta: float) -> void:
	_interact_cooldown = maxf(_interact_cooldown - delta, 0.0)
	var input := read_move_input()
	_update_jump_latch()
	_poll_touch_interaction()
	step_physics(delta, input)


## Um passo de física a partir de uma entrada explícita.
##
## `_physics_process` só lê a entrada e chama isto. A separação existe para o
## teste poder conduzir o corpo exatamente pelo mesmo caminho do jogo — sem
## emular teclado, sem depender de frame — e para o veículo poder reusar a
## leitura sem arrastar o resto do controlador.
func step_physics(delta: float, input: Vector2, jump: bool = false) -> void:
	if jump:
		_jump_requested = true

	if current_vehicle != null:
		_pin_to_vehicle()
		_advance_state(delta)
		return

	if not can_move:
		motor.step(delta, {"enabled": false})
		velocity = motor.velocity
		_advance_state(delta)
		return

	var direction := _world_direction(input)
	var magnitude := clampf(input.length(), 0.0, 1.0)
	_update_turning(direction)

	var was_on_floor := is_on_floor()
	motor.step(delta, {
		"direction": direction,
		"magnitude": magnitude,
		"sprint": sprinting,
		"walk": _walking,
		"jump_pressed": _jump_requested,
		"on_floor": was_on_floor,
		"floor_normal": get_floor_normal(),
		"enabled": true,
	})
	_jump_requested = false
	velocity = motor.velocity

	_apply_motion(delta)
	_face_direction(direction, delta)
	_advance_state(delta)

	if not was_on_floor and is_on_floor() and motor.landing_speed >= profile.landing_min_fall_speed:
		landed.emit(motor.landing_speed)

	interaction.refresh(self, delta)


## Executa o deslocamento com fatiamento quando a velocidade passa do que uma
## cápsula aguenta num passo. Em velocidade normal isto é exatamente um
## `move_and_slide` — o mesmo caminho da Etapa 1.
func _apply_motion(delta: float) -> void:
	var steps := motor.substeps_for(delta)
	if steps <= 1:
		move_and_slide()
		_was_on_floor = is_on_floor()
		return
	var original := velocity
	velocity = original / float(steps)
	for _i in range(steps):
		move_and_slide()
	velocity *= float(steps)
	if velocity.length() > original.length():
		velocity = velocity.normalized() * original.length()
	_was_on_floor = is_on_floor()


func _world_direction(input: Vector2) -> Vector3:
	if input.length_squared() < 0.0001:
		return Vector3.ZERO
	var direction := Vector3(input.x, 0.0, -input.y)
	return direction.rotated(Vector3.UP, _camera_yaw()).normalized()


## Yaw da câmera. `yaw` é propriedade de `PlayerCamera` — a Etapa 1 chamava
## `yaw()` e isso era erro de execução.
func _camera_yaw() -> float:
	if camera_rig == null:
		return rotation.y
	return camera_rig.yaw


func _update_jump_latch() -> void:
	var jump_pressed := InputBindings.is_pressed(InputBindings.ACTION_JUMP)
	if touch_controls != null and touch_controls.visible_controls and touch_controls.consume_jump():
		jump_pressed = true
	if jump_pressed and not _jump_held:
		_jump_requested = true
	_jump_held = jump_pressed


## Botão de interação da tela de toque. Fica aqui, e não em `_unhandled_input`,
## porque o controle de toque consome o evento antes de a árvore vê-lo.
func _poll_touch_interaction() -> void:
	if touch_controls == null or not touch_controls.visible_controls:
		return
	if touch_controls.consume_interact():
		try_interact()


func _update_turning(direction: Vector3) -> void:
	if direction.length_squared() < 0.01:
		_turning = false
		return
	var target_yaw := atan2(-direction.x, -direction.z)
	var angle := absf(wrapf(target_yaw - rotation.y, -PI, PI))
	_turning = angle > deg_to_rad(profile.turn_threshold_degrees)


func _face_direction(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.01:
		return
	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * profile.turn_rate, 0.0, 1.0))


func _advance_state(delta: float) -> void:
	var previous := states.state
	var speed := motor.speed()
	var next := states.update(delta, {
		"in_vehicle": current_vehicle != null,
		"movement_enabled": can_move,
		"on_floor": is_on_floor() or current_vehicle != null,
		"speed": speed,
		"vertical_velocity": velocity.y,
		"landing_timer": motor.landing_timer,
		"turning": _turning,
		"sprinting": sprinting,
		"idle_threshold": profile.idle_threshold,
		"run_threshold": profile.run_threshold,
		"sprint_threshold": profile.sprint_threshold,
	})
	if next != previous:
		state_changed.emit(next, previous)

	if character == null or current_vehicle != null:
		return
	var pose := animator.advance(delta, next, speed, velocity.y, motor.landing_timer, profile)
	character.pose(pose)


func _pin_to_vehicle() -> void:
	if current_vehicle == null:
		return
	velocity = Vector3.ZERO
	global_position = current_vehicle.global_position + Vector3.UP * 0.6


## Entrada de movimento unificada: teclado e analógico virtual, a maior amplitude
## vence. Continua sendo a porta única — o veículo lê o mesmo vetor.
func read_move_input() -> Vector2:
	var input := InputBindings.move_axis()
	_walking = InputBindings.is_pressed(InputBindings.ACTION_WALK)
	var wants_sprint := InputBindings.is_pressed(InputBindings.ACTION_SPRINT)

	if touch_controls != null and touch_controls.visible_controls:
		if touch_controls.sprint_active:
			wants_sprint = true
		if touch_controls.move_vector.length() > input.length():
			input = touch_controls.move_vector
		if touch_controls.walk_active:
			_walking = true

	if input.length() > 1.0:
		input = input.normalized()
	sprinting = wants_sprint and input.length() > 0.25 and not _walking
	return input


func try_interact() -> void:
	if _interact_cooldown > 0.0:
		return
	_interact_cooldown = INTERACT_COOLDOWN

	if current_vehicle != null:
		exit_vehicle()
		return
	if interior_manager != null and interior_manager.is_inside():
		interior_manager.exit()
		return

	_ensure_providers()
	if interaction != null:
		interaction.refresh_now(self)
		if interaction.interact(self):
			return

	# Cadeia legada: mantém o comportamento quando não há provedor registrado.
	if vehicle_manager != null:
		var vehicle := vehicle_manager.nearest(global_position, VEHICLE_RADIUS)
		if vehicle != null:
			enter_vehicle(vehicle)
			return
	if interior_manager != null and floating != null:
		var door := interior_manager.find_nearby_door(floating.viewer_metric(), DOOR_RADIUS)
		if not door.is_empty():
			interior_manager.enter(door)


## Provedores criados sob demanda: o bootstrap define os managers **depois** de
## instanciar o jogador, então registrar em `_ready` pegaria campos nulos.
func _ensure_providers() -> void:
	if interaction == null:
		return
	if not _vehicle_provider and vehicle_manager != null:
		interaction.add_provider(VehicleInteractionProvider.new(vehicle_manager, VEHICLE_RADIUS))
		_vehicle_provider = true
	if not _door_provider and interior_manager != null and floating != null:
		interaction.add_provider(DoorInteractionProvider.new(interior_manager, floating, DOOR_RADIUS))
		_door_provider = true
	if not _group_provider:
		interaction.add_provider(GroupInteractionProvider.new())
		_group_provider = true


func _on_interaction(kind: String, candidate: Dictionary) -> void:
	states.notify_interaction()
	interacted.emit(kind, str(candidate.get("id", "")))


## Texto que o HUD deve mostrar. Vazio quando não há nada ao alcance.
func interaction_prompt() -> String:
	if interaction == null:
		return ""
	return interaction.prompt_text()


func enter_vehicle(vehicle: Vehicle) -> void:
	if vehicle == null or current_vehicle != null:
		return
	current_vehicle = vehicle
	vehicle.set_driver(self)
	visible = false
	can_move = false
	motor.reset()
	velocity = Vector3.ZERO
	if camera_rig != null:
		camera_rig.set_target(vehicle)
	if interaction != null:
		interaction.refresh_now(self)
	entered_vehicle.emit(vehicle)
	CariocaBus.get_instance().vehicle_entered.emit(vehicle)


func exit_vehicle() -> void:
	var vehicle := current_vehicle
	if vehicle == null:
		return
	current_vehicle = null
	vehicle.clear_driver()
	visible = true
	can_move = true
	motor.reset()
	if camera_rig != null:
		camera_rig.set_target(self)
	var side := vehicle.global_transform.basis.x.normalized()
	var exit_position := vehicle.global_position + side * 2.3 + Vector3.UP * 1.2
	global_position = exit_position
	velocity = Vector3.ZERO
	if interaction != null:
		interaction.refresh_now(self)
	exited_vehicle.emit(vehicle)
	CariocaBus.get_instance().vehicle_exited.emit(vehicle)


## Teleporte usado ao sair de um interior, ao carregar save e no reset (R).
func teleport_to_local(local_position: Vector3) -> void:
	global_position = local_position
	velocity = Vector3.ZERO
	motor.reset()
	states.reset()
	if interaction != null:
		interaction.refresh_now(self)


func metric_position() -> Vector2:
	if floating == null:
		return Vector2.ZERO
	return floating.local_to_metric(position)


## Altura do solo no ponto atual, usada para alinhar câmera e NPCs.
func ground_height() -> float:
	if terrain == null:
		return position.y
	return terrain.height_at(metric_position())


func set_movement_enabled(enabled: bool) -> void:
	can_move = enabled
	if not enabled:
		motor.reset()
		velocity = Vector3.ZERO


func state_name() -> String:
	return states.name() if states != null else "?"


func state() -> int:
	return states.state if states != null else MovementStateMachine.State.IDLE


func speed() -> float:
	return motor.speed() if motor != null else 0.0


func is_grounded() -> bool:
	return is_on_floor()


func substeps(delta: float) -> int:
	return motor.substeps_for(delta)


## Resumo de uma linha para o HUD e o relatório.
func describe() -> String:
	return "%s · %.2f m/s · %s" % [
		state_name(),
		speed(),
		"no chão" if is_on_floor() else "no ar",
	]
