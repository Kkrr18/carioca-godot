extends TestCase

## Perfil de LOD: níveis decrescentes, faixas crescentes e coerência com o perfil
## de qualidade. Um perfil mal escrito produziria mais geometria no nível
## distante do que no próximo, que é o pior defeito possível de LOD.

func test_every_preset_has_four_levels() -> void:
	for preset_name in QualityProfile.names():
		var profile := LodProfile.from_preset(QualityProfile.get_preset(preset_name))
		assert_eq(profile.level_count(), 4, "%s tem quatro níveis" % preset_name)
		var previous := 1 << 24
		for level in range(profile.level_count()):
			var value := profile.divisions_for(level)
			assert_true(value < previous, "%s: divisões caem no nível %d" % [preset_name, level])
			previous = value


func test_level_zero_matches_quality_divisions() -> void:
	for preset_name in QualityProfile.names():
		var preset := QualityProfile.get_preset(preset_name)
		var profile := LodProfile.from_preset(preset)
		assert_eq(profile.divisions_for(0), int(preset["divisions"]), "%s: nível 0 usa as divisões do perfil" % preset_name)


func test_distances_are_increasing() -> void:
	for preset_name in QualityProfile.names():
		var profile := LodProfile.from_preset(QualityProfile.get_preset(preset_name))
		# A última faixa não tem limite (usa 0), então só as anteriores precisam
		# ser estritamente crescentes.
		for level in range(profile.level_count() - 2):
			assert_true(
				profile.distances[level] > 0.0 and profile.distances[level] < profile.distances[level + 1],
				"%s: faixa %d antes da %d" % [preset_name, level, level + 1]
			)
		# A penúltima faixa precisa ser uma distância real; a última é 0, que
		# significa "sem limite" — e infinito é sempre maior que a penúltima.
		assert_true(
			profile.distances[profile.level_count() - 2] > 0.0,
			"%s: penúltima faixa é uma distância real" % preset_name
		)
		assert_almost_eq(profile.distances[profile.level_count() - 1], 0.0, 1e-9, "%s: último nível sem limite" % preset_name)


func test_distance_selection_is_monotonic() -> void:
	var profile := LodProfile.from_preset(QualityProfile.get_preset("pc_medium"))
	assert_eq(profile.level_for_distance(0.0), 0, "colado no jogador é nível zero")
	var previous := -1
	for distance in [0.0, 100.0, 511.0, 512.0, 900.0, 1100.0, 1700.0, 1800.0, 5000.0]:
		var level := profile.level_for_distance(distance)
		assert_true(level >= previous, "nível não regride com a distância (%.0f m)" % distance)
		previous = level
	assert_eq(profile.level_for_distance(999999.0), profile.level_count() - 1, "muito longe é o último nível")


func test_collision_only_near_the_player() -> void:
	for preset_name in QualityProfile.names():
		var profile := LodProfile.from_preset(QualityProfile.get_preset(preset_name))
		assert_true(profile.has_collision(0), "%s: nível próximo tem colisão" % preset_name)
		assert_false(profile.has_collision(profile.level_count() - 1), "%s: nível distante não tem colisão" % preset_name)
		assert_greater(profile.skirt, 0.0, "%s: saia anti-rachadura configurada" % preset_name)


func test_malformed_preset_is_repaired() -> void:
	var profile := LodProfile.from_preset({
		"lod_divisions": [10, 20, 5],
		"lod_distances": [100.0, 50.0, 0.0],
	})
	assert_true(profile.divisions_for(0) > profile.divisions_for(1), "divisões crescentes corrigidas")
	assert_true(profile.divisions_for(1) > profile.divisions_for(2), "sequência de divisões coerente")
	assert_true(profile.distances[1] > profile.distances[0], "distâncias fora de ordem corrigidas")


func test_missing_keys_fall_back_to_defaults() -> void:
	var profile := LodProfile.from_preset({})
	assert_eq(profile.level_count(), LodProfile.DEFAULT_DIVISIONS.size(), "número de níveis padrão")
	assert_eq(profile.divisions_for(0), int(LodProfile.DEFAULT_DIVISIONS[0]), "divisões padrão")
	assert_true(profile.describe().contains("L0"), "descrição lista os níveis")
