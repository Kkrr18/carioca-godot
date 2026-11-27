extends TestCase

## Motor do personagem: a matemática do movimento, sem física e sem frame.
##
## Cada teste conduz o motor por passos de 1/60 s com uma intenção explícita. Se
## um teste desta bateria falhar, o problema está na conta — não no servidor de
## física, não na ordem de carga, não no frame.

const DT := 1.0 / 60.0


func _motor() -> PlayerMotor:
	return PlayerMotor.new(MovementProfile.new())


func _intent(direction: Vector3 = Vector3.ZERO, magnitude: float = 1.0, sprint: bool = false, walk: bool = false, jump: bool = false, on_floor: bool = true, normal: Vector3 = Vector3.UP, enabled: bool = true) -> Dictionary:
	return {
		"direction": direction,
		"magnitude": magnitude,
		"sprint": sprint,
		"walk": walk,
		"jump_pressed": jump,
		"on_floor": on_floor,
		"floor_normal": normal,
		"enabled": enabled,
	}


func _run(motor: PlayerMotor, steps: int, intent: Dictionary) -> void:
	for _i in range(steps):
		motor.step(DT, intent)


func test_starts_at_rest() -> void:
	var motor := _motor()
	assert_almost_eq(motor.speed(), 0.0, 1.0e-6, "começa parado")
	assert_almost_eq(motor.velocity.y, 0.0, 1.0e-6, "sem queda inicial")


func test_accelerates_up_to_run_speed() -> void:
	var motor := _motor()
	_run(motor, 120, _intent(Vector3.RIGHT))
	assert_almost_eq(motor.speed(), motor.profile.run_speed, 0.06, "chega na velocidade de corrida")
	assert_true(motor.speed() <= motor.profile.run_speed + 0.01, "nunca passa da velocidade alvo")


func test_walk_and_sprint_are_distinct_speeds() -> void:
	var walker := _motor()
	_run(walker, 120, _intent(Vector3.RIGHT, 1.0, false, true))
	var runner := _motor()
	_run(runner, 120, _intent(Vector3.RIGHT))
	var sprinter := _motor()
	_run(sprinter, 120, _intent(Vector3.RIGHT, 1.0, true))

	assert_almost_eq(walker.speed(), walker.profile.walk_speed, 0.08, "caminhada")
	assert_greater(runner.speed(), walker.speed() + 1.0, "corrida mais rápida que caminhada")
	assert_greater(sprinter.speed(), runner.speed() + 1.0, "sprint mais rápido que corrida")
	assert_true(sprinter.speed() <= sprinter.profile.sprint_speed + 0.01, "sprint respeita o teto do perfil")


func test_analog_magnitude_scales_speed() -> void:
	var half := _motor()
	_run(half, 120, _intent(Vector3.RIGHT, 0.4))
	var full := _motor()
	_run(full, 120, _intent(Vector3.RIGHT, 1.0))
	assert_greater(half.speed(), 0.5, "analógico pequeno ainda anda")
	assert_greater(full.speed(), half.speed() + 1.5, "analógico cheio anda mais rápido")


func test_releasing_input_decelerates_to_stop() -> void:
	var motor := _motor()
	_run(motor, 120, _intent(Vector3.RIGHT))
	_run(motor, 90, _intent(Vector3.ZERO, 0.0))
	assert_almost_eq(motor.speed(), 0.0, 0.05, "para quando solta a entrada")


func test_gravity_pulls_down_and_is_capped() -> void:
	var motor := _motor()
	_run(motor, 60, _intent(Vector3.ZERO, 0.0, false, false, false, false))
	assert_almost_eq(motor.velocity.y, -motor.profile.gravity, 0.6, "um segundo de queda livre")
	_run(motor, 600, _intent(Vector3.ZERO, 0.0, false, false, false, false))
	assert_almost_eq(motor.velocity.y, -motor.profile.max_fall_speed, 0.01, "velocidade terminal")


func test_jump_only_works_from_the_ground() -> void:
	var motor := _motor()
	motor.step(DT, _intent(Vector3.ZERO, 0.0, false, false, false, false))
	assert_true(motor.velocity.y < 0.0, "no ar continua caindo")
	var before := motor.velocity.y
	motor.step(DT, _intent(Vector3.ZERO, 0.0, false, false, true, false))
	assert_true(motor.velocity.y <= before + 0.01, "pulo no ar não impulsiona")


