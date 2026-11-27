extends TestCase

## Áudio do veículo: a matemática do tom do motor e o gancho da buzina.
##
## O que os sons são aqui está declarado no arquivo: placeholders sintetizados.
## O teste garante a resposta ao jogador — motor grave parado, agudo acelerando
## — e não realismo que não existe.


func test_engine_is_idle_when_stopped() -> void:
	var tone := VehicleAudio.engine_tone(0.0, 0.0)
	assert_almost_eq(float(tone["freq"]), VehicleAudio.ENGINE_BASE_HZ, 1e-6, "parado, marcha lenta grave")
	assert_true(float(tone["gain"]) > 0.0, "marcha lenta faz som")


func test_engine_pitch_rises_with_speed_and_throttle() -> void:
	var idle := float(VehicleAudio.engine_tone(0.0, 0.0)["freq"])
	var cruising := float(VehicleAudio.engine_tone(0.5, 0.0)["freq"])
	var flooring := float(VehicleAudio.engine_tone(0.5, 1.0)["freq"])
	var top := float(VehicleAudio.engine_tone(1.0, 1.0)["freq"])
	assert_true(cruising > idle, "velocidade sobe o tom")
	assert_true(flooring > cruising, "pé no acelerador sobe o tom")
	assert_true(top <= VehicleAudio.ENGINE_MAX_HZ + 1e-6, "o tom tem teto")
	assert_true(top > flooring, "teto soa mais agudo que o cruzeiro")


func test_engine_gain_grows_with_load() -> void:
	var quiet := float(VehicleAudio.engine_tone(0.0, 0.0)["gain"])
	var loud := float(VehicleAudio.engine_tone(1.0, 1.0)["gain"])
	assert_true(loud > quiet, "carga sobe o volume")
	assert_true(loud <= 0.2, "o motor não estoura a mixagem")


func test_extreme_inputs_are_clamped() -> void:
	var tone := VehicleAudio.engine_tone(9.0, -5.0)
	assert_true(float(tone["freq"]) > 0.0, "entrada absurda não quebra o tom")
	assert_true(float(tone["gain"]) > 0.0, "entrada absurda não silencia")


func test_horn_toggles_and_stops() -> void:
	var holder := Node3D.new()
	tree.root.add_child(holder)
	var audio := VehicleAudio.new()
	holder.add_child(audio)
	assert_false(audio.horn_playing(), "buzina começa muda")
	audio.set_horn(true)
	assert_true(audio.horn_playing(), "buzina toca")
	audio.set_horn(true)
	assert_true(audio.horn_playing(), "buzinar de novo não desliga")
	audio.set_horn(false)
	assert_false(audio.horn_playing(), "soltar desliga")
	audio.stop_all()
	assert_false(audio.horn_playing(), "stop_all silencia tudo")
	holder.free()
