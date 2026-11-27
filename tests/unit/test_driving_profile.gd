extends TestCase

## Perfil de direção: limites, interpolação de aderência e queda do esterço.


func test_from_preset_applies_quality_numbers() -> void:
	var profile := DrivingProfile.from_preset({
		"vehicle_engine_force": 1250.0,
		"vehicle_max_speed": 28.0,
		"vehicle_brake_force": 11.0,
		"vehicle_max_steer": 0.5,
		"vehicle_grip": 2.8,
	})
	assert_almost_eq(profile.engine_force, 1250.0, 1e-6, "força de motor vem do preset")
	assert_almost_eq(profile.max_speed, 28.0, 1e-6, "teto vem do preset")
	assert_almost_eq(profile.brake_force, 11.0, 1e-6, "freio vem do preset")
	assert_almost_eq(profile.max_steer, 0.5, 1e-6, "esterço vem do preset")
	assert_almost_eq(profile.grip_dry, 2.8, 1e-6, "aderência vem do preset")


func test_from_preset_clamps_absurd_values() -> void:
	var profile := DrivingProfile.from_preset({
		"vehicle_engine_force": -50.0,
		"vehicle_max_speed": 500.0,
		"vehicle_brake_force": 0.0,
		"vehicle_max_steer": 5.0,
		"vehicle_grip": 99.0,
	})
	assert_true(profile.engine_force >= 200.0, "motor negativo é rejeitado")
	assert_true(profile.max_speed <= 70.0, "teto absurdo é cortado")
	assert_true(profile.brake_force >= 2.0, "freio zero é rejeitado")
	assert_true(profile.max_steer <= 0.9, "esterço além do volante é cortado")
	assert_true(profile.grip_dry <= 8.0, "aderência sobrecolada é cortada")


func test_rain_interpolates_grip_between_dry_and_wet() -> void:
	var profile := DrivingProfile.new()
	assert_almost_eq(profile.grip_for(0.0), profile.grip_dry, 1e-6, "seco é seco")
	assert_almost_eq(profile.grip_for(1.0), profile.grip_wet, 1e-6, "encharcado é molhado")
	var middle := profile.grip_for(0.5)
	assert_true(middle < profile.grip_dry and middle > profile.grip_wet, "meia chuva fica entre os dois")


func test_steer_factor_only_falls_and_never_goes_negative() -> void:
	var profile := DrivingProfile.new()
	var previous := profile.steer_factor(0.0)
	assert_almost_eq(previous, 1.0, 1e-6, "parado, esterço cheio")
	var speed := 2.0
	while speed <= 80.0:
		var current := profile.steer_factor(speed)
		assert_true(current <= previous + 1e-9, "esterço nunca cresce com a velocidade")
		assert_true(current >= profile.min_steer_factor - 1e-9, "esterço nunca desaba abaixo do piso")
		assert_true(current > 0.0, "nunca há esterço zero")
		previous = current
		speed += 4.0


func test_describe_is_readable() -> void:
	var text := DrivingProfile.new().describe()
	assert_true(text.contains("motor"), "descrição fala de motor")
	assert_true(text.contains("tração"), "descrição fala de tração")
