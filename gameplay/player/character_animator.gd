class_name CharacterAnimator
extends RefCounted

## Camada de animação do personagem.
##
## Existem dois mundos aqui, e é importante não confundi-los:
##
## 1. **Animação procedural** — funciona hoje, sem asset nenhum. A partir do
##    estado e da velocidade saem parâmetros de pose (balanço de perna, de braço,
##    inclinação de tronco, subida e descida do quadril, esmagamento na
##    aterrissagem). Quem aplica esses números é o `PlaceholderCharacter`, um
##    boneco de primitivas com juntas de verdade.
##
## 2. **Animação importada** — quando existir um modelo humano com animações
##    licenciadas, `bind_tree()` e `bind_player()` ligam um `AnimationTree` e o
##    controlador passa a pedir a transição para o estado correspondente, sem
##    mudar uma linha de quem chama. Enquanto não existir, `is_bound()` é falso e
##    a máquina não finge que anima: só a procedural roda.
##
## Nenhuma animação importada é dada como concluída nesta etapa. O boneco
## provisório é provisório, e está escrito assim no relatório.

const STRIDE_LENGTH_BASE := 1.7

var stride_phase: float = 0.0
var clock: float = 0.0
var pose: Dictionary = {}

var animation_tree: AnimationTree = null
var animation_player: AnimationPlayer = null

var _state_states: Array[StringName] = []
var _last_state: int = -1
var _has_transition_request: bool = false


func _init() -> void:
	pose = {
		"leg_swing": 0.0,
		"arm_swing": 0.0,
		"bob": 0.0,
		"lean": 0.0,
		"twist": 0.0,
		"squash": 1.0,
		"crouch": 0.0,
		"stride": 0.0,
	}


## Avança a animação um passo e devolve a pose resultante.
##
##   state            valor de `MovementStateMachine.State`
##   speed            velocidade horizontal em m/s
##   vertical         velocidade vertical em m/s
##   landing_timer    tempo restante de aterrissagem
func advance(delta: float, state: int, speed: float, vertical: float, landing_timer: float, profile: MovementProfile = null) -> Dictionary:
	var step := clampf(delta, 0.0, 0.25)
	var movement := profile if profile != null else MovementProfile.new()
	clock += step

	var grounded := not MovementStateMachine.is_airborne(state) and state != MovementStateMachine.State.VEHICLE
	var speed_factor := clampf(speed / maxf(movement.run_speed, 0.1), 0.0, 2.0)
	var amplitude := clampf(speed_factor, 0.18, 1.25)

	if grounded and speed > 0.15 and state != MovementStateMachine.State.LAND:
		var stride_length := STRIDE_LENGTH_BASE + speed * 0.12
		stride_phase = fposmod(stride_phase + step * speed * TAU / stride_length, TAU)

	var leg := 0.0
	var arm := 0.0
	var bob := 0.0
	var lean := 0.0
	var twist := 0.0
	var squash := 1.0
	var crouch := 0.0

	if ground_pose(state, movement):
		leg = sin(stride_phase) * 0.62 * amplitude
		arm = -sin(stride_phase) * 0.48 * amplitude
		bob = absf(sin(stride_phase)) * 0.045 * amplitude
		lean = clampf(speed_factor * 0.09, 0.0, 0.18)
		twist = sin(stride_phase) * 0.08 * amplitude
		if state == MovementStateMachine.State.IDLE:
			# Respiração: sem isso o parado parece estátua.
			bob = sin(clock * 1.7) * 0.012
			leg = sin(clock * 1.1) * 0.02
			arm = -leg * 0.6
	elif state == MovementStateMachine.State.JUMP:
		leg = -0.34
		arm = 0.42
		lean = 0.12
	elif state == MovementStateMachine.State.FALL:
		leg = 0.22
		arm = -0.3
		lean = -0.06
	elif state == MovementStateMachine.State.LAND:
		var amount := clampf(landing_timer / maxf(movement.landing_time, 0.01), 0.0, 1.0)
		crouch = amount * 0.22
		squash = 1.0 - amount * 0.12
		leg = 0.28 * amount
		arm = -0.18 * amount
	elif state == MovementStateMachine.State.TURN:
		leg = sin(clock * 6.0) * 0.12
		arm = -leg
		twist = sin(clock * 3.0) * 0.12
	elif state == MovementStateMachine.State.VEHICLE:
		leg = 0.0
		arm = 0.0

	pose["leg_swing"] = leg
	pose["arm_swing"] = arm
	pose["bob"] = bob - crouch * 0.5
	pose["lean"] = lean
	pose["twist"] = twist
	pose["squash"] = squash
	pose["crouch"] = crouch
	pose["stride"] = stride_phase

	if state != _last_state:
		_last_state = state
		_play_animation(state)
	return pose


static func ground_pose(state: int, _profile: MovementProfile = null) -> bool:
	if MovementStateMachine.is_airborne(state):
		return false
	if state == MovementStateMachine.State.LAND:
		return false
	if state == MovementStateMachine.State.VEHICLE:
		return false
	if state == MovementStateMachine.State.DISABLED:
		return false
	return true


func animation_for(state: int) -> StringName:
	return MovementStateMachine.animation_name(state)


func bind_tree(tree: AnimationTree) -> void:
	animation_tree = tree
	_state_states.clear()
	_has_transition_request = false
	if animation_tree == null:
		return
	var root := animation_tree.tree_root
	if root is AnimationNodeStateMachine:
		for name in (root as AnimationNodeStateMachine).get_state_list():
			_state_states.append(StringName(str(name).get_slice(":", 0)))
			# O nome vem no formato "Nome:nó", a parte antes dos dois-pontos é a
			# que o `travel`/transição aceita.
	_has_transition_request = animation_tree.get("parameters/transition_request") != null


func bind_player(player: AnimationPlayer) -> void:
	animation_player = player


func is_bound() -> bool:
	return animation_tree != null or animation_player != null


## Nomes de estado que existem de fato na máquina ligada. Vazio quando não há
## `AnimationTree` — é assim que quem pergunta descobre que só a procedural roda.
func available_states() -> Array[StringName]:
	return _state_states


func _play_animation(state: int) -> void:
	var wanted := animation_for(state)
	if animation_player != null and animation_player.is_inside_tree() and animation_player.has_animation(wanted):
		animation_player.play(wanted)
		return
	if animation_tree == null:
		return
	if not _state_states.is_empty() and not _state_states.has(wanted):
		# A máquina importada não tem esse estado: não inventa transição.
		return
	if _has_transition_request:
		animation_tree.set("parameters/transition_request", String(wanted))


func reset() -> void:
	stride_phase = 0.0
	clock = 0.0
	_last_state = -1
	for key in pose.keys():
		pose[key] = 0.0
	pose["squash"] = 1.0

func describe() -> String:
	return "fase %.2f rad · perna %.2f · braço %.2f · inclinação %.2f%s" % [
		stride_phase,
		float(pose.get("leg_swing", 0.0)),
		float(pose.get("arm_swing", 0.0)),
		float(pose.get("lean", 0.0)),
		"" if not is_bound() else " · animação importada ligada",
	]