func test_jump_from_the_ground() -> void:
	var motor := _motor()
	motor.step(DT, _intent(Vector3.ZERO, 0.0, false, false, true))
	assert_almost_eq(motor.velocity.y, motor.profile.jump_velocity, 0.01, "impulso de pulo")
	assert_true(motor.just_jumped, "pulo registrado no passo")


func test_coyote_time_allows_a_late_jump() -> void:
	var motor := _motor()
	motor.step(DT, _intent(Vector3.ZERO, 0.0, false, false, false, true))
	motor.step(DT, _intent(Vector3.ZERO, 0.0, false, false, true, false))
	assert_almost_eq(motor.velocity.y, motor.profile.jump_velocity, 0.01, "pulo dentro da janela de coyote")


func test_coyote_time_expires() -> void:
	var motor := _motor()
	motor.step(DT, _intent(Vector3.ZERO, 0.0, false, false, false, true))
	_run(motor, 30, _intent(Vector3.ZERO, 0.0, false, false, false, false))
	motor.step(DT, _intent(Vector3.ZERO, 0.0, false, false, true, false))
	assert_true(motor.velocity.y < 0.0, "pulo tardio demais não vale")


func test_jump_buffer_fires_on_landing() -> void:
	var motor := _motor()
	_run(motor, 20, _intent(Vector3.ZERO, 0.0, false, false, false, false))
	motor.step(DT, _intent(Vector3.ZERO, 0.0, false, false, true, false))
	motor.step(DT, _intent(Vector3.ZERO, 0.0, false, false, false, true))
	assert_almost_eq(motor.velocity.y, motor.profile.jump_velocity, 0.01, "pulo apertado no ar vale ao encostar")


func test_landing_is_measured() -> void:
	var motor := _motor()
	_run(motor, 30, _intent(Vector3.ZERO, 0.0, false, false, false, false))
	motor.step(DT, _intent(Vector3.ZERO, 0.0, false, false, false, true))
	assert_greater(motor.landing_timer, 0.0, "estado de aterrissagem ativo")
	assert_greater(motor.landing_speed, 2.0, "velocidade de impacto registrada")


func test_slope_reduces_horizontal_speed() -> void:
	var flat := _motor()
	_run(flat, 120, _intent(Vector3.FORWARD))
	var slope := _motor()
	var normal := Vector3(0.0, cos(deg_to_rad(30.0)), sin(deg_to_rad(30.0)))
	_run(slope, 120, _intent(Vector3.BACK, 1.0, false, false, false, true, normal))
	assert_true(slope.speed() < flat.speed() * 0.95, "subir rampa rende menos velocidade horizontal")
	assert_greater(slope.speed(), 1.0, "mas continua andando")


func test_disabled_freezes_the_body() -> void:
	var motor := _motor()
	_run(motor, 60, _intent(Vector3.RIGHT))
	motor.step(DT, _intent(Vector3.RIGHT, 1.0, false, false, false, true, Vector3.UP, false))
	assert_almost_eq(motor.speed(), 0.0, 1.0e-6, "corpo congelado zera a velocidade")


func test_substeps_only_when_the_step_is_long() -> void:
	var motor := _motor()
	motor.velocity = Vector3(3.0, 0.0, 0.0)
	assert_eq(motor.substeps_for(DT), 1, "velocidade normal usa um passo")
	motor.velocity = Vector3(40.0, 0.0, 0.0)
	assert_eq(motor.substeps_for(DT), 2, "40 m/s fatia o passo")
	motor.velocity = Vector3(400.0, 0.0, 0.0)
	assert_eq(motor.substeps_for(DT), 8, "teto de subpassos")
	assert_eq(motor.substeps_for(0.0), 1, "delta zero é seguro")


func test_frame_rate_independence() -> void:
	var sixty := _motor()
	for _i in range(60):
		sixty.step(1.0 / 60.0, _intent(Vector3.RIGHT))
	var thirty := _motor()
	for _i in range(30):
		thirty.step(1.0 / 30.0, _intent(Vector3.RIGHT))
	assert_almost_eq(sixty.speed(), thirty.speed(), 0.35, "mesma velocidade em 60 e em 30 Hz")


func test_profile_from_preset_respects_ordering() -> void:
	var preset := {"player_walk_speed": 2.0, "player_run_speed": 5.0, "player_sprint_speed": 1.0}
	var profile := MovementProfile.from_preset(preset)
	assert_true(profile.sprint_speed > profile.run_speed, "sprint sempre acima da corrida, mesmo com preset inválido")
	assert_true(profile.run_speed > profile.walk_speed, "corrida sempre acima da caminhada")
