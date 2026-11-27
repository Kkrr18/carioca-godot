class_name Vehicle
extends VehicleBody3D

## Veículo dirigível — Etapa 5.
##
## A decisão de física continua a da Etapa 1, agora documentada de vez:
## **VehicleBody3D + VehicleWheel3D nativos**. Suspensão, atrito de pneu,
## contato com terreno, gravidade, inclinação e colisão vêm do servidor de
## física — reimplementar pneus em GDScript seria caro e menos estável. As
## limitações assumidas: sem câmbio simulado, sem diferencial e sem bloqueio
## de roda independente; a "transferência de peso" é a que o centro de massa
## e a suspensão produzem sozinhos.
##
## O que a Etapa 5 acrescenta, em camadas:
##
##   DrivingProfile  números (motor, teto, freio, esterço, aderência, tração)
##   DriveModel      intenção: pedais, marcha, esterço por velocidade, mão
##   VehicleAudio    motor, buzina e freio — placeholders sintetizados
##   casco visual    capô, porta-malas, teto, vidros, para-choques,
##                   retrovisores, faróis e lanternas (4 malhas + 4 rodas)
##
## Física seletiva como antes: sem motorista, freio aplicado e esterço voltando
## ao centro. Com motorista, o `DriveModel` decide e o corpo executa.
##
## A aderência continua reactiva ao clima: chuva interpola para o valor molhado
## do perfil (`apply_wetness`), e o freio de mão solta a traseira.

const LEGACY_MAX_ENGINE_FORCE := 1600.0
const LEGACY_MAX_BRAKE := 12.0
const LEGACY_MAX_STEER := 0.52
const LEGACY_REVERSE_FACTOR := 0.45
const LEGACY_DRY_FRICTION := 3.0
const LEGACY_WET_FRICTION := 1.35

## Borda lateral de saída do carro, em metros do centro (coluna A/B).
const EXIT_LATERAL := 2.05
const EXIT_HEIGHT := 1.2
const EXIT_PROBE_RADIUS := 0.5

var driver: Player = null
var terrain: TerrainService = null
var floating: FloatingOrigin = null
var spawn_metric: Vector2 = Vector2.ZERO
var wheel_radius: float = 0.36
var wheels: Array[VehicleWheel3D] = []
var body_color: Color = Color(0.72, 0.16, 0.14)
var wetness: float = 0.0

var profile: DrivingProfile = null
var model: DriveModel = null
var audio: VehicleAudio = null

var _body_mesh: MeshInstance3D = null


func _init() -> void:
	profile = DrivingProfile.new()
	model = DriveModel.new(profile)


func _ready() -> void:
	mass = profile.mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, profile.center_of_mass_height, 0.0)
	linear_damp = profile.linear_damp
	angular_damp = 1.2
	_build_chassis()
	_build_wheels()
	_build_audio()
	_apply_traction_mode()
	apply_wetness(0.0)


func _build_chassis() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.86, 1.05, 4.2)
	shape.shape = box
	shape.position = Vector3(0.0, 0.78, 0.0)
	add_child(shape)

	_body_mesh = MeshInstance3D.new()
	_body_mesh.name = "Shell"
	_body_mesh.mesh = ProceduralMeshes.car_shell()
	_body_mesh.material_override = MaterialLibrary.vehicle(body_color)
	add_child(_body_mesh)

	var trim := MeshInstance3D.new()
	trim.name = "Trim"
	trim.mesh = ProceduralMeshes.car_trim()
	trim.material_override = MaterialLibrary.vehicle_trim()
	add_child(trim)

	var glass := MeshInstance3D.new()
	glass.name = "Glass"
	glass.mesh = ProceduralMeshes.car_glass()
	glass.material_override = MaterialLibrary.vehicle_glass()
	add_child(glass)

	var headlights := MeshInstance3D.new()
	headlights.name = "Headlights"
	headlights.mesh = ProceduralMeshes.car_lights()
	headlights.material_override = MaterialLibrary.vehicle_headlight()
	add_child(headlights)

	var taillights := MeshInstance3D.new()
	taillights.name = "Taillights"
	taillights.mesh = ProceduralMeshes.car_lights()
	taillights.material_override = MaterialLibrary.vehicle_taillight()
	# Lanternas: mesmo par de luzes, atrás — espelhado em Z.
	taillights.rotation.y = PI
	add_child(taillights)


func _build_wheels() -> void:
	var positions := [
		Vector3(-0.82, 0.16, -1.32),
		Vector3(0.82, 0.16, -1.32),
		Vector3(-0.82, 0.16, 1.34),
		Vector3(0.82, 0.16, 1.34),
	]
	for i in range(4):
		var wheel := VehicleWheel3D.new()
		wheel.name = "Wheel%d" % i
		wheel.position = positions[i]
		wheel.wheel_radius = wheel_radius
		wheel.wheel_rest_length = 0.16
		wheel.wheel_friction_slip = profile.grip_dry
		wheel.suspension_travel = 0.22
		wheel.suspension_stiffness = 36.0
		wheel.damping_compression = 0.42
		wheel.damping_relaxation = 0.58
		wheel.use_as_traction = i >= 2
		wheel.use_as_steering = i < 2
		add_child(wheel)

		# O VehicleWheel3D gira e esterça os filhos sozinho: o pneu rola e o
		# eixo aponta para onde o volante aponta, sem código de visual aqui.
		var tire := MeshInstance3D.new()
		tire.mesh = ProceduralMeshes.wheel_tire()
		tire.material_override = MaterialLibrary.prop()
		tire.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		wheel.add_child(tire)
		var rim := MeshInstance3D.new()
		rim.mesh = ProceduralMeshes.wheel_rim()
		rim.material_override = MaterialLibrary.vehicle_rim()
		rim.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		wheel.add_child(rim)
		wheels.append(wheel)


