class_name MovementProfile
extends RefCounted

## Parâmetros do movimento a pé, num lugar só.
##
## Antes desta etapa os números viviam como constantes dentro de `Player`. O
## problema não era o valor, era o efeito colateral: mudar a velocidade de
## caminhada para o perfil mobile exigia editar o controlador, e não havia como
## um teste exercitar "sprint é mais rápido que corrida" sem instanciar um corpo
## físico.
##
## Agora o perfil é um objeto. O `PlayerMotor` consome um perfil, e trocar de
## perfil não muda uma linha de lógica.
##
## Três velocidades, três intenções — não é a mesma coisa que três teclas:
##
##   caminhada   analógico abaixo da metade (ou CTRL no teclado)
##   corrida     analógico cheio, sem modificador
##   sprint      modificador de corrida (SHIFT) com analógico acima de 60%
##
## No teclado as três são alcançáveis: CTRL anda, W corre, SHIFT+W dispara.
## No toque, a mesma coisa sai da amplitude do joystick mais o botão de sprint.

## Velocidades herdadas da Etapa 1, mantidas como referência de sensação.
const LEGACY_WALK_SPEED := 4.2
const LEGACY_RUN_SPEED := 7.8
const LEGACY_JUMP_SPEED := 5.4
const LEGACY_GRAVITY := 20.0

var walk_speed: float = LEGACY_WALK_SPEED
var run_speed: float = LEGACY_RUN_SPEED
var sprint_speed: float = 10.4

## Taxas em m/s². Desacelerar mais forte que acelerar é o que tira o gelo do
## personagem: ele para quando você solta, em vez de deslizar uma eternidade.
var acceleration: float = 26.0
var deceleration: float = 34.0
var air_acceleration: float = 9.0

## Giro do corpo em direção ao movimento, em rad/s.
var turn_rate: float = 13.0

var jump_velocity: float = LEGACY_JUMP_SPEED
var gravity: float = LEGACY_GRAVITY
var max_fall_speed: float = 42.0

## Janela em que o pulo ainda vale depois de sair do chão. Sem ela, andar na
## borda de uma calçada e apertar pulo "no vazio" parece bug do jogador.
var coyote_time: float = 0.12

## Janela em que um pulo apertado antes de encostar no chão continua valendo.
var jump_buffer_time: float = 0.14

## Duração do estado de aterrissagem (animação e bloqueio de giro brusco).
var landing_time: float = 0.18

## Velocidade com que o corpo é colado ao chão ao descer uma rampa.
var slope_stick_velocity: float = 2.6

## Inclinação máxima que ainda conta como chão.
var max_slope_degrees: float = 55.0

## Limiares de estado, em m/s.
var idle_threshold: float = 0.32
var run_threshold: float = 4.8
var sprint_threshold: float = 7.6

## Diferença de rumo acima da qual o corpo está "virando", em graus.
var turn_threshold_degrees: float = 55.0

## Distância máxima que o corpo avança num único `move_and_slide`, em metros.
## Acima disso o passo é fatiado: é a defesa contra atravessar parede, e é uma
## conta pura, testável sem servidor de física.
var substep_distance: float = 0.45

## Queda mínima que conta como aterrissagem para efeito de animação.
var landing_min_fall_speed: float = 2.2


static func from_preset(preset: Dictionary) -> MovementProfile:
	var profile := MovementProfile.new()
	profile.walk_speed = maxf(float(preset.get("player_walk_speed", profile.walk_speed)), 0.6)
	profile.run_speed = maxf(float(preset.get("player_run_speed", profile.run_speed)), profile.walk_speed + 0.2)
	profile.sprint_speed = maxf(float(preset.get("player_sprint_speed", profile.sprint_speed)), profile.run_speed + 0.2)
	profile.jump_velocity = maxf(float(preset.get("player_jump_velocity", profile.jump_velocity)), 1.0)
	profile.turn_rate = maxf(float(preset.get("player_turn_rate", profile.turn_rate)), 1.0)
	profile.substep_distance = clampf(float(preset.get("player_substep_distance", profile.substep_distance)), 0.1, 2.0)
	return profile


## Velocidade desejada para uma intenção de entrada.
##
## `magnitude` é a amplitude do analógico (ou 1 no teclado). A caminhada usa
## meia amplitude para baixo; acima disso a curva vai até a corrida. O sprint só
## entra com intenção forte: soltar o analógico no meio de um sprint devolve o
## personagem à caminhada, que é o que evita "sprint parado".
static func desired_speed(magnitude: float, sprint: bool, walk: bool, profile: MovementProfile = null) -> float:
	var active: MovementProfile = profile if profile != null else MovementProfile.new()
	var amount := clampf(magnitude, 0.0, 1.0)
	if amount <= 0.001:
		return 0.0
	if walk:
		return active.walk_speed * clampf(amount * 1.4, 0.25, 1.0)
	if sprint and amount >= 0.6:
		return active.sprint_speed * clampf(amount, 0.6, 1.0)
	if amount <= 0.55:
		return lerpf(active.walk_speed * 0.45, active.walk_speed, amount / 0.55)
	return lerpf(active.walk_speed, active.run_speed, (amount - 0.55) / 0.45)


func describe() -> String:
	return "caminhada %.1f · corrida %.1f · sprint %.1f m/s · pulo %.1f · giro %.0f°/s" % [
		walk_speed,
		run_speed,
		sprint_speed,
		jump_velocity,
		rad_to_deg(turn_rate),
	]
