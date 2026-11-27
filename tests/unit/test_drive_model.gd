extends TestCase

## Modelo de direção: pedais, marcha, esterço e freio de mão — sem física.
##
## É o arquivo que guarda a dirigibilidade prometida: acelerar até o teto,
## frear, ré só depois de parado segurando o freio, esterço que encurta com a
## velocidade, retorno do volante, e um passo de 1/120 s dobrado que dá o mesmo
## resultado de um de 1/60 s (independência de taxa de quadros).

const DT := 1.0 / 60.0


func _model() -> DriveModel:
	return DriveModel.new(DrivingProfile.new())


func test_throttle_accelerates_forward() -> void:
	var model := _model()
	var step := model.step(DT, 0.0, 1.0, 0.0)
	assert_greater(float(step["engine_force"]), 0.0, "acelerador produz força de motor")
	assert_almost_eq(float(step["brake"]), 0.0, 1e-6, "acelerador não freia")
	assert_eq(int(step["gear"]), DrivingProfile.GEAR_DRIVE, "acelerar mantém a marcha D")


func test_engine_tapers_to_zero_at_top_speed() -> void:
	var profile := DrivingProfile.new()
	var model := _model()
	var slow := model.step(DT, 0.0, 1.0, 0.0)
	assert_almost_eq(float(slow["engine_force"]), profile.engine_force, 1.0, "força cheia parado")
	var top := model.step(DT, profile.max_speed, 1.0, 0.0)
	assert_almost_eq(float(top["engine_force"]), 0.0, 1.0, "força seca no teto configurável")


func test_back_pedal_brakes_a_moving_car() -> void:
	var profile := DrivingProfile.new()
	var model := _model()
	var step := model.step(DT, 20.0, -1.0, 0.0)
	assert_almost_eq(float(step["brake"]), profile.brake_force, 1e-4, "S em movimento freia")
	assert_almost_eq(float(step["engine_force"]), 0.0, 1e-6, "freio não empurra")
	assert_eq(int(step["gear"]), DrivingProfile.GEAR_DRIVE, "S em movimento não engata ré")


func test_reverse_engages_after_holding_brake_at_standstill() -> void:
	var model := _model()
	for _i in range(10):
		model.step(DT, 0.0, -1.0, 0.0)
	assert_eq(model.gear, DrivingProfile.GEAR_DRIVE, "ré não engata num toque de freio")
	for _i in range(20):
		model.step(DT, 0.0, -1.0, 0.0)
	assert_eq(model.gear, DrivingProfile.GEAR_REVERSE, "segurar S parado engata a ré")
	var step := model.step(DT, -0.5, -1.0, 0.0)
	assert_true(float(step["engine_force"]) < 0.0, "na ré o motor empurra para trás")


func test_reverse_never_engages_while_the_car_moves() -> void:
	var model := _model()
	var first := model.step(DT, 15.0, -1.0, 0.0)
	assert_eq(int(first["gear"]), DrivingProfile.GEAR_DRIVE, "freio de emergência fica em D")
	var second := model.step(DT, 0.2, -1.0, 0.0)
	assert_eq(int(second["gear"]), DrivingProfile.GEAR_DRIVE, "parado por um instante ainda é freio")


func test_coast_brake_wins_when_the_pedals_are_idle() -> void:
	var profile := DrivingProfile.new()
	var model := _model()
	var step := model.step(DT, 8.0, 0.0, 0.0)
	assert_almost_eq(float(step["brake"]), profile.coast_brake, 1e-6, "pé solto freia de motor")
	assert_almost_eq(float(step["engine_force"]), 0.0, 1e-6, "pé solto não acelera")


func test_handbrake_adds_force_and_releases_the_rear() -> void:
	var profile := DrivingProfile.new()
	var model := _model()
	var step := model.step(DT, 10.0, 0.0, 0.0, true)
	assert_greater(float(step["brake"]), profile.coast_brake, "freio de mão freia mais que o pé solto")
	assert_almost_eq(model.rear_grip_factor(), profile.handbrake_grip, 1e-6, "mão solta a traseira")
	var released := model.step(DT, 10.0, 0.0, 0.0, false)
	assert_almost_eq(model.rear_grip_factor(), 1.0, 1e-6, "soltar a mão devolve a aderência")
	assert_true(float(released["brake"]) < profile.handbrake_force, "soltar a mão tira o freio extra")


func test_steering_saturates_and_falls_with_speed() -> void:
	var profile := DrivingProfile.new()
	var slow := _model()
	for _i in range(90):
		slow.step(DT, 0.0, 0.0, 1.0)
	assert_almost_eq(slow.steering, profile.max_steer, 0.01, "parado, o volante chega ao fundo")
	var fast := _model()
	for _i in range(90):
		fast.step(DT, 40.0, 0.0, 1.0)
	assert_almost_eq(fast.steering, profile.max_steer * profile.min_steer_factor, 0.01, "a 144 km/h o esterço encurta")
	assert_true(fast.steering < slow.steering, "alta velocidade esterça menos")


func test_steering_returns_to_center_when_released() -> void:
	var model := _model()
	for _i in range(90):
		model.step(DT, 0.0, 0.0, 1.0)
	var before := model.steering
	for _i in range(30):
		model.step(DT, 0.0, 0.0, 0.0)
	assert_true(model.steering < before, "soltar o volante o traz de volta ao centro")
	assert_true(model.steering > 0.0, "o retorno é progressivo, não instantâneo")


func test_two_half_steps_match_one_full_step() -> void:
	var full := _model()
	var one := full.step(DT, 5.0, 0.8, 0.7)
	var halved := _model()
	var first := halved.step(DT * 0.5, 5.0, 0.8, 0.7)
	var second := halved.step(DT * 0.5, 5.0, 0.8, 0.7)
	assert_almost_eq(halved.steering, full.steering, 1e-6, "esterço é independente da taxa")
	assert_almost_eq(float(one["engine_force"]), float(second["engine_force"]), 1e-6, "pedal é independente da taxa")
	assert_almost_eq(float(one["brake"]), float(second["brake"]), 1e-6, "freio é independente da taxa")
	assert_eq(int(first["gear"]), int(one["gear"]), "marcha é independente da taxa")


func test_gear_name_and_reset() -> void:
	var model := _model()
	assert_eq(model.gear_name(), "D", "marcha D tem nome")
	model.gear = DrivingProfile.GEAR_REVERSE
	assert_eq(model.gear_name(), "ré", "ré tem nome")
	model.reset()
	assert_eq(model.gear, DrivingProfile.GEAR_DRIVE, "reset volta a D")
	assert_almost_eq(model.steering, 0.0, 1e-9, "reset zera o volante")
