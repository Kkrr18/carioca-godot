class_name MovementStateMachine
extends RefCounted

## Estados do personagem, decididos por uma função pura.
##
## Antes desta etapa o estado do jogador era implícito: `sprinting` verdadeiro ou
## falso, `velocity.y` maior ou menor que zero, `is_on_floor()` do frame anterior.
## Cada sistema que quisesse saber "o personagem está pulando?" refazia a conta do
## seu jeito, e a câmera, a animação e o som discordavam entre si na borda.
##
## Aqui a decisão é explícita, ordenada por prioridade e sem física: entra um
## dicionário com fatos, sai um estado. É por isso que este arquivo tem teste
## puro, sem frame e sem servidor de física.
##
## Prioridade (a primeira que casar vence):
##   1. VEHICLE      dentro de um veículo, nada mais vale
##   2. DISABLED     movimento bloqueado (cutscene, menu, transição)
##   3. INTERACT     janela curta de interação
##   4. ar: JUMP enquanto sobe; FALL enquanto desce
##   5. chão: LAND na janela de aterrissagem, TURN virando parado,
##      IDLE, SPRINT, RUN, WALK por velocidade

enum State {
	DISABLED,
	IDLE,
	WALK,
	RUN,
	SPRINT,
	JUMP,
	FALL,
	LAND,
	TURN,
	INTERACT,
	VEHICLE,
}

const STATE_NAMES := {
	State.DISABLED: "desligado",
	State.IDLE: "parado",
	State.WALK: "andando",
	State.RUN: "correndo",
	State.SPRINT: "sprint",
	State.JUMP: "pulando",
	State.FALL: "caindo",
	State.LAND: "aterrissando",
	State.TURN: "virando",
	State.INTERACT: "interagindo",
	State.VEHICLE: "no veículo",
}

const STATE_ANIMATIONS := {
	State.DISABLED: "idle",
	State.IDLE: "idle",
	State.WALK: "walk",
	State.RUN: "run",
	State.SPRINT: "sprint",
	State.JUMP: "jump",
	State.FALL: "fall",
	State.LAND: "land",
	State.TURN: "turn",
	State.INTERACT: "interact",
	State.VEHICLE: "idle",
}

var state: int = State.IDLE
var previous: int = State.IDLE
var time_in_state: float = 0.0
var transitions: int = 0

## Janela em que o estado INTERACT tem prioridade sobre o movimento.
var interact_timer: float = 0.0
var interact_hold: float = 0.22


func update(delta: float, context: Dictionary) -> int:
	var step := clampf(delta, 0.0, 0.5)
	interact_timer = maxf(interact_timer - step, 0.0)
	# A janela de interação é deste objeto: o valor no contexto vem de fora e
	# poderia chegar velho, então ele é sobrescrito aqui. Sem isto, quem chama
	# precisaria lembrar de passar o temporizador decrementado — e o estado
	# dependeria de uma cópia que pode discordar da original.
	var scan := context.duplicate()
	scan["interact_timer"] = interact_timer
	var next := resolve(scan)
	if next != state:
		previous = state
		state = next
		time_in_state = 0.0
		transitions += 1
	else:
		time_in_state += step
	return state


## Sinaliza que uma interação aconteceu agora — o estado INTERACT entra na
## próxima avaliação e segura a animação por `interact_hold` segundos.
func notify_interaction() -> void:
	interact_timer = interact_hold


static func resolve(context: Dictionary) -> int:
	if bool(context.get("in_vehicle", false)):
		return State.VEHICLE
	if not bool(context.get("movement_enabled", true)):
		return State.DISABLED
	if float(context.get("interact_timer", 0.0)) > 0.0:
		return State.INTERACT

	var on_floor := bool(context.get("on_floor", true))
	var speed := float(context.get("speed", 0.0))
	var vertical := float(context.get("vertical_velocity", 0.0))

	if not on_floor:
		if vertical > 0.35:
			return State.JUMP
		return State.FALL

	if float(context.get("landing_timer", 0.0)) > 0.0:
		return State.LAND
	if bool(context.get("turning", false)) and speed < float(context.get("run_threshold", 4.8)):
		return State.TURN
	if speed <= float(context.get("idle_threshold", 0.32)):
		return State.IDLE
	if bool(context.get("sprinting", false)) and speed >= float(context.get("sprint_threshold", 7.6)):
		return State.SPRINT
	if speed >= float(context.get("run_threshold", 4.8)):
		return State.RUN
	return State.WALK


static func state_name(value: int) -> String:
	return str(STATE_NAMES.get(value, "?"))


static func animation_name(value: int) -> StringName:
	return StringName(str(STATE_ANIMATIONS.get(value, "idle")))


static func is_airborne(value: int) -> bool:
	return value == State.JUMP or value == State.FALL


func name() -> String:
	return state_name(state)


func animation() -> StringName:
	return animation_name(state)


func reset() -> void:
	state = State.IDLE
	previous = State.IDLE
	time_in_state = 0.0
	transitions = 0
	interact_timer = 0.0


func describe() -> String:
	return "%s (há %.2f s, %d transições)" % [name(), time_in_state, transitions]
