class_name DriveModel
extends RefCounted

## Modelo de direção do veículo — matemática pura, sem física.
##
## A divisão é a mesma da Etapa 4 no personagem: o `Vehicle` (VehicleBody3D)
## tem corpo, suspensão e pneus do servidor de física; quem decide **intenção**
## — acelerar, frear, engatar ré, quanto esterço existe nesta velocidade — é
## este modelo. Toda a regra que dá para testar sem servidor de física mora
## aqui, e por isso aceleração, freio, ré, freio de mão, esterço por
## velocidade e retorno do volante têm teste determinístico.
##
## Convenções:
##   `speed`     velocidade assinada ao longo da frente do carro (m/s).
##               Frente é -Z do corpo, como na Godot: > 0 indo para frente.
##   `throttle`  -1..1: 0..1 acelerador, negativo freia e, parado, engata ré.
##   `steer_in`  -1..1: -1 esquerda, 1 direita.
##
## Ré honesta: engatar ré só acontece com o carro praticamente parado. A S
## em movimento freia primeiro — o mesmo que GTA faz, e o que evita o carro
## "pisar no acelerador de ré" num freio de emergência.
##
## O passo é todo em função de `delta`: dois passos de 1/120 s e um de 1/60 s
## dão o mesmo resultado — a física é independente de taxa de quadros.

var profile: DrivingProfile = null

var steering: float = 0.0    # rad aplicado ao eixo
var gear: int = DrivingProfile.GEAR_DRIVE
var handbrake: bool = false

var _last_throttle: float = 0.0
var _brake_hold: float = 0.0  # segundos de freio contínuo com o carro parado

const SPEED_EPSILON := 0.6   # m/s: abaixo disto o carro "está parado"
const REVERSE_ENGAGE_S := 0.25  # segurar o freio parado este tempo engata a ré


func _init(new_profile: DrivingProfile = null) -> void:
	profile = new_profile if new_profile != null else DrivingProfile.new()


## Um passo. Devolve o que o corpo físico deve receber neste instante:
##   { "engine_force": float, "brake": float, "steering": float, "gear": int }
func step(delta: float, speed: float, throttle: float, steer_in: float, handbrake_now: bool = false) -> Dictionary:
	handbrake = handbrake_now
	var dt := clampf(delta, 0.0, 0.25)
	var pedals := _pedals(dt, speed, throttle)
	steering = _steering(dt, steer_in, speed)
	return {
		"engine_force": pedals["engine_force"],
		"brake": pedals["brake"],
		"steering": steering,
		"gear": gear,
	}


## Pedais. Frente: força cheia no pé, caindo perto do teto (aceleração
## progressiva e teto configurável). S em movimento: freio. S parado: freio
## primeiro; segurado por `REVERSE_ENGAGE_S` segundos parado, engata a ré —
## o que GTA faz, e o que impede o carro "pisar na ré" num freio de emergência.
func _pedals(delta: float, speed: float, throttle: float) -> Dictionary:
	var dt := clampf(delta, 0.0, 0.25)
	var engine := 0.0
	var brake := 0.0
	if throttle > 0.02:
		if gear == DrivingProfile.GEAR_REVERSE and speed < -SPEED_EPSILON:
			# Saindo da ré para frente: freia até parar antes de trocar.
			brake = profile.brake_force
		else:
			gear = DrivingProfile.GEAR_DRIVE
			_brake_hold = 0.0
			var headroom := 1.0 - clampf(speed / profile.max_speed, 0.0, 1.0)
			engine = throttle * profile.engine_force * headroom
	elif throttle < -0.02:
		if speed > SPEED_EPSILON or (gear == DrivingProfile.GEAR_DRIVE and speed < -SPEED_EPSILON):
			# Movimento (para qualquer lado, em marcha D): S é freio.
			gear = DrivingProfile.GEAR_DRIVE
			_brake_hold = 0.0
			brake = -throttle * profile.brake_force
		elif gear == DrivingProfile.GEAR_REVERSE:
			var headroom := 1.0 - clampf(-speed / profile.max_reverse_speed, 0.0, 1.0)
			engine = throttle * profile.engine_force * profile.reverse_factor * headroom
		else:
			# Parado em D segurando S: acumula freio e, depois de um instante,
			# engata a ré. O acumulador é o que separa "freio de emergência"
			# de "quero dar ré".
			_brake_hold += dt
			brake = -throttle * profile.brake_force
			if _brake_hold >= REVERSE_ENGAGE_S:
				gear = DrivingProfile.GEAR_REVERSE
				_brake_hold = 0.0
	else:
		# Pé solto: freio de motor; a ré morre sozinha até parar.
		_brake_hold = 0.0
		if absf(speed) > 0.05:
			brake = profile.coast_brake
		else:
			gear = DrivingProfile.GEAR_DRIVE
	if handbrake:
		brake = maxf(brake, profile.handbrake_force)
	_last_throttle = throttle
	return {"engine_force": engine, "brake": brake}


## Volante. O esterço disponível cai com a velocidade (`steer_factor`) e, sem
## input, o volante volta sozinho pelo centro — retorno progressivo.
func _steering(dt: float, steer_in: float, speed: float) -> float:
	var available := profile.max_steer * profile.steer_factor(speed)
	if absf(steer_in) > 0.02:
		var target := clampf(steer_in, -1.0, 1.0) * available
		return move_toward(steering, target, dt * profile.steer_rate)
	return move_toward(steering, 0.0, dt * profile.steer_return_rate)


## Aderência das rodas traseiras neste instante: o freio de mão solta a
## traseira, e é isto que deixa o carro girar. O `Vehicle` aplica por roda.
func rear_grip_factor() -> float:
	return profile.handbrake_grip if handbrake else 1.0


func reset() -> void:
	steering = 0.0
	gear = DrivingProfile.GEAR_DRIVE
	handbrake = false
	_brake_hold = 0.0


func gear_name() -> String:
	if gear == DrivingProfile.GEAR_REVERSE:
		return "ré"
	return "D"


func describe() -> String:
	return "marcha %s · esterço %.1f°" % [gear_name(), rad_to_deg(steering)]