func _build_audio() -> void:
	audio = VehicleAudio.new()
	audio.name = "VehicleAudio"
	add_child(audio)


func _physics_process(delta: float) -> void:
	if driver == null:
		var parked := model.step(delta, forward_speed(), 0.0, 0.0, false)
		engine_force = 0.0
		brake = maxf(float(parked["brake"]), LEGACY_MAX_BRAKE if forward_speed() < 1.5 else 0.0)
		steering = float(parked["steering"])
		_apply_handbrake_grip(false)
		if audio != null:
			audio.update_engine(0.0, 0.0)
			audio.set_horn(false)
		return

	var input := driver.read_move_input()
	var handbrake := InputBindings.is_pressed(InputBindings.ACTION_HANDBRAKE)
	var horn := InputBindings.is_pressed(InputBindings.ACTION_HORN)
	if driver.touch_controls != null and driver.touch_controls.visible_controls:
		if driver.touch_controls.vehicle_mode:
			var pedal := driver.touch_controls.pedal_value()
			if absf(pedal) > 0.05:
				input.y = pedal
			handbrake = handbrake or driver.touch_controls.handbrake_active
			horn = horn or driver.touch_controls.horn_active

	var step := model.step(delta, forward_speed(), input.y, input.x, handbrake)
	engine_force = float(step["engine_force"])
	brake = float(step["brake"])
	steering = float(step["steering"])
	_apply_handbrake_grip(bool(step["handbrake"]))
	if audio != null:
		var ratio := clampf(absf(forward_speed()) / maxf(profile.max_speed, 0.1), 0.0, 1.0)
		audio.update_engine(ratio, input.y)
		audio.set_horn(horn)


## Freio de mão: freio forte nas quatro rodas e aderência solta na traseira —
## é isto que deixa o carro girar de traseira em vez de só parar.
func _apply_handbrake_grip(active: bool) -> void:
	var rear_factor := model.rear_grip_factor()
	for i in range(wheels.size()):
		var wheel := wheels[i]
		if i < 2:
			wheel.wheel_friction_slip = profile.grip_for(wetness)
		else:
			wheel.wheel_friction_slip = profile.grip_for(wetness) * rear_factor


func _apply_traction_mode() -> void:
	for i in range(wheels.size()):
		match profile.traction_mode:
			"fwd":
				wheels[i].use_as_traction = i < 2
			"awd":
				wheels[i].use_as_traction = true
			_:
				wheels[i].use_as_traction = i >= 2


## Perfil de direção (do preset de qualidade ou de um veículo específico).
func apply_drive_profile(new_profile: DrivingProfile) -> void:
	if new_profile == null:
		return
	profile = new_profile
	model.profile = new_profile
	mass = profile.mass
	center_of_mass = Vector3(0.0, profile.center_of_mass_height, 0.0)
	linear_damp = profile.linear_damp
	_apply_traction_mode()
	apply_wetness(wetness)


func set_driver(new_driver: Player) -> void:
	driver = new_driver


func clear_driver() -> void:
	driver = null
	engine_force = 0.0
	brake = LEGACY_MAX_BRAKE
	model.reset()
	if audio != null:
		audio.stop_all()


## A chuva reduz a aderência: o clima não é só visual.
func apply_wetness(value: float) -> void:
	wetness = clampf(value, 0.0, 1.0)
	_apply_handbrake_grip(model.handbrake)


## Velocidade assinada ao longo da frente (m/s). Frente é -Z: em Godot o carro
## "olha" para -Z, e é por isso que as rodas dianteiras ficam em z negativo.
func forward_speed() -> float:
	return -linear_velocity.dot(global_transform.basis.z)


func metric_position() -> Vector2:
	if floating == null:
		return Vector2.ZERO
	return floating.local_to_metric(position)


func speed_kmh() -> float:
	return linear_velocity.length() * 3.6


## Posição global de uma saída lateral (+1 direita, -1 esquerda do carro).
func exit_position(side_sign: float) -> Vector3:
	var lateral := global_transform.basis.x * (side_sign * EXIT_LATERAL)
	return global_position + lateral + Vector3.UP * EXIT_HEIGHT


## O espaço lateral está livre? Sonda uma esfera do tamanho do peito do
## personagem no ponto de saída, contra o mundo estático. Sem espaço físico
## válido (fora da árvore, teste), não há como bloquear: devolve falso.
func side_is_blocked(side_sign: float) -> bool:
	var world := get_world_3d()
	if world == null:
		return false
	var space := world.direct_space_state
	if space == null:
		return false
	var shape := SphereShape3D.new()
	shape.radius = EXIT_PROBE_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), exit_position(side_sign))
	query.collision_mask = 1
	var excluded: Array[RID] = []
	excluded.append(get_rid())
	query.exclude = excluded
	return not space.intersect_shape(query, 1).is_empty()


## Escolhe o lado de saída: o mais perto do jogador primeiro, mas se estiver
## bloqueado, tenta o outro. Se os dois estiverem bloqueados, sai pelo
## preferido mesmo assim — nunca deixar o jogador preso dentro do carro.
func best_exit_side(player_position: Vector3) -> float:
	var right := exit_position(1.0)
	var left := exit_position(-1.0)
	var preferred := 1.0 if right.distance_to(player_position) <= left.distance_to(player_position) else -1.0
	if not side_is_blocked(preferred):
		return preferred
	var other := -preferred
	if not side_is_blocked(other):
		return other
	return preferred


func describe() -> String:
	return "%.0f km/h · marcha %s · %s" % [
		speed_kmh(),
		model.gear_name(),
		"com motorista" if driver != null else "estacionado",
	]
