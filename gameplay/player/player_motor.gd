class_name PlayerMotor
extends RefCounted

## A matemática do movimento, sem tocar na árvore de cena.
##
## Este objeto recebe uma intenção (direção, amplitude, modificadores, pedido de
## pulo) e o estado do chão, e devolve a velocidade que o corpo deve ter. Quem
## chama `move_and_slide` é o `Player`. Essa separação é o que permite testar
## aceleração, pulo, coyote time, buffer e gravidade sem servidor de física,
## sem frame e sem flakiness.
##
## Convenções:
##   - `velocity.y` positivo é para cima.
##   - A direção recebida já vem em espaço de mundo e horizontal (y = 0).
##   - `floor_normal` é a normal do chão devolvida por `move_and_slide`.

var profile: MovementProfile = null

var velocity: Vector3 = Vector3.ZERO

## Tempo restante da janela de coyote e do buffer de pulo.
var coyote_timer: float = 0.0
var jump_buffer: float = 0.0

## Tempo restante do estado de aterrissagem.
var landing_timer: float = 0.0

var was_on_floor: bool = false
var just_jumped: bool = false
var last_landing_speed: float = 0.0
var landing_speed: float = 0.0
var last_ground_speed: float = 0.0


func _init(movement_profile: MovementProfile = null) -> void:
	profile = movement_profile if movement_profile != null else MovementProfile.new()


## Um passo de simulação. Devolve a velocidade a aplicar.
##
## `intent`:
##   direction        Vector3 horizontal no mundo (normalizada ou zero)
##   magnitude        0..1 (analógico; teclado manda 1)
##   sprint           modificador de corrida
##   walk             modificador de caminhada
##   jump_pressed     pulo apertado neste passo
##   on_floor         resultado de `is_on_floor()` do passo anterior
##   floor_normal     normal do chão
##   enabled          falso congela o corpo (veículo, cutscene, menu)
func step(delta: float, intent: Dictionary) -> Vector3:
	just_jumped = false
	var step_delta := clampf(delta, 0.0, 0.25)
	if step_delta <= 0.0:
		return velocity

	landing_timer = maxf(landing_timer - step_delta, 0.0)

	var enabled := bool(intent.get("enabled", true))
	var on_floor := bool(intent.get("on_floor", false))
	var floor_normal: Vector3 = intent.get("floor_normal", Vector3.UP)
	var jump_pressed := bool(intent.get("jump_pressed", false))

	# --- janelas de tempo ---------------------------------------------------
	if on_floor:
		coyote_timer = profile.coyote_time
	else:
		coyote_timer = maxf(coyote_timer - step_delta, 0.0)

	if jump_pressed:
		jump_buffer = profile.jump_buffer_time
	else:
		jump_buffer = maxf(jump_buffer - step_delta, 0.0)

	# --- aterrissagem -------------------------------------------------------
	# A velocidade de impacto é copiada uma única vez, na transição ar -> chão.
	# Sem isso, um valor antigo sobrevive no campo e o próximo toque no chão
	# anunciaria uma queda que não houve.
	if on_floor and not was_on_floor:
		if last_landing_speed >= profile.landing_min_fall_speed:
			landing_timer = profile.landing_time
			landing_speed = last_landing_speed
		else:
			landing_speed = 0.0
		last_landing_speed = 0.0
	was_on_floor = on_floor

	if not enabled:
		velocity = Vector3.ZERO
		jump_buffer = 0.0
		return velocity

	# --- velocidade horizontal desejada -------------------------------------
	var direction: Vector3 = intent.get("direction", Vector3.ZERO)
	if direction.length_squared() > 0.0001:
		direction = Vector3(direction.x, 0.0, direction.z).normalized()
	else:
		direction = Vector3.ZERO
	var target_speed := MovementProfile.desired_speed(
		float(intent.get("magnitude", 0.0)),
		bool(intent.get("sprint", false)),
		bool(intent.get("walk", false)),
		profile
	)
	var target := direction * target_speed

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var slope_limited := false
	var slope_normal := Vector3.UP
	if on_floor:
		slope_normal = floor_normal.normalized() if floor_normal.length_squared() > 0.0001 else Vector3.UP
		slope_limited = slope_normal.angle_to(Vector3.UP) > deg_to_rad(profile.max_slope_degrees)
		if not slope_limited:
			# Andar numa rampa não pode ser o mesmo que andar no plano: a
			# componente da velocidade que sobe a rampa é convertida em altura.
			target = target.slide(slope_normal)
			horizontal = horizontal.slide(slope_normal)

	var rate := profile.air_acceleration
	if on_floor:
		rate = profile.acceleration if target.length() >= horizontal.length() else profile.deceleration
	horizontal = horizontal.move_toward(target, rate * step_delta)
	last_ground_speed = horizontal.length()

	# --- vertical -----------------------------------------------------------
	if on_floor and not slope_limited and jump_buffer > 0.0:
		velocity.y = profile.jump_velocity
		jump_buffer = 0.0
		coyote_timer = 0.0
		just_jumped = true
	elif not on_floor and coyote_timer > 0.0 and jump_buffer > 0.0 and velocity.y <= 0.0:
		# Pulo na janela de coyote: o pé já saiu da borda, mas o jogador ainda
		# merecia o pulo.
		velocity.y = profile.jump_velocity
		jump_buffer = 0.0
		coyote_timer = 0.0
		just_jumped = true
	elif on_floor and not slope_limited:
		# Colado ao chão: descer rampa não pode virar voo.
		velocity.y = -profile.slope_stick_velocity
	else:
		velocity.y -= profile.gravity * step_delta
		velocity.y = maxf(velocity.y, -profile.max_fall_speed)
		last_landing_speed = maxf(last_landing_speed, -velocity.y)

	velocity.x = horizontal.x
	velocity.z = horizontal.z
	return velocity


func is_falling() -> bool:
	return velocity.y < -0.35


func is_rising() -> bool:
	return velocity.y > 0.35


func reset() -> void:
	velocity = Vector3.ZERO
	coyote_timer = 0.0
	jump_buffer = 0.0
	landing_timer = 0.0
	was_on_floor = false
	just_jumped = false
	last_landing_speed = 0.0
	landing_speed = 0.0
	last_ground_speed = 0.0


## Quantos `move_and_slide` um passo precisa para não atravessar parede.
##
## A conta é intencionalmente pura: distância que o corpo percorre no passo
## dividida pelo limite por subpasso. A 60 Hz e 10 m/s o corpo anda 17 cm por
## passo, então isto vale 1 e o caminho é o `move_and_slide` normal — o fatiamento
## só entra quando a velocidade passa do que uma cápsula de 35 cm aguenta.
func substeps_for(delta: float) -> int:
	if delta <= 0.0:
		return 1
	var distance := Vector3(velocity.x, 0.0, velocity.z).length() * delta
	var limit := maxf(profile.substep_distance, 0.05)
	if distance <= limit:
		return 1
	return clampi(int(ceil(distance / limit)), 1, 8)


func speed() -> float:
	return Vector3(velocity.x, 0.0, velocity.z).length()


func describe() -> String:
	return "v=(%.2f, %.2f, %.2f) chão=%s coyote=%.2f buffer=%.2f" % [
		velocity.x,
		velocity.y,
		velocity.z,
		str(was_on_floor),
		coyote_timer,
		jump_buffer,
	]
